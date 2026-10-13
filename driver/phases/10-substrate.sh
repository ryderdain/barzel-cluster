#!/usr/bin/env bash
# 10-substrate.sh — phase 10: make (or remove) the cluster on the environment's
# substrate, through that substrate's adapter (driver/substrates/<name>.sh).
#
# Emit + generator, one function each:
#   bash driver/phases/10-substrate.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/10-substrate.sh phase_down <env> <run_dir>   # EMIT
#   bash driver/phases/10-substrate.sh phase_check <env> <run_dir>  # GENERATOR
#   bash driver/phases/10-substrate.sh phase_check_down <env> <run_dir>
# The driver calls these; run them by hand to see one phase's commands.
#
# Inputs: env/<env>.env (BRZL_SUBSTRATE, BRZL_SECRET_STORE and the adapters'
# values). Output for later phases: <run_dir>/kubeconfig; on first start the
# secret store's trust files in BRZL_SECRET_STORE_DIR (driver/secret-stores/).
# No credentials for k3d.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

phase_locus() { printf '%s\n' driver; }

phase_up() {
  local env="$1" run_dir="$2"
  phase_init "$env" || end_function "$?" 'environment definition'
  phase_header "$run_dir"
  phase_error_definition
  substrate_network_up
  if [[ -n "${BRZL_SECRET_STORE:-}" ]]; then
    # Before the cluster: k3d writes the network's members into CoreDNS when it
    # makes the cluster, so the store must exist first (as Zot must).
    secret_store_up
  fi
  substrate_up "$run_dir"
  end_function 0 "emitted 10-substrate up ($BRZL_SUBSTRATE${BRZL_SECRET_STORE:+ + $BRZL_SECRET_STORE})"
}

phase_down() {
  local env="$1" run_dir="$2"
  phase_init "$env" || end_function "$?" 'environment definition'
  phase_header "$run_dir"
  substrate_down
  end_function 0 "emitted 10-substrate down ($BRZL_SUBSTRATE)"
}

phase_check() {
  local env="$1" run_dir="$2" rc=0
  phase_init "$env" || return 1
  if [[ -n "${BRZL_SECRET_STORE:-}" ]]; then
    secret_store_check || rc=1
  fi
  substrate_check "$run_dir" || rc=1
  return "$rc"
}

phase_check_down() {
  local env="$1"
  phase_init "$env" || return 1
  substrate_check_down
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,13p' "${BASH_SOURCE[0]}"; fi
fi
