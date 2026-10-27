#!/usr/bin/env bash
# break-glass.sh — break-glass mode (GLOSSARY, ADR-0037, docs/BREAK-GLASS.md):
# the recorded exception to GitOps, for an emergency in any environment.
# `hold` stops automated sync for the whole environment and gives the team
# brzl-admins cluster-admin; `release` gives the cluster back to git. The
# driver's hold / release actions call this script; it writes run sheets, the
# driver runs them at its own locus with the cluster-admin kubeconfig.
#
#   bash driver/modes/break-glass.sh hold <env> <run_dir> <reason> [name]   # EMIT a run sheet
#   bash driver/modes/break-glass.sh hold_check <env> <run_dir>             # GENERATOR
#   bash driver/modes/break-glass.sh release <env> <run_dir> [confirm]      # EMIT a run sheet
#   bash driver/modes/break-glass.sh release_check <env> <run_dir>          # GENERATOR
#
# hold: the person is the one that the kube-API names through sign-on
# (`kubectl auth whoami` with kubeconfig-sign-on), and must be in the team
# brzl-admins. When sign-on does not answer (Dex down, Q201), [name] is the
# person's declared name, and the record says "verified": false. The run
# sheet writes the record on the cluster Secret (brzl.dev/break-glass), sets
# the switch that fast mode also uses (brzl.dev/auto-sync=false, ADR-0025),
# and creates the ClusterRoleBinding brzl-break-glass. A binding's roleRef
# cannot change, so this is a second binding beside the standing one (view).
# One hold for each environment: a hold by another person stops the sheet.
#
# release: lists each Application that differs from git, with Argo CD's diff
# (the CLI in core mode, with the cluster-admin kubeconfig), and stops while
# any differ (Q200). Commit the change to the branch Argo CD follows, or
# accept the undo with `confirm`. Then the sheet deletes the binding, turns
# automated sync on and removes the record, in that order.
#
# What these print on stderr is the record: the driver keeps it in the run
# output beside the run sheet, which goes to the admin log store (ADR-0027).
# Inputs: env/<env>.env (BRZL_SIGN_ON_ORG); <run_dir>/kubeconfig and
# <run_dir>/kubeconfig-sign-on; the live cluster Secret, Applications and
# bindings. Needs kubectl, jq, argocd and kubelogin (kiesei). Credentials:
# the cluster-admin kubeconfig, and the person's own sign-on session.

# shellcheck disable=SC2016  # the emitted text names variables for the run sheet to expand
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

binding=brzl-break-glass

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

# whoami_admin — GENERATOR: the person that sign-on names, when that person
# is in the team brzl-admins. Returns 1 when sign-on does not answer (no
# session, Dex down; kubelogin would wait for a browser, so 30 s at most),
# 3 when the person is not an admin.
whoami_admin() {
  local run_dir="$1" who
  who="$(timeout 30 kubectl --kubeconfig "$run_dir/kubeconfig-sign-on" auth whoami -o json < /dev/null 2>/dev/null)" \
    || return 1
  if ! jq -e --arg g "$admins" '.status.userInfo.groups | index($g)' <<< "$who" >/dev/null; then
    printf 'error: sign-on names you %s, who is not in the team %s; only an admin can hold\n' \
      "$(jq -r '.status.userInfo.username' <<< "$who")" "$admins" >&2
    return 3
  fi
  jq -r '.status.userInfo.username' <<< "$who"
}

