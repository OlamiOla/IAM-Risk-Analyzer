data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# DynamoDB table: historical IAM change log (audit trail, TTL-based retention)
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "audit_history" {
  name         = "${var.project_name}-audit-history"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "resource_id"
  range_key    = "event_timestamp"

  attribute {
    name = "resource_id"
    type = "S"
  }

  attribute {
    name = "event_timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
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
      Name = "${var.project_name}-audit-history"
    }
  )
}

# ---------------------------------------------------------------------------
# Lambda packaging
# ---------------------------------------------------------------------------
data "archive_file" "log_iam_changes_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/log_iam_changes.py"
  output_path = "${path.module}/lambda/log_iam_changes.zip"
}

# ---------------------------------------------------------------------------
# IAM role and policy for Lambda (least privilege, heredoc JSON)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-audit-history-lambda-role"

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

resource "aws_iam_policy" "lambda_audit_history" {
  name        = "${var.project_name}-audit-history-lambda-policy"
  description = "Least-privilege permissions for IAM audit history logging"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DynamoDBWriteAuditHistory",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem"
      ],
      "Resource": "${aws_dynamodb_table.audit_history.arn}"
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

resource "aws_iam_role_policy_attachment" "lambda_audit_history" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_audit_history.arn
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-log-iam-changes"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "log_iam_changes" {
  function_name = "${var.project_name}-log-iam-changes"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "log_iam_changes.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.log_iam_changes_lambda.output_path
  source_code_hash = data.archive_file.log_iam_changes_lambda.output_base64sha256

  environment {
    variables = {
      AUDIT_HISTORY_TABLE_NAME = aws_dynamodb_table.audit_history.name
      RETENTION_DAYS           = tostring(var.audit_history_retention_days)
      ACCOUNT_NAME             = var.account_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  tags       = var.tags
}

# ---------------------------------------------------------------------------
# EventBridge rule: reacts to IAM change events delivered by the existing
# CloudTrail trail (management events flow to the default event bus
# automatically; no direct dependency on the trail resource itself).
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "iam_change_events" {
  name        = "${var.project_name}-iam-change-events"
  description = "Captures IAM change events from CloudTrail for audit history logging"

  event_pattern = jsonencode({
    source      = ["aws.iam"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = var.monitored_iam_event_names
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "audit_history_lambda_target" {
  rule = aws_cloudwatch_event_rule.iam_change_events.name
  arn  = aws_lambda_function.log_iam_changes.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_iam_changes.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.iam_change_events.arn
}
