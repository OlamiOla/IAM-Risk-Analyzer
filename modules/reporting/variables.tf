variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "account_name" {
  description = "Environment/account name (e.g. dev, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "inventory_table_name" {
  description = "Name of the DynamoDB table holding IAM inventory"
  type        = string
}

variable "inventory_table_arn" {
  description = "ARN of the DynamoDB table holding IAM inventory"
  type        = string
}

variable "findings_table_name" {
  description = "Name of the DynamoDB table holding risk findings"
  type        = string
}

variable "findings_table_arn" {
  description = "ARN of the DynamoDB table holding risk findings"
  type        = string
}

variable "audit_history_table_name" {
  description = "Name of the DynamoDB table holding IAM audit history"
  type        = string
}

variable "audit_history_table_arn" {
  description = "ARN of the DynamoDB table holding IAM audit history"
  type        = string
}

variable "report_retention_days" {
  description = "Number of days to retain generated reports in S3"
  type        = number
  default     = 365
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for report generation"
  type        = string
  default     = "rate(7 days)"
}

variable "lambda_runtime" {
  description = "Python runtime version for the Lambda function"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Lambda execution timeout in seconds"
  type        = number
  default     = 180
}

variable "lambda_memory_size" {
  description = "Lambda memory allocation in MB"
  type        = number
  default     = 256
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "ARN of the shared CMK for CloudWatch Logs encryption"
  type        = string
}
