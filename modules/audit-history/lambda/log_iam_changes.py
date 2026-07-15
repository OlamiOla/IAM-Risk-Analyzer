"""
Audit History Lambda

Triggered by EventBridge whenever CloudTrail records an IAM change event.
Writes a structured, TTL-bound audit record to DynamoDB for historical
compliance and forensic review.
"""

import os
import logging
from datetime import datetime, timedelta, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["AUDIT_HISTORY_TABLE_NAME"]
RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "365"))
ACCOUNT_NAME = os.environ.get("ACCOUNT_NAME", "unknown")


def _extract_resource_id(detail):
    """Best-effort extraction of the IAM resource affected by this event."""
    request_params = detail.get("requestParameters") or {}
    response_elements = detail.get("responseElements") or {}

    for key in ("userName", "roleName", "groupName", "policyName", "policyArn"):
        if key in request_params:
            return request_params[key]
        if key in response_elements:
            return response_elements[key]

    return detail.get("eventName", "unknown-resource")


def handler(event, context):
    table = dynamodb.Table(TABLE_NAME)

    detail = event.get("detail", {})
    event_name = detail.get("eventName", "UnknownEvent")
    event_time = detail.get("eventTime", datetime.now(timezone.utc).isoformat())
    actor_arn = detail.get("userIdentity", {}).get("arn", "unknown")
    actor_type = detail.get("userIdentity", {}).get("type", "unknown")
    source_ip = detail.get("sourceIPAddress", "unknown")
    aws_region = detail.get("awsRegion", "unknown")
    error_code = detail.get("errorCode")

    resource_id = _extract_resource_id(detail)
    expires_at = int(
        (datetime.now(timezone.utc) + timedelta(days=RETENTION_DAYS)).timestamp()
    )

    item = {
        "resource_id": resource_id,
        "event_timestamp": event_time,
        "event_name": event_name,
        "actor_arn": actor_arn,
        "actor_type": actor_type,
        "source_ip": source_ip,
        "aws_region": aws_region,
        "success": error_code is None,
        "error_code": error_code,
        "account_name": ACCOUNT_NAME,
        "expires_at": expires_at,
    }

    table.put_item(Item=item)

    logger.info(
        "Logged audit event: %s on %s by %s", event_name, resource_id, actor_arn
    )

    return {"logged": True, "resource_id": resource_id, "event_name": event_name}