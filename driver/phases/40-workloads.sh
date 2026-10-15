#!/usr/bin/env bash
# 40-workloads.sh — phase 40: wait until Argo CD has brought up the platform,
# the admin portal and the example app from git, then check them. It applies
# nothing: phase 30-gitops handed the cluster to Argo CD. Locus: the conductor.
#
# Emit + generator, one function each:
#   bash driver/phases/40-workloads.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/40-workloads.sh phase_check <env> <run_dir>  # GENERATOR
#
# In fast mode Argo CD does not sync, so this phase waits until its timeout and
# its check fails: run it in GitOps mode (fast_off first).
#
# Inputs: <run_dir>/kubeconfig from phase 10 (for the check); BRZL_PORTAL_*
# and, in local-ca mode, the CA certificate in BRZL_SECRET_STORE_DIR. Needs
# kubectl, curl. No credentials.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

phase_locus() { printf '%s\n' conductor; }

phase_up() {
  local env="$1" run_dir="$2"
  phase_init "$env" || end_function "$?" 'environment definition'
  phase_header "$run_dir" conductor
  cat <<'EOF'
{ # Argo CD syncs every Application from git; wait until all are Synced and Healthy
  kubectl -n argocd wait applications --all --for=jsonpath='{.status.sync.status}'=Synced --timeout=900s
  kubectl -n argocd wait applications --all --for=jsonpath='{.status.health.status}'=Healthy --timeout=900s
}
EOF
  end_function 0 'emitted 40-workloads up'
}

phase_check() {
  local env="$1" run_dir="$2" rc=0 not_ready
  phase_init "$env" || return 1
  export KUBECONFIG="$run_dir/kubeconfig"
  not_ready="$(kubectl -n argocd get applications --no-headers \
    -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' 2>&1 \
    | grep -v ' Synced  *Healthy$')"
  if [[ -n "$not_ready" ]]; then
    printf 'fix: Applications not Synced and Healthy (see: kubectl -n argocd get applications):\n%s\n' "$not_ready" >&2
    rc=1
  fi
  if [[ -n "${BRZL_SECRET_STORE:-}" ]]; then
    local projected
    projected="$(kubectl -n brzl-system get secret smoke -o jsonpath='{.data.value}' 2>/dev/null | base64 -d | sha256sum)"
    if [[ ! -s "$run_dir/smoke.sha256" || "$projected" != "$(<"$run_dir/smoke.sha256")" ]]; then
      printf 'fix: the smoke secret ESO projected does not match what phase 25 wrote (or is absent); see: kubectl -n brzl-system describe externalsecret smoke; kubectl describe clustersecretstore brzl-secrets\n' >&2
      rc=1
    else
      printf 'the smoke secret round-trips through the cluster secret store\n'
    fi
  fi
  if ! kubectl -n cnpg-demo wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' \
      cluster/pg --timeout=300s >/dev/null; then
    printf 'fix: Postgres cluster cnpg-demo/pg is not healthy; see: kubectl -n cnpg-demo describe cluster/pg\n' >&2
    rc=1
  fi
  if ! kubectl -n demo rollout status deploy/demo-app --timeout=180s >/dev/null; then
    printf 'fix: demo-app is not rolled out; see: kubectl -n demo describe deploy/demo-app\n' >&2
    rc=1
  fi
  portal_check || rc=1
  return "$rc"
}

# portal_check — the admin portal answers over TLS at its host name, from this
# machine, and passes /argocd/ through. The name is resolved here (--resolve),
# so the check does not depend on the operating system's resolver; the CA is
# the store's in local-ca mode.
portal_check() {
  local url="https://$BRZL_PORTAL_HOST" code
  local -a curl=(curl -sS -o /dev/null -w '%{http_code}' --max-time 10
                 --resolve "$BRZL_PORTAL_HOST:$BRZL_PORTAL_PORT:127.0.0.1")
  [[ "$BRZL_PORTAL_PORT" == 443 ]] || url+=":$BRZL_PORTAL_PORT"
  [[ "${BRZL_PORTAL_TLS:-}" == local-ca ]] && curl+=(--cacert "$repo_root/$BRZL_SECRET_STORE_DIR/ca.crt")
  if ! kubectl -n portal rollout status deploy/portal --timeout=180s >/dev/null; then
    printf 'fix: the admin portal is not rolled out; see: kubectl -n portal describe deploy/portal; kubectl -n portal describe certificate portal\n' >&2
    return 1
  fi
  code="$("${curl[@]}" "$url/" 2>&1)"
  if [[ "$code" != 200 ]]; then
    printf 'fix: the admin portal does not answer at %s/ (%s); see: kubectl -n portal logs deploy/portal; docker ps (host port %s)\n' \
      "$url" "$code" "$BRZL_PORTAL_PORT" >&2
    return 1
  fi
  code="$("${curl[@]}" "$url/argocd/" 2>&1)"
  if [[ "$code" != 200 ]]; then
    printf 'fix: the portal does not pass /argocd/ through (%s); see: kubectl -n argocd logs deploy/argocd-server\n' "$code" >&2
    return 1
  fi
  printf 'the admin portal answers at %s/ and passes /argocd/ through\n' "$url"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,14p' "${BASH_SOURCE[0]}"; fi
fi
