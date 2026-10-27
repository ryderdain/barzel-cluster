#!/usr/bin/env bash
# 10-substrate.sh — phase 10: make (or remove) the cluster on the environment's
# substrate, through that substrate's adapter (driver/substrates/<name>.sh).
#
# Emit + generator, one function each:
#   bash driver/phases/10-substrate.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/10-substrate.sh phase_down <env> <run_dir>   # EMIT
#   bash driver/phases/10-substrate.sh phase_check <env> <run_dir>  # GENERATOR
#   bash driver/phases/10-substrate.sh phase_check_down <env> <run_dir>
# The driver calls these; run them by hand to see one phase's commands.
#
# Inputs: env/<env>.env (BRZL_SUBSTRATE, BRZL_SECRET_STORE and the adapters'
# values). Output for later phases: <run_dir>/kubeconfig; on first start the
# secret store's trust files in BRZL_SECRET_STORE_DIR (driver/secret-stores/).
# Output for people: <run_dir>/kubeconfig-sign-on, the kubeconfig that signs
# in through Dex (sign-on step 2, Q188), beside the kube-API's authentication
# configuration that the adapter writes (<run_dir>/apiserver/).
# In local-ca mode (BRZL_PORTAL_TLS) the store's CA is made here, before the
# cluster, and it issues the client certificate of the collector beside the
# cluster (BRZL_SECRET_STORE_DIR/log-shipper/, BACKLOG 4a): that collector
# starts in this phase, and the in-cluster receiver accepts only it.
# Output for the operator's machine: <run_dir>/10-host.sh, the host run sheet
# (Q180): the steps that make the machine resolve the portal's host name and
# trust the store's CA. It runs on the host, not in kiesei: driver/kiesei.sh
# offers to run it when the stream ends (docs/LOCAL.md, "Steps on your
# machine").
# No credentials for k3d.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

phase_locus() { printf '%s\n' driver; }

phase_up() {
  local env="$1" run_dir="$2"
  phase_init "$env" || end_function "$?" 'environment definition'
  phase_header "$run_dir"
  phase_error_definition
  substrate_network_up
  if [[ -n "${BRZL_SECRET_STORE:-}" ]]; then
    # Before the cluster: k3d writes the network's members into CoreDNS when it
    # makes the cluster, so the store must exist first (as Zot must).
    secret_store_up
    if [[ "${BRZL_PORTAL_TLS:-}" == local-ca ]]; then
      secret_store_prelude
      secret_store_ca_up "$BRZL_PORTAL_HOST"
      secret_store_client_cert_up log-shipper log-shipper "$BRZL_SECRET_STORE_DIR/log-shipper"
    fi
  fi
  substrate_up "$run_dir"
  sign_on_kubeconfig_up "$env" "$run_dir"
  host_sheet_up "$run_dir"
  end_function 0 "emitted 10-substrate up ($BRZL_SUBSTRATE${BRZL_SECRET_STORE:+ + $BRZL_SECRET_STORE})"
}

