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
# and, in local-ca mode, the CA certificate in BRZL_SECRET_STORE_DIR;
# BRZL_EXAMPLE_APP_NAME (the example app's namespace, Deployment and portal
# path all carry its name; its Postgres is Cluster `pg` there). Needs
# kubectl, curl, jq. No credentials.
#
# The logs (ADR-0027): the check asks each log store, through the API
# server's service proxy, whether records arrived: every source of the admin
# log store, and the example app's pod logs in the diagnostic log store. It
# asks with a query, not Loki's /ready. The run outputs of the earlier phases
# waited in the queue of the collector beside the cluster, so the check waits
# up to three minutes for them.

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
  local app="$BRZL_EXAMPLE_APP_NAME"
  if ! kubectl -n "$app" wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' \
      cluster/pg --timeout=300s >/dev/null; then
    printf 'fix: the example app'"'"'s Postgres %s/pg is not healthy; see: kubectl -n %s describe cluster/pg\n' "$app" "$app" >&2
    rc=1
  fi
  if ! kubectl -n "$app" rollout status "deploy/$app" --timeout=180s >/dev/null; then
    printf 'fix: the example app %s is not rolled out; see: kubectl -n %s describe deploy/%s\n' "$app" "$app" "$app" >&2
    rc=1
  fi
  logs_check || rc=1
  portal_check || rc=1
  return "$rc"
}

# loki_query <store> <logql> — GENERATOR: the instant query's result (JSON),
# through the API server's proxy to the store's Service (no port-forward).
loki_query() {
  local store="$1" query
  query="$(jq -rn --arg q "$2" '$q | @uri')"
  kubectl get --raw "/api/v1/namespaces/logs/services/log-store-$store:3100/proxy/loki/api/v1/query?query=$query" 2>/dev/null
}

