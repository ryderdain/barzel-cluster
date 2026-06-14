#!/usr/bin/env bash
# install_ebs_csi.sh — EMIT the commands that install the aws-ebs-csi-driver Helm
# chart + the default gp3 StorageClass, for the STANDALONE (non-GitOps) path. Per
# the repo convention this is a mutating/action script: it only PRINTS commands to
# stdout. Review them first:
#
#   bash gitops/bootstrap/install_ebs_csi.sh
#
# then execute by piping into a shell:
#
#   bash gitops/bootstrap/install_ebs_csi.sh | bash
#
# WHY this exists: the GitOps bring-up installs EBS CSI + gp3 as ApplicationSet
# wave 0 (gitops/infrastructure/ebs-csi). The DR restore path (platform.sh
# operator→recover) deliberately BYPASSES GitOps to recover-before-adopt, so it
# inherits GitOps's setup responsibilities — without the CSI driver + a default
# StorageClass, the recovered CNPG cluster's gp3 PVCs hang Pending (GUIDANCE §2.6,
# the A2 lesson). This script is that standalone install, kept faithful to the
# GitOps path by rendering the SAME committed values file.
#
# What the emitted sequence does (&&-chained, fail-fast):
#   1. renders gitops/infrastructure/ebs-csi/values.yaml to a temp file, swapping
#      the __ECR_REGISTRY_HOST__ sentinel for this account's live ECR host (so the
#      CSI sidecars pull through our registry; no account id in git — ADR-0013);
#   2. helm-installs aws-ebs-csi-driver 2.37.0 into kube-system with that values
#      file (same chart/version/ns the ApplicationSet pins);
#   3. waits for the controller + node rollout;
#   4. strips k3s local-path's default-StorageClass annotation so the chart's gp3
#      class is the single default (mirrors bootstrap_argocd.sh; tolerant || true).
#
# Credentials: AWS_PROFILE if set (laptop), else ambient/instance-role creds (the
# conductor) — the dual-locus rule (CLAUDE.md). resolve_ecr_host.sh derives the
# account-bearing host at run time; nothing leans on shell memory (GUIDANCE §1.7).
#
# Sourceable (CLAUDE.md): `source` it and call emit_install_ebs_csi, or run it
# directly. No `set -euo pipefail` in this generator (BashPitfalls/105): the only
# emit-time command whose failure matters (resolving the host) is checked
# explicitly; the emitted stream is &&-chained and does its own fail-fast.

# Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck disable=SC1091  # dynamic path; runlib.sh is shellchecked on its own
source "${repo_root}/gitops/tools/lib/runlib.sh"

ebs_csi_chart_version="${EBS_CSI_CHART_VERSION:-2.37.0}"
namespace="${EBS_CSI_NAMESPACE:-kube-system}"

emit_install_ebs_csi() {
  require_tools aws helm kubectl || end_function "$?" 'need aws + helm + kubectl on PATH'

  local values_file="${repo_root}/gitops/infrastructure/ebs-csi/values.yaml"
  if [[ ! -r "$values_file" ]]; then
    printf 'error: ebs-csi values file not readable: %s\n' "$values_file" >&2
    end_function 1 'no ebs-csi values'
    return 1
  fi

  # Resolve the ECR registry host live from the caller's account via the shim
  # (resolve_ecr_host.sh → `aws sts get-caller-identity`), substituted into the
  # rendered values below — never committed to git (same approach as ArgoCD's
  # imageParams render; here a plain sed on the shared values file).
  local registry
  if ! registry="$(bash "${repo_root}/gitops/bootstrap/resolve_ecr_host.sh")"; then
    printf 'error: resolve_ecr_host.sh failed (creds/role set?)\n' >&2
    end_function 1 'no ECR host'
    return 1
  fi

  # Render to a per-run temp file in the emitted stream (mktemp on the EXECUTING
  # host), so the piped shell does the substitution at run time. The host is not a
  # secret (bootstrap_argocd.sh likewise emits it verbatim via --set).
  printf '%s\n' "\
rendered_values=\"\$(mktemp -t brzl-ebs-csi-values.XXXXXX.yaml)\" && \\
sed 's|__ECR_REGISTRY_HOST__|${registry}|g' ${values_file} > \"\$rendered_values\" && \\
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver && \\
helm repo update aws-ebs-csi-driver && \\
helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \\
  --version ${ebs_csi_chart_version} \\
  --namespace ${namespace} --create-namespace \\
  -f \"\$rendered_values\" && \\
kubectl -n ${namespace} rollout status deploy/ebs-csi-controller --timeout=300s && \\
kubectl -n ${namespace} rollout status ds/ebs-csi-node --timeout=300s && \\
kubectl get storageclass gp3"

  # Make gp3 the single default StorageClass: drop k3s local-path's default
  # annotation. Tolerant (|| true) — local-path may be absent or already non-default.
  printf '%s\n' "\
kubectl patch storageclass local-path \\
  -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}' || true"

  printf '\n--- NOTE ---------------------------------------------------------------\n' >&2
  printf 'Standalone EBS CSI + gp3 install (DR path; GUIDANCE §2.6). CSI sidecars\n' >&2
  printf 'pull through %s; the gp3 StorageClass is set default. Verify after run:\n' "$registry" >&2
  printf '  kubectl -n %s get pods -l app.kubernetes.io/name=aws-ebs-csi-driver\n' "$namespace" >&2
  printf '  kubectl get storageclass   # gp3 (default), local-path (no longer default)\n' >&2
  printf -- '----------------------------------------------------------------------\n' >&2
  end_function 0 'emitted EBS CSI + gp3 standalone install'
}

# CLI dispatch — only when run directly. Default = emit_install_ebs_csi.
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else emit_install_ebs_csi; fi
fi