hold() {
  local env="$1" run_dir="$2" reason="${3:-}" declared="${4:-}" current auto person verified=true rc record line
  if [[ -z "$reason" ]]; then
    printf 'usage: break-glass.sh hold <env> <run_dir> <reason> [declared name, only when Dex is down]\n' >&2
    return 2
  fi
  bg_init "$env" "$run_dir" || end_function "$?" 'break-glass'
  current="$(annotation brzl.dev/break-glass)" || end_function "$?" "cluster Secret $secret"
  auto="$(annotation brzl.dev/auto-sync)" || end_function "$?" "cluster Secret $secret"
  if [[ -z "$current" && "$auto" == false ]]; then
    printf 'error: fast mode is on, and a hold would take over its switch. Commit what fast mode applied, then: bash driver/driver.sh %s fast_off (unpushed fast-mode changes go away), then hold\n' "$env" >&2
    end_function 3 'fast mode is on'
    return 3
  fi
  person="$(whoami_admin "$run_dir")"
  rc=$?
  if (( rc == 3 )); then
    end_function 3 'not an admin'
    return 3
  elif (( rc != 0 )) && [[ -z "$declared" ]]; then
    printf 'error: sign-on does not name you (no session, or Dex is down). Sign in first in the kiesei shell (kubectl auth whoami). When Dex is down, give your name after the reason: hold %s <your name>\n' \
      "$(squote "$reason")" >&2
    end_function 3 'no sign-on'
    return 3
  elif (( rc != 0 )); then
    person="$declared"
    verified=false
    printf 'warning: sign-on does not answer; the record names %s as declared, not verified (docs/BREAK-GLASS.md, "When Dex is down")\n' "$person" >&2
  elif [[ -n "$declared" ]]; then
    printf 'note: sign-on names you %s; the declared name %s is not used\n' "$person" "$declared" >&2
  fi
  if [[ -n "$current" && "$(jq -r '.person' <<< "$current")" != "$person" ]]; then
    printf 'error: a hold exists already (%s); one hold for each environment. Work in it, or ask its holder to release it\n' "$current" >&2
    end_function 3 'a hold exists'
    return 3
  fi
  if [[ -n "$current" ]]; then
    record="$current"   # your own hold: its start stays; this run makes sure that it is complete
    printf 'note: your hold exists since %s; this run completes it\n' "$(jq -r '.start' <<< "$current")" >&2
  else
    record="$(jq -cn --arg person "$person" --argjson verified "$verified" \
      --arg start "$(TZ=UTC printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1)" --arg reason "$reason" \
      '{person: $person, verified: $verified, start: $start, reason: $reason}')" || end_function "$?" 'record'
  fi
  line="$(jq -r '"break-glass hold: person=\(.person) verified=\(.verified) start=\(.start) reason=\(.reason | @json)"' <<< "$record")"
  printf '%s\n' "$line" >&2
  phase_header "$run_dir"
  phase_error_definition
  printf '{ # the record of this hold, in this run output (the admin log store keeps it)\n'
  printf '  printf '\''%%s\\n'\'' %s\n' "$(squote "$line")"
  printf '}\n'
  printf '{ # one hold for each environment: stop when another person holds\n'
  printf '  current="$(kubectl -n argocd get secret %q -o json | jq -r '\''.metadata.annotations["brzl.dev/break-glass"] // empty'\'')" \\\n' "$secret"
  printf '    || error 3 %s\n' "$(squote "could not read the cluster Secret $secret; nothing changed")"
  printf '  [[ -z "$current" || "$(jq -r .person <<< "$current")" == %s ]] \\\n' "$(squote "$person")"
  printf '    || error 3 "a hold exists already ($current); nothing changed"\n'
  printf '}\n'
  printf '{ # Argo CD holds: no automated sync for any Application; the record goes on the cluster Secret\n'
  printf '  kubectl -n argocd annotate --overwrite secret %q brzl.dev/auto-sync=false %s\n' \
    "$secret" "$(squote "brzl.dev/break-glass=$record")"
  printf '}\n'
  printf '{ # the elevation: the team brzl-admins is cluster-admin until release (a second binding; the standing one is view)\n'
  printf "  kubectl apply -f - <<'EOF'\n"
  printf 'apiVersion: rbac.authorization.k8s.io/v1\nkind: ClusterRoleBinding\n'
  printf 'metadata:\n  name: %s\n  labels:\n    brzl.dev/break-glass: "true"\n' "$binding"
  printf 'roleRef:\n  apiGroup: rbac.authorization.k8s.io\n  kind: ClusterRole\n  name: cluster-admin\n'
  printf 'subjects:\n  - kind: Group\n    apiGroup: rbac.authorization.k8s.io\n    name: %s\n' "$admins"
  printf 'EOF\n'
  printf '}\n'
  end_function 0 "emitted break-glass hold for $person"
}

# hold_check — GENERATOR: the record, the binding, the admins' rights, and
# no Application syncs automatically (waits up to 90 s for the ApplicationSet).
hold_check() {
  local env="$1" run_dir="$2" record counts
  bg_init "$env" "$run_dir" || return "$?"
  record="$(annotation brzl.dev/break-glass)" || return 1
  if [[ -z "$record" ]]; then
    printf 'fix: the cluster Secret %s has no record brzl.dev/break-glass; run hold again\n' "$secret" >&2
    return 1
  fi
  if [[ "$(kubectl get clusterrolebinding "$binding" -o jsonpath='{.roleRef.name}' 2>/dev/null)" != cluster-admin ]]; then
    printf 'fix: the ClusterRoleBinding %s to cluster-admin is missing; run hold again\n' "$binding" >&2
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
  printf 'break-glass hold by %s since %s: Argo CD holds (%s Applications sync automatically); the team brzl-admins is cluster-admin until release\n' \
    "$(jq -r '.person' <<< "$record")" "$(jq -r '.start' <<< "$record")" "$counts"
}

