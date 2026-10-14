#!/usr/bin/env bash
# SPIKE (branch spike-logs, never merged) — the pass-6 log design, tried
# beside the local cluster: OTel Collector + two Loki installations + Grafana.
#
# Archetype: emit (annotate, up, kill_admin, reader, down) and read-only
# check (check). The emit functions print commands; pipe them to bash.
#
#   bash spikes/logs/spike.sh annotate | bash   # optional: route two namespaces
#   bash spikes/logs/spike.sh up       | bash   # snapshot data, start the stack
#     (round 2: SPIKE_ADMIN_FLUSH=short bash spikes/logs/spike.sh up | bash)
#   bash spikes/logs/spike.sh check admin       # also: diagnostic, reader
#   bash spikes/logs/spike.sh kill_admin | bash # the cluster is lost
#   bash spikes/logs/spike.sh reader   | bash   # break-glass read of the data
#   bash spikes/logs/spike.sh down     | bash   # remove the stack, the annotations
#
# Needs: a running local cluster (driver.sh local up), docker, kubectl, curl,
# jq. Grafana: http://127.0.0.1:3000 (anonymous, localhost only).
# Results and data: var/spike-logs/ (gitignored). The kubeconfig copy there
# holds the cluster's client key; it stays mode 600 and in var/.
(( BASH_VERSINFO[0] < 4 )) && { printf 'error: bash >= 4 required\n' >&2; exit 1; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$root/spikes/logs"
spike="$root/var/spike-logs"
cluster=brzl-local                       # BRZL_K3D_CLUSTER
network=brzl-local                       # BRZL_DOCKER_NETWORK
node="k3d-$cluster-server-0"
kubeconfig="$root/var/run/local/current/kubeconfig"

loki_image=grafana/loki:3.7.8
otelcol_image=otel/opentelemetry-collector-contrib:0.162.0
grafana_image=grafana/grafana:13.2.4

declare -A port=([admin]=3101 [diagnostic]=3102 [reader]=3103)

# Round 2: a short flush on the admin Loki, to measure the loss window.
admin_flush=''
if [[ "${SPIKE_ADMIN_FLUSH:-}" == short ]]; then
  admin_flush='-e LOKI_CHUNK_IDLE_PERIOD=1m -e LOKI_MAX_CHUNK_AGE=5m '
fi

annotate() {
  cat <<EOF
# demo: diagnostic and cold, kept 30 days; kube-system: dropped (Q95, Q98)
{
  kubectl --kubeconfig '$kubeconfig' annotate namespace demo --overwrite \\
    brzl.dev/log-routes=diagnostic,cold brzl.dev/log-retention=30d
  kubectl --kubeconfig '$kubeconfig' annotate namespace kube-system --overwrite \\
    brzl.dev/log-routes=drop
}
EOF
}

up() {
  cat <<EOF
# snapshot: run-logs, pod logs and the k3s server log; a kubeconfig for the
# collector that reaches the API over the docker network
{
  mkdir -p '$spike/data/run-logs/local' '$spike/data/k3s-server' '$spike/admin-store' '$spike/cold'
  cp -R '$root/var/run/local/'[0-9]* '$spike/data/run-logs/local/'
  docker cp '$node:/var/log/pods' '$spike/data/pods'
  docker logs '$node' > '$spike/data/k3s-server/server.log' 2>&1
  awk '/certificate-authority-data:/ { next }
       /^ *server: / { i = substr(\$0, 1, index(\$0, "server:") - 1)
                       print i "server: https://$node:6443"
                       print i "insecure-skip-tls-verify: true"; next }
       { print }' '$kubeconfig' > '$spike/data/kubeconfig'
  chmod 600 '$spike/data/kubeconfig'
}

# admin log store: data on a host directory (stands in for the bucket),
# working state (WAL) in a volume (stands in for the cluster)
docker run -d --name brzl-spike-loki-admin --network '$network' --user 0 \\
  -p 127.0.0.1:${port[admin]}:3100 \\
  -v '$here/loki.yaml:/etc/loki/loki.yaml:ro' \\
  -v '$spike/admin-store:/store' -v brzl-spike-loki-admin-work:/loki \\
  -e LOKI_RETENTION_PERIOD=2160h $admin_flush\\
  '$loki_image' -config.file=/etc/loki/loki.yaml -config.expand-env=true

# diagnostic log store: everything in one volume (lost with the cluster)
docker run -d --name brzl-spike-loki-diagnostic --network '$network' --user 0 \\
  -p 127.0.0.1:${port[diagnostic]}:3100 \\
  -v '$here/loki.yaml:/etc/loki/loki.yaml:ro' \\
  -v brzl-spike-loki-diagnostic-work:/loki -e LOKI_STORE_DIR=/loki/store \\
  -e LOKI_RETENTION_PERIOD=168h \\
  '$loki_image' -config.file=/etc/loki/loki.yaml -config.expand-env=true

docker run -d --name brzl-spike-grafana --network '$network' \\
  -p 127.0.0.1:3000:3000 \\
  -e GF_AUTH_ANONYMOUS_ENABLED=true -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \\
  -e GF_AUTH_DISABLE_LOGIN_FORM=true \\
  -v '$here/grafana-datasources.yaml:/etc/grafana/provisioning/datasources/spike.yaml:ro' \\
  '$grafana_image'

docker run -d --name brzl-spike-otelcol --network '$network' --user 0 \\
  -e KUBECONFIG=/data/kubeconfig \\
  -v '$here/otelcol.yaml:/etc/otelcol/config.yaml:ro' \\
  -v '$spike/data:/data:ro' -v '$spike/cold:/cold' \\
  '$otelcol_image' --config=/etc/otelcol/config.yaml
EOF
}

kill_admin() {
  cat <<EOF
# the cluster is lost: the admin Loki and its WAL go, the host directory stays
docker kill brzl-spike-loki-admin
docker rm brzl-spike-loki-admin
docker volume rm brzl-spike-loki-admin-work
EOF
}

reader() {
  cat <<EOF
# break-glass reader: a fresh Loki on the admin data alone, no WAL, no retention
docker run -d --name brzl-spike-loki-admin-reader --network '$network' --user 0 \\
  -p 127.0.0.1:${port[reader]}:3100 \\
  -v '$here/loki.yaml:/etc/loki/loki.yaml:ro' -v '$spike/admin-store:/store' \\
  -e LOKI_RETENTION_ENABLED=false \\
  '$loki_image' -config.file=/etc/loki/loki.yaml -config.expand-env=true
EOF
}

down() {
  cat <<EOF
docker rm -f brzl-spike-otelcol brzl-spike-grafana brzl-spike-loki-admin brzl-spike-loki-diagnostic brzl-spike-loki-admin-reader
docker volume rm brzl-spike-loki-admin-work brzl-spike-loki-diagnostic-work
{
  kubectl --kubeconfig '$kubeconfig' annotate namespace demo brzl.dev/log-routes- brzl.dev/log-retention-
  kubectl --kubeconfig '$kubeconfig' annotate namespace kube-system brzl.dev/log-routes-
}
# the data stays in $spike; remove it by hand when the verdict is written
EOF
}

# read-only: one LogQL instant query, one line per series
query() {
  local store="$1" logql="$2"
  printf '\n## %s\n' "$logql"
  curl -sG "http://127.0.0.1:${port[$store]}/loki/api/v1/query" \
    --data-urlencode "query=$logql" \
    | jq -r '.data.result[]? | "\(.metric | to_entries | map("\(.key)=\(.value)") | join(" "))  \(.value[1])"'
}

check() {
  local store="${1:-admin}"
  [[ -n "${port[$store]:-}" ]] || { printf 'usage: check admin|diagnostic|reader\n' >&2; return 2; }
  printf '# %s: ready = %s\n' "$store" "$(curl -s "http://127.0.0.1:${port[$store]}/ready")"
  printf '# labels: %s\n' "$(curl -s "http://127.0.0.1:${port[$store]}/loki/api/v1/labels" | jq -c '.data')"
  query "$store" 'sum by (brzl_store, brzl_source) (count_over_time({brzl_source=~".+"}[7d]))'
  query "$store" 'sum by (brzl_run, brzl_phase) (count_over_time({brzl_source="run-log"}[7d]))'
  query "$store" 'sum (count_over_time({brzl_source="run-log"} |= "smoke" [7d]))'
  query "$store" 'sum by (k8s_namespace_name, brzl_retention) (count_over_time({brzl_source="pod"}[7d]))'

  printf '\n# expected: lines per run-log in the snapshot\n'
  ( cd "$spike/data/run-logs/local" && wc -l -- */*.out )
  printf '\n# admin store: files in storage\n'
  ( cd "$spike/admin-store" && find . -type f | sed 's#/[^/]*$##' | sort | uniq -c )
  printf '\n# memory\n'
  docker stats --no-stream --format '{{.Name}}  {{.MemUsage}}' \
    | grep brzl-spike
  printf '\n# cold: records per class\n'
  local file
  for file in "$spike"/cold/*.jsonl; do
    [[ -e "$file" ]] || continue
    printf '%s  %s\n' "${file##*/}" \
      "$(jq -s 'map([.resourceLogs[].scopeLogs[].logRecords | length] | add) | add' "$file")"
  done
}

if (( $# )); then "$@"; else sed -n '2,19p' "${BASH_SOURCE[0]}"; fi
