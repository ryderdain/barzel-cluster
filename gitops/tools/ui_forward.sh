#!/usr/bin/env bash
# ui_forward.sh — open the cluster's web UIs locally via `kubectl port-forward`,
# and print each one's URL + admin credentials. The zero-cost alternative to a
# LoadBalancer/Ingress (none of these UIs are exposed publicly — deliberately):
# everything is reached through the API server you already have access to.
#
#   bash gitops/tools/ui_forward.sh            # all three (grafana, prometheus, argocd)
#   bash gitops/tools/ui_forward.sh grafana    # just one (grafana|prometheus|argocd)
#
# Running this ON THE CONDUCTOR? The forwards bind to the conductor's localhost, which
# your laptop browser can't reach directly. This script detects it's on EC2 (IMDS) and
# prints the exact `aws ssm start-session` port-forward commands to run ON YOUR LAPTOP
# to chain each UI through the SSM tunnel to the SAME localhost port — so the URLs
# below stay identical (http://localhost:3000 etc.) whether you're on the box or local.
#
# Leave it running; Ctrl-C tears the forwards down. Read-only: it starts local
# port-forwards and reads two Secrets for the admin passwords — it changes nothing
# in the cluster.
#
# No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): the few commands whose
# failure matters are checked explicitly; a UI that isn't installed yet is skipped
# with a warning rather than aborting the others.

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  printf 'error: kubectl not found on PATH\n' >&2
  exit 1
fi
if ! kubectl version -o json >/dev/null 2>&1 && ! kubectl cluster-info >/dev/null 2>&1; then
  printf 'error: cannot reach the cluster (kubeconfig/context?)\n' >&2
  printf '       try: bash gitops/tools/kubeconfig_setup.sh\n' >&2
  exit 1
fi

target="${1:-all}"
case "$target" in
  all|grafana|prometheus|argocd) ;;
  *) printf 'error: unknown target %q (use: grafana|prometheus|argocd|all)\n' "$target" >&2; exit 2 ;;
esac

# Track the port-forward PIDs so the trap can reap them all on exit, and the
# forwarded UIs (name|local-port|url) so the conductor-chaining hint can emit one
# laptop-side SSM port-forward per UI.
pids=()
fwd_lines=()
cleanup() {
  printf '\nstopping port-forwards...\n' >&2
  local pid
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null
  done
  wait 2>/dev/null
}
trap cleanup INT TERM EXIT

