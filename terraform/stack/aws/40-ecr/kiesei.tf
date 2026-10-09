# Build + publish the operator kiesei image as part of this layer, so a successful
# `tofu apply` is an implicit end-to-end check that the kiesei builds and publishes
# cleanly into the ECR repo. dev only (kiesei_build_enabled=true in dev.tfvars, and
# "kiesei" in dev's repositories); prod leaves it off. It re-runs only when the
# Dockerfile or a vendored signing key changes (triggers_replace), so steady-state
# applies are no-ops.
#
# Couples the apply host to a working docker/buildx + arm64 build path. Set
# kiesei_build_enabled=false on a host/runner without docker (the repo still gets
# created; push it separately with containers/kiesei/build-push.sh).

variable "kiesei_build_enabled" {
  description = "Build + push the kiesei image to ECR during apply (needs docker on the apply host; dev only)."
  type        = bool
  default     = false
}

locals {
  kiesei_ctx = "${path.module}/../../../../containers/kiesei"

  # Content-addressed tag from the build inputs. The ECR repos are IMMUTABLE, so a
  # rolling `latest` could only be pushed once; a hash of the inputs gives a unique
  # tag per Dockerfile/key change, pushed exactly once. kiesei-shell.sh resolves
  # the newest pushed tag, so nothing needs to know this value.
  kiesei_tag = substr(sha256(join("", [
    filesha256("${local.kiesei_ctx}/Dockerfile"),
    filesha256("${local.kiesei_ctx}/awscli-public-key.asc"),
    filesha256("${local.kiesei_ctx}/session-manager-plugin-key.asc"),
  ])), 0, 12)
}

resource "terraform_data" "kiesei_image" {
  count = var.kiesei_build_enabled ? 1 : 0

  # Rebuild when the content tag changes; otherwise this stays a no-op.
  triggers_replace = {
    tag        = local.kiesei_tag
    repository = module.ecr.repository_urls["kiesei"]
  }

  # build-push.sh EMITS the build/push/verify commands (&&-chained, fail-fast);
  # pipefail ensures a generator failure isn't masked by the downstream shell.
  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    command     = "set -o pipefail; bash '${local.kiesei_ctx}/build-push.sh' | bash"
    environment = {
      AWS_REGION   = var.aws_region
      KIESEI_REPO = "brzl-${var.env}/kiesei"
      KIESEI_TAG  = local.kiesei_tag
    }
  }

  depends_on = [module.ecr]
}
