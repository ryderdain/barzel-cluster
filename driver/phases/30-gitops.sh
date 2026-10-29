#!/usr/bin/env bash
# 30-gitops.sh — phase 30: hand the cluster to Argo CD (GitOps mode). Installs
# Argo CD with helm (it then manages itself, wave -1), registers this cluster
# with the labels and annotations the platform ApplicationSet reads, and
# applies that ApplicationSet (gitops/platform/applicationset.yaml, ADR-0025).
# Argo CD then deploys the operators and the workloads from git. Locus: the
# conductor.
#
# Everything the conductor needs is rendered into the run sheet when the phase is
# emitted: the Argo CD values, the AppProject, the cluster Secret, the
# ApplicationSet. The conductor needs no copy of the repo, and the run sheet is
# the record of what was applied.
#
# Before it applies the ApplicationSet, the run sheet stops (`error 3`) if a live
# Application has no element in the new file: the ApplicationSet would leave it
# behind (ADR-0016, ADR-0025).
#
# The git revision Argo CD follows: an exported BRZL_GITOPS_REVISION, else the
# branch checked out when the phase is emitted (Q56). Argo CD reads only what
# is pushed; a warning on stderr says when the branch is ahead of its remote.
# The auto-sync annotation is never written here: fast_on/fast_off own it, so
# running this phase again keeps fast mode as it is.
#
# Emit + generator, one function each:
#   bash driver/phases/30-gitops.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/30-gitops.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: env/<env>.env (BRZL_EXAMPLE_APP_NAME, BRZL_WORKLOAD_FOLLOW,
# BRZL_PORTAL_HOST); the substrate adapter (registry host, upstream prefixes);
# gitops/platform/applicationset.yaml,
# gitops/clusters/<env>/project.yaml, gitops/infrastructure/argocd/values.yaml;
# <run_dir>/kubeconfig (for the check). Needs git, yq (kiesei). No credentials:
# the repo credential is phase 25's.

# shellcheck disable=SC2016  # the emitted text names variables for the run sheet to expand
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

appset_file=gitops/platform/applicationset.yaml
appset_name=brzl-platform

phase_locus() { printf '%s\n' conductor; }

# gitops_revision — the revision Argo CD follows; warns when it is not pushed.
gitops_revision() {
  local revision ahead
  local -a git=(git -c "safe.directory=$repo_root" -C "$repo_root")
  if [[ -n "${BRZL_GITOPS_REVISION:-}" ]]; then
    printf '%s' "$BRZL_GITOPS_REVISION"
    return 0
  fi
  if ! revision="$("${git[@]}" symbolic-ref --short -q HEAD)"; then
    printf 'error: HEAD is detached; check out a branch or export BRZL_GITOPS_REVISION\n' >&2
    return 1
  fi
  if ! ahead="$("${git[@]}" rev-list --count '@{upstream}..HEAD' 2>/dev/null)"; then
    printf 'warning: branch %s has no remote branch; Argo CD cannot read it until it is pushed\n' "$revision" >&2
  elif (( ahead > 0 )); then
    printf 'warning: branch %s is %d commit(s) ahead of its remote; Argo CD reads only what is pushed\n' \
      "$revision" "$ahead" >&2
  fi
  printf '%s' "$revision"
}

# cluster_secret <env> <revision> — this cluster's registration, with the
# labels and annotations the platform ApplicationSet reads.
cluster_secret() {
  local env="$1" revision="$2" host upstream
  host="$(substrate_registry_host)" || return 1
  cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: brzl-$env-in-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    brzl.dev/appset-cluster: "true"
    brzl.dev/env: $env
    brzl.dev/substrate: $BRZL_SUBSTRATE
    brzl.dev/workload-follow: $BRZL_WORKLOAD_FOLLOW
  annotations:
    brzl.dev/registry-host: "$host"
    brzl.dev/revision: "$revision"
    brzl.dev/portal-host: "$BRZL_PORTAL_HOST"
EOF
  for upstream in quay k8s github docker-hub; do
    printf '    brzl.dev/prefix-%s: "%s"\n' "$upstream" "$(substrate_upstream_prefix "$upstream")" || return 1
  done
  cat <<'EOF'
type: Opaque
stringData:
  name: in-cluster
  server: https://kubernetes.default.svc
  config: |
    {"tlsClientConfig":{"insecure":false}}
EOF
}

