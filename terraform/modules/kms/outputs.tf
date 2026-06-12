output "key_arn" {
  description = "ARN of the CMK (use for EBS kms_key_id, S3 SSE, IAM kms grants)."
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "Key id of the CMK."
  value       = aws_kms_key.this.key_id
}

output "alias_name" {
  description = "Full alias (alias/<name>) pointing at the key."
  value       = aws_kms_alias.this.name
}
