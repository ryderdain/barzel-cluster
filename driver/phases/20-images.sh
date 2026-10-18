#!/usr/bin/env bash
# 20-images.sh — phase 20: the images the cluster cannot pull from an upstream,
# into the substrate's registry (Zot, for k3d): today only the kiesei image
# (built beforehand, docs/LOCAL.md) for the conductor. A workload's image is
# the workload's own: its CI publishes it, and the cluster pulls it through
# the registry like any upstream image (ADR-0034). Locus: the driver, because
# a push needs the container engine.
#
# Emit + generator, one function each:
#   bash driver/phases/20-images.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/20-images.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: env/<env>.env (BRZL_KIESEI_IMAGE); the kiesei image on the local
# engine. Needs docker. No credentials.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

phase_locus() { printf '%s\n' driver; }

# kiesei_ref — the kiesei image's reference in the substrate's registry.
kiesei_ref() { substrate_image_ref "kiesei:${BRZL_KIESEI_IMAGE##*:}"; }

phase_up() {
  local env="$1" run_dir="$2" kiesei
  phase_init "$env" || end_function "$?" 'environment definition'
  kiesei="$(kiesei_ref)"
  phase_header "$run_dir"
  printf '{ # kiesei image (the conductor runs it) into the registry the cluster pulls from\n'
  printf '  docker tag %q %q\n' "$BRZL_KIESEI_IMAGE" "$kiesei"
  printf '  docker push %q\n' "$kiesei"
  printf '}\n'
  end_function 0 'emitted 20-images up'
}

phase_check() {
  local env="$1" run_dir="$2" image
  phase_init "$env" || return 1
  image="$(kiesei_ref)"
  if ! docker manifest inspect --insecure "$image" >/dev/null 2>&1; then
    printf 'fix: %s is not in the registry; run the 20-images phase again\n' "$image" >&2
    return 1
  fi
  printf 'the kiesei image is in the registry\n'
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,11p' "${BASH_SOURCE[0]}"; fi
fi
