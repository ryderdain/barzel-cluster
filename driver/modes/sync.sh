#!/usr/bin/env bash
# sync.sh — the sync switch (GLOSSARY, ADR-0025, docs/LOCAL.md "Sync off and
# on"): Argo CD's automated sync for the whole environment, off or on, and
# `apply`, which puts the working tree into the cluster while it is off. The
# driver's `sync off`, `sync on` and `apply` actions call this script; it
# writes run sheets, the driver runs them at its own locus with the
# cluster-admin kubeconfig.
#
#   bash driver/modes/sync.sh sync_switch <off|on> <env> <run_dir> [confirm]  # EMIT a run sheet
#   bash driver/modes/sync.sh sync_check <off|on> <env> <run_dir>             # GENERATOR
#   bash driver/modes/sync.sh apply <env> <run_dir>                           # EMIT a run sheet
#
# The switch is one annotation on the cluster Secret, brzl.dev/auto-sync
# ("false" = off). The platform ApplicationSet reads it and renders every
# Application with or without automated sync (ADR-0025); nothing in git
# changes. Break-glass mode (ADR-0037) moves the same switch: `hold` turns
# sync off with a record and the elevation, `release` turns it on again. So
# these actions refuse while a hold is on: `sync on` would end the hold
# without its record.
#
# sync on: lists each Application that differs from git, with Argo CD's diff
# (the CLI in core mode), and stops while any differ (Q225): commit and push
# the change to the branch Argo CD follows, or accept the undo with
# `confirm`. `release` runs the same check (differences_from_git,
# driver/lib/phase-common.sh).
#
# apply: at emit time, Argo CD's own diff of the working tree against the
# cluster for each kustomize Application (`argocd app diff --local`, Q224);
# the run sheet then syncs each Application that differs (`argocd app sync
# --local`): Argo CD renders the tree with the Application's own images and
# patches, and writes its own tracking marks. The example app renders from
# its checkout beside this repo (BRZL_EXAMPLE_APP_SRC, ADR-0034). The helm
# Applications change only through a pushed branch (Q58). While sync is on,
# apply prints the diff and stops (Q226): Argo CD refuses a local sync then,
# and self-heal would undo it. No prune: an object removed from the working
# tree stays until `sync on`.
#
# What these print on stderr is the record: the driver keeps it in the run
# output beside the run sheet, which goes to the admin log store (ADR-0027).
# Only for an environment whose definition sets BRZL_SYNC_SWITCH_ALLOWED=true
# (local). Inputs: <run_dir>/kubeconfig; the live cluster Secret and
# Applications; the working tree. Needs kubectl, jq, yq, argocd (kiesei). No
# credentials beyond the cluster-admin kubeconfig.

# shellcheck disable=SC2016  # the emitted text names variables for the run sheet to expand
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

appset_file=gitops/platform/applicationset.yaml
# The platform's own repo, as the ApplicationSet names it; any other repoURL
# is a workload's (ADR-0034).
platform_repo=git@github.com:ryderdain/barzel-cluster.git

sync_init() {
  local env="$1" run_dir="$2"
  phase_init "$env" || return 1
  if [[ "${BRZL_SYNC_SWITCH_ALLOWED:-}" != true ]]; then
    printf 'error: the sync switch is only for the local environment (env/%s.env has no BRZL_SYNC_SWITCH_ALLOWED=true); for an emergency use hold (docs/BREAK-GLASS.md)\n' "$env" >&2
    return 2
  fi
  if [[ ! -s "$run_dir/kubeconfig" ]]; then
    printf 'error: no kubeconfig in %s; bring the environment up first\n' "$run_dir" >&2
    return 1
  fi
  export KUBECONFIG="$run_dir/kubeconfig"
  secret="brzl-$env-in-cluster"
}