phase_up() {
  local env="$1" run_dir="$2" revision chart_version argocd_image redis_image secret app_names name
  phase_init "$env" || end_function "$?" 'environment definition'
  require_tools git yq || end_function "$?" 'git and yq (run the stream in kiesei)'
  revision="$(gitops_revision)" || end_function "$?" 'git revision'
  chart_version="$(yq '.. | select(type == "!!map" and .appName == "argocd") | .chartVersion' \
    "$repo_root/$appset_file")" || end_function "$?" 'argo-cd chart version'
  argocd_image="$(substrate_registry_host)/$(substrate_upstream_prefix quay)/argoproj/argocd" \
    || end_function "$?" 'Argo CD image'
  # The same two images the ApplicationSet injects (its imageParams for argocd).
  redis_image="$(substrate_registry_host)/$(substrate_upstream_prefix docker-hub)/library/redis" \
    || end_function "$?" 'Redis image'
  secret="$(cluster_secret "$env" "$revision")" || end_function "$?" 'cluster Secret'
  app_names="$(yq '.. | select(type == "!!map" and has("appName")) | .appName' "$repo_root/$appset_file")" \
    || end_function "$?" 'Application names'
  # The example app is named in three places that must agree: the environment
  # definition, the ApplicationSet element and the portal's location.
  if ! grep -qx "$BRZL_EXAMPLE_APP_NAME" <<< "$app_names"; then
    printf 'error: BRZL_EXAMPLE_APP_NAME=%s has no element in %s\n' "$BRZL_EXAMPLE_APP_NAME" "$appset_file" >&2
    end_function 1 'example app element'
    return 1
  fi

  phase_header "$run_dir" conductor
  printf '# GitOps revision: %s\n' "$revision"
  phase_error_definition
  printf '{ # Argo CD itself, from its chart (Argo CD then manages it: Application argocd, wave -1)\n'
  printf '  helm repo add argo https://argoproj.github.io/argo-helm\n'
  printf '  helm repo update argo\n'
  printf '  helm upgrade --install argocd argo/argo-cd --version %q \\\n' "$chart_version"
  printf '    --namespace argocd --create-namespace --set global.image.repository=%q \\\n' "$argocd_image"
  printf '    --set redis.image.repository=%q \\\n' "$redis_image"
  printf '    --set configs.cm.url=%q \\\n' "https://$BRZL_PORTAL_HOST/argocd"
  printf "    --wait -f - <<'EOF'\n"
  cat "$repo_root/gitops/infrastructure/argocd/values.yaml"
  printf 'EOF\n'
  printf '}\n'
  printf '{ # the AppProject, and this cluster registered with the values the ApplicationSet reads\n'
  printf "  kubectl apply -f - <<'EOF'\n"
  cat "$repo_root/gitops/clusters/$env/project.yaml"
  printf -- '---\n%s\nEOF\n' "$secret"
  printf '}\n'
  printf '{ # every live Application must still have an element; else the ApplicationSet would leave it behind\n'
  printf '  declare -A element=('
  while IFS= read -r name; do printf ' [%s]=1' "$name"; done <<< "$app_names"
  printf ' )\n'
  printf '  orphans=\n'
  printf "  for app in \$(kubectl -n argocd get applications -o jsonpath='{.items[*].metadata.name}'); do\n"
  printf '    [[ -n "${element[$app]:-}" ]] || orphans+=" $app"\n'
  printf '  done\n'
  printf '  [[ -z "$orphans" ]] \\\n'
  printf '    || error 3 "Application(s)${orphans} have no element in the new ApplicationSet; nothing applied. Remove them on purpose, or restore their elements (ADR-0025)"\n'
  printf '}\n'
  printf '{ # the platform ApplicationSet (%s)\n' "$appset_file"
  printf "  kubectl apply -f - <<'EOF'\n"
  cat "$repo_root/$appset_file"
  printf 'EOF\n'
  printf '  kubectl -n argocd wait %q --for=condition=ResourcesUpToDate --timeout=180s\n' \
    "applicationset/$appset_name"
  printf '}\n'
  end_function 0 'emitted 30-gitops up'
}

phase_check() {
  local env="$1" run_dir="$2" state apps
  phase_init "$env" || return 1
  export KUBECONFIG="$run_dir/kubeconfig"
  if ! kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=180s >/dev/null; then
    printf 'fix: the ApplicationSet controller is not ready; see: kubectl -n argocd describe deploy/argocd-applicationset-controller\n' >&2
    return 1
  fi
  state="$(kubectl -n argocd get applicationset "$appset_name" \
    -o jsonpath='{.status.conditions[?(@.type=="ResourcesUpToDate")].status}' 2>/dev/null)"
  if [[ "$state" != True ]]; then
    printf 'fix: ApplicationSet %s has not made its Applications; see: kubectl -n argocd describe applicationset %s\n' \
      "$appset_name" "$appset_name" >&2
    return 1
  fi
  # The ApplicationSet in the cluster must be the one in the file. When the run
  # sheet stopped at its guard (orphan Applications), Argo CD is up and the OLD
  # ApplicationSet is up to date, and this is the only test that tells.
  local live wanted
  live="$(kubectl -n argocd get applicationset "$appset_name" \
    -o jsonpath='{.spec.generators..appName}' | tr ' ' '\n' | sort | tr '\n' ' ')"
  wanted="$(yq '.. | select(type == "!!map" and has("appName")) | .appName' "$repo_root/$appset_file" | sort | tr '\n' ' ')"
  if [[ "$live" != "$wanted" ]]; then
    printf 'fix: ApplicationSet %s in the cluster has elements [%s] but %s has [%s]: the run sheet stopped before it applied the file (read %s/30-gitops.out: orphan Applications?), or the file changed since; run the 30-gitops phase again\n' \
      "$appset_name" "$live" "$appset_file" "$wanted" "$run_dir" >&2
    return 1
  fi
  apps="$(kubectl -n argocd get applications -o jsonpath='{.items[*].metadata.name}')"
  printf 'Argo CD is up; ApplicationSet %s is the one in %s; it made: %s\n' "$appset_name" "$appset_file" "$apps"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,32p' "${BASH_SOURCE[0]}"; fi
fi
