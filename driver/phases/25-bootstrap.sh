#!/usr/bin/env bash
# 25-bootstrap.sh — phase 25: what the driver puts into the cluster before
# GitOps takes over. Two things today: the read-only deploy key that lets
# Argo CD read this (private) repo, as an Argo CD repository Secret; and the
# conductor (driver/conductor/conductor.yaml, rendered with the kiesei image
# that phase 20 pushed and the idle limit). Locus: the driver, because a secret
# resolves where the run-log runs, and only the driver has the operator's
# environment; and because a locus never installs itself (ADR-0021).
# Pass 5 extends this phase to seed the cluster secret store (OpenBao); later
# the deploy key gives way to a GitHub App (BACKLOG gate, Q61).
#
# Emit + generator, one function each:
#   bash driver/phases/25-bootstrap.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/25-bootstrap.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: <run_dir>/kubeconfig from phase 10; env/<env>.env (BRZL_KIESEI_IMAGE,
# BRZL_CONDUCTOR_IDLE_SECONDS); the repo URL from the platform ApplicationSet.
# Credentials: the bootstrap secret source BRZL_REPO_DEPLOY_KEY (the private
# key's text, exported or given to the command that runs the stream;
# docs/LOCAL.md). The run-log carries only its NAME, never the key; the key
# reaches kubectl on stdin, not in argv.

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
  local env="$1" run_dir="$2" url image manifest
  phase_init "$env" || end_function "$?" 'environment definition'
  url="$(gitops_repo_url)" || end_function "$?" 'repo URL from the ApplicationSet'
  image="$(substrate_image_ref "kiesei:${BRZL_KIESEI_IMAGE##*:}")"
  manifest="$(<"$repo_root/driver/conductor/conductor.yaml")" \
    || end_function "$?" 'conductor manifest'
  manifest="${manifest//__KIESEI_IMAGE__/$image}"
  manifest="${manifest//__IDLE_SECONDS__/$BRZL_CONDUCTOR_IDLE_SECONDS}"
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
  printf '{ # the conductor: namespace, service account, RBAC, deployment (image from phase 20)\n'
  printf "  kubectl apply -f - <<'EOF'\n%s\nEOF\n" "$manifest"
  printf '}\n'
  end_function 0 'emitted 25-bootstrap up'
}

# The check reads only whether the key is there; it never prints it.
phase_check() {
  local env="$1" run_dir="$2" type key rc=0
  phase_init "$env" || return 1
  export KUBECONFIG="$run_dir/kubeconfig"
  type="$(kubectl -n argocd get secret "$secret_name" \
    -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/secret-type}' 2>/dev/null)"
  key="$(kubectl -n argocd get secret "$secret_name" -o jsonpath='{.data.sshPrivateKey}' 2>/dev/null)"
  if [[ "$type" != repository || -z "$key" ]]; then
    printf 'fix: the Argo CD repository Secret argocd/%s is missing or has no key; set BRZL_REPO_DEPLOY_KEY and run the 25-bootstrap phase again\n' \
      "$secret_name" >&2
    rc=1
  else
    printf 'the Argo CD repository Secret argocd/%s holds a deploy key (%d bytes, base64)\n' \
      "$secret_name" "${#key}"
  fi
  if ! kubectl -n brzl-system rollout status deployment/conductor --timeout=300s >/dev/null; then
    printf 'fix: the conductor is not ready; see: kubectl -n brzl-system describe deployment/conductor\n' >&2
    rc=1
  else
    printf 'the conductor is ready in brzl-system\n'
  fi
  return "$rc"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,22p' "${BASH_SOURCE[0]}"; fi
fi
