#!/usr/bin/env bash
# fast-mode.sh — fast mode on the local environment (GLOSSARY): Argo CD holds,
# and the driver applies the working tree directly, for changes to the
# structure of the cluster. The driver's fast_on / fast_off / apply actions call
# this script; it writes run sheets, the driver runs them (driver.sh).
#
#   bash driver/fast-mode.sh fast_switch <on|off> <env> <run_dir>  # EMIT a run sheet
#   bash driver/fast-mode.sh fast_check <on|off> <env> <run_dir>   # GENERATOR
#   bash driver/fast-mode.sh fast_apply <env> <run_dir>            # EMIT a run sheet
#
# The switch is one annotation on the cluster Secret, brzl.dev/auto-sync
# ("false" = hold). The platform ApplicationSet reads it and renders every
# Application with or without automated sync (ADR-0025); nothing in git
# changes. fast_off gives the cluster back to git: Argo CD prunes and
# self-heals to the pushed branch, so unpushed fast-mode changes go away.
#
# fast_apply renders every kustomize app from the WORKING TREE with the same
# images and patches that Argo CD injects — read from each live Application,
# not copied from the template — and the run sheet applies the result; the
# driver runs it on the conductor. An app from another repo (the example app,
# ADR-0034) renders from its checkout beside this repo (BRZL_EXAMPLE_APP_SRC),
# so the loop "edit the app, apply, look" needs no push. The helm apps change
# only through a pushed branch (Q58).
#
# Only for an environment whose definition sets BRZL_FAST_MODE_ALLOWED=true
# (local). Inputs: <run_dir>/kubeconfig; the live cluster Secret and
# Applications. Needs kubectl, jq, yq (kiesei). No credentials.

# shellcheck disable=SC2016  # the emitted text names variables for the run sheet to expand
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

appset_file=gitops/platform/applicationset.yaml
# The platform's own repo, as the ApplicationSet names it; any other repoURL
# is a workload's (ADR-0034).
platform_repo=git@github.com:ryderdain/barzel-cluster.git

fast_init() {
  local env="$1" run_dir="$2"
  phase_init "$env" || return 1
  if [[ "${BRZL_FAST_MODE_ALLOWED:-}" != true ]]; then
    printf 'error: fast mode is only for the local environment (env/%s.env has no BRZL_FAST_MODE_ALLOWED=true)\n' "$env" >&2
    return 2
  fi
  if [[ ! -s "$run_dir/kubeconfig" ]]; then
    printf 'error: no kubeconfig in %s; bring the environment up first\n' "$run_dir" >&2
    return 1
  fi
  export KUBECONFIG="$run_dir/kubeconfig"
}

fast_switch() {
  local state="$1" env="$2" run_dir="$3" value
  case "$state" in
    on) value=false ;;
    off) value=true ;;
    *) printf 'usage: fast-mode.sh fast_switch <on|off> <env> <run_dir>\n' >&2; return 2 ;;
  esac
  fast_init "$env" "$run_dir" || end_function "$?" 'fast mode'
  phase_header "$run_dir"
  if [[ "$state" == on ]]; then
    printf '{ # fast mode ON: Argo CD holds (no automated sync); the working tree can be applied\n'
  else
    printf '{ # fast mode OFF: Argo CD syncs again, back to the pushed branch (unpushed changes go away)\n'
  fi
  printf '  kubectl -n argocd annotate --overwrite secret %q %q\n' \
    "brzl-$env-in-cluster" "brzl.dev/auto-sync=$value"
  printf '}\n'
  end_function 0 "emitted fast mode $state"
}

# fast_check <on|off> — GENERATOR: waits up to 90 s for the ApplicationSet to
# render every Application without (on) or with (off) automated sync.
fast_check() {
  local state="$1" env="$2" run_dir="$3" waited=0 automated total
  fast_init "$env" "$run_dir" || return "$?"
  while (( waited <= 90 )); do
    automated="$(kubectl -n argocd get applications -o json \
      | jq '[.items[] | select(.spec.syncPolicy.automated != null)] | length')" || return 1
    total="$(kubectl -n argocd get applications -o json | jq '.items | length')" || return 1
    if [[ "$state" == on && "$automated" == 0 ]] || [[ "$state" == off && "$automated" == "$total" ]]; then
      printf 'fast mode is %s: %s of %s Applications sync automatically\n' "$state" "$automated" "$total"
      return 0
    fi
    sleep 5
    waited=$(( waited + 5 ))
  done
  printf 'fix: after 90 s, %s of %s Applications still sync automatically; see: kubectl -n argocd describe applicationset brzl-platform\n' \
    "$automated" "$total" >&2
  return 1
}

