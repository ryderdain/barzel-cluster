# Layer 40 — ECR. Image + OCI Helm chart registry, pull-through cache. Single source
# for all AWS environments (model B); independent of compute (no remote_state).
#
# Per-env via <env>.tfvars: the repo set (dev also publishes the operator `toolbox`
# image — see toolbox.tf; prod deliberately omits it, the conductor carries its own
# toolchain) and the toolbox-build flag. The Secrets Manager credential ARNs are
# account-level and SHARED across dev/prod (one ghcr/Docker-Hub token each), so they
# come from a gitignored `credentials.auto.tfvars` rendered by the secrets phase —
# auto-loaded for whichever env applies (same ARNs either way).

locals {
  name = "brzl-${var.env}"
}

module "ecr" {
  source = "../../../modules/ecr"

  name         = local.name
  repositories = var.repositories
  # AWS requires authenticated pull-through for Docker Hub (Grafana images) and
  # ghcr.io (CloudNativePG images); quay.io (ArgoCD) is credential-free — no ARN.
  dockerhub_credential_arn = var.dockerhub_credential_arn
  ghcr_credential_arn      = var.ghcr_credential_arn
}
