"""
Reporting Lambda

Aggregates data from the IAM inventory, risk findings, and audit history
tables into a single JSON summary report, written to S3 on a schedule.
"""

import os
import json
import logging
from collections import Counter
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
s3_client = boto3.client("s3")

INVENTORY_TABLE_NAME = os.environ["INVENTORY_TABLE_NAME"]
FINDINGS_TABLE_NAME = os.environ["FINDINGS_TABLE_NAME"]
AUDIT_HISTORY_TABLE_NAME = os.environ["AUDIT_HISTORY_TABLE_NAME"]
REPORTS_BUCKET_NAME = os.environ["REPORTS_BUCKET_NAME"]
ACCOUNT_NAME = os.environ.get("ACCOUNT_NAME", "unknown")


def _now_iso():
    return datetime.now(timezone.utc).isoformat()


def _scan_all(table):
    items = []
    response = table.scan()
    items.extend(response.get("Items", []))
    while "LastEvaluatedKey" in response:
        response = table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
        items.extend(response.get("Items", []))
    return items


def _summarize_inventory(items):
    by_type = Counter(i.get("resource_type", "unknown") for i in items)
    total_access_keys = sum(len(i.get("access_keys", [])) for i in items)

    return {
        "total_users": by_type.get("user", 0),
        "total_roles": by_type.get("role", 0),
        "total_groups": by_type.get("group", 0),
        "total_access_keys": total_access_keys,
    }


def _summarize_findings(items):
    by_severity = Counter(i.get("severity", "UNKNOWN") for i in items)
    by_type = Counter(i.get("finding_type", "unknown") for i in items)
    by_status = Counter(i.get("status", "UNKNOWN") for i in items)

    top_resources = Counter(i.get("resource_id", "unknown") for i in items)

    return {
        "total_findings": len(items),
        "by_severity": dict(by_severity),
        "by_type": dict(by_type),
        "by_status": dict(by_status),
        "top_flagged_resources": dict(top_resources.most_common(10)),
    }


def _summarize_audit_history(items):
    by_event = Counter(i.get("event_name", "unknown") for i in items)
    failed_events = sum(1 for i in items if not i.get("success", True))

    return {
        "total_events_recorded": len(items),
        "failed_api_calls": failed_events,
        "top_event_types": dict(by_event.most_common(10)),
    }


def handler(event, context):
    logger.info("Starting IAM risk report generation")

    inventory_table = dynamodb.Table(INVENTORY_TABLE_NAME)
    findings_table = dynamodb.Table(FINDINGS_TABLE_NAME)
    audit_table = dynamodb.Table(AUDIT_HISTORY_TABLE_NAME)

    inventory_items = _scan_all(inventory_table)
    findings_items = _scan_all(findings_table)
    audit_items = _scan_all(audit_table)

    report = {
        "report_generated_at": _now_iso(),
        "account_name": ACCOUNT_NAME,
        "inventory_summary": _summarize_inventory(inventory_items),
        "findings_summary": _summarize_findings(findings_items),
        "audit_history_summary": _summarize_audit_history(audit_items),
    }

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    report_key = f"reports/{timestamp}/iam-risk-summary.json"

    s3_client.put_object(
        Bucket=REPORTS_BUCKET_NAME,
        Key=report_key,
        Body=json.dumps(report, indent=2, default=str),
        ContentType="application/json",
        ServerSideEncryption="AES256",
    )

    logger.info("Report written to s3://%s/%s", REPORTS_BUCKET_NAME, report_key)

    return {
        "report_location": f"s3://{REPORTS_BUCKET_NAME}/{report_key}",
        "findings_total": report["findings_summary"]["total_findings"],
        "users_total": report["inventory_summary"]["total_users"],
    }