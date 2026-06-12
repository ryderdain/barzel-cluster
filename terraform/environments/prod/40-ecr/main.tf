# Layer 40 — ECR (prod). Same module as dev with the prod prefix, so the
# pull-through cache rules (brzl-prod-*) and repos coexist with dev's in the
# single PoC account. The Secrets Manager credentials are account-level and
# shared with dev (one ghcr/Docker-Hub token each — pass the same ARNs).
#
# No toolbox.tf here: the toolbox is operator tooling, not an environment
# component — the conductor carries its own toolchain, and the dev layer
# already publishes the image for in-cluster use.

locals {
  name = "brzl-prod"
}

module "ecr" {
  source = "../../../modules/ecr"

  name                     = local.name
  repositories             = ["demo-app", "helm-charts"]
  dockerhub_credential_arn = var.dockerhub_credential_arn
  ghcr_credential_arn      = var.ghcr_credential_arn
}
