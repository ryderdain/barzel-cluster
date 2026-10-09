#!/usr/bin/env bash
# k3d.sh — the substrate adapter for k3d (a k3s cluster in the local container
# engine). Every substrate adapter has the same four functions:
#
#   substrate_up <run_dir>          EMIT: make the cluster; write <run_dir>/kubeconfig
#   substrate_down                  EMIT: remove the cluster
#   substrate_load_image <image>    EMIT: make a locally built image available to
#                                   the cluster (pass 3 replaces this with Zot)
#   substrate_check <run_dir>       GENERATOR: is the cluster there and Ready?
#
# Sourced by driver/phases/*.sh, never run on its own. Inputs come from the
# environment definition: BRZL_K3D_CLUSTER, BRZL_K3D_SERVERS, BRZL_K3D_AGENTS.
# Needs k3d, docker and kubectl on PATH. No credentials.

substrate_up() {
  local run_dir="$1"
  printf '{ # k3d cluster %s, and its kubeconfig for the later phases\n' "$BRZL_K3D_CLUSTER"
  printf '  k3d cluster create %q --servers %q --agents %q --wait\n' \
    "$BRZL_K3D_CLUSTER" "$BRZL_K3D_SERVERS" "$BRZL_K3D_AGENTS"
  printf '  k3d kubeconfig get %q > %q\n' "$BRZL_K3D_CLUSTER" "$run_dir/kubeconfig"
  printf '}\n'
}

substrate_down() {
  printf '{ # remove k3d cluster %s and everything in it\n' "$BRZL_K3D_CLUSTER"
  printf '  k3d cluster delete %q\n' "$BRZL_K3D_CLUSTER"
  printf '}\n'
}

substrate_load_image() {
  local image="$1"
  printf '  k3d image import %q -c %q\n' "$image" "$BRZL_K3D_CLUSTER"
}

substrate_check() {
  local run_dir="$1" not_ready
  if ! k3d cluster get "$BRZL_K3D_CLUSTER" >/dev/null 2>&1; then
    printf 'fix: the cluster %s does not exist; run the 10-substrate phase again\n' \
      "$BRZL_K3D_CLUSTER" >&2
    return 1
  fi
  if [[ ! -s "$run_dir/kubeconfig" ]]; then
    printf 'fix: k3d kubeconfig get %q > %q\n' "$BRZL_K3D_CLUSTER" "$run_dir/kubeconfig" >&2
    return 1
  fi
  if ! not_ready="$(kubectl --kubeconfig "$run_dir/kubeconfig" get nodes --no-headers 2>&1)"; then
    printf 'fix: the cluster API does not answer: %s\n' "$not_ready" >&2
    return 1
  fi
  not_ready="$(grep -v ' Ready ' <<< "$not_ready")"
  if [[ -n "$not_ready" ]]; then
    printf 'fix: nodes not Ready yet; wait and check again:\n%s\n' "$not_ready" >&2
    return 1
  fi
  printf 'k3d cluster %s is up and its nodes are Ready\n' "$BRZL_K3D_CLUSTER"
}

substrate_check_down() {
  if k3d cluster get "$BRZL_K3D_CLUSTER" >/dev/null 2>&1; then
    printf 'fix: k3d cluster delete %q\n' "$BRZL_K3D_CLUSTER" >&2
    return 1
  fi
  printf 'k3d cluster %s is gone\n' "$BRZL_K3D_CLUSTER"
}
