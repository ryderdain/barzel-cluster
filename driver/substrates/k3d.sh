#!/usr/bin/env bash
# k3d.sh — the substrate adapter for k3d (a k3s cluster in the local container
# engine), with a Zot registry beside it. Every substrate adapter has the same
# functions:
#
#   substrate_network_up            EMIT: the container network the registry,
#                                   the secret store and the cluster share
#   substrate_up <run_dir>          EMIT: make the registry and the cluster;
#                                   write <run_dir>/kubeconfig
#   substrate_down                  EMIT: remove the cluster (the registry and
#                                   the collector beside it stay)
#   substrate_image_ref <name:tag>  print the reference to push a locally built
#                                   image to, which the cluster can also pull
#   substrate_registry_host         print the registry host the cluster pulls
#                                   from (the ApplicationSet's registry-host)
#   substrate_registry_credentials_file   the registry's upstream credentials file
#   substrate_registry_reload             EMIT: the registry reads that file again
#   substrate_upstream_prefix <upstream>
#                                   print the path under that host for an
#                                   upstream: docker-hub, github, quay, k8s
#   substrate_check <run_dir>       GENERATOR: registry ready, cluster Ready?
#   substrate_check_down            GENERATOR: is the cluster gone?
#
# The registry is Zot (ADR-0023), outside the cluster, on its own volume, so its
# cache survives `down`. It is a pull-through cache for docker.io, ghcr.io,
# quay.io, registry.k8s.io and public.ecr.aws (k3s
# mirrors rewrite each upstream into its own namespace in Zot), and the push
# registry for images built here, under localhost:<port> from the host and from
# the cluster alike. The same namespaces serve injected image paths:
# localhost:<port>/quay.io/argoproj/argocd is quay.io/argoproj/argocd.
#
# Zot reads its config only when it starts. The container carries the config's
# sha256 as a label; when the label differs from the committed config, `up`
# replaces the container (its data volume stays).
#
# The k3s image is pinned to the cloud's k3s version. The API listens on
# 127.0.0.1:<port>, so one kubeconfig works on the host and in a kiesei
# container on the host network (driver/kiesei.sh). k3s's bundled Traefik and
# service load balancer are off: the platform layer does not use them (SPEC
# §3 portability), and a cloud gives no ingress for free either. The admin
# portal's NodePort is mapped to a host port instead (ADR-0028).
#
# Logs (ADR-0027). The admin log store's data is a host directory,
# BRZL_LOG_STORE_DIR/admin, mounted into the server node; the admin Loki in
# the cluster keeps it there, so it outlives the cluster as a bucket would.
# The API server writes an audit log (k3s-audit-policy.yaml, metadata level)
# and k3s writes its own log to a file, both on the server node, where the
# in-cluster collector reads them. A collector beside the cluster
# (BRZL_LOG_COLLECTOR_NAME, config k3d-otelcol.yaml) reads the run outputs in
# var/run/<env>/ and the secret store's audit log, and sends them to the
# in-cluster collector's host port on the server node, over the shared
# container network, with mutual TLS: its client certificate comes from the
# store's CA (phase 10, BRZL_SECRET_STORE_DIR/log-shipper/), and it expects
# the receiver's certificate for log-intake.<portal host> (BACKLOG 4a). It
# queues on disk in BRZL_LOG_STORE_DIR/queue while the cluster is absent. It is replaced when its config changes, like Zot.
#
# Public DNS has a local stand-in (ADR-0036), used only when the portal's host
# name is not under .localhost (a name the operator chose, as if public): a
# CoreDNS container beside Zot that answers for that one name (127.0.0.1),
# from driver/substrates/k3d-dns.Corefile. The operating system must be told
# to ask it for that name; the check prints the line. This copy has no link
# to the cluster's own CoreDNS. A .localhost name (the default,
# brzl-<env>.localhost) resolves to 127.0.0.1 by itself on macOS and in
# browsers, so it needs no stand-in.
#
# Sourced by driver/phases/*.sh, never run on its own. Inputs: BRZL_K3D_*,
# BRZL_K3S_IMAGE, BRZL_DOCKER_NETWORK, BRZL_ZOT_*, BRZL_DNS_*, BRZL_PORTAL_*,
# BRZL_LOG_* from the environment definition. Needs k3d, docker, kubectl, curl, dig. No
# credentials (anonymous upstream pulls). The sourcing phase script sets
# repo_root.
# shellcheck disable=SC2154

