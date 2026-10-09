#!/usr/bin/env bash
# 30-workloads.sh — phase 30: the smoke workload. Builds the demo-app image,
# makes it available to the cluster, and applies the local overlay (namespaces,
# the Postgres cluster, the demo-app). Pass 3 moves the image to Zot; pass 4
# moves the apply under Argo CD.
#
# Emit + generator, one function each:
#   bash driver/phases/30-workloads.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/30-workloads.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: env/<env>.env (BRZL_DEMO_APP_TAG); <run_dir>/kubeconfig from phase 10.
# Needs docker for the build. No credentials.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

# The node architecture is the host's: k3d nodes run in the host's engine.
host_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'amd64' ;;
    *) printf 'arm64' ;;
  esac
}

phase_up() {
  local env="$1" run_dir="$2" image
  phase_init "$env" || end_function "$?" 'environment definition'
  image="demo-app:$BRZL_DEMO_APP_TAG"
  phase_header "$run_dir"
  printf '{ # demo-app image, built here and handed to the cluster\n'
  printf '  docker build --build-arg TARGETARCH=%q -t %q apps/demo-app\n' "$(host_arch)" "$image"
  substrate_load_image "$image"
  printf '}\n'
  printf '{ # the demo stack: namespaces, Postgres cluster, demo-app (local overlay)\n'
  printf '  kubectl apply -k gitops/clusters/local\n'
  printf '}\n'
  end_function 0 'emitted 30-workloads up'
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
  if (( $# )); then "$@"; else sed -n '2,12p' "${BASH_SOURCE[0]}"; fi
fi