# resolve_svc <namespace> <label-selector> — print the first matching Service name,
# or empty if none (the component isn't installed). Keeps us off hard-coded Helm
# release names, which vary with the ArgoCD Application name.
resolve_svc() {
  local ns="$1" selector="$2"
  kubectl -n "$ns" get svc -l "$selector" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# secret_val <namespace> <secret> <key> — decode one key from a Secret (no value
# ever printed unless the caller asks; here only the admin passwords, by design).
secret_val() {
  local ns="$1" name="$2" key="$3" v
  v="$(kubectl -n "$ns" get secret "$name" -o jsonpath="{.data.${key}}" 2>/dev/null)" || return 1
  [[ -n "$v" ]] || return 1
  printf '%s' "$v" | base64 -d 2>/dev/null
}

# forward <name> <ns> <svc> <remote-port> <local-port> <url> <user> <pass>
forward() {
  local name="$1" ns="$2" svc="$3" rport="$4" lport="$5" url="$6" user="$7" pass="$8"
  if [[ -z "$svc" ]]; then
    printf 'skip   %-10s : not found in namespace %q (installed & synced yet?)\n' "$name" "$ns" >&2
    return
  fi
  kubectl -n "$ns" port-forward "svc/${svc}" "${lport}:${rport}" >/dev/null 2>&1 &
  pids+=("$!")
  fwd_lines+=("${name}|${lport}|${url}")
  printf '\n%s\n' "── ${name} ──────────────────────────────────────────────"
  printf '  url   : %s\n' "$url"
  [[ -n "$user" ]] && printf '  user  : %s\n' "$user"
  [[ -n "$pass" ]] && printf '  pass  : %s\n' "$pass"
}

# on_ec2_instance_id — echo this host's instance-id if we're on EC2 (IMDSv2, which
# the conductor requires), else nothing/non-zero. Short timeouts so it returns fast
# on a laptop where 169.254.169.254 isn't routable.
on_ec2_instance_id() {
  command -v curl >/dev/null 2>&1 || return 1
  local token id
  token="$(curl -fsS --connect-timeout 1 --max-time 2 -X PUT \
    'http://169.254.169.254/latest/api/token' \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' 2>/dev/null)" || return 1
  [[ -n "$token" ]] || return 1
  id="$(curl -fsS --connect-timeout 1 --max-time 2 \
    -H "X-aws-ec2-metadata-token: ${token}" \
    'http://169.254.169.254/latest/meta-data/instance-id' 2>/dev/null)" || return 1
  [[ -n "$id" ]] && printf '%s' "$id"
}

# print_laptop_chaining — when running on the conductor, emit the laptop-side SSM
# port-forward command for each forwarded UI (same local port → identical URLs). On a
# laptop (no IMDS) it prints nothing: the localhost URLs already open in the browser.
print_laptop_chaining() {
  local iid region line name lport url
  iid="$(on_ec2_instance_id)" || return 0
  [[ -n "$iid" ]] || return 0
  region="${AWS_DEFAULT_REGION:-${AWS_REGION:-eu-central-1}}"
  printf '\n%s\n' "── reach these from your LAPTOP browser ───────────────────" >&2
  printf 'The forwards above are on the CONDUCTOR (%s). Run each command below ON\n' "$iid" >&2
  printf 'YOUR LAPTOP (one per terminal; needs the session-manager-plugin) to tunnel\n' >&2
  printf 'the same port through SSM — then the URLs above work in your laptop browser:\n' >&2
  for line in "${fwd_lines[@]}"; do
    IFS='|' read -r name lport url <<< "$line"
    printf '\n  # %s  →  %s\n' "$name" "$url" >&2
    printf "  aws ssm start-session --region %s --target %s \\\\\n" "$region" "$iid" >&2
    printf '    --document-name AWS-StartPortForwardingSession \\\n' >&2
    printf "    --parameters '{\"portNumber\":[\"%s\"],\"localPortNumber\":[\"%s\"]}'\n" "$lport" "$lport" >&2
  done
  printf '%s\n' "──────────────────────────────────────────────────────────" >&2
}

if [[ "$target" == all || "$target" == grafana ]]; then
  svc="$(resolve_svc monitoring 'app.kubernetes.io/name=grafana')"
  # admin creds live in the bootstrap-created `grafana-admin` Secret (values.yaml
  # admin.existingSecret), not the chart's own random one.
  guser="$(secret_val monitoring grafana-admin admin-user)" || guser="admin"
  pass="$(secret_val monitoring grafana-admin admin-password)" || pass='<grafana-admin secret missing — see BOOTSTRAP.md>'
  forward grafana monitoring "$svc" 80 3000 'http://localhost:3000' "${guser:-admin}" "$pass"
fi

if [[ "$target" == all || "$target" == prometheus ]]; then
  # The chart's Prometheus Service carries this label; fall back to the operator's
  # always-present headless service if the named one isn't found.
  svc="$(resolve_svc monitoring 'app.kubernetes.io/name=prometheus,operator.prometheus.io/name')"
  [[ -z "$svc" ]] && svc="$(resolve_svc monitoring 'operated-prometheus=true')"
  [[ -z "$svc" ]] && svc="prometheus-operated"
  forward prometheus monitoring "$svc" 9090 9090 'http://localhost:9090' '' ''
fi

if [[ "$target" == all || "$target" == argocd ]]; then
  svc="$(resolve_svc argocd 'app.kubernetes.io/name=argocd-server')"
  pass="$(secret_val argocd argocd-initial-admin-secret password)" || pass='<deleted/rotated — see docs/ACCESS.md>'
  # ArgoCD runs server.insecure=true (TLS terminated at an ingress in prod), so the
  # server speaks HTTP on 8080 — forward the http port, not 443 (which just maps to
  # the same plaintext 8080 and so can't TLS-handshake).
  forward argocd argocd "${svc:-argocd-server}" 80 8080 'http://localhost:8080' admin "$pass"
fi

if (( ${#pids[@]} == 0 )); then
  printf '\nnothing to forward (no matching UIs found).\n' >&2
  exit 1
fi

print_laptop_chaining

printf '\n%s\n' "forwarding ${#pids[@]} UI(s) — press Ctrl-C to stop."
wait
