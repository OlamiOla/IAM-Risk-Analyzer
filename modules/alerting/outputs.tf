output "lambda_function_arn" {
  description = "ARN of the alerting Lambda function"
  value       = aws_lambda_function.send_alert.arn
}

output "lambda_function_name" {
  description = "Name of the alerting Lambda function"
  value       = aws_lambda_function.send_alert.function_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for risk alerts"
  value       = aws_sns_topic.risk_alerts.arn
}
