#!/usr/bin/env bash
# 15-conductor.sh — phase 15: put the conductor in the cluster. Pushes the kiesei
# image to the substrate's registry, then applies the conductor manifest
# (driver/conductor/conductor.yaml), rendered with that image and the idle
# limit. Later phases whose locus is the conductor run there (driver/conductor.sh).
# Locus: the driver.
#
# Emit + generator, one function each:
#   bash driver/phases/15-conductor.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/15-conductor.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: env/<env>.env (BRZL_KIESEI_IMAGE, BRZL_CONDUCTOR_IDLE_SECONDS);
# <run_dir>/kubeconfig from phase 10; the kiesei image on the local engine.
# No credentials.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

phase_locus() { printf '%s\n' driver; }

phase_up() {
  local env="$1" run_dir="$2" image manifest
  phase_init "$env" || end_function "$?" 'environment definition'
  image="$(substrate_image_ref "kiesei:${BRZL_KIESEI_IMAGE##*:}")"
  manifest="$(<"$repo_root/driver/conductor/conductor.yaml")" \
    || end_function "$?" 'conductor manifest'
  manifest="${manifest//__KIESEI_IMAGE__/$image}"
  manifest="${manifest//__IDLE_SECONDS__/$BRZL_CONDUCTOR_IDLE_SECONDS}"
  phase_header "$run_dir"
  printf '{ # kiesei image into the registry the cluster pulls from\n'
  printf '  docker tag %q %q\n' "$BRZL_KIESEI_IMAGE" "$image"
  printf '  docker push %q\n' "$image"
  printf '}\n'
  printf '{ # the conductor: namespace, service account, RBAC, deployment\n'
  printf "  kubectl apply -f - <<'EOF'\n%s\nEOF\n" "$manifest"
  printf '}\n'
  end_function 0 'emitted 15-conductor up'
}

phase_check() {
  local env="$1" run_dir="$2"
  phase_init "$env" || return 1
  export KUBECONFIG="$run_dir/kubeconfig"
  if ! kubectl -n brzl-system rollout status deployment/conductor --timeout=300s >/dev/null; then
    printf 'fix: the conductor is not ready; see: kubectl -n brzl-system describe deployment/conductor\n' >&2
    return 1
  fi
  printf 'the conductor is ready in brzl-system\n'
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,15p' "${BASH_SOURCE[0]}"; fi
fi
