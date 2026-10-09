#!/usr/bin/env bash
# 20-platform.sh — phase 20: the platform operators every workload needs:
# CloudNativePG and External Secrets, installed from their upstream charts.
# (Pass 4 moves this under Argo CD; until then helm installs them directly.)
#
# Emit + generator, one function each:
#   bash driver/phases/20-platform.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/20-platform.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: env/<env>.env (BRZL_CNPG_CHART_VERSION, BRZL_ESO_CHART_VERSION);
# <run_dir>/kubeconfig from phase 10. No credentials (public charts).

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

phase_up() {
  local env="$1" run_dir="$2"
  phase_init "$env" || end_function "$?" 'environment definition'
  phase_header "$run_dir"
  cat <<EOF
{ # helm chart repositories for the operators
  helm repo add cnpg https://cloudnative-pg.github.io/charts
  helm repo add external-secrets https://charts.external-secrets.io
  helm repo update cnpg external-secrets
}
{ # CloudNativePG operator
  helm upgrade --install cnpg-operator cnpg/cloudnative-pg --version $(printf %q "$BRZL_CNPG_CHART_VERSION") \\
    --namespace cnpg-system --create-namespace --wait
}
{ # External Secrets operator
  helm upgrade --install external-secrets external-secrets/external-secrets --version $(printf %q "$BRZL_ESO_CHART_VERSION") \\
    --namespace external-secrets --create-namespace --set installCRDs=true --wait
}
EOF
  end_function 0 'emitted 20-platform up'
}

phase_check() {
  local env="$1" run_dir="$2" release ns crd rc=0
  phase_init "$env" || return 1
  export KUBECONFIG="$run_dir/kubeconfig"
  for release in cnpg-operator:cnpg-system external-secrets:external-secrets; do
    ns="${release#*:}"; release="${release%%:*}"
    if [[ "$(helm status "$release" -n "$ns" -o json 2>/dev/null | jq -r '.info.status')" != deployed ]]; then
      printf 'fix: helm release %s in %s is not deployed; run the 20-platform phase again\n' \
        "$release" "$ns" >&2
      rc=1
    fi
  done
  for crd in clusters.postgresql.cnpg.io externalsecrets.external-secrets.io; do
    if ! kubectl get crd "$crd" >/dev/null 2>&1; then
      printf 'fix: CRD %s is missing; run the 20-platform phase again\n' "$crd" >&2
      rc=1
    fi
  done
  (( rc == 0 )) && printf 'CloudNativePG and External Secrets operators are deployed\n'
  return "$rc"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,11p' "${BASH_SOURCE[0]}"; fi
fi
