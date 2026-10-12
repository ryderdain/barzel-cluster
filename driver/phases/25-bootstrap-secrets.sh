#!/usr/bin/env bash
# 25-bootstrap-secrets.sh — phase 25: put the bootstrap secrets into the cluster.
# Today one: the read-only deploy key that lets Argo CD read this (private)
# repo, as an Argo CD repository Secret. Locus: the driver, because a secret
# resolves where the run-log runs, and only the driver has the operator's
# environment (the conductor does not). Pass 5 extends this phase to seed the
# cluster secret store (OpenBao); later the deploy key gives way to a GitHub
# App (BACKLOG gate, Q61).
#
# Emit + generator, one function each:
#   bash driver/phases/25-bootstrap-secrets.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/25-bootstrap-secrets.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: <run_dir>/kubeconfig from phase 10; the repo URL from the platform
# ApplicationSet. Credentials: the bootstrap secret source BRZL_REPO_DEPLOY_KEY
# (the private key's text, exported or given to the command that runs the
# stream; docs/LOCAL.md). The run-log carries only its NAME, never the key; the
# key reaches kubectl on stdin, not in argv.

# shellcheck disable=SC2016  # the emitted text names variables for the run-log to expand
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

secret_name=repo-barzel-cluster

phase_locus() { printf '%s\n' driver; }

phase_up() {
  local env="$1" run_dir="$2" url
  phase_init "$env" || end_function "$?" 'environment definition'
  url="$(gitops_repo_url)" || end_function "$?" 'repo URL from the ApplicationSet'
  if [[ -z "${BRZL_REPO_DEPLOY_KEY:-}" ]]; then
    printf 'note: BRZL_REPO_DEPLOY_KEY is not set here; it must be set where the stream runs (docs/LOCAL.md)\n' >&2
  fi
  phase_header "$run_dir"
  phase_error_definition
  printf '{ # Argo CD reads the private repo with a read-only deploy key (bootstrap secret source)\n'
  printf '  [[ -n "${BRZL_REPO_DEPLOY_KEY:-}" ]] \\\n'
  printf "    || error 3 'BRZL_REPO_DEPLOY_KEY is not set: nothing written; set it (docs/LOCAL.md) and run the phase again'\n"
  printf '  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -\n'
  printf '  printf '\''%%s\\n'\'' "$BRZL_REPO_DEPLOY_KEY" \\\n'
  printf '    | kubectl -n argocd create secret generic %q --dry-run=client -o yaml \\\n' "$secret_name"
  printf '        --from-literal=type=git --from-literal=url=%q --from-file=sshPrivateKey=/dev/stdin \\\n' "$url"
  printf '    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \\\n'
  printf '    | kubectl apply -f -\n'
  printf '}\n'
  end_function 0 'emitted 25-bootstrap-secrets up'
}

# The check reads only whether the key is there; it never prints it.
phase_check() {
  local env="$1" run_dir="$2" type key
  phase_init "$env" || return 1
  export KUBECONFIG="$run_dir/kubeconfig"
  type="$(kubectl -n argocd get secret "$secret_name" \
    -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/secret-type}' 2>/dev/null)"
  key="$(kubectl -n argocd get secret "$secret_name" -o jsonpath='{.data.sshPrivateKey}' 2>/dev/null)"
  if [[ "$type" != repository || -z "$key" ]]; then
    printf 'fix: the Argo CD repository Secret argocd/%s is missing or has no key; set BRZL_REPO_DEPLOY_KEY and run the 25-bootstrap-secrets phase again\n' \
      "$secret_name" >&2
    return 1
  fi
  printf 'the Argo CD repository Secret argocd/%s holds a deploy key (%d bytes, base64)\n' \
    "$secret_name" "${#key}"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,19p' "${BASH_SOURCE[0]}"; fi
fi
