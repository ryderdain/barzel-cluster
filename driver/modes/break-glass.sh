#!/usr/bin/env bash
# break-glass.sh — break-glass mode (GLOSSARY, ADR-0037, ADR-0038,
# docs/BREAK-GLASS.md): the recorded exception to GitOps, in any environment.
# `open` stops automated sync for the whole environment (the sync switch,
# ADR-0025) and gives the team brzl-admins cluster-admin; `apply` puts a
# source tree into the cluster while it is open (local); `close` gives the
# cluster back to git. The driver's break-glass verbs call this script; it
# writes run sheets, the driver runs them at its own locus with the
# cluster-admin kubeconfig.
#
#   bash driver/modes/break-glass.sh open <env> <run_dir> <reason> [name]   # EMIT a run sheet
#   bash driver/modes/break-glass.sh open_check <env> <run_dir>             # GENERATOR
#   bash driver/modes/break-glass.sh apply <env> <run_dir> [dir]            # EMIT a run sheet
#   bash driver/modes/break-glass.sh close <env> <run_dir> [confirm]        # EMIT a run sheet
#   bash driver/modes/break-glass.sh close_check <env> <run_dir>            # GENERATOR
#
# open: the person is the one that the kube-API names through sign-on
# (`kubectl auth whoami` with kubeconfig-sign-on), and must be in the team
# brzl-admins. When sign-on does not answer (no session, Dex down; Q201,
# Q241), the record names [name], else the account on the operator's machine
# (BRZL_HOST_USER), as declared: "verified": false. The run sheet writes the
# record on the cluster Secret (brzl.dev/break-glass), sets the sync switch
# (brzl.dev/auto-sync=false), and creates the ClusterRoleBinding
# brzl-break-glass. A binding's roleRef cannot change, so this is a second
# binding beside the standing one (view). One open for each environment: an
# open by another person stops the sheet.
#
# apply: only while the break-glass is open (Q237), and only for an
# environment whose definition sets BRZL_SYNC_SWITCH_ALLOWED=true (local). At
# emit time, Argo CD's own diff of the source tree against the cluster for
# each kustomize Application (`argocd app diff --local`); the run sheet then
# syncs each Application that differs (`argocd app sync --local`): Argo CD
# renders the tree with the Application's own images and patches, and writes
# its own tracking marks. That render edits the kustomization it is given
# (kustomize edit), so both steps work on a copy of the tree, never on the
# tree itself. The platform renders from [dir] (default: this working tree);
# the example app from its checkout beside this repo (BRZL_EXAMPLE_APP_SRC,
# ADR-0034). The helm Applications change only through a pushed branch
# (Q58). No prune: an object removed from the tree stays until close.
#
# close: lists each Application that differs from git, with Argo CD's diff
# (the CLI in core mode, with the cluster-admin kubeconfig;
# differences_from_git, driver/lib/phase-common.sh), and stops while any
# differ (Q200): commit and push the change to the branch Argo CD follows,
# or accept the undo with `confirm`. Then the sheet deletes the binding,
# syncs each kustomize Application from git (after a local sync, Argo CD
# compares against the manifests it last synced until a sync from git, so
# without this step it would heal nothing; no change when git and the
# cluster agree), turns automated sync on and removes the record.
#
# What these print on stderr is the record: the driver keeps it in the run
# output beside the run sheet, which goes to the admin log store (ADR-0027).
# Inputs: env/<env>.env (BRZL_SIGN_ON_ORG, BRZL_SYNC_SWITCH_ALLOWED,
# BRZL_EXAMPLE_APP_SRC); <run_dir>/kubeconfig and <run_dir>/kubeconfig-sign-on;
# the live cluster Secret, Applications and bindings; the source tree. Needs
# kubectl, jq, yq, argocd and kubelogin (kiesei). Credentials: the
# cluster-admin kubeconfig, and the person's own sign-on session.

# shellcheck disable=SC2016  # the emitted text names variables for the run sheet to expand
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