# annotation <name> — GENERATOR: one annotation of the cluster Secret (empty
# when absent); fails when the Secret cannot be read.
annotation() {
  kubectl -n argocd get secret "$secret" -o json | jq -r --arg k "$1" '.metadata.annotations[$k] // empty'
}

# not_in_hold <env> — the sync switch and break-glass mode share one switch,
# so these actions refuse while a hold is on (docs/BREAK-GLASS.md).
not_in_hold() {
  local env="$1" record
  record="$(annotation brzl.dev/break-glass)" || return 1
  if [[ -n "$record" ]]; then
    printf 'error: a break-glass hold is on (%s); the sync switch is its. End the hold first: bash driver/driver.sh %s release\n' \
      "$record" "$env" >&2
    return 3
  fi
}

sync_switch() {
  local state="$1" env="$2" run_dir="$3" confirm="${4:-}" value summary rc
  case "$state" in
    off) value=false ;;
    on) value=true ;;
    *) printf 'usage: sync.sh sync_switch <off|on> <env> <run_dir> [confirm]\n' >&2; return 2 ;;
  esac
  if [[ -n "$confirm" && ( "$state" != on || "$confirm" != confirm ) ]]; then
    printf 'usage: sync.sh sync_switch <off|on> <env> <run_dir> [confirm]\n' >&2
    return 2
  fi
  sync_init "$env" "$run_dir" || end_function "$?" 'sync switch'
  not_in_hold "$env" || end_function "$?" 'break-glass hold'
  if [[ "$state" == on ]]; then
    # The safety for a kept change (Q225): nothing goes back to git by
    # accident. What differs is on stderr, the record.
    summary="$(differences_from_git)"; rc=$?
    (( rc == 2 )) && end_function 2 'could not prepare the kubeconfig for argocd --core'
    printf '\nsync on: %s confirm=%s\n' "$summary" "${confirm:-no}" >&2
    if (( rc )) && [[ -z "$confirm" ]]; then
      printf 'error: sync on stops while an Application differs from git (above). Commit and push each change to the branch Argo CD follows and run sync on again, or accept the undo: bash driver/driver.sh %s sync on confirm\n' "$env" >&2
      end_function 3 'differences from git'
      return 3
    fi
  fi
  phase_header "$run_dir"
  if [[ "$state" == off ]]; then
    printf '{ # sync OFF: no automated sync for any Application; the working tree can be applied\n'
  else
    printf '{ # sync ON: Argo CD syncs again, back to the pushed branch (an unpushed change goes away)\n'
    printf '  printf '\''%%s\\n'\'' %s\n' "$(squote "sync on: $summary confirm=${confirm:-no}")"
  fi
  printf '  kubectl -n argocd annotate --overwrite secret %q %q\n' "$secret" "brzl.dev/auto-sync=$value"
  printf '}\n'
  end_function 0 "emitted sync $state"
}

# sync_check <off|on> — GENERATOR: waits up to 90 s for the ApplicationSet to
# render every Application without (off) or with (on) automated sync.
sync_check() {
  local state="$1" env="$2" run_dir="$3" counts want=all
  sync_init "$env" "$run_dir" || return "$?"
  [[ "$state" == off ]] && want=none
  if counts="$(auto_sync_wait "$want")"; then
    printf 'sync is %s: %s Applications sync automatically\n' "$state" "$counts"
    return 0
  fi
  printf 'fix: after 90 s, %s Applications still sync automatically; see: kubectl -n argocd describe applicationset brzl-platform\n' \
    "$counts" >&2
  return 1
}

# local_source <application-json> — GENERATOR: prints "<path> <root>", where
# the working tree of the Application's source is <root>/<path>: this repo
# for the platform repo, the example app's checkout for any other.
local_source() {
  local app_json="$1" path repo root=.
  path="$(jq -r '.spec.source.path' <<< "$app_json")" || return 1
  repo="$(jq -r '.spec.source.repoURL' <<< "$app_json")" || return 1
  if [[ "$repo" != "$platform_repo" ]]; then
    root="$BRZL_EXAMPLE_APP_SRC"
    if [[ ! -d "$repo_root/$root/$path" ]]; then
      printf 'error: %s renders from %s, but %s/%s is not a directory (clone the example app beside this repo)\n' \
        "$(jq -r '.metadata.name' <<< "$app_json")" "$repo" "$root" "$path" >&2
      return 1
    fi
  fi
  printf '%s %s' "$path" "$root"
}

