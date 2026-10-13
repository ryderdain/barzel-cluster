#!/usr/bin/env bash
# 25-bootstrap.sh — phase 25: what the driver puts into the cluster, and into
# the cluster secret store, before GitOps takes over:
#   1. the store learns to verify the cluster's tokens (Kubernetes auth), so
#      ESO can read from it;
#   2. the store is seeded from the bootstrap secret sources that are set —
#      today the read-only deploy key (BRZL_REPO_DEPLOY_KEY) — plus a random
#      smoke value, whose hash goes to the run directory (phase 40 compares
#      it with what ESO projects);
#   3. Argo CD's repository credential is written into the cluster FROM THE
#      STORE, so the deploy key is given once: the store keeps it;
#   4. the conductor (driver/conductor/conductor.yaml, rendered with the kiesei
#      image that phase 20 pushed and the idle limit).
# Locus: the driver, because a secret resolves where the run-log runs, and only
# the driver has the operator's environment and the store's driver token; and
# because a locus never installs itself (ADR-0021). Later the deploy key gives
# way to a GitHub App (BACKLOG gate, Q61).
#
# Emit + generator, one function each:
#   bash driver/phases/25-bootstrap.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/25-bootstrap.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: <run_dir>/kubeconfig from phase 10; env/<env>.env (BRZL_KIESEI_IMAGE,
# BRZL_CONDUCTOR_IDLE_SECONDS, the store's values); the repo URL from the
# platform ApplicationSet; the store's driver token. Credentials: the bootstrap
# secret source BRZL_REPO_DEPLOY_KEY (the private key's text, given to the
# command that runs the stream; needed only until the store holds it). The
# run-log carries only its NAME, never the key; values move on stdin, never in
# argv.

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
  [[ -n "${BRZL_SECRET_STORE:-}" ]] || end_function 1 'this phase needs a cluster secret store (BRZL_SECRET_STORE)'
  url="$(gitops_repo_url)" || end_function "$?" 'repo URL from the ApplicationSet'
  image="$(substrate_image_ref "kiesei:${BRZL_KIESEI_IMAGE##*:}")"
  manifest="$(<"$repo_root/driver/conductor/conductor.yaml")" \
    || end_function "$?" 'conductor manifest'
  manifest="${manifest//__KIESEI_IMAGE__/$image}"
  manifest="${manifest//__IDLE_SECONDS__/$BRZL_CONDUCTOR_IDLE_SECONDS}"
  phase_header "$run_dir"
  phase_error_definition
  secret_store_prelude
  printf "{ # namespace for the driver's own objects in the cluster\n"
  printf '  kubectl create namespace brzl-system --dry-run=client -o yaml | kubectl apply -f -\n'
  printf '}\n'
  secret_store_bind_cluster
  printf '{ # seed the store: the deploy key, when given (the store keeps it; later runs need no key)\n'
  printf '  if [[ -n "${BRZL_REPO_DEPLOY_KEY:-}" ]]; then\n'
  printf '    %s\n' "$(secret_put repo-deploy-key BRZL_REPO_DEPLOY_KEY)"
  printf '  fi\n'
  printf '  %s \\\n' "$(secret_exists repo-deploy-key)"
  printf "    || error 3 'no deploy key in the store and BRZL_REPO_DEPLOY_KEY not given: nothing written; see docs/LOCAL.md'\n"
  printf '}\n'
  printf '{ # smoke value: a random secret through the store; phase 40 checks that ESO projects the same bytes\n'
  printf '  smoke="$(openssl rand -hex 32)"\n'
  printf '  %s\n' "$(secret_put smoke smoke)"
  printf '  printf '\''%%s'\'' "$smoke" | sha256sum > %q\n' "$run_dir/smoke.sha256"
  printf '  unset smoke\n'
  printf '}\n'
  printf '{ # Argo CD reads the private repo with the deploy key, taken from the store\n'
  printf '  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -\n'
  # (a key file must end with a newline; the store keeps the value as given)
  printf '  { %s; echo; } \\\n' "$(secret_get repo-deploy-key)"
  printf '    | kubectl -n argocd create secret generic %q --dry-run=client -o yaml \\\n' "$secret_name"
  printf '        --from-literal=type=git --from-literal=url=%q --from-file=sshPrivateKey=/dev/stdin \\\n' "$url"
  printf '    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \\\n'
  printf '    | kubectl apply -f -\n'
  printf '}\n'
  printf '{ # the conductor: service account, RBAC, deployment (image from phase 20)\n'
  printf "  kubectl apply -f - <<'EOF'\n%s\nEOF\n" "$manifest"
  printf '}\n'
  end_function 0 'emitted 25-bootstrap up'
}

# The check reads only whether the key is there; it never prints it.
phase_check() {
  local env="$1" run_dir="$2" type key rc=0
  phase_init "$env" || return 1
  export KUBECONFIG="$run_dir/kubeconfig"
  if ! secret_store_has repo-deploy-key; then
    printf 'fix: the store holds no deploy key; give BRZL_REPO_DEPLOY_KEY to the 25-bootstrap phase once\n' >&2
    rc=1
  else
    printf 'the store holds the deploy key\n'
  fi
  if [[ ! -s "$run_dir/smoke.sha256" ]] || ! secret_store_has smoke; then
    printf 'fix: no smoke value in the store or no %s; run the 25-bootstrap phase again\n' "$run_dir/smoke.sha256" >&2
    rc=1
  fi
  if ! openbao_run_bao read -format=json auth/kubernetes/config >/dev/null 2>&1; then
    printf 'fix: the store has no Kubernetes auth config; run the 25-bootstrap phase again\n' >&2
    rc=1
  fi
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
  if (( $# )); then "$@"; else sed -n '2,32p' "${BASH_SOURCE[0]}"; fi
fi