release() {
  local env="$1" run_dir="$2" confirm="${3:-}" current releaser kc app diff rc differing=() unknown=()
  if [[ -n "$confirm" && "$confirm" != confirm ]]; then
    printf 'usage: break-glass.sh release <env> <run_dir> [confirm]\n' >&2
    return 2
  fi
  bg_init "$env" "$run_dir" || end_function "$?" 'break-glass'
  current="$(annotation brzl.dev/break-glass)" || end_function "$?" "cluster Secret $secret"
  if [[ -z "$current" ]] && ! kubectl get clusterrolebinding "$binding" >/dev/null 2>&1; then
    printf 'error: %s has no hold (no record on the cluster Secret, no binding %s)\n' "$env" "$binding" >&2
    end_function 3 'no hold'
    return 3
  fi
  # Who releases: any person whom sign-on names (the driver acts with the
  # cluster-admin kubeconfig either way); without sign-on, not verified.
  releaser="$(timeout 30 kubectl --kubeconfig "$run_dir/kubeconfig-sign-on" auth whoami \
    -o jsonpath='{.status.userInfo.username}' < /dev/null 2>/dev/null)" || releaser=''
  [[ -n "$releaser" ]] || releaser='not-verified(no-sign-on)'
  # The differences from git: Argo CD's own diff, from its CLI in core mode
  # (no server login; it needs the namespace argocd in the kubeconfig's
  # context). The copy of the kubeconfig stays in kiesei's /tmp.
  kc="$(mktemp)" || end_function "$?" 'temporary kubeconfig'
  if ! kubectl config view --raw > "$kc" || ! KUBECONFIG="$kc" kubectl config set-context --current --namespace argocd >/dev/null; then
    rm -f "$kc"
    end_function 1 'could not prepare the kubeconfig for argocd --core'
    return 1
  fi
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    diff="$(KUBECONFIG="$kc" timeout 120 argocd app diff "$app" --core < /dev/null 2>&1)"
    rc=$?
    case "$rc" in
      0) ;;
      1) differing+=("$app")
         printf '\n=== %s differs from git (Argo CD would put git back):\n%s\n' "$app" "$diff" >&2 ;;
      *) unknown+=("$app")
         printf '\n=== %s: no diff (argocd exit %s):\n%s\n' "$app" "$rc" "$diff" >&2 ;;
    esac
  done < <(kubectl -n argocd get applications -o json | jq -r '.items[] | select(.status.sync.status != "Synced") | .metadata.name')
  rm -f "$kc"
  printf '\nbreak-glass release: by=%s hold=%s differing=%s no_diff=%s confirm=%s\n' \
    "$releaser" "$current" "${differing[*]:-none}" "${unknown[*]:-none}" "${confirm:-no}" >&2
  if (( ${#differing[@]} + ${#unknown[@]} )) && [[ -z "$confirm" ]]; then
    printf 'error: release stops while an Application differs from git (above). Commit each change to the branch Argo CD follows and run release again, or accept the undo: bash driver/driver.sh %s release confirm\n' "$env" >&2
    end_function 3 'differences from git'
    return 3
  fi
  phase_header "$run_dir"
  printf '{ # the record of this release, in this run output (the admin log store keeps it)\n'
  printf '  printf '\''%%s\\n'\'' %s\n' "$(squote "break-glass release: by=$releaser undone=${differing[*]:-none}${unknown[*]:+ unknown=${unknown[*]}} hold=$current")"
  printf '}\n'
  printf '{ # the elevation ends: the team brzl-admins is back to view\n'
  printf '  kubectl delete clusterrolebinding %q --ignore-not-found\n' "$binding"
  printf '}\n'
  printf '{ # Argo CD syncs again and puts git back over each difference; the record of the hold ends\n'
  printf '  kubectl -n argocd annotate --overwrite secret %q brzl.dev/auto-sync=true brzl.dev/break-glass-\n' "$secret"
  printf '}\n'
  end_function 0 'emitted break-glass release'
}

# release_check — GENERATOR: no record, no binding, the admins back to view,
# and every Application syncs automatically (waits up to 90 s).
release_check() {
  local env="$1" run_dir="$2" counts
  bg_init "$env" "$run_dir" || return "$?"
  if [[ -n "$(annotation brzl.dev/break-glass)" ]]; then
    printf 'fix: the cluster Secret %s still has the record brzl.dev/break-glass; run release again\n' "$secret" >&2
    return 1
  fi
  if kubectl get clusterrolebinding "$binding" >/dev/null 2>&1; then
    printf 'fix: the ClusterRoleBinding %s still exists; run release again\n' "$binding" >&2
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
  printf 'break-glass released: Argo CD syncs again (%s Applications), and the team brzl-admins has view\n' "$counts"
  # The review (Q203): part of the incident's analysis, after normal
  # operations return. Where its records are, in Grafana's Explore.
  printf 'the review: Grafana, Explore, data source "Admin log store", the time of the hold:\n'
  printf '  {brzl_source="run-output", brzl_phase=~"break-glass-.*"}\n'
  printf '  {brzl_source="api-audit"} | json | user_username=~"oidc:.*" | verb=~"create|update|patch|delete|deletecollection"\n'
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,34p' "${BASH_SOURCE[0]}"; fi
fi
