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
# Inputs: env/<env>.env (BRZL_SUBSTRATE and the adapter's values). Output for
# later phases: <run_dir>/kubeconfig. No credentials for k3d.

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
  substrate_up "$run_dir"
  end_function 0 "emitted 10-substrate up ($BRZL_SUBSTRATE)"
}

phase_down() {
  local env="$1" run_dir="$2"
  phase_init "$env" || end_function "$?" 'environment definition'
  phase_header "$run_dir"
  substrate_down
  end_function 0 "emitted 10-substrate down ($BRZL_SUBSTRATE)"
}

phase_check() {
  local env="$1" run_dir="$2"
  phase_init "$env" || return 1
  substrate_check "$run_dir"
}

phase_check_down() {
  local env="$1"
  phase_init "$env" || return 1
  substrate_check_down
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,13p' "${BASH_SOURCE[0]}"; fi
fi
