output "repository_urls" {
  description = "Map of short name -> repository URL (push/pull targets)."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "registry_id" {
  description = "ECR registry id (account id) hosting these repositories."
  value       = values(aws_ecr_repository.this)[0].registry_id
}

output "k8s_cache_prefix" {
  description = "ECR repository prefix that mirrors registry.k8s.io (if enabled)."
  value       = try(aws_ecr_pull_through_cache_rule.k8s[0].ecr_repository_prefix, null)
}

output "quay_cache_prefix" {
  description = "ECR repository prefix that mirrors quay.io (null unless creds supplied)."
  value       = try(aws_ecr_pull_through_cache_rule.quay[0].ecr_repository_prefix, null)
}

output "ghcr_cache_prefix" {
  description = "ECR repository prefix that mirrors ghcr.io (null unless creds supplied)."
  value       = try(aws_ecr_pull_through_cache_rule.ghcr[0].ecr_repository_prefix, null)
}

output "dockerhub_cache_prefix" {
  description = "ECR repository prefix that mirrors Docker Hub (null unless creds supplied)."
  value       = try(aws_ecr_pull_through_cache_rule.dockerhub[0].ecr_repository_prefix, null)
}

output "registry_host" {
  description = "ECR registry host (<account>.dkr.ecr.<region>.amazonaws.com) for image refs."
  value       = "${values(aws_ecr_repository.this)[0].registry_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

output "registry_host_param" {
  description = "SSM Parameter Store name holding the ECR registry host (read by GitOps bootstrap)."
  value       = aws_ssm_parameter.registry_host.name
}

output "kms_key_arn" {
  description = "CMK encrypting ECR images."
  value       = aws_kms_key.ecr.arn
}