# kustomization_for <application-json> <dir> <label_key> — a kustomization, to
# be written in <dir> (relative to the repo root), that puts the live
# Application's images and patches over its path in the working tree: this
# repo's for the platform repo, the example app's checkout
# (BRZL_EXAMPLE_APP_SRC) for any other. kustomize takes only relative resource
# paths, so the path climbs from <dir> to the repo root first.
#
# It also adds Argo CD's tracking label <label_key>=<app>, as Argo CD does when
# it syncs (the "label" tracking method; fast_apply refuses any other). The key
# is argocd-cm's application.instanceLabelKey — the argo-cd chart sets
# argocd.argoproj.io/instance, not the upstream default. Without the label,
# kubectl's three-way merge removes it, and Argo CD shows the object OutOfSync
# even when its spec is unchanged. The label goes on metadata only, never into
# selectors.
kustomization_for() {
  local app_json="$1" dir="$2" label_key="$3" path repo up='' i image name ref new_name new_tag
  local -a part
  path="$(jq -r '(.spec.sources // [.spec.source])[0].path' <<< "$app_json")" || return 1
  repo="$(jq -r '(.spec.sources // [.spec.source])[0].repoURL' <<< "$app_json")" || return 1
  if [[ "$repo" != "$platform_repo" ]]; then
    if [[ ! -d "$repo_root/$BRZL_EXAMPLE_APP_SRC/$path" ]]; then
      printf 'error: %s renders from %s, but %s/%s is not a directory (clone the example app beside this repo)\n' \
        "$(jq -r '.metadata.name' <<< "$app_json")" "$repo" "$BRZL_EXAMPLE_APP_SRC" "$path" >&2
      return 1
    fi
    path="$BRZL_EXAMPLE_APP_SRC/$path"
  fi
  IFS=/ read -ra part <<< "$dir"
  for (( i = 0; i < ${#part[@]}; i++ )); do up+='../'; done
  printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n'
  printf 'resources:\n  - %s\n' "$up$path"
  printf 'labels:\n  - includeSelectors: false\n    pairs:\n      %s: %s\n' \
    "$label_key" "$(jq -r '.metadata.name' <<< "$app_json")"
  printf 'images:\n'
  while IFS= read -r image; do
    [[ -n "$image" ]] || continue
    name="${image%%=*}"; ref="${image#*=}"
    new_name="$ref"; new_tag=''
    if [[ "${ref##*/}" == *:* ]]; then
      new_name="${ref%:*}"; new_tag="${ref##*:}"
    fi
    printf '  - name: %s\n    newName: %s\n' "$name" "$new_name"
    [[ -n "$new_tag" ]] && printf '    newTag: "%s"\n' "$new_tag"
  done < <(jq -r '(.spec.sources // [.spec.source])[0].kustomize.images // [] | .[]' <<< "$app_json")
  printf 'patches:\n'
  jq '(.spec.sources // [.spec.source])[0].kustomize.patches // []' <<< "$app_json" \
    | yq -P '.[] | [.]' | sed 's/^/  /'
}

fast_apply() {
  local env="$1" run_dir="${2#"$repo_root"/}" auto tracking label_key app app_json ns dir rendered with_ns without_ns
  fast_init "$env" "$run_dir" || end_function "$?" 'fast mode'
  auto="$(kubectl -n argocd get secret "brzl-$env-in-cluster" \
    -o jsonpath='{.metadata.annotations.brzl\.dev/auto-sync}')" || end_function "$?" 'cluster Secret'
  tracking="$(kubectl -n argocd get configmap argocd-cm \
    -o jsonpath='{.data.application\.resourceTrackingMethod}')" || end_function "$?" 'argocd-cm'
  if [[ -n "$tracking" && "$tracking" != label ]]; then
    printf 'error: Argo CD tracks resources by %s; fast apply writes only the label method\n' "$tracking" >&2
    end_function 1 'unsupported tracking method'
    return 1
  fi
  label_key="$(kubectl -n argocd get configmap argocd-cm \
    -o jsonpath='{.data.application\.instanceLabelKey}')" || end_function "$?" 'argocd-cm'
  label_key="${label_key:-app.kubernetes.io/instance}"
  if [[ "$auto" != false ]]; then
    printf 'error: fast mode is off; Argo CD would revert the change. Run first: bash driver/driver.sh %s fast_on\n' "$env" >&2
    end_function 3 'fast mode is off'
    return 3
  fi
  phase_header "$run_dir" conductor
  while IFS= read -r app; do
    app_json="$(kubectl -n argocd get application "$app" -o json)" || end_function "$?" "Application $app"
    ns="$(jq -r '.spec.destination.namespace' <<< "$app_json")"
    # Kept in the run directory: the record of how this apply was rendered.
    dir="$run_dir/fast-apply-kustomize/$app"
    mkdir -p "$repo_root/$dir" || end_function "$?" "directory $dir"
    kustomization_for "$app_json" "$dir" "$label_key" > "$repo_root/$dir/kustomization.yaml" \
      || end_function "$?" "kustomization for $app"
    rendered="$(kubectl kustomize --load-restrictor LoadRestrictionsNone "$repo_root/$dir")" \
      || end_function "$?" "could not render $app from the working tree"
    # As Argo CD does: an object with its own namespace stays there; only an
    # object with none goes to the Application's destination namespace.
    with_ns="$(yq 'select(.metadata.namespace != null)' <<< "$rendered")" \
      || end_function "$?" "could not split $app by namespace"
    without_ns="$(yq 'select(.metadata.namespace == null)' <<< "$rendered")" \
      || end_function "$?" "could not split $app by namespace"
    printf '{ # %s from the working tree, with the images and patches Argo CD injects\n' "$app"
    [[ -n "$without_ns" ]] && printf "  kubectl apply -n %q -f - <<'EOF'\n%s\nEOF\n" "$ns" "$without_ns"
    [[ -n "$with_ns" ]] && printf "  kubectl apply -f - <<'EOF'\n%s\nEOF\n" "$with_ns"
    printf '}\n'
  done < <(yq '.. | select(type == "!!map" and .kind == "kustomize" and has("appName")) | .appName' \
    "$repo_root/$appset_file")
  end_function 0 'emitted fast apply'
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,26p' "${BASH_SOURCE[0]}"; fi
fi
