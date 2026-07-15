data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Lambda packaging
# ---------------------------------------------------------------------------
data "archive_file" "remediate_credentials_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/remediate_credentials.py"
  output_path = "${path.module}/lambda/remediate_credentials.zip"
}

# ---------------------------------------------------------------------------
# IAM role and policy for Lambda (least privilege, heredoc JSON)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-auto-remediation-lambda-role"

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

resource "aws_iam_policy" "lambda_remediation" {
  name        = "${var.project_name}-auto-remediation-lambda-policy"
  description = "Least-privilege permissions for automated credential remediation"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DynamoDBReadWriteFindings",
      "Effect": "Allow",
      "Action": [
        "dynamodb:Scan",
        "dynamodb:Query",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem"
      ],
      "Resource": "${var.findings_table_arn}"
    },
    {
      "Sid": "IAMCredentialRemediation",
      "Effect": "Allow",
      "Action": [
        "iam:UpdateAccessKey",
        "iam:GetAccessKeyLastUsed"
      ],
      "Resource": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*"
    },
    {
      "Sid": "SNSPublishRemediationNotice",
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "${var.sns_topic_arn}"
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

resource "aws_iam_role_policy_attachment" "lambda_remediation" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_remediation.arn
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-remediate-credentials"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "remediate_credentials" {
  function_name = "${var.project_name}-remediate-credentials"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "remediate_credentials.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.remediate_credentials_lambda.output_path
  source_code_hash = data.archive_file.remediate_credentials_lambda.output_base64sha256

  environment {
    variables = {
      FINDINGS_TABLE_NAME      = var.findings_table_name
      SNS_TOPIC_ARN            = var.sns_topic_arn
      AUTO_REMEDIATE           = tostring(var.auto_remediate)
      REMEDIABLE_FINDING_TYPES = join(",", var.remediable_finding_types)
      ACCOUNT_NAME             = var.account_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  tags       = var.tags
}

# ---------------------------------------------------------------------------
# EventBridge schedule trigger
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "remediation_schedule" {
  name                = "${var.project_name}-remediation-schedule"
  description         = "Triggers scan of OPEN findings eligible for automated remediation"
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "remediation_lambda_target" {
  rule = aws_cloudwatch_event_rule.remediation_schedule.name
  arn  = aws_lambda_function.remediate_credentials.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate_credentials.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.remediation_schedule.arn
}
