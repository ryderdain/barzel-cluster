variable "aws_region" {
  description = "AWS region. Must match ../backend.hcl and every other prod layer."
  type        = string
  default     = "eu-central-1"
}

variable "dockerhub_credential_arn" {
  description = <<-EOT
    Secrets Manager ARN with Docker Hub creds (account-level; same ARN as dev).
    Leave "" to skip that cache rule.
  EOT
  type        = string
  default     = ""
}

variable "ghcr_credential_arn" {
  description = <<-EOT
    Secrets Manager ARN with ghcr.io creds (account-level; same ARN as dev).
    Leave "" to skip.
  EOT
  type        = string
  default     = ""
}
