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

variable "lambda_runtime" {
  description = "Python runtime version for the Lambda function"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Lambda execution timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Lambda memory allocation in MB"
  type        = number
  default     = 256
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for inventory scans"
  type        = string
  default     = "rate(1 day)"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 90
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
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
