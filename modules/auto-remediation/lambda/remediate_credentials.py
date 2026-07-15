"""
Auto-Remediation Lambda

Scans OPEN risk findings for types explicitly marked remediable. When
AUTO_REMEDIATE is true, performs the remediation action (currently:
disabling stale access keys). When false, runs in dry-run mode — logs and
notifies what *would* happen without making any change. Always updates the
finding's status in DynamoDB and always notifies via SNS, regardless of mode.
"""

import os
import logging
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iam_client = boto3.client("iam")
sns_client = boto3.client("sns")
dynamodb = boto3.resource("dynamodb")

FINDINGS_TABLE_NAME = os.environ["FINDINGS_TABLE_NAME"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
AUTO_REMEDIATE = os.environ.get("AUTO_REMEDIATE", "false").lower() == "true"
REMEDIABLE_FINDING_TYPES = set(
    t.strip() for t in os.environ.get("REMEDIABLE_FINDING_TYPES", "").split(",") if t
)
ACCOUNT_NAME = os.environ.get("ACCOUNT_NAME", "unknown")


def _now_iso():
    return datetime.now(timezone.utc).isoformat()


def _fetch_open_remediable_findings(table):
    """Scan for OPEN findings whose finding_type is in the remediable set."""
    items = []
    response = table.scan(
        FilterExpression="#s = :open",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":open": "OPEN"},
    )
    items.extend(response.get("Items", []))
    while "LastEvaluatedKey" in response:
        response = table.scan(
            FilterExpression="#s = :open",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":open": "OPEN"},
            ExclusiveStartKey=response["LastEvaluatedKey"],
        )
        items.extend(response.get("Items", []))

    return [f for f in items if f.get("finding_type") in REMEDIABLE_FINDING_TYPES]


def _disable_access_key(user_name, access_key_id):
    iam_client.update_access_key(
        UserName=user_name,
        AccessKeyId=access_key_id,
        Status="Inactive",
    )


def _notify(subject, message):
    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject[:100],
        Message=message,
    )


def _update_finding_status(table, finding, new_status, action_taken):
    table.update_item(
        Key={
            "finding_id": finding["finding_id"],
            "resource_id": finding["resource_id"],
        },
        UpdateExpression="SET #s = :status, remediation_action = :action, remediated_at = :ts",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":status": new_status,
            ":action": action_taken,
            ":ts": _now_iso(),
        },
    )


def _process_stale_access_key(table, finding):
    resource_id = finding["resource_id"]  # format: "username:access_key_id"
    try:
        user_name, access_key_id = resource_id.split(":", 1)
    except ValueError:
        logger.warning("Unexpected resource_id format: %s", resource_id)
        return None

    if AUTO_REMEDIATE:
        _disable_access_key(user_name, access_key_id)
        action_taken = f"Disabled access key {access_key_id} for user {user_name}"
        new_status = "REMEDIATED"
        subject = f"[REMEDIATED] Stale access key disabled — {user_name}"
    else:
        action_taken = (
            f"DRY-RUN: Would disable access key {access_key_id} for user {user_name}"
        )
        new_status = "REMEDIATION_PENDING"
        subject = f"[DRY-RUN] Stale access key flagged for remediation — {user_name}"

    _update_finding_status(table, finding, new_status, action_taken)

    message = (
        f"IAM Auto-Remediation — {ACCOUNT_NAME}\n"
        f"{'=' * 40}\n"
        f"Mode:      {'LIVE' if AUTO_REMEDIATE else 'DRY-RUN'}\n"
        f"Finding:   {finding.get('finding_type')}\n"
        f"Resource:  {resource_id}\n"
        f"Action:    {action_taken}\n"
    )
    _notify(subject, message)

    return action_taken


REMEDIATION_HANDLERS = {
    "stale_access_key": _process_stale_access_key,
}


def handler(event, context):
    table = dynamodb.Table(FINDINGS_TABLE_NAME)

    logger.info(
        "Starting remediation scan (auto_remediate=%s, types=%s)",
        AUTO_REMEDIATE,
        REMEDIABLE_FINDING_TYPES,
    )

    findings = _fetch_open_remediable_findings(table)

    remediated_count = 0
    skipped_count = 0

    for finding in findings:
        handler_fn = REMEDIATION_HANDLERS.get(finding.get("finding_type"))
        if not handler_fn:
            skipped_count += 1
            continue

        result = handler_fn(table, finding)
        if result:
            remediated_count += 1

    summary = {
        "scanned_at": _now_iso(),
        "mode": "LIVE" if AUTO_REMEDIATE else "DRY_RUN",
        "findings_processed": remediated_count,
        "findings_skipped": skipped_count,
    }

    logger.info("Remediation scan complete: %s", summary)
    return summary