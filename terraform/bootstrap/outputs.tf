output "state_bucket" {
  description = "S3 bucket holding remote state. Use as `bucket` in every backend.hcl."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "DynamoDB lock table. Use as `dynamodb_table` in every backend.hcl."
  value       = aws_dynamodb_table.lock.name
}

output "region" {
  description = "Region of the state backend. Use as `region` in every backend.hcl."
  value       = var.aws_region
}

output "state_kms_key_arn" {
  description = "CMK encrypting state. terraform/identity grants the plan role kms perms on it."
  value       = aws_kms_key.state.arn
}

output "state_kms_alias" {
  description = "Alias for the state CMK (looked up by terraform/identity)."
  value       = aws_kms_alias.state.name
}
