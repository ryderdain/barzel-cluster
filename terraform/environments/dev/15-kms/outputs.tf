output "ebs_kms_key_arn" {
  description = "CMK encrypting node EBS root volumes + gp3 PVCs (consumed by 50-compute)."
  value       = module.kms_ebs.key_arn
}

output "backup_kms_key_arn" {
  description = "CMK for CNPG/Barman backup SSE-KMS (consumed by 30-iam for the node role grant)."
  value       = module.kms_backup.key_arn
}

output "backup_bucket_arn" {
  description = "ARN of the CNPG/Barman backup bucket (consumed by 30-iam)."
  value       = module.backup.bucket_arn
}

output "backup_bucket_name" {
  description = "Name of the CNPG/Barman backup bucket (CNPG barmanObjectStore destinationPath)."
  value       = module.backup.bucket_name
}
