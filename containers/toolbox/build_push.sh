#!/usr/bin/env bash
# build_push.sh — EMIT the commands that build the arm64 operator toolbox image
# and push it to ECR. Per the repo convention this is a mutating/action script:
# it only PRINTS commands to stdout; review them with `bash build_push.sh`, then
# execute by piping into a shell:
#
#   AWS_PROFILE=brzl-apply bash containers/toolbox/build_push.sh | bash
#
# This is also invoked by the 40-ecr layer's local-exec so a `tofu apply` builds
# + publishes + verifies the toolbox as an implicit end-to-end check. The emitted
# commands are &&-chained so the run fails fast; wrap with `set -o pipefail` when
# piping (the 40-ecr local-exec does) so a failure here isn't masked downstream.
#
# Credentials: AWS_PROFILE if set (laptop), else ambient/instance-role creds (the
# conductor) — the dual-locus rule (CLAUDE.md).
#
# Sourceable (CLAUDE.md): `source` it and call emit_build_push, or run it directly.
# Same shape as apps/demo-app/build_push.sh. No `set -euo pipefail` in this generator
# (BashPitfalls/105): the only emit-time command whose failure matters (resolving the
# account) is checked explicitly; the emitted stream does its own &&-chained fail-fast.

# Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/../.." && pwd -P)"
# shellcheck disable=SC1091  # dynamic path; runlib.sh is shellchecked on its own
source "${repo_root}/gitops/tools/lib/runlib.sh"

region="${AWS_REGION:-eu-central-1}"
repo="${TOOLBOX_REPO:-brzl-dev/toolbox}"
tag="${TOOLBOX_TAG:-latest}"

emit_build_push() {
  require_tools aws docker || end_function "$?" 'need aws + docker on PATH'

  # Build context = this script's directory (Dockerfile + vendored .asc keys).
  local context="$script_dir"

  # Resolve the ECR registry from the caller's account (read-only).
  local account registry image
  if ! account="$(aws sts get-caller-identity --query Account --output text 2>&1)"; then
    printf 'error: could not resolve AWS account (creds set?):\n%s\n' "$account" >&2
    end_function 1 'no AWS account'
    return 1
  fi
  registry="${account}.dkr.ecr.${region}.amazonaws.com"
  image="${registry}/${repo}:${tag}"

  # Emit the &&-chained build/push/verify pipeline.
  printf '%s\n' "\
aws ecr get-login-password --region ${region} \
| docker login --username AWS --password-stdin ${registry} && \\
docker build --platform=linux/arm64 -t ${image} ${context} && \\
docker push ${image} && \\
aws ecr describe-images --region ${region} --repository-name ${repo} \
--image-ids imageTag=${tag} --query 'imageDetails[0].imageDigest' --output text >/dev/null && \\
echo 'toolbox published: ${image}'"
  end_function 0 "emitted build/push for ${image}"
}

# CLI dispatch — only when run directly. Default = emit_build_push.
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else emit_build_push; fi
fi
