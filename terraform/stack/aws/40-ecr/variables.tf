variable "env" {
  description = "Target environment: dev | prod. Drives the brzl-<env> name prefix (repos + pull-through cache rules), the Environment tag, and this layer's S3 state key."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
  }
}

variable "aws_region" {
  description = "AWS region. One per account for this PoC; matches the backend region."
  type        = string
  default     = "eu-central-1"
}

variable "repositories" {
  description = "ECR repos to create. dev adds \"toolbox\" (it publishes the operator image — toolbox.tf); prod omits it (intentional — the conductor carries its own toolchain)."
  type        = list(string)
  default     = ["demo-app", "helm-charts"]
}

# Account-level Secrets Manager ARNs, shared dev/prod — set in the gitignored
# credentials.auto.tfvars (rendered by the secrets phase), not in <env>.tfvars.
variable "dockerhub_credential_arn" {
  description = "Secrets Manager ARN with Docker Hub creds (authenticated pull-through). \"\" skips that cache rule."
  type        = string
  default     = ""
}

variable "ghcr_credential_arn" {
  description = "Secrets Manager ARN with ghcr.io creds — fine-grained PAT, read:packages (routes CloudNativePG images). \"\" skips."
  type        = string
  default     = ""
}
