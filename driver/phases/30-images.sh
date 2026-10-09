#!/usr/bin/env bash
# 30-images.sh — phase 30: build the workload images and push them to the
# substrate's registry (Zot, for k3d), where the cluster pulls them from.
# Locus: the driver, because a build needs the container engine.
#
# Emit + generator, one function each:
#   bash driver/phases/30-images.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/30-images.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: env/<env>.env (BRZL_DEMO_APP_TAG). Needs docker. No credentials.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

phase_locus() { printf '%s\n' driver; }

# The node architecture is the host's: k3d nodes run in the host's engine.
host_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'amd64' ;;
    *) printf 'arm64' ;;
  esac
}

phase_up() {
  local env="$1" run_dir="$2" image
  phase_init "$env" || end_function "$?" 'environment definition'
  image="$(substrate_image_ref "demo-app:$BRZL_DEMO_APP_TAG")"
  phase_header "$run_dir"
  printf '{ # demo-app image: build it here, push it to the registry the cluster pulls from\n'
  printf '  docker build --build-arg TARGETARCH=%q -t %q apps/demo-app\n' "$(host_arch)" "$image"
  printf '  docker push %q\n' "$image"
  printf '}\n'
  end_function 0 'emitted 30-images up'
}

phase_check() {
  local env="$1" run_dir="$2" image
  phase_init "$env" || return 1
  image="$(substrate_image_ref "demo-app:$BRZL_DEMO_APP_TAG")"
  if ! docker manifest inspect --insecure "$image" >/dev/null 2>&1; then
    printf 'fix: %s is not in the registry; run the 30-images phase again\n' "$image" >&2
    return 1
  fi
  printf '%s is in the registry\n' "$image"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,10p' "${BASH_SOURCE[0]}"; fi
fi
