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
#   operator_step <why> <command>...
#                             print, on stderr, a step the operator must do by
#                             hand on their own machine, in a block that stands
#                             out from tool output; one command per argument
#   host_os                   print the operating system of the driver's
#                             machine: BRZL_HOST_OS when set (driver/kiesei.sh
#                             sets it, because inside the container uname says
#                             Linux), else uname
#   auto_sync_wait <none|all> wait up to 90 s until the ApplicationSet renders
#                             no (none) or every (all) Application with
#                             automated sync (the sync switch, ADR-0025;
#                             driver/modes/sync.sh and break-glass.sh); print
#                             "<automated> of <total>"; return 1 on timeout
#   argocd_core_kubeconfig    print the path of a copy of the current kubeconfig
#                             whose context names the namespace argocd, which
#                             `argocd --core` needs; the caller removes it
#   differences_from_git      Argo CD's diff, in core mode, of every Application
#                             after a refresh (after a local sync, the status
#                             says Synced until the next compare), on stderr
#                             (the record); print
#                             "differing=<names|none> no_diff=<names|none>";
#                             return 0 when every Application agrees with git,
#                             1 when any differs or gave no diff, 2 on a failure
#                             to prepare the kubeconfig
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

operator_step() {
  local why="$1" command
  shift
  {
    printf '\n'
    printf '╔═ ONE-TIME STEP ON YOUR MACHINE (%s) ═══════════════════════════════\n' "$(host_os)"
    printf '║ %s\n' "$why"
    for command in "$@"; do printf '║   %s\n' "$command"; done
    printf '╚══════════════════════════════════════════════════════════════════════\n'
    printf '\n'
  } >&2
}

# squote <text> — single-quote text for an emitted stream, readably (plain
# POSIX quoting, unlike printf %q's backslashes). driver.sh has the same.
squote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

host_os() {
  if [[ -n "${BRZL_HOST_OS:-}" ]]; then printf '%s' "$BRZL_HOST_OS"; else uname; fi
}

auto_sync_wait() {
  local want="$1" waited=0 apps automated='?' total='?'
  while (( waited <= 90 )); do
    if apps="$(kubectl -n argocd get applications -o json)"; then
      automated="$(jq '[.items[] | select(.spec.syncPolicy.automated != null)] | length' <<< "$apps")"
      total="$(jq '.items | length' <<< "$apps")"
      if [[ "$want" == none && "$automated" == 0 ]] || [[ "$want" == all && "$automated" == "$total" ]]; then
        printf '%s of %s' "$automated" "$total"
        return 0
      fi
    fi
    sleep 5
    waited=$(( waited + 5 ))
  done
  printf '%s of %s' "$automated" "$total"
  return 1
}

argocd_core_kubeconfig() {
  local kc
  kc="$(mktemp)" || return 1
  if ! kubectl config view --raw > "$kc" || ! KUBECONFIG="$kc" kubectl config set-context --current --namespace argocd >/dev/null; then
    rm -f "$kc"
    return 1
  fi
  printf '%s' "$kc"
}

# The safety for a kept change (Q200, Q225): `release` and `sync on` stop
# while an Application differs from git, and show what Argo CD would put
# back.
differences_from_git() {
  local kc app diff rc differing=() unknown=()
  kc="$(argocd_core_kubeconfig)" || return 2
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    diff="$(KUBECONFIG="$kc" timeout 120 argocd app diff "$app" --core --refresh < /dev/null 2>&1)"
    rc=$?
    case "$rc" in
      0) ;;
      1) differing+=("$app")
         printf '\n=== %s differs from git (Argo CD would put git back):\n%s\n' "$app" "$diff" >&2 ;;
      *) unknown+=("$app")
         printf '\n=== %s: no diff (argocd exit %s):\n%s\n' "$app" "$rc" "$diff" >&2 ;;
    esac
  done < <(kubectl -n argocd get applications -o json | jq -r '.items[].metadata.name')
  rm -f "$kc"
  printf 'differing=%s no_diff=%s' "${differing[*]:-none}" "${unknown[*]:-none}"
  (( ${#differing[@]} + ${#unknown[@]} == 0 ))
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
