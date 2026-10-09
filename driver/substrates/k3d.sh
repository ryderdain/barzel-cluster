#!/usr/bin/env bash
# k3d.sh — the substrate adapter for k3d (a k3s cluster in the local container
# engine), with a Zot registry beside it. Every substrate adapter has the same
# functions:
#
#   substrate_up <run_dir>          EMIT: make the registry and the cluster;
#                                   write <run_dir>/kubeconfig
#   substrate_down                  EMIT: remove the cluster (the registry stays)
#   substrate_image_ref <name:tag>  print the reference to push a locally built
#                                   image to, which the cluster can also pull
#   substrate_check <run_dir>       GENERATOR: registry ready, cluster Ready?
#   substrate_check_down            GENERATOR: is the cluster gone?
#
# The registry is Zot (ADR-0023), outside the cluster, on its own volume, so its
# cache survives `down`. It is a pull-through cache for docker.io, ghcr.io,
# quay.io, registry.k8s.io and oci.external-secrets.io (k3s mirrors rewrite each upstream into its own
# namespace in Zot), and the push registry for images built here, under
# localhost:<port> from the host and from the cluster alike.
#
# The k3s image is pinned to the cloud's k3s version. The API listens on
# 127.0.0.1:<port>, so one kubeconfig works on the host and in a kiesei
# container on the host network (driver/kiesei.sh).
#
# Sourced by driver/phases/*.sh, never run on its own. Inputs: BRZL_K3D_*,
# BRZL_K3S_IMAGE, BRZL_DOCKER_NETWORK, BRZL_ZOT_* from the environment
# definition. Needs k3d, docker, kubectl, curl. No credentials (anonymous
# upstream pulls). The sourcing phase script sets repo_root.
# shellcheck disable=SC2154

substrate_up() {
  local run_dir="$1" zot="$BRZL_ZOT_NAME" port="$BRZL_ZOT_PORT"
  printf '{ # container network shared by the registry and the cluster\n'
  printf '  docker network create %q\n' "$BRZL_DOCKER_NETWORK"
  printf '}\n'
  printf '{ # Zot registry (pull-through cache + push registry); its data outlives the cluster\n'
  printf '  docker volume create %q\n' "$BRZL_ZOT_VOLUME"
  printf '  docker run -d --name %q --network %q --restart unless-stopped \\\n' "$zot" "$BRZL_DOCKER_NETWORK"
  printf '    -p %q -v %q \\\n' "127.0.0.1:$port:5000" "$BRZL_ZOT_VOLUME:/var/lib/registry"
  printf '    -v %q \\\n' "$repo_root/driver/substrates/k3d-zot.json:/etc/zot/config.json:ro"
  printf '    %q\n' "$BRZL_ZOT_IMAGE"
  printf '}\n'
  printf '{ # k3s registry mirrors: each upstream through Zot, in its own namespace\n'
  printf "  cat > %q <<'EOF'\n" "$run_dir/registries.yaml"
  printf 'mirrors:\n'
  local upstream
  for upstream in docker.io ghcr.io quay.io registry.k8s.io oci.external-secrets.io; do
    # shellcheck disable=SC2016  # "$1" is for containerd's rewrite, not for bash
    printf '  %s:\n    endpoint: ["http://%s:5000"]\n    rewrite:\n      "^(.*)$": "%s/$1"\n' \
      "$upstream" "$zot" "$upstream"
  done
  printf '  "localhost:%s":\n    endpoint: ["http://%s:5000"]\n' "$port" "$zot"
  printf 'EOF\n'
  printf '}\n'
  printf '{ # k3d cluster %s, and its kubeconfig for the later phases\n' "$BRZL_K3D_CLUSTER"
  printf '  k3d cluster create %q --image %q --servers %q --agents %q \\\n' \
    "$BRZL_K3D_CLUSTER" "$BRZL_K3S_IMAGE" "$BRZL_K3D_SERVERS" "$BRZL_K3D_AGENTS"
  printf '    --api-port %q --network %q --registry-config %q --wait\n' \
    "127.0.0.1:$BRZL_K3D_API_PORT" "$BRZL_DOCKER_NETWORK" "$run_dir/registries.yaml"
  printf '  k3d kubeconfig get %q > %q\n' "$BRZL_K3D_CLUSTER" "$run_dir/kubeconfig"
  printf '}\n'
}

substrate_down() {
  printf '{ # remove k3d cluster %s and everything in it (Zot and its cache stay)\n' "$BRZL_K3D_CLUSTER"
  printf '  k3d cluster delete %q\n' "$BRZL_K3D_CLUSTER"
  printf '}\n'
}

substrate_image_ref() {
  printf 'localhost:%s/brzl/%s' "$BRZL_ZOT_PORT" "$1"
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
}

substrate_check_down() {
  if k3d cluster get "$BRZL_K3D_CLUSTER" >/dev/null 2>&1; then
    printf 'fix: k3d cluster delete %q\n' "$BRZL_K3D_CLUSTER" >&2
    return 1
  fi
  printf 'k3d cluster %s is gone (Zot %s and its cache are kept)\n' "$BRZL_K3D_CLUSTER" "$BRZL_ZOT_NAME"
}
