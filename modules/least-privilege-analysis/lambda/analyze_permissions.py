"""
Least-Privilege Analysis Lambda

Reads the IAM inventory snapshot from DynamoDB, cross-references IAM Access
Analyzer unused-access findings, flags stale access keys, and writes
risk findings to DynamoDB for the alerting module to consume.
"""

import os
import logging
import uuid
from datetime import datetime, timedelta, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iam_client = boto3.client("iam")
analyzer_client = boto3.client("accessanalyzer")
dynamodb = boto3.resource("dynamodb")

INVENTORY_TABLE_NAME = os.environ["INVENTORY_TABLE_NAME"]
FINDINGS_TABLE_NAME = os.environ["FINDINGS_TABLE_NAME"]
ACCESS_ANALYZER_ARN = os.environ["ACCESS_ANALYZER_ARN"]
UNUSED_ACCESS_THRESHOLD = int(os.environ.get("UNUSED_ACCESS_THRESHOLD", "90"))
ACCOUNT_NAME = os.environ.get("ACCOUNT_NAME", "unknown")

HIGH_RISK_ACTIONS = {
    "iam:*",
    "*",
    "iam:CreateAccessKey",
    "iam:AttachUserPolicy",
    "iam:AttachRolePolicy",
    "iam:PutUserPolicy",
    "iam:PutRolePolicy",
    "sts:AssumeRole",
}


def _now_iso():
    return datetime.now(timezone.utc).isoformat()


def _put_finding(table, resource_id, finding_type, severity, detail, remediation):
    table.put_item(
        Item={
            "finding_id": str(uuid.uuid4()),
            "resource_id": resource_id,
            "finding_type": finding_type,
            "severity": severity,
            "detail": detail,
            "remediation": remediation,
            "detected_at": _now_iso(),
            "account_name": ACCOUNT_NAME,
            "status": "OPEN",
        }
    )


def _fetch_inventory(table):
    """Scan the full IAM inventory snapshot."""
    items = []
    response = table.scan()
    items.extend(response.get("Items", []))
    while "LastEvaluatedKey" in response:
        response = table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
        items.extend(response.get("Items", []))
    return items


def _check_unused_access_analyzer(findings_table):
    """Pull Access Analyzer unused-access findings (unused roles, unused permissions)."""
    count = 0
    paginator = analyzer_client.get_paginator("list_findings_v2")
    for page in paginator.paginate(
        analyzerArn=ACCESS_ANALYZER_ARN,
        filter={"status": {"eq": ["ACTIVE"]}},
    ):
        for finding in page.get("findings", []):
            resource_id = finding.get("resource", "unknown")
            finding_type = finding.get("findingType", "UnusedAccess")

            _put_finding(
                table=findings_table,
                resource_id=resource_id,
                finding_type=f"access_analyzer_{finding_type}",
                severity="MEDIUM",
                detail=finding.get("findingDetails", str(finding)),
                remediation="Review and remove unused permissions or the role/policy if fully unused.",
            )
            count += 1
    return count


def _check_stale_access_keys(inventory_items, findings_table):
    """Flag access keys with no recent usage or excessive age."""
    threshold_date = datetime.now(timezone.utc) - timedelta(
        days=UNUSED_ACCESS_THRESHOLD
    )
    count = 0

    for item in inventory_items:
        if item.get("resource_type") != "user":
            continue

        for key in item.get("access_keys", []):
            if key.get("status") != "Active":
                continue

            last_used_str = key.get("last_used_date")
            is_stale = False

            if not last_used_str:
                is_stale = True
            else:
                last_used_date = datetime.fromisoformat(last_used_str)
                if last_used_date < threshold_date:
                    is_stale = True

            if is_stale:
                _put_finding(
                    table=findings_table,
                    resource_id=f"{item['resource_id']}:{key['access_key_id']}",
                    finding_type="stale_access_key",
                    severity="HIGH",
                    detail=f"Access key unused for {UNUSED_ACCESS_THRESHOLD}+ days or never used",
                    remediation="Rotate or disable this access key.",
                )
                count += 1

    return count


def _check_wildcard_policies(inventory_items, findings_table):
    """Flag inline/attached policies referencing wildcard actions on IAM/STS."""
    count = 0

    for item in inventory_items:
        resource_id = item.get("resource_id")
        attached = item.get("attached_policies", [])

        for policy_arn in attached:
            try:
                policy = iam_client.get_policy(PolicyArn=policy_arn)["Policy"]
                version = iam_client.get_policy_version(
                    PolicyArn=policy_arn,
                    VersionId=policy["DefaultVersionId"],
                )
                statements = version["PolicyVersion"]["Document"].get(
                    "Statement", []
                )
                if isinstance(statements, dict):
                    statements = [statements]

                for stmt in statements:
                    if stmt.get("Effect") != "Allow":
                        continue
                    actions = stmt.get("Action", [])
                    if isinstance(actions, str):
                        actions = [actions]

                    if HIGH_RISK_ACTIONS.intersection(actions):
                        _put_finding(
                            table=findings_table,
                            resource_id=resource_id,
                            finding_type="overpermissioned_policy",
                            severity="HIGH",
                            detail=f"Policy {policy_arn} grants broad/high-risk actions: {actions}",
                            remediation="Scope policy actions to specific required permissions (least privilege).",
                        )
                        count += 1
            except iam_client.exceptions.NoSuchEntityException:
                logger.warning("Policy %s no longer exists, skipping", policy_arn)
                continue

    return count


def handler(event, context):
    inventory_table = dynamodb.Table(INVENTORY_TABLE_NAME)
    findings_table = dynamodb.Table(FINDINGS_TABLE_NAME)

    logger.info("Starting least-privilege analysis")

    inventory_items = _fetch_inventory(inventory_table)

    unused_access_count = _check_unused_access_analyzer(findings_table)
    stale_keys_count = _check_stale_access_keys(inventory_items, findings_table)
    wildcard_policy_count = _check_wildcard_policies(inventory_items, findings_table)

    summary = {
        "analyzed_at": _now_iso(),
        "inventory_items_reviewed": len(inventory_items),
        "unused_access_findings": unused_access_count,
        "stale_access_key_findings": stale_keys_count,
        "overpermissioned_policy_findings": wildcard_policy_count,
    }

    logger.info("Least-privilege analysis complete: %s", summary)
    return summary