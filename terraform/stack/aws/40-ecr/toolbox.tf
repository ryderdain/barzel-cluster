# Build + publish the operator toolbox image as part of this layer, so a successful
# `tofu apply` is an implicit end-to-end check that the toolbox builds and publishes
# cleanly into the ECR repo. dev only (toolbox_build_enabled=true in dev.tfvars, and
# "toolbox" in dev's repositories); prod leaves it off. It re-runs only when the
# Dockerfile or a vendored signing key changes (triggers_replace), so steady-state
# applies are no-ops.
#
# Couples the apply host to a working docker/buildx + arm64 build path. Set
# toolbox_build_enabled=false on a host/runner without docker (the repo still gets
# created; push it separately with containers/toolbox/build_push.sh).

variable "toolbox_build_enabled" {
  description = "Build + push the toolbox image to ECR during apply (needs docker on the apply host; dev only)."
  type        = bool
  default     = false
}

locals {
  toolbox_ctx = "${path.module}/../../../../containers/toolbox"

  # Content-addressed tag from the build inputs. The ECR repos are IMMUTABLE, so a
  # rolling `latest` could only be pushed once; a hash of the inputs gives a unique
  # tag per Dockerfile/key change, pushed exactly once. toolbox_shell.sh resolves
  # the newest pushed tag, so nothing needs to know this value.
  toolbox_tag = substr(sha256(join("", [
    filesha256("${local.toolbox_ctx}/Dockerfile"),
    filesha256("${local.toolbox_ctx}/awscli-public-key.asc"),
    filesha256("${local.toolbox_ctx}/session-manager-plugin-key.asc"),
  ])), 0, 12)
}

resource "terraform_data" "toolbox_image" {
  count = var.toolbox_build_enabled ? 1 : 0

  # Rebuild when the content tag changes; otherwise this stays a no-op.
  triggers_replace = {
    tag        = local.toolbox_tag
    repository = module.ecr.repository_urls["toolbox"]
  }

  # build_push.sh EMITS the build/push/verify commands (&&-chained, fail-fast);
  # pipefail ensures a generator failure isn't masked by the downstream shell.
  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    command     = "set -o pipefail; bash '${local.toolbox_ctx}/build_push.sh' | bash"
    environment = {
      AWS_REGION   = var.aws_region
      TOOLBOX_REPO = "brzl-${var.env}/toolbox"
      TOOLBOX_TAG  = local.toolbox_tag
    }
  }

  depends_on = [module.ecr]
}