# container_state <name> <label> <want> — print `absent`, `current` or `stale`
# for a container that carries its config's sha256 as a label, read from the
# engine when the phase is emitted.
container_state() {
  local name="$1" label="$2" want="$3" have
  if ! have="$(docker inspect --format "{{ index .Config.Labels \"$label\" }}" "$name" 2>/dev/null)"; then
    printf absent
  elif [[ "$have" == "$want" ]]; then
    printf current
  else
    printf stale
  fi
}

substrate_network_up() {
  printf '{ # container network shared by the registry, the secret store and the cluster\n'
  printf '  docker network create %q\n' "$BRZL_DOCKER_NETWORK"
  printf '}\n'
}

substrate_up() {
  local run_dir="$1" zot="$BRZL_ZOT_NAME" port="$BRZL_ZOT_PORT" config sha state
  config="$repo_root/driver/substrates/k3d-zot.json"
  sha="$(sha256sum < "$config")"; sha="${sha%% *}"
  state="$(container_state "$zot" dev.brzl.zot-config-sha256 "$sha")"
  if [[ "$state" == current ]]; then
    printf '{ # Zot registry: its config is current; make sure it runs\n'
    printf '  docker start %q\n' "$zot"
    printf '}\n'
  else
    printf '{ # Zot registry (pull-through cache + push registry); its data outlives the cluster\n'
    printf '  docker volume create %q\n' "$BRZL_ZOT_VOLUME"
    # The upstream credentials file (a private workload's packages token, ADR-0034):
    # phase 25 writes it from the store and reloads Zot; until then it is empty.
    printf '  [[ -e %q ]] || { umask 077; mkdir -p %q; printf '"'"'{}\\n'"'"' > %q; }\n' \
      "$(substrate_registry_credentials_file)" "$BRZL_SECRET_STORE_DIR" "$(substrate_registry_credentials_file)"
    [[ "$state" == stale ]] && printf '  docker rm -f %q   # its config changed; the cache volume stays\n' "$zot"
    printf '  docker run -d --name %q --network %q --restart unless-stopped \\\n' "$zot" "$BRZL_DOCKER_NETWORK"
    printf '    --label %q \\\n' "dev.brzl.zot-config-sha256=$sha"
    printf '    -p %q -v %q \\\n' "127.0.0.1:$port:5000" "$BRZL_ZOT_VOLUME:/var/lib/registry"
    printf '    -v %q \\\n' "$config:/etc/zot/config.json:ro"
    printf '    -v %q \\\n' "$repo_root/$(substrate_registry_credentials_file):/etc/zot/credentials.json:ro"
    printf '    %q\n' "$BRZL_ZOT_IMAGE"
    printf '}\n'
  fi
  printf '{ # k3s registry mirrors: each upstream through Zot, in its own namespace\n'
  printf "  cat > %q <<'EOF'\n" "$run_dir/registries.yaml"
  printf 'mirrors:\n'
  local upstream
  for upstream in docker.io ghcr.io quay.io registry.k8s.io public.ecr.aws; do
    # shellcheck disable=SC2016  # "$1" is for containerd's rewrite, not for bash
    printf '  %s:\n    endpoint: ["http://%s:5000"]\n    rewrite:\n      "^(.*)$": "%s/$1"\n' \
      "$upstream" "$zot" "$upstream"
  done
  printf '  "localhost:%s":\n    endpoint: ["http://%s:5000"]\n' "$port" "$zot"
  printf 'EOF\n'
  printf '}\n'
  dns_up
  log_collector_up "$run_dir"
  local arg
  printf '{ # k3d cluster %s (no Traefik, no servicelb; the portal NodePort on host port %s;\n' \
    "$BRZL_K3D_CLUSTER" "$BRZL_PORTAL_PORT"
  printf '  # the admin log store'"'"'s data and the API audit policy mounted in), and its kubeconfig\n'
  printf '  k3d cluster create %q --image %q --servers %q --agents %q \\\n' \
    "$BRZL_K3D_CLUSTER" "$BRZL_K3S_IMAGE" "$BRZL_K3D_SERVERS" "$BRZL_K3D_AGENTS"
  printf '    --api-port %q --network %q --registry-config %q \\\n' \
    "127.0.0.1:$BRZL_K3D_API_PORT" "$BRZL_DOCKER_NETWORK" "$run_dir/registries.yaml"
  printf '    --volume %q \\\n' \
    "$repo_root/$BRZL_LOG_STORE_DIR/admin:/var/lib/brzl/admin-log-store@server:0" \
    "$repo_root/driver/substrates/k3s-audit-policy.yaml:/etc/brzl/audit-policy.yaml@server:*"
  for arg in --disable=traefik,servicelb \
      --kube-apiserver-arg=audit-policy-file=/etc/brzl/audit-policy.yaml \
      --kube-apiserver-arg=audit-log-path=/var/log/kubernetes/audit/audit.log \
      --kube-apiserver-arg=audit-log-maxsize=50 --kube-apiserver-arg=audit-log-maxbackup=3 \
      --log=/var/log/k3s.log --alsologtostderr; do
    printf '    --k3s-arg %q \\\n' "$arg@server:*"
  done
  printf '    --port %q --wait\n' "127.0.0.1:$BRZL_PORTAL_PORT:$BRZL_PORTAL_NODE_PORT@server:0"
  printf '  k3d kubeconfig get %q > %q\n' "$BRZL_K3D_CLUSTER" "$run_dir/kubeconfig"
  printf '}\n'
  cluster_dns_up
}

# cluster_dns_up — EMIT: in the cluster, the portal's host name is the
# portal's Service. Browsers reach Dex at https://<host>/dex through the
# portal; Argo CD, oauth2-proxy and Grafana must reach the same issuer URL
# from their pods (sign-on, pass 6a). k3s's CoreDNS reads extra rules from
# the ConfigMap coredns-custom; the restart makes it read them at once.
cluster_dns_up() {
  local svc=portal.portal.svc.cluster.local
  printf '{ # in the cluster, %s is the portal'"'"'s Service (so pods reach Dex at the issuer URL)\n' "$BRZL_PORTAL_HOST"
  printf "  kubectl apply -f - <<'EOF'\n"
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: coredns-custom\n  namespace: kube-system\n'
  printf 'data:\n  brzl-portal.override: |\n'
  printf '    rewrite stop {\n      name exact %s %s\n      answer name %s %s\n    }\n' \
    "$BRZL_PORTAL_HOST" "$svc" "$svc" "$BRZL_PORTAL_HOST"
  printf 'EOF\n'
  printf '  kubectl -n kube-system rollout restart deployment/coredns\n'
  printf '}\n'
}

# substrate_host_steps — print the part of the host run sheet (phase 10,
# Q180) that makes the operator's machine resolve the portal's host name:
# on macOS a file in /etc/resolver that sends the name to the DNS stand-in,
# on Linux a line in /etc/hosts. Each step is added only when it is not
# done; the sheet runs on the host, so it can tell. Nothing for a .localhost
# name.
# shellcheck disable=SC2016  # the host run sheet expands these, not this script
substrate_host_steps() {
  local host="$BRZL_PORTAL_HOST" want
  dns_needed || return 0
  want="nameserver 127.0.0.1"$'\n'"port $BRZL_DNS_PORT"
  printf '# resolve %s: ask the DNS stand-in on 127.0.0.1:%s (macOS), or /etc/hosts (Linux)\n' "$host" "$BRZL_DNS_PORT"
  printf 'if [[ "$(uname)" == Darwin ]]; then\n'
  printf '  if [[ "$(cat %s 2>/dev/null)" != %q ]]; then\n' "/etc/resolver/$host" "$want"
  printf '    steps+=(%s\n' "$(squote "sudo mkdir -p /etc/resolver")"
  printf '           %s)\n' "$(squote "printf 'nameserver 127.0.0.1\\nport $BRZL_DNS_PORT\\n' | sudo tee /etc/resolver/$host >/dev/null")"
  printf '  fi\n'
  printf 'elif ! grep -Eq %s /etc/hosts; then\n' "$(squote "^127\\.0\\.0\\.1[[:space:]]+(.*[[:space:]])?${host//./\\.}([[:space:]]|\$)")"
  printf '  steps+=(%s)\n' "$(squote "printf '127.0.0.1 $host\\n' | sudo tee -a /etc/hosts >/dev/null")"
  printf 'fi\n'
}

# log_collector_up <run_dir> — EMIT: the log store's directories and the
# collector beside the cluster (see the header). The environment's name and
# its run directories come from the run directory, var/run/<env>/<run>.
log_collector_up() {
  local run_dir="$1" name="$BRZL_LOG_COLLECTOR_NAME" dir="$BRZL_LOG_STORE_DIR" runs env endpoint intake config sha state
  runs="${run_dir%/*}"; env="${runs##*/}"
  endpoint="https://k3d-$BRZL_K3D_CLUSTER-server-0:4318"
  intake="log-intake.$BRZL_PORTAL_HOST"         # the receiver's certificate name (BACKLOG 4a)
  config="$repo_root/driver/substrates/k3d-otelcol.yaml"
  sha="$(cat "$config" <(printf '%s %s %s %s' "$env" "$endpoint" "$intake" "$BRZL_LOG_COLLECTOR_IMAGE") | sha256sum)"; sha="${sha%% *}"
  state="$(container_state "$name" dev.brzl.log-collector-config-sha256 "$sha")"
  printf '{ # the log store'"'"'s directories beside the cluster: the admin log store'"'"'s data, the collector'"'"'s queue\n'
  printf '  mkdir -p %q %q\n' "$dir/admin" "$dir/queue"
  printf '}\n'
  if [[ "$state" == current ]]; then
    printf '{ # collector beside the cluster: its config is current; make sure it runs\n'
    printf '  docker start %q\n' "$name"
    printf '}\n'
    return 0
  fi
  printf '{ # collector beside the cluster (ADR-0027): run outputs and the store'"'"'s audit log to the\n'
  printf '  # cluster'"'"'s collector at %s; it queues on disk while the cluster is absent\n' "$endpoint"
  [[ "$state" == stale ]] && printf '  docker rm -f %q   # its config changed; the queue stays\n' "$name"
  printf '  docker run -d --name %q --network %q --restart unless-stopped --user 0 \\\n' "$name" "$BRZL_DOCKER_NETWORK"
  printf '    --label %q \\\n' "dev.brzl.log-collector-config-sha256=$sha"
  printf '    -e %q -e %q -e %q \\\n' "BRZL_ENV=$env" "BRZL_OTLP_ENDPOINT=$endpoint" "BRZL_LOG_INTAKE_NAME=$intake"
  printf '    -v %q \\\n' \
    "$config:/etc/otelcol-contrib/config.yaml:ro" \
    "$repo_root/$runs:/run-outputs:ro" \
    "$repo_root/$dir/openbao-audit:/openbao-audit:ro" \
    "$repo_root/$dir/queue:/queue" \
    "$repo_root/$BRZL_SECRET_STORE_DIR/log-shipper:/tls:ro"
  printf '    %q\n' "$BRZL_LOG_COLLECTOR_IMAGE"
  printf '}\n'
}

# dns_needed — is the portal's host name one the stand-in must answer for?
dns_needed() { [[ "$BRZL_PORTAL_HOST" != *.localhost ]]; }

# dns_up — EMIT: the local DNS stand-in (see the header). The container is
# replaced when the Corefile or the host name changes; it has no data.
dns_up() {
  local name="$BRZL_DNS_NAME" config sha state
  dns_needed || return 0
  config="$repo_root/driver/substrates/k3d-dns.Corefile"
  sha="$(cat "$config" <(printf '%s' "$BRZL_PORTAL_HOST") | sha256sum)"; sha="${sha%% *}"
  state="$(container_state "$name" dev.brzl.dns-config-sha256 "$sha")"
  if [[ "$state" == current ]]; then
    printf '{ # local DNS stand-in for %s: its config is current; make sure it runs\n' "$BRZL_PORTAL_HOST"
    printf '  docker start %q\n' "$name"
    printf '}\n'
    return 0
  fi
  printf '{ # local DNS stand-in (ADR-0036): answers %s -> 127.0.0.1 on 127.0.0.1:%s, nothing else\n' \
    "$BRZL_PORTAL_HOST" "$BRZL_DNS_PORT"
  [[ "$state" == stale ]] && printf '  docker rm -f %q   # its config or host name changed\n' "$name"
  printf '  docker run -d --name %q --network %q --restart unless-stopped \\\n' "$name" "$BRZL_DOCKER_NETWORK"
  printf '    --label %q -e %q \\\n' "dev.brzl.dns-config-sha256=$sha" "BRZL_PORTAL_HOST=$BRZL_PORTAL_HOST"
  printf '    -p %q -p %q \\\n' "127.0.0.1:$BRZL_DNS_PORT:53/udp" "127.0.0.1:$BRZL_DNS_PORT:53/tcp"
  printf '    -v %q \\\n' "$config:/Corefile:ro"
  printf '    %q -conf /Corefile\n' "$BRZL_DNS_IMAGE"
  printf '}\n'
}

# dns_check <run_dir> — GENERATOR: the stand-in runs (and answers, where dig exists).
# Whether the operator's machine asks it is checked only when the check runs
# on that machine; in kiesei (BRZL_HOST_OS is set) it cannot be, so the check
# names the host run sheet as information. Never a failure: it is the
# operator's machine.
dns_check() {
  local answer
  if ! dns_needed; then
    printf 'portal host %s is under .localhost: it resolves to 127.0.0.1 by itself (no DNS stand-in)\n' "$BRZL_PORTAL_HOST"
    return 0
  fi
  if [[ "$(docker inspect --format '{{ .State.Running }}' "$BRZL_DNS_NAME" 2>/dev/null)" != true ]]; then
    printf 'fix: the local DNS stand-in %s is not running; see: docker logs %s\n' "$BRZL_DNS_NAME" "$BRZL_DNS_NAME" >&2
    return 1
  fi
  if command -v dig >/dev/null 2>&1; then
    answer="$(dig +short +time=2 +tries=1 @127.0.0.1 -p "$BRZL_DNS_PORT" "$BRZL_PORTAL_HOST" 2>/dev/null)"
    if [[ "$answer" != 127.0.0.1 ]]; then
      printf 'fix: the local DNS stand-in does not answer %s on 127.0.0.1:%s; see: docker logs %s\n' \
        "$BRZL_PORTAL_HOST" "$BRZL_DNS_PORT" "$BRZL_DNS_NAME" >&2
      return 1
    fi
  fi
  printf 'local DNS stand-in %s runs: %s -> 127.0.0.1 on 127.0.0.1:%s\n' "$BRZL_DNS_NAME" "$BRZL_PORTAL_HOST" "$BRZL_DNS_PORT"
  if [[ -n "${BRZL_HOST_OS:-}" ]]; then
    printf 'whether your machine resolves %s is in the host run sheet (10-host.sh, docs/LOCAL.md)\n' "$BRZL_PORTAL_HOST"
    return 0
  fi
  if [[ "$(uname)" == Darwin ]]; then
    [[ "$(dscacheutil -q host -a name "$BRZL_PORTAL_HOST" 2>/dev/null)" == *'ip_address: 127.0.0.1'* ]] && return 0
  else
    getent hosts "$BRZL_PORTAL_HOST" >/dev/null 2>&1 && return 0
  fi
  operator_step "your machine does not resolve $BRZL_PORTAL_HOST yet. The host run sheet does it:" \
    "bash $1/10-host.sh"
}

substrate_down() {
  printf '{ # remove k3d cluster %s and everything in it (Zot, its cache, the DNS stand-in,\n' "$BRZL_K3D_CLUSTER"
  printf '  # the collector beside the cluster and the admin log store'"'"'s data stay)\n'
  printf '  k3d cluster delete %q\n' "$BRZL_K3D_CLUSTER"
  printf '}\n'
}

substrate_image_ref() {
  printf 'localhost:%s/brzl/%s' "$BRZL_ZOT_PORT" "$1"
}

# substrate_registry_credentials_file — where the registry reads its upstream
# credentials (Zot's sync credentialsFile), relative to the repo root; in the
# store's directory, which is gitignored and holds the driver's secret files.
substrate_registry_credentials_file() {
  printf '%s/zot-credentials.json' "$BRZL_SECRET_STORE_DIR"
}

# substrate_registry_reload — EMIT: make the registry read its credentials
# file again (Zot reads it at start).
substrate_registry_reload() {
  printf '  docker restart %q >/dev/null\n' "$BRZL_ZOT_NAME"
}

substrate_registry_host() {
  printf 'localhost:%s' "$BRZL_ZOT_PORT"
}

substrate_upstream_prefix() {
  case "$1" in
    docker-hub) printf 'docker.io' ;;
    github) printf 'ghcr.io' ;;
    quay) printf 'quay.io' ;;
    k8s) printf 'registry.k8s.io' ;;
    *) printf 'error: no upstream %s in the k3d adapter\n' "$1" >&2; return 1 ;;
  esac
}

