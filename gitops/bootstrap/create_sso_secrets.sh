#!/usr/bin/env bash
# create_sso_secrets.sh — EMIT the commands that create the in-cluster Secrets the
# operator-SSO stack needs: Dex's GitHub OAuth client, and oauth2-proxy's OIDC
# client + cookie. Per the repo convention this is a mutating/action script — it
# only PRINTS commands (via the shared emit_k8s_secret helper); the tokens are
# referenced as runtime env vars (never interpolated into the printed text), so a
# dry run reveals nothing. Export, then preview, then pipe to a shell:
#
#   export GITHUB_CLIENT_ID=...        GITHUB_CLIENT_SECRET=...       # the GitHub OAuth App (Dex)
#   export OAUTH2_PROXY_CLIENT_SECRET=...                              # Dex static client for oauth2-proxy
#   bash gitops/bootstrap/create_sso_secrets.sh            # preview
#   bash gitops/bootstrap/create_sso_secrets.sh | bash     # run
#
# The oauth2-proxy *cookie* secret is generated in the piped shell if not supplied
# (32 random bytes via `openssl rand -hex 16`, AES-256). The FreeDNS (afraid.org)
# credential for cert-manager's DNS-01 webhook is NOT here — it's passed to that
# webhook's Helm install at bring-up (see k3d_up.sh --with-sso), so it never lands
# in a manifest either.
#
# Sibling secret-creators sharing this shape (sourceable main() + runlib emit_k8s_secret):
#   create_pullthrough_secrets.sh (AWS Secrets Manager) · create_cluster_secrets.sh
#   (core in-cluster: grafana-admin). One consistent secrets surface.
#
# No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): the emit-time arg checks
# are explicit; the emitted create-or-update stream is &&-chained per Secret.

# Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck disable=SC1091  # dynamic path; runlib.sh is shellchecked on its own
source "${repo_root}/gitops/tools/lib/runlib.sh"

dex_ns="${DEX_NAMESPACE:-sso}"
proxy_ns="${OAUTH2_PROXY_NAMESPACE:-sso}"

emit_sso_secrets() {
  require_tools kubectl || end_function "$?" 'kubectl required'

  local v
  for v in GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET OAUTH2_PROXY_CLIENT_SECRET; do
    if [[ -z "${!v:-}" ]]; then
      printf 'error: %s must be exported (GitHub OAuth App + the Dex client secret for oauth2-proxy)\n' "$v" >&2
      end_function 1 "missing $v"
      return 1
    fi
  done

  emit_k8s_secret "$dex_ns" dex-github \
    clientID=GITHUB_CLIENT_ID clientSecret=GITHUB_CLIENT_SECRET

  # Cookie: use a supplied OAUTH2_PROXY_COOKIE_SECRET, else mint a valid 32-char
  # (32-byte, AES-256) value inline in the piped shell. Single-quoted ON PURPOSE so
  # the expression reaches the piped shell verbatim (SC2016 is the desired behaviour).
  # shellcheck disable=SC2016
  emit_k8s_secret "$proxy_ns" oauth2-proxy-oidc \
    client-secret=OAUTH2_PROXY_CLIENT_SECRET \
    'cookie-secret=@${OAUTH2_PROXY_COOKIE_SECRET:-$(openssl rand -hex 16)}'

  printf '\n--- NEXT --------------------------------------------------------------\n' >&2
  printf 'Secrets: %s/dex-github, %s/oauth2-proxy-oidc.\n' "$dex_ns" "$proxy_ns" >&2
  printf 'The FreeDNS cred for cert-manager DNS-01 is passed at bring-up:\n' >&2
  printf '  export FREEDNS_USERNAME=... FREEDNS_PASSWORD=...\n' >&2
  printf '  bash gitops/clusters/local/k3d_up.sh --with-sso | bash\n' >&2
  printf -- '----------------------------------------------------------------------\n' >&2
  end_function 0 'emitted SSO Secret create-or-update'
}

# CLI dispatch — only when run directly. Default = emit_sso_secrets (preview).
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else emit_sso_secrets; fi
fi
