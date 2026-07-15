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

variable "findings_table_name" {
  description = "Name of the DynamoDB table holding risk findings"
  type        = string
}

variable "findings_table_arn" {
  description = "ARN of the DynamoDB table holding risk findings"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic used for remediation notifications"
  type        = string
}

variable "auto_remediate" {
  description = "If true, actually performs remediation actions. If false, dry-run only (logs + notifies what would happen)."
  type        = bool
  default     = false
}

variable "remediable_finding_types" {
  description = "Finding types eligible for automated remediation"
  type        = list(string)
  default     = ["stale_access_key"]
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for remediation scan runs"
  type        = string
  default     = "rate(1 day)"
}

variable "lambda_runtime" {
  description = "Python runtime version for the Lambda function"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Lambda execution timeout in seconds"
  type        = number
  default     = 120
}

variable "lambda_memory_size" {
  description = "Lambda memory allocation in MB"
  type        = number
  default     = 128
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