substrate_check() {
  local run_dir="$1" not_ready
  if ! curl -fsS "http://127.0.0.1:$BRZL_ZOT_PORT/readyz" >/dev/null 2>&1; then
    printf 'fix: Zot is not ready on 127.0.0.1:%s; see: docker logs %s\n' \
      "$BRZL_ZOT_PORT" "$BRZL_ZOT_NAME" >&2
    return 1
  fi
  if ! k3d cluster get "$BRZL_K3D_CLUSTER" >/dev/null 2>&1; then
    printf 'fix: the cluster %s does not exist; run the 10-substrate phase again\n' \
      "$BRZL_K3D_CLUSTER" >&2
    return 1
  fi
  if [[ ! -s "$run_dir/kubeconfig" ]]; then
    printf 'fix: k3d kubeconfig get %q > %q\n' "$BRZL_K3D_CLUSTER" "$run_dir/kubeconfig" >&2
    return 1
  fi
  if ! not_ready="$(kubectl --kubeconfig "$run_dir/kubeconfig" get nodes --no-headers 2>&1)"; then
    printf 'fix: the cluster API does not answer: %s\n' "$not_ready" >&2
    return 1
  fi
  not_ready="$(grep -v ' Ready ' <<< "$not_ready")"
  if [[ -n "$not_ready" ]]; then
    printf 'fix: nodes not Ready yet; wait and check again:\n%s\n' "$not_ready" >&2
    return 1
  fi
  printf 'Zot is ready on 127.0.0.1:%s; k3d cluster %s is up and its nodes are Ready\n' \
    "$BRZL_ZOT_PORT" "$BRZL_K3D_CLUSTER"
  if [[ "$(docker inspect --format '{{ .State.Running }}' "$BRZL_LOG_COLLECTOR_NAME" 2>/dev/null)" != true ]]; then
    printf 'fix: the collector beside the cluster %s is not running; see: docker logs %s\n' \
      "$BRZL_LOG_COLLECTOR_NAME" "$BRZL_LOG_COLLECTOR_NAME" >&2
    return 1
  fi
  printf 'the collector beside the cluster %s runs\n' "$BRZL_LOG_COLLECTOR_NAME"
  if [[ "$(kubectl --kubeconfig "$run_dir/kubeconfig" -n kube-system get configmap coredns-custom \
        -o jsonpath='{.data.brzl-portal\.override}' 2>/dev/null)" != *"name exact $BRZL_PORTAL_HOST "* ]]; then
    printf 'fix: the cluster'"'"'s CoreDNS does not answer %s with the portal'"'"'s Service (ConfigMap kube-system/coredns-custom); run the 10-substrate phase again\n' \
      "$BRZL_PORTAL_HOST" >&2
    return 1
  fi
  printf 'in the cluster, %s is the portal'"'"'s Service\n' "$BRZL_PORTAL_HOST"
  dns_check "$run_dir"
}

substrate_check_down() {
  if k3d cluster get "$BRZL_K3D_CLUSTER" >/dev/null 2>&1; then
    printf 'fix: k3d cluster delete %q\n' "$BRZL_K3D_CLUSTER" >&2
    return 1
  fi
  printf 'k3d cluster %s is gone (Zot %s, its cache, the DNS stand-in %s and the collector %s are kept)\n' \
    "$BRZL_K3D_CLUSTER" "$BRZL_ZOT_NAME" "$BRZL_DNS_NAME" "$BRZL_LOG_COLLECTOR_NAME"
}
