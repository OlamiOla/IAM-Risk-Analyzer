data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# DynamoDB table: current-state IAM inventory (consumed by downstream modules)
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "iam_inventory" {
  name         = "${var.project_name}-inventory"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "resource_type"
  range_key    = "resource_id"

  attribute {
    name = "resource_type"
    type = "S"
  }

  attribute {
    name = "resource_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-inventory"
    }
  )
}

# ---------------------------------------------------------------------------
# Lambda packaging
# ---------------------------------------------------------------------------
data "archive_file" "iam_inventory_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/iam_inventory.py"
  output_path = "${path.module}/lambda/iam_inventory.zip"
}

# ---------------------------------------------------------------------------
# IAM role and policy for Lambda (least privilege, heredoc JSON)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-inventory-lambda-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY

  tags = var.tags
}

resource "aws_iam_policy" "lambda_iam_readonly" {
  name        = "${var.project_name}-inventory-lambda-policy"
  description = "Least-privilege read-only IAM inventory permissions"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "IAMReadOnlyInventory",
      "Effect": "Allow",
      "Action": [
        "iam:ListUsers",
        "iam:ListRoles",
        "iam:ListGroups",
        "iam:ListAttachedUserPolicies",
        "iam:ListAttachedRolePolicies",
        "iam:ListAttachedGroupPolicies",
        "iam:ListUserPolicies",
        "iam:ListRolePolicies",
        "iam:ListGroupPolicies",
        "iam:ListAccessKeys",
        "iam:ListGroupsForUser",
        "iam:GetAccessKeyLastUsed",
        "iam:GetUser",
        "iam:GetRole",
        "iam:GetGroup",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:GenerateCredentialReport",
        "iam:GetCredentialReport"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DynamoDBWriteInventory",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:BatchWriteItem"
      ],
      "Resource": "${aws_dynamodb_table.iam_inventory.arn}"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "lambda_iam_readonly" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_iam_readonly.arn
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group (explicit, so retention is enforced)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-iam-inventory"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "iam_inventory" {
  function_name = "${var.project_name}-iam-inventory"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "iam_inventory.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.iam_inventory_lambda.output_path
  source_code_hash = data.archive_file.iam_inventory_lambda.output_base64sha256

  environment {
    variables = {
      INVENTORY_TABLE_NAME = aws_dynamodb_table.iam_inventory.name
      ACCOUNT_NAME         = var.account_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  tags       = var.tags
}

# ---------------------------------------------------------------------------
# EventBridge schedule trigger
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "inventory_schedule" {
  name                = "${var.project_name}-inventory-schedule"
  description         = "Triggers IAM inventory scan on a schedule"
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "inventory_lambda_target" {
  rule = aws_cloudwatch_event_rule.inventory_schedule.name
  arn  = aws_lambda_function.iam_inventory.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iam_inventory.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.inventory_schedule.arn
}