binding=brzl-break-glass
appset_file=gitops/platform/applicationset.yaml
# The platform's own repo, as the ApplicationSet names it; any other repoURL
# is a workload's (ADR-0034).
platform_repo=git@github.com:ryderdain/barzel-cluster.git

bg_init() {
  local env="$1" run_dir="$2"
  phase_init "$env" || return 1
  if [[ -z "${BRZL_SIGN_ON_ORG:-}" ]]; then
    printf 'error: env/%s.env has no BRZL_SIGN_ON_ORG (the GitHub organization of the access tiers)\n' "$env" >&2
    return 2
  fi
  if [[ ! -s "$run_dir/kubeconfig" ]]; then
    printf 'error: no kubeconfig in %s; bring the environment up first\n' "$run_dir" >&2
    return 1
  fi
  export KUBECONFIG="$run_dir/kubeconfig"
  secret="brzl-$env-in-cluster"
  admins="oidc:$BRZL_SIGN_ON_ORG:brzl-admins"
}

# annotation <name> — GENERATOR: one annotation of the cluster Secret (empty
# when absent); fails when the Secret cannot be read.
annotation() {
  kubectl -n argocd get secret "$secret" -o json | jq -r --arg k "$1" '.metadata.annotations[$k] // empty'
}

# kustomize_apps — GENERATOR: the name of each kustomize Application that
# the platform ApplicationSet renders, one per line.
kustomize_apps() {
  yq '.. | select(type == "!!map" and .kind == "kustomize" and has("appName")) | .appName' "$repo_root/$appset_file"
}

# whoami_admin — GENERATOR: the person that sign-on names, when that person
# is in the team brzl-admins. Returns 1 when sign-on does not answer (no
# session, Dex down; kubelogin would wait for a browser, so 30 s at most),
# 3 when the person is not an admin.
whoami_admin() {
  local run_dir="$1" who
  # With no cached session kubelogin prints a URL and waits for the browser,
  # 30 s at most here; its output shows, so the person can open the URL.
  printf 'sign-on: asking the kube-API who you are (when kubelogin prints a URL, open it within 30 s; or sign in first in the kiesei shell)\n' >&2
  who="$(timeout 30 kubectl --kubeconfig "$run_dir/kubeconfig-sign-on" auth whoami -o json < /dev/null)" \
    || return 1
  if ! jq -e --arg g "$admins" '.status.userInfo.groups | index($g)' <<< "$who" >/dev/null; then
    printf 'error: sign-on names you %s, who is not in the team %s; only an admin can open\n' \
      "$(jq -r '.status.userInfo.username' <<< "$who")" "$admins" >&2
    return 3
  fi
  jq -r '.status.userInfo.username' <<< "$who"
}

