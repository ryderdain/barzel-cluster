#!/usr/bin/env bash
# phase-common.sh — what every phase script in driver/phases/ shares. Not an
# action script; `source` it from one, after runlib.sh.
#
#   phase_init <env>          load env/<env>.env, the substrate adapter it names,
#                             and the secret-store adapter (BRZL_SECRET_STORE), if any
#   phase_header <run_dir> [locus]
#                             print the top of a run sheet: the resolved inputs,
#                             and for the driver locus the kubeconfig to use (a
#                             conductor run sheet uses its in-cluster account)
#   gitops_repo_url           print the git repo URL that the platform
#                             ApplicationSet follows (its one home)
#   phase_error_definition    print the error() function (driver/lib/error.sh)
#                             for a run sheet that stops itself with `error 3`
#                             (a run sheet runs as its own process, so it needs
#                             its own copy; STYLE.md §1.2)
#
# Each phase script also defines phase_locus, which prints `driver` or
# `conductor`; the driver reads it to choose how to run the phase.
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
  source "$repo_root/driver/substrates/$BRZL_SUBSTRATE.sh" || return 1
  [[ -n "${BRZL_SECRET_STORE:-}" ]] || return 0
  if [[ ! -r "$repo_root/driver/secret-stores/$BRZL_SECRET_STORE.sh" ]]; then
    printf 'error: no secret-store adapter for BRZL_SECRET_STORE=%s\n' "$BRZL_SECRET_STORE" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$repo_root/driver/secret-stores/$BRZL_SECRET_STORE.sh"
}

phase_header() {
  local run_dir="$1" locus="${2:-driver}"
  printf '# resolved environment definition:\n'
  env_definition_record
  if [[ "$locus" == conductor ]]; then
    printf '# locus: conductor (in-cluster service account)\n'
  else
    printf '# locus: driver\n'
    printf 'export KUBECONFIG=%q\n' "$run_dir/kubeconfig"
  fi
}

phase_error_definition() {
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
}

gitops_repo_url() {
  local line
  while IFS= read -r line; do
    if [[ "$line" =~ repoURL:\ (git@[^[:space:]]+) ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done < "$repo_root/gitops/platform/applicationset.yaml"
  printf 'error: no git repoURL in gitops/platform/applicationset.yaml\n' >&2
  return 1
}
