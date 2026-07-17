data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# IAM Access Analyzer (account-level, unused access findings)
# ---------------------------------------------------------------------------
resource "aws_accessanalyzer_analyzer" "unused_access" {
  analyzer_name = "${var.project_name}-unused-access-analyzer"
  type          = "ACCOUNT_UNUSED_ACCESS"

  configuration {
    unused_access {
      unused_access_age = var.unused_access_threshold_days
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# DynamoDB table: risk findings (consumed by alerting + reporting modules)
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "risk_findings" {
  name         = "${var.project_name}-risk-findings"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "finding_id"
  range_key    = "resource_id"

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  attribute {
    name = "finding_id"
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
      Name = "${var.project_name}-risk-findings"
    }
  )
}

# ---------------------------------------------------------------------------
# Lambda packaging
# ---------------------------------------------------------------------------
data "archive_file" "analyze_permissions_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/analyze_permissions.py"
  output_path = "${path.module}/lambda/analyze_permissions.zip"
}

# ---------------------------------------------------------------------------
# IAM role and policy for Lambda (least privilege, heredoc JSON)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-analysis-lambda-role"

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

resource "aws_iam_policy" "lambda_analysis" {
  name        = "${var.project_name}-analysis-lambda-policy"
  description = "Least-privilege permissions for IAM risk analysis"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AccessAnalyzerReadFindings",
      "Effect": "Allow",
      "Action": [
        "access-analyzer:ListFindingsV2",
        "access-analyzer:GetFindingV2",
        "access-analyzer:ListAnalyzers"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMPolicySimulation",
      "Effect": "Allow",
      "Action": [
        "iam:SimulatePrincipalPolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:GetRole",
        "iam:GetUser"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DynamoDBReadInventory",
      "Effect": "Allow",
      "Action": [
        "dynamodb:Scan",
        "dynamodb:GetItem",
        "dynamodb:Query"
      ],
      "Resource": "${var.inventory_table_arn}"
    },
    {
      "Sid": "DynamoDBWriteFindings",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:BatchWriteItem"
      ],
      "Resource": "${aws_dynamodb_table.risk_findings.arn}"
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

resource "aws_iam_role_policy_attachment" "lambda_analysis" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_analysis.arn
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-analyze-permissions"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "analyze_permissions" {
  function_name = "${var.project_name}-analyze-permissions"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "analyze_permissions.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.analyze_permissions_lambda.output_path
  source_code_hash = data.archive_file.analyze_permissions_lambda.output_base64sha256

  environment {
    variables = {
      INVENTORY_TABLE_NAME    = var.inventory_table_name
      FINDINGS_TABLE_NAME     = aws_dynamodb_table.risk_findings.name
      ACCESS_ANALYZER_ARN     = aws_accessanalyzer_analyzer.unused_access.arn
      UNUSED_ACCESS_THRESHOLD = tostring(var.unused_access_threshold_days)
      ACCOUNT_NAME            = var.account_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  tags       = var.tags
}

# ---------------------------------------------------------------------------
# EventBridge schedule trigger
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "analysis_schedule" {
  name                = "${var.project_name}-analysis-schedule"
  description         = "Triggers IAM least-privilege analysis on a schedule"
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "analysis_lambda_target" {
  rule = aws_cloudwatch_event_rule.analysis_schedule.name
  arn  = aws_lambda_function.analyze_permissions.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analyze_permissions.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.analysis_schedule.arn
}

