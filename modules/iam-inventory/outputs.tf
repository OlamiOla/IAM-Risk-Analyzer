output "lambda_function_arn" {
  description = "ARN of the IAM inventory Lambda function"
  value       = aws_lambda_function.iam_inventory.arn
}

output "lambda_function_name" {
  description = "Name of the IAM inventory Lambda function"
  value       = aws_lambda_function.iam_inventory.function_name
}

output "inventory_table_name" {
  description = "DynamoDB table name holding current IAM inventory state"
  value       = aws_dynamodb_table.iam_inventory.name
}

output "inventory_table_arn" {
  description = "DynamoDB table ARN holding current IAM inventory state"
  value       = aws_dynamodb_table.iam_inventory.arn
}
