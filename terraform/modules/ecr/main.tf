# Private ECR repositories for our own artifacts (demo-app image, OCI Helm
# charts) plus pull-through cache rules that mirror upstream registries into ECR
# on first pull. Production recommendation is Harbor (documented in docs/);
# ECR keeps the take-home self-contained on AWS.

# Generated CMK for image encryption (not the AWS-managed ECR key) — key policy
# we control, rotation, and grantable to other contexts.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key" "ecr" {
  description             = "${var.name} ECR image encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.ecr_key.json
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.name}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

data "aws_iam_policy_document" "ecr_key" {
  statement {
    sid       = "EnableIAMRoot"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = "${var.name}/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = var.tags
}

# registry.k8s.io: no upstream credentials required.
resource "aws_ecr_pull_through_cache_rule" "k8s" {
  count = var.enable_pull_through_cache ? 1 : 0

  ecr_repository_prefix = "${var.name}-k8s"
  upstream_registry_url = "registry.k8s.io"
}

# Docker Hub: AWS requires authenticated pull-through. Only create the rule when
# a Secrets Manager credential ARN is supplied.
resource "aws_ecr_pull_through_cache_rule" "dockerhub" {
  count = var.enable_pull_through_cache && var.dockerhub_credential_arn != "" ? 1 : 0

  ecr_repository_prefix = "${var.name}-docker-hub"
  upstream_registry_url = "registry-1.docker.io"
  credential_arn        = var.dockerhub_credential_arn
}

# quay.io: hosts the ArgoCD images. Unlike Docker Hub/ghcr, ECR treats quay.io as
# a credential-FREE upstream (passing a credential_arn fails with
# UnsupportedUpstreamRegistryException), so this rule needs no Secrets Manager
# secret — like registry.k8s.io.
resource "aws_ecr_pull_through_cache_rule" "quay" {
  count = var.enable_pull_through_cache ? 1 : 0

  ecr_repository_prefix = "${var.name}-quay"
  upstream_registry_url = "quay.io"
}

# ghcr.io: hosts the CloudNativePG operator + Postgres images. AWS requires
# authenticated pull-through (a read:packages PAT) even for public packages.
resource "aws_ecr_pull_through_cache_rule" "ghcr" {
  count = var.enable_pull_through_cache && var.ghcr_credential_arn != "" ? 1 : 0

  ecr_repository_prefix = "${var.name}-github"
  upstream_registry_url = "ghcr.io"
  credential_arn        = var.ghcr_credential_arn
}

# The account-bearing registry host (<account>.dkr.ecr.<region>.amazonaws.com) is
# config, not a secret — publish it to SSM Parameter Store (a plain String, free
# standard tier) so the GitOps bootstrap/tools can resolve it on demand without
# committing the account id to git (the Helm values keep a __ECR_REGISTRY_HOST__
# sentinel). Pull-through CREDENTIALS, by contrast, must live in Secrets Manager —
# ECR's credential_arn cannot reference Parameter Store.
resource "aws_ssm_parameter" "registry_host" {
  name        = "/${var.name}/ecr/registry_host"
  description = "ECR registry host for ${var.name} image refs (resolved by GitOps bootstrap)."
  type        = "String"
  value       = "${values(aws_ecr_repository.this)[0].registry_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
  tags        = var.tags
}
