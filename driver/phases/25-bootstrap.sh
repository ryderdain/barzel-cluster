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
#   3b. the workload's access (ADR-0034, a private repo on GitHub): the files
#      that driver/access/github.sh left in var/access/github/<org>/ seed the
#      store once (the App's id, installation and key; the packages user and
#      token); from the store, the run sheet writes Argo CD's repo-creds
#      Secret for the organization (also the SCM generator's credential) and
#      the registry's upstream credentials file, and reloads the registry;
#   4. the conductor (driver/conductor/conductor.yaml, rendered with the kiesei
#      image that phase 20 pushed and the idle limit);
#   5. in local-ca mode (BRZL_PORTAL_TLS), the store becomes the CA that
#      cert-manager asks to sign the admin portal's certificate (ADR-0036):
#      PKI engine, a root made once, a role for the portal's host, and the
#      auth role cert-manager logs in with. The CA certificate goes to
#      BRZL_SECRET_STORE_DIR/ca.crt; the check prints how to trust it once.
# Locus: the driver, because a secret resolves where the run sheet runs, and only
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
# run sheet carries only its NAME, never the key; values move on stdin, never in
# argv.

# shellcheck disable=SC2016  # the emitted text names variables for the run sheet to expand
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

secret_name=repo-barzel-cluster
# The workload's credential in Argo CD: one repo-creds Secret for the
# organization; the ApplicationSet's SCM generator names it (appSecretName).
workload_secret_name=workload-github-app

phase_locus() { printf '%s\n' driver; }

# workload_org — the organization of the example app's repo, from the
# ApplicationSet (the element with a `repo`), and its host's access directory.
workload_org() {
  local url
  url="$(yq '[.. | select(type == "!!map" and has("repo")) | .repo] | .[0]' "$repo_root/gitops/platform/applicationset.yaml")" || return 1
  url="${url#https://github.com/}"
  printf '%s' "${url%%/*}"
}

# workload_access_up <org> — EMIT: seed the store from the access files when
# they are there, then the cluster and the registry from the store. Without
# access files and without store entries, nothing: a public workload.
workload_access_up() {
  local org="$1" dir="var/access/github/$1" creds
  creds="$(substrate_registry_credentials_file)"
  printf '{ # the workload'"'"'s access on GitHub (%s): seed the store from %s once\n' "$org" "$dir"
  printf '  if [[ -s %q ]]; then\n' "$dir/app.pem"
  printf '    %s\n' "$(secret_put_file workload-github-app-id "$dir/app-id")"
  printf '    %s\n' "$(secret_put_file workload-github-app-installation "$dir/installation-id")"
  printf '    %s\n' "$(secret_put_file workload-github-app-key "$dir/app.pem")"
  printf '    %s\n' "$(secret_put_file workload-packages-user "$dir/packages-user")"
  printf '    %s\n' "$(secret_put_file workload-packages-token "$dir/packages-token")"
  printf '  fi\n'
  printf '}\n'
  printf '{ # from the store: Argo CD'"'"'s repo-creds Secret for https://github.com/%s (the SCM generator uses it too)\n' "$org"
  printf '  if %s; then\n' "$(secret_exists workload-github-app-key)"
  # The ids first, on their own: a `bao` call inside the pipeline below would
  # read the key from the pipe (docker exec -i inherits stdin) and leave the
  # Secret without it.
  printf '    app_id="$(%s)"\n' "$(secret_get workload-github-app-id)"
  printf '    installation="$(%s)"\n' "$(secret_get workload-github-app-installation)"
  printf '    %s \\\n' "$(secret_get workload-github-app-key)"
  printf '      | kubectl -n argocd create secret generic %q --dry-run=client -o yaml \\\n' "$workload_secret_name"
  printf '          --from-literal=type=git --from-literal=url=%q \\\n' "https://github.com/$org"
  printf '          --from-literal=githubAppID="$app_id" --from-literal=githubAppInstallationID="$installation" \\\n'
  printf '          --from-file=githubAppPrivateKey=/dev/stdin \\\n'
  printf '      | kubectl label --local -f - argocd.argoproj.io/secret-type=repo-creds -o yaml \\\n'
  printf '      | kubectl apply -f -\n'
  printf '  else\n'
  printf '    echo "no workload access in the store: Argo CD reads the workload as a public repo"\n'
  printf '  fi\n'
  printf '}\n'
  printf '{ # from the store: the registry'"'"'s upstream credentials (ghcr.io), then the registry reads them again\n'
  printf '  if %s; then\n' "$(secret_exists workload-packages-token)"
  printf '    before="$(sha256sum < %q)"\n' "$creds"
  printf '    umask 077\n'
  printf '    jq -n --arg user "$(%s)" --arg token "$(%s)" '"'"'{"ghcr.io": {username: $user, password: $token}}'"'"' > %q\n' \
    "$(secret_get workload-packages-user)" "$(secret_get workload-packages-token)" "$creds.new"
  printf '    mv %q %q\n' "$creds.new" "$creds"
  printf '    if [[ "$(sha256sum < %q)" != "$before" ]]; then\n' "$creds"
  substrate_registry_reload | sed 's/^/    /'
  printf '    fi\n'
  printf '  fi\n'
  printf '}\n'
}

