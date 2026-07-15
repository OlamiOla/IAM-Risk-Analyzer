output "lambda_function_arn" {
  description = "ARN of the audit history Lambda function"
  value       = aws_lambda_function.log_iam_changes.arn
}

output "lambda_function_name" {
  description = "Name of the audit history Lambda function"
  value       = aws_lambda_function.log_iam_changes.function_name
}

output "audit_history_table_name" {
  description = "DynamoDB table name holding historical IAM change records"
  value       = aws_dynamodb_table.audit_history.name
}

output "audit_history_table_arn" {
  description = "DynamoDB table ARN holding historical IAM change records"
  value       = aws_dynamodb_table.audit_history.arn
}

output "event_rule_arn" {
  description = "ARN of the EventBridge rule capturing IAM change events"
  value       = aws_cloudwatch_event_rule.iam_change_events.arn
}
