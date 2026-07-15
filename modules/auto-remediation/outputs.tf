output "lambda_function_arn" {
  description = "ARN of the auto-remediation Lambda function"
  value       = aws_lambda_function.remediate_credentials.arn
}

output "lambda_function_name" {
  description = "Name of the auto-remediation Lambda function"
  value       = aws_lambda_function.remediate_credentials.function_name
}

output "auto_remediate_enabled" {
  description = "Whether this environment is running remediation live or in dry-run mode"
  value       = var.auto_remediate
}