phase_up() {
  local env="$1" run_dir="$2" url image manifest org
  phase_init "$env" || end_function "$?" 'environment definition'
  require_tools yq jq || end_function "$?" 'yq and jq (run the stream in kiesei)'
  [[ -n "${BRZL_SECRET_STORE:-}" ]] || end_function 1 'this phase needs a cluster secret store (BRZL_SECRET_STORE)'
  case "${BRZL_PORTAL_TLS:-}" in
    local-ca) ;;
    letsencrypt) end_function 1 'BRZL_PORTAL_TLS=letsencrypt is not built yet (BACKLOG pass 8); use local-ca' ;;
    *) end_function 1 "BRZL_PORTAL_TLS must be local-ca or letsencrypt (got '${BRZL_PORTAL_TLS:-}')" ;;
  esac
  url="$(gitops_repo_url)" || end_function "$?" 'repo URL from the ApplicationSet'
  org="$(workload_org)" || end_function "$?" 'the workload organization from the ApplicationSet'
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
  secret_store_pki_up "$BRZL_PORTAL_HOST"
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
  workload_access_up "$org"
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
  if [[ "${BRZL_PORTAL_TLS:-}" == local-ca ]]; then
    secret_store_pki_check "$BRZL_PORTAL_HOST" || rc=1
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
  if secret_store_has workload-github-app-key; then
    type="$(kubectl -n argocd get secret "$workload_secret_name" \
      -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/secret-type}' 2>/dev/null)"
    key="$(kubectl -n argocd get secret "$workload_secret_name" -o jsonpath='{.data.githubAppPrivateKey}' 2>/dev/null)"
    if [[ "$type" != repo-creds || -z "$key" ]]; then
      printf 'fix: the Argo CD repo-creds Secret argocd/%s is missing or has no key; run the 25-bootstrap phase again\n' \
        "$workload_secret_name" >&2
      rc=1
    else
      printf 'the Argo CD repo-creds Secret argocd/%s holds the GitHub App key (%d bytes, base64)\n' \
        "$workload_secret_name" "${#key}"
    fi
    if ! jq -e '."ghcr.io".password | length > 0' "$repo_root/$(substrate_registry_credentials_file)" >/dev/null 2>&1; then
      printf 'fix: the registry has no ghcr.io credential in %s; run the 25-bootstrap phase again\n' \
        "$(substrate_registry_credentials_file)" >&2
      rc=1
    else
      printf 'the registry holds the packages credential for ghcr.io\n'
    fi
  else
    printf 'no workload access in the store (a public workload, or driver/access/github.sh not run yet)\n'
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
