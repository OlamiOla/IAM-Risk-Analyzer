output "lambda_function_arn" {
  description = "ARN of the analysis Lambda function"
  value       = aws_lambda_function.analyze_permissions.arn
}

output "lambda_function_name" {
  description = "Name of the analysis Lambda function"
  value       = aws_lambda_function.analyze_permissions.function_name
}

output "findings_table_name" {
  description = "DynamoDB table name holding risk findings"
  value       = aws_dynamodb_table.risk_findings.name
}

output "findings_table_arn" {
  description = "DynamoDB table ARN holding risk findings"
  value       = aws_dynamodb_table.risk_findings.arn
}

output "analyzer_arn" {
  description = "ARN of the IAM Access Analyzer (unused access)"
  value       = aws_accessanalyzer_analyzer.unused_access.arn
}

output "findings_table_stream_arn" {
  description = "DynamoDB Stream ARN for risk findings (consumed by alerting module)"
  value       = aws_dynamodb_table.risk_findings.stream_arn
}