apply() {
  local env="$1" run_dir="$2" auto kc app app_json path root diff rc differing=()
  sync_init "$env" "$run_dir" || end_function "$?" 'apply'
  not_in_hold "$env" || end_function "$?" 'break-glass hold'
  auto="$(annotation brzl.dev/auto-sync)" || end_function "$?" "cluster Secret $secret"
  kc="$(argocd_core_kubeconfig)" || end_function "$?" 'could not prepare the kubeconfig for argocd --core'
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    app_json="$(kubectl -n argocd get application "$app" -o json)" || { rm -f "$kc"; end_function "$?" "Application $app"; }
    read -r path root <<< "$(local_source "$app_json")" || { rm -f "$kc"; end_function 1 "the working tree of $app"; }
    diff="$(cd "$repo_root/$root" && KUBECONFIG="$kc" timeout 120 argocd app diff "$app" --core \
      --local "$path" --local-repo-root . < /dev/null 2>&1 | grep -v '^Warning: local diff')"
    rc="${PIPESTATUS[0]}"
    case "$rc" in
      0) ;;
      1) differing+=("$app"); printf '\n=== %s: the working tree differs from the cluster:\n%s\n' "$app" "$diff" >&2 ;;
      *) rm -f "$kc"
         printf '\n=== %s: no diff (argocd exit %s):\n%s\n' "$app" "$rc" "$diff" >&2
         end_function 1 "could not diff $app"; return 1 ;;
    esac
  done < <(yq '.. | select(type == "!!map" and .kind == "kustomize" and has("appName")) | .appName' "$repo_root/$appset_file")
  rm -f "$kc"
  printf '\napply: differing=%s sync=%s\n' "${differing[*]:-none}" "$([[ "$auto" == false ]] && printf off || printf on)" >&2
  if [[ "$auto" != false ]]; then
    printf 'error: sync is on, so Argo CD would refuse the local sync and self-heal would undo it; nothing changed. Run first: bash driver/driver.sh %s sync off, then apply again\n' "$env" >&2
    end_function 3 'sync is on'
    return 3
  fi
  phase_header "$run_dir"
  if (( ${#differing[@]} == 0 )); then
    printf '{ # nothing to apply: the working tree and the cluster agree\n  printf '\''apply: nothing differs\\n'\''\n}\n'
    end_function 0 'emitted apply (nothing differs)'
    return 0
  fi
  printf '{ # a kubeconfig for argocd --core: its context names the namespace argocd (a copy in /tmp)\n'
  printf '  kc="$(mktemp)"; kubectl config view --raw > "$kc"; KUBECONFIG="$kc" kubectl config set-context --current --namespace argocd >/dev/null\n'
  printf '}\n'
  for app in "${differing[@]}"; do
    app_json="$(kubectl -n argocd get application "$app" -o json)" || end_function "$?" "Application $app"
    read -r path root <<< "$(local_source "$app_json")" || end_function 1 "the working tree of $app"
    printf '{ # %s from the working tree (Argo CD renders it with the Application'"'"'s images and patches)\n' "$app"
    printf '  ( cd %q && KUBECONFIG="$kc" argocd app sync %q --core --local %q --local-repo-root . < /dev/null )\n' \
      "$root" "$app" "$path"
    printf '}\n'
  done
  printf '{ # the copy goes\n  rm -f "$kc"\n}\n'
  end_function 0 'emitted apply'
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,42p' "${BASH_SOURCE[0]}"; fi
fi