open() {
  local env="$1" run_dir="$2" reason="${3:-}" declared="${4:-}" current auto person verified=true rc record line
  if [[ -z "$reason" ]]; then
    printf 'usage: break-glass.sh open <env> <run_dir> <reason> [declared name, when sign-on does not answer]\n' >&2
    return 2
  fi
  bg_init "$env" "$run_dir" || end_function "$?" 'break-glass'
  current="$(annotation brzl.dev/break-glass)" || end_function "$?" "cluster Secret $secret"
  auto="$(annotation brzl.dev/auto-sync)" || end_function "$?" "cluster Secret $secret"
  if [[ -z "$current" && "$auto" == false ]]; then
    printf 'note: sync is off with no record (a change by hand); this open takes the switch, and close turns it on\n' >&2
  fi
  person="$(whoami_admin "$run_dir")"
  rc=$?
  if (( rc == 3 )); then
    end_function 3 'not an admin'
    return 3
  elif (( rc != 0 )); then
    # Q241: without sign-on, the record names the declared name, else the
    # account on the operator's machine, as declared, not verified.
    person="${declared:-${BRZL_HOST_USER:-$(id -un)}}"
    verified=false
    printf 'warning: sign-on does not answer (no session, or Dex is down); the record names %s as declared, not verified (docs/BREAK-GLASS.md, "When Dex is down")\n' "$person" >&2
  elif [[ -n "$declared" ]]; then
    printf 'note: sign-on names you %s; the declared name %s is not used\n' "$person" "$declared" >&2
  fi
  if [[ -n "$current" && "$(jq -r '.person' <<< "$current")" != "$person" ]]; then
    printf 'error: the break-glass is open already (%s); one open for each environment. Work in it, or ask the person who opened it to close it\n' "$current" >&2
    end_function 3 'open already'
    return 3
  fi
  if [[ -n "$current" ]]; then
    record="$current"   # your own open: its start stays; this run makes sure that it is complete
    printf 'note: your break-glass is open since %s; this run completes it\n' "$(jq -r '.start' <<< "$current")" >&2
  else
    record="$(jq -cn --arg person "$person" --argjson verified "$verified" \
      --arg start "$(TZ=UTC printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1)" --arg reason "$reason" \
      '{person: $person, verified: $verified, start: $start, reason: $reason}')" || end_function "$?" 'record'
  fi
  line="$(jq -r '"break-glass open: person=\(.person) verified=\(.verified) start=\(.start) reason=\(.reason | @json)"' <<< "$record")"
  printf '%s\n' "$line" >&2
  phase_header "$run_dir"
  phase_error_definition
  printf '{ # the record of this open, in this run output (the admin log store keeps it)\n'
  printf '  printf '\''%%s\\n'\'' %s\n' "$(squote "$line")"
  printf '}\n'
  printf '{ # one open for each environment: stop when another person has it open\n'
  printf '  current="$(kubectl -n argocd get secret %q -o json | jq -r '\''.metadata.annotations["brzl.dev/break-glass"] // empty'\'')" \\\n' "$secret"
  printf '    || error 3 %s\n' "$(squote "could not read the cluster Secret $secret; nothing changed")"
  printf '  [[ -z "$current" || "$(jq -r .person <<< "$current")" == %s ]] \\\n' "$(squote "$person")"
  printf '    || error 3 "the break-glass is open already ($current); nothing changed"\n'
  printf '}\n'
  printf '{ # Argo CD pauses: no automated sync for any Application; the record goes on the cluster Secret\n'
  printf '  kubectl -n argocd annotate --overwrite secret %q brzl.dev/auto-sync=false %s\n' \
    "$secret" "$(squote "brzl.dev/break-glass=$record")"
  printf '}\n'
  printf '{ # the elevation: the team brzl-admins is cluster-admin until close (a second binding; the standing one is view)\n'
  printf "  kubectl apply -f - <<'EOF'\n"
  printf 'apiVersion: rbac.authorization.k8s.io/v1\nkind: ClusterRoleBinding\n'
  printf 'metadata:\n  name: %s\n  labels:\n    brzl.dev/break-glass: "true"\n' "$binding"
  printf 'roleRef:\n  apiGroup: rbac.authorization.k8s.io\n  kind: ClusterRole\n  name: cluster-admin\n'
  printf 'subjects:\n  - kind: Group\n    apiGroup: rbac.authorization.k8s.io\n    name: %s\n' "$admins"
  printf 'EOF\n'
  printf '}\n'
  end_function 0 "emitted break-glass open for $person"
}

# open_check — GENERATOR: the record, the binding, the admins' rights, and
# no Application syncs automatically (waits up to 90 s for the ApplicationSet).
open_check() {
  local env="$1" run_dir="$2" record counts
  bg_init "$env" "$run_dir" || return "$?"
  record="$(annotation brzl.dev/break-glass)" || return 1
  if [[ -z "$record" ]]; then
    printf 'fix: the cluster Secret %s has no record brzl.dev/break-glass; run open again\n' "$secret" >&2
    return 1
  fi
  if [[ "$(kubectl get clusterrolebinding "$binding" -o jsonpath='{.roleRef.name}' 2>/dev/null)" != cluster-admin ]]; then
    printf 'fix: the ClusterRoleBinding %s to cluster-admin is missing; run open again\n' "$binding" >&2
    return 1
  fi
  if [[ "$(kubectl auth can-i '*' '*' --as=oidc:probe --as-group="$admins" 2>/dev/null)" != yes ]]; then
    printf 'fix: the group %s is not cluster-admin; see: kubectl get clusterrolebinding %s -o yaml\n' "$admins" "$binding" >&2
    return 1
  fi
  if ! counts="$(auto_sync_wait none)"; then
    printf 'fix: after 90 s, %s Applications still sync automatically; see: kubectl -n argocd describe applicationset brzl-platform\n' "$counts" >&2
    return 1
  fi
  printf 'break-glass open by %s since %s: Argo CD pauses (%s Applications sync automatically); the team brzl-admins is cluster-admin until close\n' \
    "$(jq -r '.person' <<< "$record")" "$(jq -r '.start' <<< "$record")" "$counts"
}

