#!/usr/bin/env bash
# 40-workloads.sh — phase 40: wait until Argo CD has brought up the platform
# and the smoke workload from git, then check them. It applies nothing: phase
# 30-gitops handed the cluster to Argo CD. Locus: the conductor.
#
# Emit + generator, one function each:
#   bash driver/phases/40-workloads.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/40-workloads.sh phase_check <env> <run_dir>  # GENERATOR
#
# In fast mode Argo CD does not sync, so this phase waits until its timeout and
# its check fails: run it in GitOps mode (fast_off first).
#
# Inputs: <run_dir>/kubeconfig from phase 10 (for the check). Needs kubectl. No
# credentials.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

phase_locus() { printf '%s\n' conductor; }

phase_up() {
  local env="$1" run_dir="$2"
  phase_init "$env" || end_function "$?" 'environment definition'
  phase_header "$run_dir" conductor
  cat <<'EOF'
{ # Argo CD syncs every Application from git; wait until all are Synced and Healthy
  kubectl -n argocd wait applications --all --for=jsonpath='{.status.sync.status}'=Synced --timeout=900s
  kubectl -n argocd wait applications --all --for=jsonpath='{.status.health.status}'=Healthy --timeout=900s
}
EOF
  end_function 0 'emitted 40-workloads up'
}

phase_check() {
  local env="$1" run_dir="$2" rc=0 not_ready
  phase_init "$env" || return 1
  export KUBECONFIG="$run_dir/kubeconfig"
  not_ready="$(kubectl -n argocd get applications --no-headers \
    -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' 2>&1 \
    | grep -v ' Synced  *Healthy$')"
  if [[ -n "$not_ready" ]]; then
    printf 'fix: Applications not Synced and Healthy (see: kubectl -n argocd get applications):\n%s\n' "$not_ready" >&2
    rc=1
  fi
  if ! kubectl -n cnpg-demo wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' \
      cluster/pg --timeout=300s >/dev/null; then
    printf 'fix: Postgres cluster cnpg-demo/pg is not healthy; see: kubectl -n cnpg-demo describe cluster/pg\n' >&2
    rc=1
  fi
  if ! kubectl -n demo rollout status deploy/demo-app --timeout=180s >/dev/null; then
    printf 'fix: demo-app is not rolled out; see: kubectl -n demo describe deploy/demo-app\n' >&2
    rc=1
  fi
  (( rc == 0 )) && printf 'demo stack is up; open it: kubectl --kubeconfig %q -n demo port-forward svc/demo-app 8088:80\n' \
    "$run_dir/kubeconfig"
  return "$rc"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,14p' "${BASH_SOURCE[0]}"; fi
fi
