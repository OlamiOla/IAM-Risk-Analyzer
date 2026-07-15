"""
Alerting Lambda

Triggered by the DynamoDB Stream on the risk_findings table. Formats each
new finding with remediation guidance and publishes it to SNS, filtered by
minimum severity threshold.
"""

import os
import json
import logging

import boto3
from boto3.dynamodb.types import TypeDeserializer

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns_client = boto3.client("sns")
deserializer = TypeDeserializer()

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
MINIMUM_ALERT_SEVERITY = os.environ.get("MINIMUM_ALERT_SEVERITY", "MEDIUM")
ACCOUNT_NAME = os.environ.get("ACCOUNT_NAME", "unknown")

SEVERITY_RANK = {"LOW": 0, "MEDIUM": 1, "HIGH": 2}


def _deserialize_image(image):
    return {k: deserializer.deserialize(v) for k, v in image.items()}


def _meets_severity_threshold(severity):
    return SEVERITY_RANK.get(severity, 0) >= SEVERITY_RANK.get(
        MINIMUM_ALERT_SEVERITY, 1
    )


def _format_message(finding):
    return (
        f"IAM Risk Alert — {ACCOUNT_NAME}\n"
        f"{'=' * 40}\n"
        f"Severity:     {finding.get('severity', 'UNKNOWN')}\n"
        f"Finding type: {finding.get('finding_type', 'unknown')}\n"
        f"Resource:     {finding.get('resource_id', 'unknown')}\n"
        f"Detected at:  {finding.get('detected_at', 'unknown')}\n\n"
        f"Detail:\n{finding.get('detail', 'No additional detail provided')}\n\n"
        f"Recommended remediation:\n{finding.get('remediation', 'Review manually')}\n"
    )


def handler(event, context):
    alerts_sent = 0
    alerts_skipped = 0

    for record in event.get("Records", []):
        if record.get("eventName") not in ("INSERT", "MODIFY"):
            continue

        new_image = record.get("dynamodb", {}).get("NewImage")
        if not new_image:
            continue

        finding = _deserialize_image(new_image)
        severity = finding.get("severity", "LOW")

        if not _meets_severity_threshold(severity):
            alerts_skipped += 1
            continue

        message = _format_message(finding)
        subject = f"[{severity}] IAM Risk Finding — {finding.get('finding_type', 'unknown')}"[:100]

        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message,
        )
        alerts_sent += 1
        logger.info("Alert sent for finding_id=%s", finding.get("finding_id"))

    summary = {"alerts_sent": alerts_sent, "alerts_skipped": alerts_skipped}
    logger.info("Alert processing complete: %s", summary)
    return summary