"""
IAM Inventory Lambda

Scans all IAM users, roles, and groups in the account, along with their
attached/inline policies and access key metadata, and writes a current-state
snapshot to DynamoDB for downstream analysis (least-privilege-analysis module).
"""

import os
import logging
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iam_client = boto3.client("iam")
dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["INVENTORY_TABLE_NAME"]
ACCOUNT_NAME = os.environ.get("ACCOUNT_NAME", "unknown")


def _now_iso():
    return datetime.now(timezone.utc).isoformat()


def _get_attached_policies(entity_type, entity_name):
    """Return attached managed policy ARNs for a user/role/group."""
    paginator_map = {
        "user": iam_client.get_paginator("list_attached_user_policies"),
        "role": iam_client.get_paginator("list_attached_role_policies"),
        "group": iam_client.get_paginator("list_attached_group_policies"),
    }
    kwarg_map = {
        "user": {"UserName": entity_name},
        "role": {"RoleName": entity_name},
        "group": {"GroupName": entity_name},
    }

    policies = []
    for page in paginator_map[entity_type].paginate(**kwarg_map[entity_type]):
        policies.extend(p["PolicyArn"] for p in page["AttachedPolicies"])
    return policies


def _get_inline_policy_names(entity_type, entity_name):
    paginator_map = {
        "user": iam_client.get_paginator("list_user_policies"),
        "role": iam_client.get_paginator("list_role_policies"),
        "group": iam_client.get_paginator("list_group_policies"),
    }
    kwarg_map = {
        "user": {"UserName": entity_name},
        "role": {"RoleName": entity_name},
        "group": {"GroupName": entity_name},
    }

    names = []
    for page in paginator_map[entity_type].paginate(**kwarg_map[entity_type]):
        names.extend(page["PolicyNames"])
    return names


def _get_access_key_metadata(user_name):
    """Return access key IDs, status, and last-used info for a user."""
    keys = []
    paginator = iam_client.get_paginator("list_access_keys")
    for page in paginator.paginate(UserName=user_name):
        for key in page["AccessKeyMetadata"]:
            last_used_info = {}
            try:
                response = iam_client.get_access_key_last_used(
                    AccessKeyId=key["AccessKeyId"]
                )
                last_used = response.get("AccessKeyLastUsed", {})
                last_used_info = {
                    "last_used_date": last_used.get("LastUsedDate", "").isoformat()
                    if last_used.get("LastUsedDate")
                    else None,
                    "service_used": last_used.get("ServiceName"),
                    "region_used": last_used.get("Region"),
                }
            except ClientError as e:
                logger.warning(
                    "Could not retrieve last-used data for key %s: %s",
                    key["AccessKeyId"],
                    e,
                )

            keys.append(
                {
                    "access_key_id": key["AccessKeyId"],
                    "status": key["Status"],
                    "create_date": key["CreateDate"].isoformat(),
                    **last_used_info,
                }
            )
    return keys


def _inventory_users(table, scan_timestamp):
    count = 0
    paginator = iam_client.get_paginator("list_users")
    for page in paginator.paginate():
        for user in page["Users"]:
            name = user["UserName"]
            item = {
                "resource_type": "user",
                "resource_id": name,
                "arn": user["Arn"],
                "create_date": user["CreateDate"].isoformat(),
                "attached_policies": _get_attached_policies("user", name),
                "inline_policies": _get_inline_policy_names("user", name),
                "access_keys": _get_access_key_metadata(name),
                "scanned_at": scan_timestamp,
                "account_name": ACCOUNT_NAME,
            }
            table.put_item(Item=item)
            count += 1
    return count


def _inventory_roles(table, scan_timestamp):
    count = 0
    paginator = iam_client.get_paginator("list_roles")
    for page in paginator.paginate():
        for role in page["Roles"]:
            name = role["RoleName"]
            item = {
                "resource_type": "role",
                "resource_id": name,
                "arn": role["Arn"],
                "create_date": role["CreateDate"].isoformat(),
                "attached_policies": _get_attached_policies("role", name),
                "inline_policies": _get_inline_policy_names("role", name),
                "max_session_duration": role.get("MaxSessionDuration"),
                "scanned_at": scan_timestamp,
                "account_name": ACCOUNT_NAME,
            }
            table.put_item(Item=item)
            count += 1
    return count


def _inventory_groups(table, scan_timestamp):
    count = 0
    paginator = iam_client.get_paginator("list_groups")
    for page in paginator.paginate():
        for group in page["Groups"]:
            name = group["GroupName"]
            item = {
                "resource_type": "group",
                "resource_id": name,
                "arn": group["Arn"],
                "create_date": group["CreateDate"].isoformat(),
                "attached_policies": _get_attached_policies("group", name),
                "inline_policies": _get_inline_policy_names("group", name),
                "scanned_at": scan_timestamp,
                "account_name": ACCOUNT_NAME,
            }
            table.put_item(Item=item)
            count += 1
    return count


def handler(event, context):
    table = dynamodb.Table(TABLE_NAME)
    scan_timestamp = _now_iso()

    logger.info("Starting IAM inventory scan at %s", scan_timestamp)

    users_count = _inventory_users(table, scan_timestamp)
    roles_count = _inventory_roles(table, scan_timestamp)
    groups_count = _inventory_groups(table, scan_timestamp)

    summary = {
        "scanned_at": scan_timestamp,
        "users_scanned": users_count,
        "roles_scanned": roles_count,
        "groups_scanned": groups_count,
    }

    logger.info("IAM inventory scan complete: %s", summary)
    return summary