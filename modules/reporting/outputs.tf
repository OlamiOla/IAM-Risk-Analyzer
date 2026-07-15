output "lambda_function_arn" {
  description = "ARN of the reporting Lambda function"
  value       = aws_lambda_function.generate_report.arn
}

output "lambda_function_name" {
  description = "Name of the reporting Lambda function"
  value       = aws_lambda_function.generate_report.function_name
}

output "reports_bucket_name" {
  description = "S3 bucket name where reports are stored"
  value       = aws_s3_bucket.reports.id
}

output "reports_bucket_arn" {
  description = "S3 bucket ARN where reports are stored"
  value       = aws_s3_bucket.reports.arn
}
