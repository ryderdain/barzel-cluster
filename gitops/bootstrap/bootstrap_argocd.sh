#!/usr/bin/env bash
# bootstrap_argocd.sh — EMIT the one-time commands that install ArgoCD and hand
# the cluster over to GitOps. Per the repo convention this is a mutating/action
# script: it only PRINTS commands to stdout. Review them first:
#
#   AWS_PROFILE=brzl-apply bash gitops/bootstrap/bootstrap_argocd.sh
#
# then execute by piping into a shell:
#
#   AWS_PROFILE=brzl-apply bash gitops/bootstrap/bootstrap_argocd.sh | bash
#
# What the emitted sequence does (&&-chained, fail-fast):
#   1. helm-installs the argo-cd chart into the argocd namespace, with the ArgoCD
#      image routed through ECR pull-through (quay.io upstream);
#   2. waits for argocd-server to roll out;
#   3. registers the private repo deploy-key Secret (if you've created it);
#   4. applies the AppProject + the in-cluster cluster Secret + the **ApplicationSet**
#      (ADR-0016 — a single ApplicationSet, NOT an app-of-apps root), after which
#      ArgoCD adopts its own release and syncs everything else from git by wave.
# It also strips k3s's default-StorageClass annotation from local-path so the
# wave-0 gp3 class can become the single default.
#
# Credentials: AWS_PROFILE if set (laptop), else ambient/instance-role creds (the
# conductor) — the dual-locus rule (CLAUDE.md).
#
# Sourceable (CLAUDE.md): `source` it and call emit_bootstrap_argocd, or run it
# directly. No `set -euo pipefail` in this generator (BashPitfalls/105): the only
# emit-time command whose failure matters (resolving the account) is checked
# explicitly; the emitted stream is &&-chained and does its own fail-fast.

# Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck disable=SC1091  # dynamic path; runlib.sh is shellchecked on its own
source "${repo_root}/gitops/tools/lib/runlib.sh"

region="${AWS_REGION:-eu-central-1}"
argocd_chart_version="${ARGOCD_CHART_VERSION:-7.7.0}"
namespace="${ARGOCD_NAMESPACE:-argocd}"
# Target environment (matches platform.sh): scopes the cluster manifests dir, the
# pull-through prefix, the SSM params, and the in-cluster Secret/ApplicationSet names.
env_name="${ENV:-dev}"

