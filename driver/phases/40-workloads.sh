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
#
# Sign-on (ADR-0035): a check cannot sign in to GitHub, so it checks what
# sign-on is made of. The portal refuses a request without a session and
# sends it to sign in; Dex answers at the issuer URL through the portal;
# Argo CD's public settings name that issuer (so Argo CD read its Secret);
# oauth2-proxy is ready (it starts only when it reaches Dex from its pod,
# through the cluster's DNS rule and the CA); Grafana is healthy. The workload's
# path stays open (Q144). For kubectl through Dex (step 2): Dex advertises
# PKCE, the portal has its fixed address, the tiers' bindings give the
# expected rights (by impersonation), and the admin log store and
# oauth2-proxy have their NetworkPolicies. The sign-in itself is the operator's test (docs/LOCAL.md,
# "Sign-on" and "Use it").

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
{ # Argo CD syncs every Application from git; wait until all are Synced and Healthy (at most 900 s).
  # Argo CD retries a failed sync with no limit (BACKLOG 20); an Application that is not
  # Synced and has failed 3 times or more is named here, with its error, once per count.
  warned=' '
  for _ in $(seq 60); do
    if apps="$(kubectl -n argocd get applications -o json)"; then
      jq -e '[.items[] | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")] | length == 0' \
        <<< "$apps" >/dev/null && { printf 'every Application is Synced and Healthy\n'; break; }
      while IFS=$'\t' read -r name count message; do
        [[ "$warned" == *" $name:$count "* ]] && continue
        printf 'WARNING: Argo CD failed to sync %s %s times: %s\n' "$name" "$count" "$message"
        warned+="$name:$count "
      done < <(jq -r '.items[] | .status as $s
          | select(($s.operationState.retryCount // 0) >= 3 and $s.operationState.phase != "Succeeded" and $s.sync.status != "Synced")
          | [.metadata.name, $s.operationState.retryCount, ($s.operationState.message // "" | .[0:200])] | @tsv' <<< "$apps")
    fi
    sleep 15
  done
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
  portal_check "$env" || rc=1
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
  if [[ "$(loki_query admin 'sum(count_over_time({brzl_source="k8s-event"} | brzl_collector_node != "" [24h]))' \
        | jq -r '.data.result[0].value[1] // 0' 2>/dev/null)" == 0 ]]; then
    printf 'fix: the events in the admin log store do not name the node of their collector (brzl_collector_node); see: gitops/infrastructure/logs/collector.yaml\n' >&2
    return 1
  fi
  printf 'the platform records name the node of the collector that read them\n'
  if [[ "$(loki_query diagnostic "sum(count_over_time({k8s_namespace_name=\"$app\"}[24h]))" \
        | jq -r '.data.result[0].value[1] // 0' 2>/dev/null)" == 0 ]]; then
    printf 'fix: the diagnostic log store has no logs of the example app %s; see: kubectl -n logs logs ds/log-collector-agent\n' "$app" >&2
    return 1
  fi
  printf 'the diagnostic log store has the example app'"'"'s logs (%s)\n' "$app"
}

# portal_check <env> — the admin portal answers over TLS at its host name, from
# this machine, with sign-on in front of it (see the header), and passes the
# example app's /apps/<name>/ through without it. The name is resolved here
# (--resolve), so the check does not depend on the operating system's
# resolver; the CA is the store's in local-ca mode. Also the access tiers'
# rights, in and outside a break-glass hold (ADR-0037).
portal_check() {
  local env="$1" url="https://$BRZL_PORTAL_HOST" issuer="https://$BRZL_PORTAL_HOST/dex" code out
  local -a get=(curl -sS --max-time 10 --resolve "$BRZL_PORTAL_HOST:$BRZL_PORTAL_PORT:127.0.0.1")
  [[ "$BRZL_PORTAL_PORT" == 443 ]] || url+=":$BRZL_PORTAL_PORT"
  [[ "${BRZL_PORTAL_TLS:-}" == local-ca ]] && get+=(--cacert "$repo_root/$BRZL_SECRET_STORE_DIR/ca.crt")
  local -a status=("${get[@]}" -o /dev/null -w '%{http_code} %{redirect_url}')
  if ! kubectl -n portal wait --for=condition=Ready certificate/portal --timeout=180s >/dev/null 2>&1; then
    printf 'fix: the admin portal has no ready certificate; see: kubectl -n portal describe certificate portal\n' >&2
    return 1
  fi
  if ! kubectl -n portal rollout status deploy/portal --timeout=180s >/dev/null; then
    printf 'fix: the admin portal is not rolled out; see: kubectl -n portal describe deploy/portal\n' >&2
    return 1
  fi
  if ! kubectl -n sign-on rollout status deploy/dex deploy/oauth2-proxy --timeout=180s >/dev/null; then
    printf 'fix: Dex or oauth2-proxy is not ready; see: kubectl -n sign-on logs deploy/oauth2-proxy; kubectl -n sign-on logs deploy/dex\n' >&2
    return 1
  fi
  # The gate: without a session, a redirect to sign in; sign-in leads to Dex.
  out="$("${status[@]}" "$url/" 2>&1)"
  if [[ "$out" != "302 $url/oauth2/sign_in?"* ]]; then
    printf 'fix: the admin portal does not send a request without a session to sign in (%s); see: kubectl -n portal logs deploy/portal; kubectl -n sign-on logs deploy/oauth2-proxy; docker ps (host port %s)\n' \
      "$out" "$BRZL_PORTAL_PORT" >&2
    return 1
  fi
  out="$("${status[@]}" "$url/oauth2/sign_in?rd=$url/" 2>&1)"
  if [[ "$out" != "302 $issuer/auth?"* ]]; then
    printf 'fix: sign-in does not lead to Dex at %s (%s); see: kubectl -n sign-on logs deploy/oauth2-proxy\n' "$issuer" "$out" >&2
    return 1
  fi
  local discovery
  discovery="$("${get[@]}" "$url/dex/.well-known/openid-configuration" 2>/dev/null)"
  if [[ "$(jq -r '.issuer // empty' <<< "$discovery" 2>/dev/null)" != "$issuer" ]]; then
    printf 'fix: Dex does not answer as %s through the portal; see: kubectl -n sign-on logs deploy/dex\n' "$issuer" >&2
    return 1
  fi
  # PKCE (the security review of 2026-10-26, condition 3): kubelogin and the
  # browser clients use S256 when the issuer advertises it.
  if ! jq -e '.code_challenge_methods_supported | index("S256")' <<< "$discovery" >/dev/null 2>&1; then
    printf 'fix: Dex does not advertise PKCE S256 in its discovery document; see: kubectl -n sign-on logs deploy/dex\n' >&2
    return 1
  fi
  if [[ "$("${get[@]}" "$url/argocd/api/v1/settings" 2>/dev/null | jq -r '.oidcConfig.issuer // empty' 2>/dev/null)" != "$issuer" ]]; then
    printf 'fix: Argo CD does not name the issuer %s in its settings; see: kubectl -n argocd get secret brzl-argocd-oidc; kubectl -n argocd logs deploy/argocd-server\n' "$issuer" >&2
    return 1
  fi
  # The Argo CD CLI reads the same settings over gRPC-web before it signs in
  # (seen 2026-10-27: the gate redirected that call, and the CLI died with
  # "unexpected EOF"): that path must be outside the gate too.
  code="$("${get[@]}" -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/grpc-web+proto' \
    --data-binary '' "$url/argocd/cluster.SettingsService/Get" 2>&1)"
  if [[ "$code" == 30? || "$code" == 401 ]]; then
    printf 'fix: the gate does not let the Argo CD CLI read the settings over gRPC-web (%s on /argocd/cluster.SettingsService/Get); see gitops/infrastructure/portal/nginx.conf\n' "$code" >&2
    return 1
  fi
  # Argo CD's settings read the Secret on each request, but its sign-in reads
  # it only when argocd-server starts (seen 2026-10-23): the server must have
  # started after the Secret's last change.
  local changed started
  changed="$(kubectl -n argocd get secret brzl-argocd-oidc -o json 2>/dev/null \
    | jq -r '[.metadata.creationTimestamp, (.metadata.managedFields[]?.time // empty)] | max')"
  started="$(kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-server -o json 2>/dev/null \
    | jq -r '[.items[] | select(.metadata.deletionTimestamp == null) | .status.startTime] | min // empty')"
  if [[ -z "$changed" || -z "$started" || "$started" < "$changed" ]]; then
    printf 'fix: argocd-server started (%s) before its OIDC Secret last changed (%s), so its sign-in uses the old values: kubectl -n argocd rollout restart deployment/argocd-server\n' \
      "${started:-?}" "${changed:-?}" >&2
    return 1
  fi
  code="$("${get[@]}" -o /dev/null -w '%{http_code}' "$url/apps/$BRZL_EXAMPLE_APP_NAME/" 2>&1)"
  if [[ "$code" != 200 ]]; then
    printf 'fix: the portal does not pass /apps/%s/ through without sign-on (%s); see: kubectl -n portal logs deploy/portal; kubectl -n %s logs deploy/%s\n' \
      "$BRZL_EXAMPLE_APP_NAME" "$code" "$BRZL_EXAMPLE_APP_NAME" "$BRZL_EXAMPLE_APP_NAME" >&2
    return 1
  fi
  if [[ "$(kubectl get --raw /api/v1/namespaces/monitoring/services/monitoring-grafana:80/proxy/grafana/api/health 2>/dev/null \
        | jq -r '.database // empty' 2>/dev/null)" != ok ]]; then
    printf 'fix: Grafana is not healthy; see: kubectl -n monitoring logs deploy/monitoring-grafana; kubectl -n monitoring describe externalsecret grafana-oidc\n' >&2
    return 1
  fi
  # kubectl through Dex (step 2): the portal's fixed address, which the
  # kube-API resolves the issuer to; the tiers' bindings, checked by
  # impersonation (no sign-in here); and the admin log store, which admits
  # only its writers and Grafana. The sign-in itself needs a person:
  # `kubectl auth whoami` with kubeconfig-sign-on (docs/LOCAL.md).
  local ip org="${BRZL_SIGN_ON_ORG:?}" team
  ip="$(kubectl -n portal get svc portal -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
  if [[ -n "${BRZL_PORTAL_CLUSTER_IP:-}" && "$ip" != "$BRZL_PORTAL_CLUSTER_IP" ]]; then
    printf 'fix: the portal Service has the address %s, not BRZL_PORTAL_CLUSTER_IP=%s: env/<env>.env and gitops/clusters/<env>/portal/kustomization.yaml must agree, and a Service address cannot change (run the driver'"'"'s down, then up)\n' \
      "${ip:-none}" "$BRZL_PORTAL_CLUSTER_IP" >&2
    return 1
  fi
  # Break-glass (ADR-0037): the admins are cluster-admin only in a hold, through
  # the binding brzl-break-glass, and the hold's record is on the cluster
  # Secret. Both or neither: one without the other is a hold or a release
  # that did not finish.
  local held record teams=(brzl-admins brzl-operators brzl-auditors)
  held="$(kubectl get clusterrolebinding brzl-break-glass -o name 2>/dev/null)"
  record="$(kubectl -n argocd get secret "brzl-$env-in-cluster" -o json 2>/dev/null \
    | jq -r '.metadata.annotations["brzl.dev/break-glass"] // empty')"
  if [[ -n "$held" && -z "$record" ]] || [[ -z "$held" && -n "$record" ]]; then
    printf 'fix: the binding brzl-break-glass (%s) and the hold'"'"'s record on the cluster Secret (%s) disagree: run the driver'"'"'s hold or release again (docs/BREAK-GLASS.md)\n' \
      "${held:-absent}" "${record:-absent}" >&2
    return 1
  fi
  if [[ -n "$held" ]]; then
    printf 'WARNING: a break-glass hold is on (%s): the admins are cluster-admin, and Argo CD holds\n' "$record" >&2
    if [[ "$(kubectl auth can-i '*' '*' --as=oidc:probe --as-group="oidc:$org:brzl-admins" 2>/dev/null)" != yes ]]; then
      printf 'fix: in a hold the group oidc:%s:brzl-admins is cluster-admin, and it is not; see: kubectl get clusterrolebinding brzl-break-glass -o yaml\n' "$org" >&2
      return 1
    fi
    teams=(brzl-operators brzl-auditors)
  fi
  for team in "${teams[@]}"; do
    if [[ "$(kubectl auth can-i list pods --all-namespaces --as=oidc:probe --as-group="oidc:$org:$team" 2>/dev/null)" != yes \
        || "$(kubectl auth can-i create pods --as=oidc:probe --as-group="oidc:$org:$team" 2>/dev/null)" != no ]]; then
      printf 'fix: the group oidc:%s:%s does not have exactly the view role; see: kubectl get clusterrolebindings -o wide | grep %s; kubectl -n argocd get application access\n' \
        "$org" "$team" "$team" >&2
      return 1
    fi
  done
  if ! kubectl -n logs get networkpolicy log-store-admin-ingress >/dev/null 2>&1; then
    printf 'fix: the admin log store has no NetworkPolicy (logs/loki-admin.yaml, extraObjects); see: kubectl -n argocd get application log-store-admin\n' >&2
    return 1
  fi
  if ! kubectl -n sign-on get networkpolicy oauth2-proxy >/dev/null 2>&1; then
    printf 'fix: oauth2-proxy has no NetworkPolicy (sign-on/oauth2-proxy.yaml, networkPolicy); see: kubectl -n argocd get application oauth2-proxy\n' >&2
    return 1
  fi
  printf 'the admin portal at %s/ sends a request without a session to sign in at %s; Argo CD names that issuer; Grafana is healthy; /apps/%s/ is open; the portal is %s; the tiers have their kubectl rights; the admin log store admits only its writers; only the portal reaches oauth2-proxy\n' \
    "$url" "$issuer" "$BRZL_EXAMPLE_APP_NAME" "$ip"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,14p' "${BASH_SOURCE[0]}"; fi
fi
