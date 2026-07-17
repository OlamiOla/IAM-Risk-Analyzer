resource "aws_kms_key" "project_cmk" {
  description             = "${var.project_name} CMK for CloudWatch Logs and SNS encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableRootAccountPermissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudWatchLogsUse",
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.${var.aws_region}.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowSNSUse",
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
POLICY

  tags = var.tags
}

resource "aws_kms_alias" "project_cmk" {
  name          = "alias/${var.project_name}-cmk"
  target_key_id = aws_kms_key.project_cmk.key_id
}

data "aws_caller_identity" "current" {}
