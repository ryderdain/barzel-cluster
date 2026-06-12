# Layer 40 — ECR. Image + OCI Helm chart registry, pull-through cache.
# Independent of compute; only the later image-pull config depends on it.

locals {
  name = "brzl-dev"
}

module "ecr" {
  source = "../../../modules/ecr"

  name = local.name
  # demo-app + helm-charts (module defaults) plus the operator toolbox image,
  # pulled in-cluster by gitops/tools/toolbox_shell.sh.
  repositories             = ["demo-app", "helm-charts", "toolbox"]
  dockerhub_credential_arn = var.dockerhub_credential_arn
  # ghcr.io (CloudNativePG images) needs a Secrets Manager credential. quay.io
  # (ArgoCD images) is credential-free for ECR pull-through — no ARN to pass.
  ghcr_credential_arn = var.ghcr_credential_arn
}
