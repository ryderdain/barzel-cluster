#!/usr/bin/env bash
# kubeconfig_setup.sh — make plain `kubectl` work against the dev cluster. Takes the
# admin kubeconfig the kubernetes role fetched (ansible/.kube/config-dev.yaml),
# renames its generic `default` cluster/user/context to `brzl-dev`, re-resolves the
# CURRENT primary node endpoint (node IPs drift when compute is recreated between
# sessions), and installs it.
#
#   # merge into ~/.kube/config (backs it up) + switch to the context (default):
#   AWS_PROFILE=brzl-apply bash gitops/tools/kubeconfig_setup.sh
#   kubectl get nodes
#
#   # just print the rewritten kubeconfig to stdout, change nothing:
#   bash gitops/tools/kubeconfig_setup.sh --print > ~/.kube/brzl-dev.yaml
#
#   # force a specific API endpoint (skip the tofu lookup):
#   bash gitops/tools/kubeconfig_setup.sh --endpoint 1.2.3.4
#
# This is the ONE tool here that writes a file: it edits your LOCAL kubeconfig (the
# whole point), never any cloud/cluster resource, and backs up the dest first.
# Endpoint resolution is read-only (a `tofu output`); if tofu/creds are unavailable
# it keeps the server already embedded in the fetched config. Credentials: AWS_PROFILE
# if set (laptop), else ambient/instance-role creds (the conductor).
#
# Sourceable (CLAUDE.md): `source` it and call `setup_kubeconfig [--print|--endpoint X]`,
# or run it directly with the same flags. No `set -euo pipefail` (BashPitfalls/105):
# each step's failure is checked explicitly; a missing endpoint lookup degrades.

# Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/../.." && pwd -P)"
# shellcheck disable=SC1091  # dynamic path; runlib.sh is shellchecked on its own
source "${repo_root}/gitops/tools/lib/runlib.sh"

# ENV scopes the context name and which environment's compute layer resolves
# the endpoint (matches platform.sh). The fetched-kubeconfig filename is the
# Ansible role's local artifact and stays env-agnostic.
env_name="${ENV:-dev}"
context_name="${CONTEXT_NAME:-brzl-${env_name}}"
src="${KUBECONFIG_SRC:-${repo_root}/ansible/.kube/config-dev.yaml}"
dest="${KUBECONFIG_DEST:-${HOME}/.kube/config}"
compute_dir="${repo_root}/terraform/environments/${env_name}/50-compute"

setup_kubeconfig() {
  local do_print=0 endpoint=""
  while (( $# )); do
    case "$1" in
      --print)    do_print=1 ;;
      --endpoint) shift; endpoint="${1:-}" ;;
      -h|--help)  sed -n '2,22p' "${BASH_SOURCE[0]}"; return 0 ;;
      *) printf 'error: unknown argument: %s (try --help)\n' "$1" >&2; return 2 ;;
    esac
    shift
  done

  require_tools kubectl || end_function "$?" 'kubectl required'

  if [[ ! -r "$src" ]]; then
    printf 'error: fetched kubeconfig not readable: %s\n' "$src" >&2
    printf '       run the kubernetes role first (ansible playbooks/cluster.yml)\n' >&2
    end_function 1 'no source kubeconfig'
    return 1
  fi

  # Resolve the current primary endpoint unless one was forced. Best-effort: the
  # primary is node index 0 (matches the inventory generator's k3s_primary == i==0).
  if [[ -z "$endpoint" ]] && command -v tofu >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    local ips_json kind
    # public first; private as the fallback (private-subnet envs — only useful
    # from a host inside the VPC; from elsewhere pass --endpoint 127.0.0.1 and
    # tunnel over SSM, as platform.sh's prod branch does).
    for kind in public_ips private_ips; do
      if ips_json="$(tofu -chdir="$compute_dir" output -json "$kind" 2>/dev/null)"; then
        endpoint="$(printf '%s' "$ips_json" | python3 -c \
          'import json,sys; v=json.load(sys.stdin); print(v[0] if v and v[0] else "")' 2>/dev/null)"
        [[ -n "$endpoint" ]] && break
      fi
    done
  fi

  # Build the rewritten config in a temp file. The k3s kubeconfig names its
  # cluster/user/context all "default"; rename ONLY those identifier lines so we
  # never touch the base64 cert blobs, which can themselves contain "default".
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064  # expand $tmp now: clean up this exact file on return
  trap "rm -f '$tmp'" RETURN

  # The (- )? handles the YAML list-item form (`- name: default`) and the indented
  # form (`  name: default`, `    cluster: default`).
  sed -E "s/^([[:space:]]*(- )?(name|cluster|user|current-context):[[:space:]]*)default[[:space:]]*$/\1${context_name}/" \
    "$src" > "$tmp"

  # Rewrite the API server host if we resolved a (different) endpoint.
  if [[ -n "$endpoint" ]]; then
    sed -E -i.bak "s#(server: https://)[^:]+(:6443)#\1${endpoint}\2#" "$tmp" && rm -f "${tmp}.bak"
  fi

  local server
  server="$(grep -E '^[[:space:]]*server:' "$tmp" | head -1 | awk '{print $2}')"

  if (( do_print )); then
    cat "$tmp"
    printf 'context %q -> %s (printed only; nothing installed)\n' "$context_name" "$server" >&2
    end_function 0 'printed rewritten kubeconfig'
    return 0
  fi

  # Merge into the destination kubeconfig, preserving any existing contexts.
  mkdir -p -- "$(dirname -- "$dest")"
  if [[ -f "$dest" ]]; then
    local backup merged
    backup="${dest}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p -- "$dest" "$backup"
    merged="$(mktemp)"
    # tmp FIRST: on a kubeconfig merge the first file wins for conflicting names, so
    # the freshly-rewritten brzl-dev context (new endpoint) overrides any stale one
    # left in dest by a previous session; other contexts in dest are preserved.
    if ! KUBECONFIG="${tmp}:${dest}" kubectl config view --flatten > "$merged" 2>/dev/null; then
      rm -f "$merged"
      printf 'error: failed to merge kubeconfigs; %s left untouched (backup: %s)\n' "$dest" "$backup" >&2
      end_function 1 'merge failed'
      return 1
    fi
    mv -- "$merged" "$dest"
    printf 'merged context %q into %s (backup: %s)\n' "$context_name" "$dest" "$backup" >&2
  else
    # No existing config: flatten the single file into place (normalises it).
    KUBECONFIG="$tmp" kubectl config view --flatten > "$dest"
    printf 'wrote %s with context %q\n' "$dest" "$context_name" >&2
  fi
  # No `--` before the mode: BSD/macOS chmod treats it as a filename. $dest is an
  # absolute path, so it needs no leading-dash guard anyway.
  chmod 600 "$dest"

  if ! KUBECONFIG="$dest" kubectl config use-context "$context_name" >/dev/null 2>&1; then
    printf 'warning: could not switch to context %q; select it manually\n' "$context_name" >&2
  fi

  printf 'API endpoint     : %s\n' "$server" >&2
  printf 'current context  : %s\n' "$context_name" >&2
  printf 'verify           : kubectl get nodes   (or bash gitops/tools/cluster_status.sh)\n' >&2
  printf 'if it hangs      : bash gitops/tools/admin_ip_check.sh   (public IP vs SG /32)\n' >&2
  end_function 0 "installed context ${context_name} -> ${server}"
}

# CLI dispatch — only when run directly. Pass flags straight through to the action.
if [[ "$is_sourced" == false ]]; then
  setup_kubeconfig "$@"
fi