# local_source <application-json> [dir] — GENERATOR: prints "<path> <root>",
# where the source tree of the Application is <root>/<path>: [dir] (default
# this repo) for the platform repo, the example app's checkout for any
# other. The copy that Argo CD renders is <root>'s first directory of <path>
# (gitops/, deploy/): every kustomize reference stays inside it.
local_source() {
  local app_json="$1" root="${2:-.}" path repo
  path="$(jq -r '.spec.source.path' <<< "$app_json")" || return 1
  repo="$(jq -r '.spec.source.repoURL' <<< "$app_json")" || return 1
  if [[ "$repo" != "$platform_repo" ]]; then
    root="$BRZL_EXAMPLE_APP_SRC"
  fi
  [[ "$root" == /* ]] || root="$repo_root/$root"
  if [[ ! -d "$root/$path" ]]; then
    printf 'error: %s renders from %s, but %s/%s is not a directory\n' \
      "$(jq -r '.metadata.name' <<< "$app_json")" "$repo" "$root" "$path" >&2
    return 1
  fi
  printf '%s %s' "$path" "$root"
}

apply() {
  local env="$1" run_dir="$2" dir="${3:-}" current kc tmp app app_json path root diff rc differing=()
  bg_init "$env" "$run_dir" || end_function "$?" 'apply'
  if [[ "${BRZL_SYNC_SWITCH_ALLOWED:-}" != true ]]; then
    printf 'error: apply is only for the local environment (env/%s.env has no BRZL_SYNC_SWITCH_ALLOWED=true); in an emergency, change the cluster with your own kubectl (docs/BREAK-GLASS.md)\n' "$env" >&2
    end_function 2 'not local'
    return 2
  fi
  if [[ -n "$dir" && ! -d "$dir" ]]; then
    printf 'error: %s is not a directory\n' "$dir" >&2
    end_function 2 'no such directory'
    return 2
  fi
  current="$(annotation brzl.dev/break-glass)" || end_function "$?" "cluster Secret $secret"
  if [[ -z "$current" ]]; then
    printf "error: the break-glass is not open, so Argo CD would refuse the local sync and self-heal would undo it; nothing changed. Open it first: BRZL_ENV=%s bash driver/driver.sh break-glass open '<reason>', then apply again\\n" "$env" >&2
    end_function 3 'not open'
    return 3
  fi
  kc="$(argocd_core_kubeconfig)" || end_function "$?" 'could not prepare the kubeconfig for argocd --core'
  tmp="$(mktemp -d)" || { rm -f "$kc"; end_function 1 'temporary directory'; }
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    app_json="$(kubectl -n argocd get application "$app" -o json)" || { rm -rf "$kc" "$tmp"; end_function "$?" "Application $app"; }
    read -r path root <<< "$(local_source "$app_json" "$dir")" || { rm -rf "$kc" "$tmp"; end_function 1 "the source tree of $app"; }
    mkdir -p "$tmp/$app" && cp -R "$root/${path%%/*}" "$tmp/$app/" \
      || { rm -rf "$kc" "$tmp"; end_function 1 "could not copy the source tree of $app"; }
    diff="$(cd "$tmp/$app" && KUBECONFIG="$kc" timeout 120 argocd app diff "$app" --core \
      --local "$path" --local-repo-root . < /dev/null 2>&1)"
    rc=$?
    diff="$(grep -v '^Warning: local diff' <<< "$diff")"
    case "$rc" in
      0) ;;
      1) differing+=("$app"); printf '\n=== %s: the source tree differs from the cluster:\n%s\n' "$app" "$diff" >&2 ;;
      *) rm -rf "$kc" "$tmp"
         printf '\n=== %s: no diff (argocd exit %s):\n%s\n' "$app" "$rc" "$diff" >&2
         end_function 1 "could not diff $app"; return 1 ;;
    esac
  done < <(kustomize_apps)
  rm -rf "$kc" "$tmp"
  printf '\napply: source=%s differing=%s open=%s\n' "${dir:-working-tree}" "${differing[*]:-none}" "$current" >&2
  phase_header "$run_dir"
  phase_error_definition
  if (( ${#differing[@]} == 0 )); then
    printf '{ # nothing to apply: the source tree and the cluster agree\n'
    printf '  printf '\''apply: nothing differs\\n'\''\n'
    printf '}\n'
    end_function 0 'emitted apply (nothing differs)'
    return 0
  fi
  printf '{ # a kubeconfig for argocd --core: its context names the namespace argocd (a copy in /tmp)\n'
  printf '  kc="$(mktemp)"\n'
  printf '  kubectl config view --raw > "$kc"\n'
  printf '  KUBECONFIG="$kc" kubectl config set-context --current --namespace argocd >/dev/null\n'
  printf '}\n'
  for app in "${differing[@]}"; do
    app_json="$(kubectl -n argocd get application "$app" -o json)" || end_function "$?" "Application $app"
    read -r path root <<< "$(local_source "$app_json" "$dir")" || end_function 1 "the source tree of $app"
    printf '{ # %s from the source tree: a copy of %s (Argo CD edits the kustomization it renders), with the Application'"'"'s images and patches\n' \
      "$app" "$root/${path%%/*}"
    printf '  d="$(mktemp -d)"\n'
    printf '  cp -R %q "$d/"\n' "$root/${path%%/*}"
    printf '  (\n'
    printf '    cd "$d" || exit 1\n'
    printf '    KUBECONFIG="$kc" argocd app sync %q --core --local %q --local-repo-root . < /dev/null\n' "$app" "$path"
    printf '  ) || error 3 %s\n' "$(squote "$app did not sync (break-glass stays open); read above, fix, then apply again")"
    printf '  rm -rf "$d"\n'
    printf '}\n'
  done
  printf '{ # the copy goes\n  rm -f "$kc"\n}\n'
  end_function 0 'emitted apply'
}

close() {
  local env="$1" run_dir="$2" confirm="${3:-}" current closer summary rc app
  if [[ -n "$confirm" && "$confirm" != confirm ]]; then
    printf 'usage: break-glass.sh close <env> <run_dir> [confirm]\n' >&2
    return 2
  fi
  bg_init "$env" "$run_dir" || end_function "$?" 'break-glass'
  current="$(annotation brzl.dev/break-glass)" || end_function "$?" "cluster Secret $secret"
  if [[ -z "$current" ]] && ! kubectl get clusterrolebinding "$binding" >/dev/null 2>&1; then
    printf 'error: the break-glass of %s is not open (no record on the cluster Secret, no binding %s)\n' "$env" "$binding" >&2
    end_function 3 'not open'
    return 3
  fi
  # Who closes: any person whom sign-on names (the driver acts with the
  # cluster-admin kubeconfig either way); without sign-on, not verified.
  printf 'sign-on: asking the kube-API who you are (when kubelogin prints a URL, open it within 30 s)\n' >&2
  closer="$(timeout 30 kubectl --kubeconfig "$run_dir/kubeconfig-sign-on" auth whoami \
    -o jsonpath='{.status.userInfo.username}' < /dev/null)" || closer=''
  [[ -n "$closer" ]] || closer='not-verified(no-sign-on)'
  # The differences from git (Q200): Argo CD's own diff in core mode on
  # stderr (the record).
  summary="$(differences_from_git)"; rc=$?
  (( rc == 2 )) && end_function 2 'could not prepare the kubeconfig for argocd --core'
  printf '\nbreak-glass close: by=%s open=%s %s confirm=%s\n' \
    "$closer" "$current" "$summary" "${confirm:-no}" >&2
  if (( rc )) && [[ -z "$confirm" ]]; then
    printf 'error: close stops while an Application differs from git (above). Commit and push each change to the branch Argo CD follows and run close again, or accept the undo: BRZL_ENV=%s bash driver/driver.sh break-glass close confirm\n' "$env" >&2
    end_function 3 'differences from git'
    return 3
  fi
  phase_header "$run_dir"
  phase_error_definition
  printf '{ # the record of this close, in this run output (the admin log store keeps it)\n'
  printf '  printf '\''%%s\\n'\'' %s\n' "$(squote "break-glass close: by=$closer $summary confirm=${confirm:-no} open=$current")"
  printf '}\n'
  printf '{ # the elevation ends: the team brzl-admins is back to view\n'
  printf '  kubectl delete clusterrolebinding %q --ignore-not-found\n' "$binding"
  printf '}\n'
  printf '{ # a kubeconfig for argocd --core: its context names the namespace argocd (a copy in /tmp)\n'
  printf '  kc="$(mktemp)"\n'
  printf '  kubectl config view --raw > "$kc"\n'
  printf '  KUBECONFIG="$kc" kubectl config set-context --current --namespace argocd >/dev/null\n'
  printf '}\n'
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    printf '{ # %s from git again (after a local sync Argo CD compares against what it last synced; no change when git and the cluster agree)\n' "$app"
    printf '  KUBECONFIG="$kc" argocd app sync %q --core < /dev/null \\\n' "$app"
    printf '    || error 3 %s\n' "$(squote "$app did not sync from git (break-glass stays open); read above, then run close again")"
    printf '}\n'
  done < <(kustomize_apps)
  printf '{ # the copy goes; Argo CD syncs again and puts git back over each difference; the record ends\n'
  printf '  rm -f "$kc"\n'
  printf '  kubectl -n argocd annotate --overwrite secret %q brzl.dev/auto-sync=true brzl.dev/break-glass-\n' "$secret"
  printf '}\n'
  end_function 0 'emitted break-glass close'
}

# close_check — GENERATOR: no record, no binding, the admins back to view,
# and every Application syncs automatically (waits up to 90 s).
close_check() {
  local env="$1" run_dir="$2" counts
  bg_init "$env" "$run_dir" || return "$?"
  if [[ -n "$(annotation brzl.dev/break-glass)" ]]; then
    printf 'fix: the cluster Secret %s still has the record brzl.dev/break-glass; run close again\n' "$secret" >&2
    return 1
  fi
  if kubectl get clusterrolebinding "$binding" >/dev/null 2>&1; then
    printf 'fix: the ClusterRoleBinding %s still exists; run close again\n' "$binding" >&2
    return 1
  fi
  if [[ "$(kubectl auth can-i create pods --as=oidc:probe --as-group="$admins" 2>/dev/null)" != no ]]; then
    printf 'fix: the group %s can still write; see: kubectl get clusterrolebindings -o wide | grep brzl-admins\n' "$admins" >&2
    return 1
  fi
  if ! counts="$(auto_sync_wait all)"; then
    printf 'fix: after 90 s, only %s Applications sync automatically; see: kubectl -n argocd describe applicationset brzl-platform\n' "$counts" >&2
    return 1
  fi
  printf 'break-glass closed: Argo CD syncs again (%s Applications), and the team brzl-admins has view\n' "$counts"
  # The review (Q203): part of the incident's analysis, after normal
  # operations return. Where its records are, in Grafana's Explore.
  printf 'the review: Grafana, Explore, data source "Admin log store", the time it was open:\n'
  printf '  {brzl_source="run-output", brzl_phase=~"break-glass-.*"}\n'
  printf '  {brzl_source="api-audit"} | json | user_username=~"oidc:.*" | verb=~"create|update|patch|delete|deletecollection"\n'
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,52p' "${BASH_SOURCE[0]}"; fi
fi
