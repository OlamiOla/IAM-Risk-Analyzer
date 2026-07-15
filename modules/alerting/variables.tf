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

variable "findings_table_stream_arn" {
  description = "DynamoDB Stream ARN of the risk findings table"
  type        = string
}

variable "alert_email_subscribers" {
  description = "List of email addresses to subscribe to risk alerts"
  type        = list(string)
  default     = []
}

variable "stream_batch_size" {
  description = "Number of stream records to process per Lambda invocation"
  type        = number
  default     = 10
}

variable "stream_starting_position" {
  description = "Where to start reading the DynamoDB stream"
  type        = string
  default     = "LATEST"
}

variable "minimum_alert_severity" {
  description = "Minimum severity level that triggers an alert (LOW, MEDIUM, HIGH)"
  type        = string
  default     = "MEDIUM"

  validation {
    condition     = contains(["LOW", "MEDIUM", "HIGH"], var.minimum_alert_severity)
    error_message = "minimum_alert_severity must be one of: LOW, MEDIUM, HIGH."
  }
}

variable "lambda_runtime" {
  description = "Python runtime version for the Lambda function"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Lambda execution timeout in seconds"
  type        = number
  default     = 60
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
