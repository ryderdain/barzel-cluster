#!/usr/bin/env bash
# phase-common.sh — what every phase script in driver/phases/ shares. Not an
# action script; `source` it from one, after runlib.sh.
#
#   phase_init <env>          load env/<env>.env and the substrate adapter it names
#   phase_header <run_dir>    print the top of a run-log: the resolved inputs and
#                             the kubeconfig the later commands use
#
# Paths are relative to the repo root: the driver's stream starts with `cd` to it.
# The sourcing phase script sets repo_root.
# shellcheck disable=SC2154

phase_init() {
  local env="$1"
  if [[ -z "$env" ]]; then
    printf 'error: no environment given (e.g. local)\n' >&2
    return 2
  fi
  load_env_definition "$repo_root/env/$env.env" || return 1
  if [[ ! -r "$repo_root/driver/substrates/$BRZL_SUBSTRATE.sh" ]]; then
    printf 'error: no substrate adapter for BRZL_SUBSTRATE=%s\n' "$BRZL_SUBSTRATE" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$repo_root/driver/substrates/$BRZL_SUBSTRATE.sh"
}

phase_header() {
  local run_dir="$1"
  printf '# resolved environment definition:\n'
  env_definition_record
  printf 'export KUBECONFIG=%q\n' "$run_dir/kubeconfig"
}
