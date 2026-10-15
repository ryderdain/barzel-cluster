#!/usr/bin/env bash
# k3d.sh — the substrate adapter for k3d (a k3s cluster in the local container
# engine), with a Zot registry beside it. Every substrate adapter has the same
# functions:
#
#   substrate_network_up            EMIT: the container network the registry,
#                                   the secret store and the cluster share
#   substrate_up <run_dir>          EMIT: make the registry and the cluster;
#                                   write <run_dir>/kubeconfig
#   substrate_down                  EMIT: remove the cluster (the registry stays)
#   substrate_image_ref <name:tag>  print the reference to push a locally built
#                                   image to, which the cluster can also pull
#   substrate_registry_host         print the registry host the cluster pulls
#                                   from (the ApplicationSet's registry-host)
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
# Public DNS has a local stand-in (ADR-0036): a CoreDNS container beside Zot
# that answers for the portal's host name only (127.0.0.1), from
# driver/substrates/k3d-dns.Corefile. The operating system must be told to
# ask it for that name; the check prints the line. This copy has no link to
# the cluster's own CoreDNS.
#
# Sourced by driver/phases/*.sh, never run on its own. Inputs: BRZL_K3D_*,
# BRZL_K3S_IMAGE, BRZL_DOCKER_NETWORK, BRZL_ZOT_*, BRZL_DNS_*, BRZL_PORTAL_*
# from the environment definition. Needs k3d, docker, kubectl, curl, dig. No
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
    [[ "$state" == stale ]] && printf '  docker rm -f %q   # its config changed; the cache volume stays\n' "$zot"
    printf '  docker run -d --name %q --network %q --restart unless-stopped \\\n' "$zot" "$BRZL_DOCKER_NETWORK"
    printf '    --label %q \\\n' "dev.brzl.zot-config-sha256=$sha"
    printf '    -p %q -v %q \\\n' "127.0.0.1:$port:5000" "$BRZL_ZOT_VOLUME:/var/lib/registry"
    printf '    -v %q \\\n' "$config:/etc/zot/config.json:ro"
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
  printf '{ # k3d cluster %s (no Traefik, no servicelb; the portal NodePort on host port %s), and its kubeconfig\n' \
    "$BRZL_K3D_CLUSTER" "$BRZL_PORTAL_PORT"
  printf '  k3d cluster create %q --image %q --servers %q --agents %q \\\n' \
    "$BRZL_K3D_CLUSTER" "$BRZL_K3S_IMAGE" "$BRZL_K3D_SERVERS" "$BRZL_K3D_AGENTS"
  printf '    --api-port %q --network %q --registry-config %q \\\n' \
    "127.0.0.1:$BRZL_K3D_API_PORT" "$BRZL_DOCKER_NETWORK" "$run_dir/registries.yaml"
  printf '    --k3s-arg %q --port %q --wait\n' \
    '--disable=traefik,servicelb@server:*' "127.0.0.1:$BRZL_PORTAL_PORT:$BRZL_PORTAL_NODE_PORT@server:0"
  printf '  k3d kubeconfig get %q > %q\n' "$BRZL_K3D_CLUSTER" "$run_dir/kubeconfig"
  printf '}\n'
}

# dns_up — EMIT: the local DNS stand-in (see the header). The container is
# replaced when the Corefile or the host name changes; it has no data.
dns_up() {
  local name="$BRZL_DNS_NAME" config sha state
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

# dns_check — GENERATOR: the stand-in runs (and answers, where dig exists).
# Whether the operator's machine asks it is checked only when the check runs
# on that machine (macOS); from kiesei it cannot be, so the one-time line is
# printed as information. Never a failure: it is the operator's machine.
dns_check() {
  local answer resolver="/etc/resolver/$BRZL_PORTAL_HOST"
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
  if [[ "$(uname)" == Darwin ]] \
      && [[ "$(dscacheutil -q host -a name "$BRZL_PORTAL_HOST" 2>/dev/null)" == *'ip_address: 127.0.0.1'* ]]; then
    return 0
  fi
  printf 'once, on your machine (macOS), so that it asks the stand-in for this name:\n' >&2
  printf '  sudo mkdir -p /etc/resolver && printf '"'"'nameserver 127.0.0.1\\nport %s\\n'"'"' | sudo tee %q >/dev/null\n' \
    "$BRZL_DNS_PORT" "$resolver" >&2
}

substrate_down() {
  printf '{ # remove k3d cluster %s and everything in it (Zot, its cache and the DNS stand-in stay)\n' "$BRZL_K3D_CLUSTER"
  printf '  k3d cluster delete %q\n' "$BRZL_K3D_CLUSTER"
  printf '}\n'
}

substrate_image_ref() {
  printf 'localhost:%s/brzl/%s' "$BRZL_ZOT_PORT" "$1"
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
  dns_check
}

substrate_check_down() {
  if k3d cluster get "$BRZL_K3D_CLUSTER" >/dev/null 2>&1; then
    printf 'fix: k3d cluster delete %q\n' "$BRZL_K3D_CLUSTER" >&2
    return 1
  fi
  printf 'k3d cluster %s is gone (Zot %s, its cache and the DNS stand-in %s are kept)\n' \
    "$BRZL_K3D_CLUSTER" "$BRZL_ZOT_NAME" "$BRZL_DNS_NAME"
}
