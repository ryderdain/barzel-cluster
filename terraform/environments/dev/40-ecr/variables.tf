variable "aws_region" {
  description = "AWS region. Must match ../backend.hcl and every other dev layer."
  type        = string
  default     = "eu-central-1"
}

variable "dockerhub_credential_arn" {
  description = <<-EOT
    Secrets Manager ARN with Docker Hub creds. AWS requires authenticated
    pull-through for Docker Hub; leave "" to skip that cache rule (the
    registry.k8s.io rule is always created).
  EOT
  type        = string
  default     = ""
}

variable "ghcr_credential_arn" {
  description = <<-EOT
    Secrets Manager ARN with ghcr.io creds — a fine-grained PAT with
    read:packages (routes CloudNativePG images through ECR). AWS requires
    authenticated pull-through for ghcr.io; leave "" to skip.
  EOT
  type        = string
  default     = ""
}
