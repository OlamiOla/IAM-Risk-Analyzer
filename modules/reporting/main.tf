data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# S3 bucket for generated reports
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "reports" {
  bucket = "${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "expire-old-reports"
    status = "Enabled"

    filter {}

    expiration {
      days = var.report_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# kics-scan ignore-block
resource "aws_s3_bucket" "reports_access_logs" {
  bucket = "${var.project_name}-reports-access-logs-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "reports_access_logs" {
  bucket                  = aws_s3_bucket.reports_access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports_access_logs" {
  bucket = aws_s3_bucket.reports_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "reports_access_logs" {
  bucket = aws_s3_bucket.reports_access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "reports" {
  bucket        = aws_s3_bucket.reports.id
  target_bucket = aws_s3_bucket.reports_access_logs.id
  target_prefix = "reports-access-logs/"
}

# ---------------------------------------------------------------------------
# Lambda packaging
# ---------------------------------------------------------------------------
data "archive_file" "generate_report_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/generate_report.py"
  output_path = "${path.module}/lambda/generate_report.zip"
}

# ---------------------------------------------------------------------------
# IAM role and policy for Lambda (least privilege, heredoc JSON)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-reporting-lambda-role"

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

resource "aws_iam_policy" "lambda_reporting" {
  name        = "${var.project_name}-reporting-lambda-policy"
  description = "Least-privilege permissions for IAM risk reporting"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DynamoDBReadInventory",
      "Effect": "Allow",
      "Action": [
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": "${var.inventory_table_arn}"
    },
    {
      "Sid": "DynamoDBReadFindings",
      "Effect": "Allow",
      "Action": [
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": "${var.findings_table_arn}"
    },
    {
      "Sid": "DynamoDBReadAuditHistory",
      "Effect": "Allow",
      "Action": [
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": "${var.audit_history_table_arn}"
    },
    {
      "Sid": "S3WriteReports",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "${aws_s3_bucket.reports.arn}/*"
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

resource "aws_iam_role_policy_attachment" "lambda_reporting" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_reporting.arn
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-generate-report"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "generate_report" {
  function_name = "${var.project_name}-generate-report"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "generate_report.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.generate_report_lambda.output_path
  source_code_hash = data.archive_file.generate_report_lambda.output_base64sha256

  environment {
    variables = {
      INVENTORY_TABLE_NAME     = var.inventory_table_name
      FINDINGS_TABLE_NAME      = var.findings_table_name
      AUDIT_HISTORY_TABLE_NAME = var.audit_history_table_name
      REPORTS_BUCKET_NAME      = aws_s3_bucket.reports.id
      ACCOUNT_NAME             = var.account_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  tags       = var.tags
}

# ---------------------------------------------------------------------------
# EventBridge schedule trigger
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "report_schedule" {
  name                = "${var.project_name}-report-schedule"
  description         = "Triggers weekly IAM risk summary report generation"
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "report_lambda_target" {
  rule = aws_cloudwatch_event_rule.report_schedule.name
  arn  = aws_lambda_function.generate_report.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.generate_report.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.report_schedule.arn
}
