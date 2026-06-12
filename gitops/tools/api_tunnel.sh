#!/usr/bin/env bash
# api_tunnel.sh — ensure the kube-API is reachable when the cluster has no
# public endpoint (prod: private-subnet nodes). If the active kubeconfig points
# at https://127.0.0.1:6443 and nothing answers there, this starts a background
# SSM port-forward to the env's primary node and waits for the port — so no
# operator has to remember to open a tunnel (platform.sh calls this before
# every kubectl-using phase). Anywhere else (dev's public endpoint, local k3d)
# it is a no-op.
#
#   bash gitops/tools/api_tunnel.sh            # ensure (default)
#   bash gitops/tools/api_tunnel.sh stop_api_tunnel
#
# The tunnel is a plain `aws ssm start-session` (AWS-StartPortForwardingSession,
# 6443→6443) — IAM-gated and audited like every other SSM channel; 127.0.0.1 is
# in k3s's default TLS SANs, so certificate validation holds through the tunnel.
# PID + log live under /tmp (brzl-<env>-api-tunnel.{pid,log}); re-runs reuse a
# live tunnel and replace a dead one.
#
# Sourceable (CLAUDE.md): `source` it and call ensure_api_tunnel / stop_api_tunnel,
# or run it directly. No `set -euo pipefail` (BashPitfalls/105): every failure that
# matters is checked explicitly and reported.

# Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/../.." && pwd -P)"
# shellcheck disable=SC1091  # dynamic path; runlib.sh is shellchecked on its own
source "${repo_root}/gitops/tools/lib/runlib.sh"

tunnel_env="${ENV:-dev}"
tunnel_region="${AWS_REGION:-eu-central-1}"
tunnel_pid_file="/tmp/brzl-${tunnel_env}-api-tunnel.pid"
tunnel_log_file="/tmp/brzl-${tunnel_env}-api-tunnel.log"

# True iff something accepts TCP on 127.0.0.1:6443 (bash built-in probe; no nc).
_api_port_open() {
  (exec 3<>/dev/tcp/127.0.0.1/6443) 2>/dev/null || return 1
  exec 3>&- 3<&-
  return 0
}

ensure_api_tunnel() {
  require_tools kubectl aws || { end_function "$?" 'need kubectl + aws'; return 1; }

  # Self-scoping gate: only the tunnel topology (server = localhost) is our
  # business. A public/dev endpoint or k3d context passes straight through.
  local server
  server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)"
  if [[ "$server" != "https://127.0.0.1:6443" ]]; then
    end_function 0 "API server is ${server:-unset} — no tunnel needed"
    return 0
  fi

  if _api_port_open; then
    end_function 0 'API tunnel already up (127.0.0.1:6443 answering)'
    return 0
  fi

  # Stale PID file from a dead tunnel? Clear it.
  if [[ -f "$tunnel_pid_file" ]] && ! kill -0 "$(cat "$tunnel_pid_file")" 2>/dev/null; then
    rm -f "$tunnel_pid_file"
  fi

  # Resolve the primary node (index 0 — matches the inventory generator) from
  # the env's compute layer.
  local primary_id
  primary_id="$(tofu -chdir="${repo_root}/terraform/environments/${tunnel_env}/50-compute" \
    output -json instance_ids 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)[0])' 2>/dev/null)"
  if [[ -z "$primary_id" ]]; then
    printf 'error: cannot resolve the primary instance id (is %s 50-compute applied/initialized?)\n' \
      "$tunnel_env" >&2
    end_function 1 'no primary instance id'
    return 1
  fi

  printf 'starting SSM API tunnel to %s (log: %s)...\n' "$primary_id" "$tunnel_log_file" >&2
  nohup aws ssm start-session --region "$tunnel_region" --target "$primary_id" \
    --document-name AWS-StartPortForwardingSession \
    --parameters portNumber=6443,localPortNumber=6443 \
    >"$tunnel_log_file" 2>&1 &
  printf '%s' "$!" > "$tunnel_pid_file"

  # Wait for the port (SSM session setup takes a few seconds).
  local _attempt
  for _attempt in $(seq 1 30); do
    _api_port_open && { end_function 0 "API tunnel up (pid $(cat "$tunnel_pid_file"))"; return 0; }
    sleep 1
  done
  printf 'error: tunnel did not answer on 127.0.0.1:6443 within 30s — see %s\n' "$tunnel_log_file" >&2
  end_function 1 'tunnel failed to come up'
  return 1
}

stop_api_tunnel() {
  if [[ -f "$tunnel_pid_file" ]] && kill -0 "$(cat "$tunnel_pid_file")" 2>/dev/null; then
    kill "$(cat "$tunnel_pid_file")" 2>/dev/null
    rm -f "$tunnel_pid_file"
    end_function 0 'API tunnel stopped'
  else
    rm -f "$tunnel_pid_file"
    end_function 0 'no live API tunnel to stop'
  fi
}

# CLI dispatch — only when run directly. Default = ensure_api_tunnel.
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else ensure_api_tunnel; fi
fi