# logs_check — every admin source has records in the admin log store, and the
# example app's pod logs are in the diagnostic log store (see the header).
logs_check() {
  local want=(run-output k3s-server api-audit openbao-audit k8s-event) have missing source app="$BRZL_EXAMPLE_APP_NAME" i
  for (( i = 0; i < 36; i++ )); do
    have="$(loki_query admin 'sum by (brzl_source) (count_over_time({brzl_store="admin-log-store"}[24h]))' \
      | jq -r '.data.result[]?.metric.brzl_source' 2>/dev/null)"
    missing=''
    for source in "${want[@]}"; do
      grep -qx -- "$source" <<< "$have" || missing+=" $source"
    done
    [[ -z "$missing" ]] && break
    sleep 5
  done
  if [[ -n "$missing" ]]; then
    printf 'fix: the admin log store has no records from:%s; see: kubectl -n logs logs ds/log-collector-agent; docker logs %s\n' \
      "$missing" "$BRZL_LOG_COLLECTOR_NAME" >&2
    return 1
  fi
  printf 'the admin log store has records from every source: %s\n' "${want[*]}"
  if [[ "$(loki_query diagnostic "sum(count_over_time({k8s_namespace_name=\"$app\"}[24h]))" \
        | jq -r '.data.result[0].value[1] // 0' 2>/dev/null)" == 0 ]]; then
    printf 'fix: the diagnostic log store has no logs of the example app %s; see: kubectl -n logs logs ds/log-collector-agent\n' "$app" >&2
    return 1
  fi
  printf 'the diagnostic log store has the example app'"'"'s logs (%s)\n' "$app"
}

# portal_check — the admin portal answers over TLS at its host name, from this
# machine, and passes /argocd/, /grafana/ and the example app's /apps/<name>/
# through.
# The name is resolved here (--resolve),
# so the check does not depend on the operating system's resolver; the CA is
# the store's in local-ca mode.
portal_check() {
  local url="https://$BRZL_PORTAL_HOST" code
  local -a curl=(curl -sS -o /dev/null -w '%{http_code}' --max-time 10
                 --resolve "$BRZL_PORTAL_HOST:$BRZL_PORTAL_PORT:127.0.0.1")
  [[ "$BRZL_PORTAL_PORT" == 443 ]] || url+=":$BRZL_PORTAL_PORT"
  [[ "${BRZL_PORTAL_TLS:-}" == local-ca ]] && curl+=(--cacert "$repo_root/$BRZL_SECRET_STORE_DIR/ca.crt")
  if ! kubectl -n portal wait --for=condition=Ready certificate/portal --timeout=180s >/dev/null 2>&1; then
    printf 'fix: the admin portal has no ready certificate; see: kubectl -n portal describe certificate portal\n' >&2
    return 1
  fi
  if ! kubectl -n portal rollout status deploy/portal --timeout=180s >/dev/null; then
    printf 'fix: the admin portal is not rolled out; see: kubectl -n portal describe deploy/portal\n' >&2
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
  code="$("${curl[@]}" "$url/apps/$BRZL_EXAMPLE_APP_NAME/" 2>&1)"
  if [[ "$code" != 200 ]]; then
    printf 'fix: the portal does not pass /apps/%s/ through (%s); see: kubectl -n portal logs deploy/portal; kubectl -n %s logs deploy/%s\n' \
      "$BRZL_EXAMPLE_APP_NAME" "$code" "$BRZL_EXAMPLE_APP_NAME" "$BRZL_EXAMPLE_APP_NAME" >&2
    return 1
  fi
  code="$("${curl[@]}" "$url/grafana/api/health" 2>&1)"
  if [[ "$code" != 200 ]]; then
    printf 'fix: the portal does not pass /grafana/ through (%s); see: kubectl -n monitoring logs deploy/monitoring-grafana; kubectl -n monitoring describe externalsecret grafana-admin\n' "$code" >&2
    return 1
  fi
  grafana_query_check "$url" || return 1
  printf 'the admin portal answers at %s/ and passes /argocd/, /grafana/ and /apps/%s/ through\n' "$url" "$BRZL_EXAMPLE_APP_NAME"
}

# grafana_query_check <url> — what a browser does in
# Explore: log in through the portal, then query the admin log store, with
# the browser's Origin header. Grafana refuses a query whose origin is not
# the Host it receives ("origin not allowed"), so this catches a portal that
# passes the wrong Host. The password goes from the Secret to curl's stdin;
# nothing prints it.
grafana_query_check() {
  local url="$1" jar out
  local -a c=(curl -sS --max-time 20 --resolve "$BRZL_PORTAL_HOST:$BRZL_PORTAL_PORT:127.0.0.1")
  [[ "${BRZL_PORTAL_TLS:-}" == local-ca ]] && c+=(--cacert "$repo_root/$BRZL_SECRET_STORE_DIR/ca.crt")
  jar="$(mktemp)" || return 1
  kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d \
    | jq -Rs '{user: "admin", password: .}' \
    | "${c[@]}" -c "$jar" -X POST -H 'Content-Type: application/json' -d @- "$url/grafana/login" >/dev/null 2>&1
  out="$("${c[@]}" -b "$jar" -X POST -H 'Content-Type: application/json' -H "Origin: $url" \
    -d '{"queries":[{"refId":"A","datasource":{"uid":"admin-log-store"},"expr":"{brzl_source=\"run-output\"}","queryType":"range"}],"from":"now-1h","to":"now"}' \
    "$url/grafana/api/ds/query" 2>&1)"
  rm -f "$jar"
  if [[ "$(jq -r '.results.A.status // empty' <<< "$out" 2>/dev/null)" != 200 ]]; then
    printf 'fix: a query in Grafana on the admin log store failed through the portal: %s; see: kubectl -n monitoring logs deploy/monitoring-grafana\n' \
      "$(head -c 200 <<< "$out")" >&2
    return 1
  fi
  printf 'Grafana queries the admin log store through the portal, as a browser does\n'
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,14p' "${BASH_SOURCE[0]}"; fi
fi