# sign_on_kubeconfig_up <env> <run_dir> — EMIT: <run_dir>/kubeconfig-sign-on,
# a person's kubeconfig (sign-on step 2, Q188): the same cluster as the
# cluster-admin kubeconfig, and a user whose token comes from kubelogin
# through Dex (the public client `kubernetes`, kubelogin's browser callback
# on localhost). It holds no secret. kubelogin keeps the person's tokens in
# <run_dir>/oidc-cache/ (Q189), and refreshes them without a step. The paths
# are absolute, and the repo is at the same path in kiesei, so one file
# serves the host and the container. In local-ca mode kubelogin trusts the
# store's CA when it reaches Dex.
# shellcheck disable=SC2016  # the run sheet expands $server and $ca, not this script
sign_on_kubeconfig_up() {
  local env="$1" run_dir="$2" admin="$2/kubeconfig" kc="$2/kubeconfig-sign-on" abs="$2" cluster="brzl-$1"
  [[ "$abs" == /* ]] || abs="$repo_root/$abs"
  printf '{ # the sign-on kubeconfig (step 2 of pass 6a): a person through Dex, with kubelogin; it holds no secret\n'
  printf '  server="$(kubectl --kubeconfig %q config view --raw -o jsonpath=%s)"\n' "$admin" "$(squote '{.clusters[0].cluster.server}')"
  printf '  ca="$(kubectl --kubeconfig %q config view --raw -o jsonpath=%s)"\n' "$admin" "$(squote '{.clusters[0].cluster.certificate-authority-data}')"
  printf '  rm -f %q\n' "$kc"
  printf '  kubectl --kubeconfig %q config set-cluster %q --server="$server"\n' "$kc" "$cluster"
  printf '  kubectl --kubeconfig %q config set %q "$ca"\n' "$kc" "clusters.$cluster.certificate-authority-data"
  # interactiveMode is required by the v1 exec API; Never, as kubelogin's
  # own setup writes it (the browser flow needs no stdin).
  printf '  kubectl --kubeconfig %q config set-credentials sign-on \\\n' "$kc"
  printf '    --exec-api-version=client.authentication.k8s.io/v1 --exec-interactive-mode=Never \\\n'
  printf '    --exec-command=kubelogin \\\n'
  printf '    --exec-arg=get-token --exec-arg=%q --exec-arg=--oidc-client-id=kubernetes \\\n' \
    "--oidc-issuer-url=https://$BRZL_PORTAL_HOST/dex"
  printf '    --exec-arg=--oidc-extra-scope=profile --exec-arg=--oidc-extra-scope=groups \\\n'
  printf '    --exec-arg=--oidc-extra-scope=offline_access \\\n'
  if [[ "${BRZL_PORTAL_TLS:-}" == local-ca ]]; then
    printf '    --exec-arg=%q \\\n' "--certificate-authority=$repo_root/$BRZL_SECRET_STORE_DIR/ca.crt"
  fi
  printf '    --exec-arg=%q\n' "--token-cache-dir=$abs/oidc-cache"
  printf '  kubectl --kubeconfig %q config set-context %q --cluster=%q --user=sign-on\n' \
    "$kc" "$cluster-sign-on" "$cluster"
  printf '  kubectl --kubeconfig %q config use-context %q\n' "$kc" "$cluster-sign-on"
  printf '  mkdir -p %q && chmod 0700 %q\n' "$abs/oidc-cache" "$abs/oidc-cache"
  printf '}\n'
}

# host_sheet_up <run_dir> — EMIT: write the host run sheet (see the header).
# Its steps come from the adapters: the substrate's name resolution and, in
# local-ca mode, the store's CA. Each step is added only when the sheet,
# running on the host, finds it not done; then it shows the steps, asks once
# and runs them. Bash 3.2 (macOS) runs it.
host_sheet_up() {
  local run_dir="$1" sheet="$1/10-host.sh" steps
  steps="$(substrate_host_steps)"
  if [[ -n "${BRZL_SECRET_STORE:-}" && "${BRZL_PORTAL_TLS:-}" == local-ca ]]; then
    steps+=$'\n'"$(secret_store_host_steps)"
  fi
  [[ -n "${steps//[[:space:]]/}" ]] || return 0
  printf '{ # the steps on your machine: the host run sheet %s (driver/kiesei.sh offers to run it at the end)\n' "$sheet"
  printf "  cat > %q <<'EOF'\n" "$sheet"
  cat <<SHEET
#!/usr/bin/env bash
# 10-host.sh — the steps on your machine for this environment (docs/LOCAL.md,
# "Steps on your machine"; Q180), written by phase 10. It runs on your
# machine, not in kiesei: driver/kiesei.sh offers to run it when a stream
# ends, or run it yourself:  bash $sheet
# It adds only the steps that are not done, shows them, asks once, and runs
# them; sudo asks for your password.
steps=()
$steps
if [ \${#steps[@]} -eq 0 ]; then
  printf 'the steps on your machine are done\n'
  exit 0
fi
printf 'These commands change your machine:\n'
printf '  %s\n' "\${steps[@]}"
printf 'Run them now? [y/N] '
read -r answer || answer=
case "\$answer" in
  y|Y|yes) ;;
  *) printf 'not run. To run them later: bash %s\n' "\$0"; exit 3 ;;
esac
rc=0
for step in "\${steps[@]}"; do
  printf '+ %s\n' "\$step"
  bash -c "\$step" || rc=\$?
done
exit "\$rc"
SHEET
  printf 'EOF\n'
  printf '}\n'
}

phase_down() {
  local env="$1" run_dir="$2"
  phase_init "$env" || end_function "$?" 'environment definition'
  phase_header "$run_dir"
  substrate_down
  end_function 0 "emitted 10-substrate down ($BRZL_SUBSTRATE)"
}

phase_check() {
  local env="$1" run_dir="$2" rc=0
  phase_init "$env" || return 1
  if [[ -n "${BRZL_SECRET_STORE:-}" ]]; then
    secret_store_check || rc=1
    if [[ "${BRZL_PORTAL_TLS:-}" == local-ca ]]; then
      secret_store_client_cert_check "$BRZL_SECRET_STORE_DIR/log-shipper" || rc=1
    fi
  fi
  substrate_check "$run_dir" || rc=1
  if ! grep -q -- "--oidc-issuer-url=https://$BRZL_PORTAL_HOST/dex" "$run_dir/kubeconfig-sign-on" 2>/dev/null; then
    printf 'fix: %s/kubeconfig-sign-on is absent or does not name the issuer https://%s/dex; run the 10-substrate phase again\n' \
      "$run_dir" "$BRZL_PORTAL_HOST" >&2
    rc=1
  else
    printf '%s/kubeconfig-sign-on signs in through https://%s/dex\n' "$run_dir" "$BRZL_PORTAL_HOST"
  fi
  return "$rc"
}

phase_check_down() {
  local env="$1"
  phase_init "$env" || return 1
  substrate_check_down
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,13p' "${BASH_SOURCE[0]}"; fi
fi
