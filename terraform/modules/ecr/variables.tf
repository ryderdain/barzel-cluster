variable "name" {
  description = "Name prefix for ECR repositories (e.g. brzl-dev)."
  type        = string
}

variable "repositories" {
  description = <<-EOT
    Private ECR repositories to create. `demo-app` holds the application image
    (built for arm64 / Graviton); `helm-charts` holds OCI Helm charts.
  EOT
  type        = list(string)
  default     = ["demo-app", "helm-charts"]
}

variable "enable_pull_through_cache" {
  description = <<-EOT
    Create pull-through cache rules so upstream images (Docker Hub,
    registry.k8s.io) are mirrored into ECR on first pull. Pull-through serves
    multi-arch manifests transparently, so arm64 nodes resolve the right layers.
  EOT
  type        = bool
  default     = true
}

variable "dockerhub_credential_arn" {
  description = <<-EOT
    Secrets Manager ARN holding Docker Hub credentials. AWS now requires
    authenticated pull-through for Docker Hub, so the Docker Hub cache rule is
    only created when this is set. registry.k8s.io needs no credentials and is
    always created. Leave "" to skip the Docker Hub rule (scaffolding default).
  EOT
  type        = string
  default     = ""
}

variable "ghcr_credential_arn" {
  description = <<-EOT
    Secrets Manager ARN holding GitHub Container Registry (ghcr.io) credentials
    (a fine-grained PAT with read:packages). AWS requires authenticated
    pull-through for ghcr.io, so the rule is only created when this is set. Routes
    CloudNativePG images (ghcr.io/cloudnative-pg/*) through ECR. Leave "" to skip.
  EOT
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags merged onto ECR resources."
  type        = map(string)
  default     = {}
}
