output "repository_urls" {
  value = module.ecr.repository_urls
}

output "registry_id" {
  value = module.ecr.registry_id
}

output "registry_host" {
  description = "ECR registry host for image refs (used by GitOps Helm values)."
  value       = module.ecr.registry_host
}

output "registry_host_param" {
  description = "SSM Parameter Store name holding the ECR registry host."
  value       = module.ecr.registry_host_param
}

output "k8s_cache_prefix" {
  value = module.ecr.k8s_cache_prefix
}

output "quay_cache_prefix" {
  value = module.ecr.quay_cache_prefix
}

output "ghcr_cache_prefix" {
  value = module.ecr.ghcr_cache_prefix
}
