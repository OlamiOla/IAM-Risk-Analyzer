data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# SNS topic for risk alerts (encrypted with AWS-managed SNS key)
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "risk_alerts" {
  name              = "${var.project_name}-risk-alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = var.tags
}

resource "aws_sns_topic_policy" "risk_alerts" {
  arn = aws_sns_topic.risk_alerts.arn

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountPublish",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "sns:Publish",
      "Resource": "${aws_sns_topic.risk_alerts.arn}"
    }
  ]
}
POLICY
}

resource "aws_sns_topic_subscription" "email_subscribers" {
  for_each  = toset(var.alert_email_subscribers)
  topic_arn = aws_sns_topic.risk_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------------------------------------------------------------------------
# Lambda packaging
# ---------------------------------------------------------------------------
data "archive_file" "send_alert_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/send_alert.py"
  output_path = "${path.module}/lambda/send_alert.zip"
}

# ---------------------------------------------------------------------------
# IAM role and policy for Lambda (least privilege, heredoc JSON)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-alerting-lambda-role"

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

resource "aws_iam_policy" "lambda_alerting" {
  name        = "${var.project_name}-alerting-lambda-policy"
  description = "Least-privilege permissions for IAM risk alerting"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DynamoDBStreamRead",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetRecords",
        "dynamodb:GetShardIterator",
        "dynamodb:DescribeStream",
        "dynamodb:ListStreams"
      ],
      "Resource": "${var.findings_table_stream_arn}"
    },
    {
      "Sid": "SNSPublishAlerts",
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "${aws_sns_topic.risk_alerts.arn}"
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

resource "aws_iam_role_policy_attachment" "lambda_alerting" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_alerting.arn
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-send-alert"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "send_alert" {
  function_name = "${var.project_name}-send-alert"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "send_alert.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.send_alert_lambda.output_path
  source_code_hash = data.archive_file.send_alert_lambda.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN          = aws_sns_topic.risk_alerts.arn
      MINIMUM_ALERT_SEVERITY = var.minimum_alert_severity
      ACCOUNT_NAME           = var.account_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  tags       = var.tags
}

# ---------------------------------------------------------------------------
# DynamoDB Stream trigger
# ---------------------------------------------------------------------------
resource "aws_lambda_event_source_mapping" "findings_stream" {
  event_source_arn               = var.findings_table_stream_arn
  function_name                  = aws_lambda_function.send_alert.arn
  starting_position              = var.stream_starting_position
  batch_size                     = var.stream_batch_size
  bisect_batch_on_function_error = true
  maximum_retry_attempts         = 3
}
