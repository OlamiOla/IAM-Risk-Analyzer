output "kms_key_arn" {
  value = aws_kms_key.project_cmk.arn
}

output "kms_key_id" {
  value = aws_kms_key.project_cmk.key_id
}