emit_bootstrap_argocd() {
  require_tools aws helm kubectl || end_function "$?" 'need aws + helm + kubectl on PATH'

  # Cluster reachability: the kubeconfig fetched by the Ansible kubernetes role.
  local kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
  if [[ ! -r "$kubeconfig" ]]; then
    printf 'error: kubeconfig not readable: %s (run the kubernetes role first)\n' "$kubeconfig" >&2
    end_function 1 'no kubeconfig'
    return 1
  fi

  local argocd_values="${repo_root}/gitops/infrastructure/argocd/values.yaml"
  local project_manifest="${repo_root}/gitops/clusters/${env_name}/project.yaml"
  local in_cluster_manifest="${repo_root}/gitops/clusters/${env_name}/in-cluster.yaml"
  local appset_manifest="${repo_root}/gitops/clusters/${env_name}/applicationset.yaml"
  local deploy_key="${repo_root}/gitops/bootstrap/repo-deploy-key.yaml"

  # Resolve the ECR registry host live from the caller's account via the shim
  # (resolve_ecr_host.sh → `aws sts get-caller-identity`). Injected into the install
  # via `helm --set` below; the self-managed apps get it from the in-cluster Secret
  # annotations (ADR-0016) — never committed to git.
  local registry argocd_image
  if ! registry="$(bash "${repo_root}/gitops/bootstrap/resolve_ecr_host.sh")"; then
    printf 'error: resolve_ecr_host.sh failed (creds/role set?)\n' >&2
    end_function 1 'no ECR host'
    return 1
  fi
  argocd_image="${registry}/brzl-${env_name}-quay/argoproj/argocd"

  # Resolve the CNPG backup bucket name (for __BACKUP_BUCKET__) from the SSM param
  # 15-kms publishes. Optional at emit time — only the CNPG apps need it.
  local bucket_param="${BACKUP_BUCKET_PARAM:-/brzl-${env_name}/backup/bucket_name}" backup_bucket
  backup_bucket="$(aws ssm get-parameter --region "$region" --name "$bucket_param" \
    --query Parameter.Value --output text 2>/dev/null)"
  if [[ -z "$backup_bucket" || "$backup_bucket" == "None" ]]; then
    backup_bucket=""
    printf 'note: SSM param %s not found; the __BACKUP_BUCKET__ render line below will be blank (apply 15-kms to publish it).\n' \
      "$bucket_param" >&2
  fi

  # The deploy-key Secret is optional at emit time but required for ArgoCD to read
  # the private repo — warn (to stderr) rather than fail, so a dry run still prints.
  local deploy_key_step=":  # (no deploy-key Secret found; create gitops/bootstrap/repo-deploy-key.yaml — see .example)"
  if [[ -r "$deploy_key" ]]; then
    deploy_key_step="kubectl apply -f ${deploy_key}"
  else
    printf 'note: %s not found — emitting a placeholder for the repo-secret step.\n' "$deploy_key" >&2
    printf '      ArgoCD cannot sync the PRIVATE repo until that Secret exists.\n' >&2
  fi

  # Emit the &&-chained install pipeline. The self-managed apps get the host/bucket
  # from the in-cluster Secret's annotations (written below), read by the
  # ApplicationSet's clusters generator — no account id in git (ADR-0016).
  printf '%s\n' "\
helm repo add argo https://argoproj.github.io/argo-helm && \\
helm repo update argo && \\
helm upgrade --install argocd argo/argo-cd \\
  --version ${argocd_chart_version} \\
  --namespace ${namespace} --create-namespace \\
  -f ${argocd_values} \\
  --set global.image.repository=${argocd_image} && \\
kubectl -n ${namespace} rollout status deploy/argocd-server --timeout=300s && \\
${deploy_key_step} && \\
kubectl apply -f ${project_manifest} && \\
kubectl apply -f ${in_cluster_manifest} && \\
kubectl annotate --overwrite -n ${namespace} secret brzl-${env_name}-in-cluster \\
  brzl.dev/ecr-host=${registry} brzl.dev/backup-bucket=${backup_bucket} && \\
kubectl apply -f ${appset_manifest}"

  # Make gp3 the single default StorageClass: drop k3s local-path's default
  # annotation. Tolerant (|| true) — local-path may be absent or already non-default.
  printf '%s\n' "\
kubectl patch storageclass local-path \\
  -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}' || true"

  # Operator NOTE (stderr, not part of the piped command stream).
  printf '\n--- NOTE ---------------------------------------------------------------\n' >&2
  printf 'Account-id hygiene (ADR-0016): the host is NOT in git. The ArgoCD install\n' >&2
  printf 'gets it live from resolve_ecr_host.sh via --set; the self-managed apps get it\n' >&2
  printf 'from the in-cluster Secret annotations set above (brzl.dev/ecr-host = %s,\n' "$registry" >&2
  printf 'brzl.dev/backup-bucket = %s), which the ApplicationSet clusters generator\n' "${backup_bucket:-<unset: apply 15-kms>}" >&2
  printf 'reads and injects at render (Helm parameters / kustomize images+patches).\n' >&2
  printf 'Verify after sync:\n' >&2
  printf '  kubectl -n %s get applicationset brzl-%s\n' "$namespace" "$env_name" >&2
  printf '  kubectl -n %s get applications -o wide   # 6 apps, Synced/Healthy by wave\n' "$namespace" >&2
  printf '  # image refs should resolve to %s/...\n' "$registry" >&2
  printf -- '----------------------------------------------------------------------\n' >&2
  end_function 0 'emitted ArgoCD bootstrap + ApplicationSet handover'
}

# CLI dispatch — only when run directly. Default = emit_bootstrap_argocd.
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else emit_bootstrap_argocd; fi
fi
