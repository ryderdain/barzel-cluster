#!/usr/bin/env bash
# 40-workloads.sh — phase 40: the smoke workload. Applies the local overlay
# (namespaces, the Postgres cluster, the demo-app). Locus: the conductor.
#
# The overlay is rendered when the phase is emitted, and the rendered manifests
# go into the run-log itself. So the conductor needs no copy of the repo, and the
# run-log is the exact record of what was applied. (Pass 4 moves this under
# Argo CD.)
#
# Emit + generator, one function each:
#   bash driver/phases/40-workloads.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/40-workloads.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: env/<env>.env; the overlay gitops/clusters/<env>; <run_dir>/kubeconfig
# from phase 10 (for the check). Needs kubectl (kustomize built in). No
# credentials.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

phase_locus() { printf '%s\n' conductor; }

phase_up() {
  local env="$1" run_dir="$2" rendered
  phase_init "$env" || end_function "$?" 'environment definition'
  rendered="$(kubectl kustomize "$repo_root/gitops/clusters/$env")" \
    || end_function "$?" "could not render gitops/clusters/$env"
  phase_header "$run_dir" conductor
  printf '{ # the demo stack: namespaces, Postgres cluster, demo-app (overlay gitops/clusters/%s, rendered)\n' "$env"
  printf "  kubectl apply -f - <<'EOF'\n%s\nEOF\n" "$rendered"
  printf '}\n'
  end_function 0 'emitted 40-workloads up'
}

phase_check() {
  local env="$1" run_dir="$2" rc=0
  phase_init "$env" || return 1
  export KUBECONFIG="$run_dir/kubeconfig"
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
  if (( $# )); then "$@"; else sed -n '2,17p' "${BASH_SOURCE[0]}"; fi
fi
