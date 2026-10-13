#!/usr/bin/env bash
# 20-images.sh — phase 20: every image this repo supplies, into the substrate's
# registry (Zot, for k3d), where the cluster pulls them from: the kiesei image
# (built beforehand, docs/LOCAL.md) for the conductor, and the demo-app, built
# here. Locus: the driver, because a build and a push need the container engine.
#
# Emit + generator, one function each:
#   bash driver/phases/20-images.sh phase_up <env> <run_dir>     # EMIT
#   bash driver/phases/20-images.sh phase_check <env> <run_dir>  # GENERATOR
#
# Inputs: env/<env>.env (BRZL_KIESEI_IMAGE, BRZL_DEMO_APP_TAG); the kiesei image
# on the local engine. Needs docker. No credentials.

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

# kiesei_ref — the kiesei image's reference in the substrate's registry.
kiesei_ref() { substrate_image_ref "kiesei:${BRZL_KIESEI_IMAGE##*:}"; }

phase_up() {
  local env="$1" run_dir="$2" image kiesei
  phase_init "$env" || end_function "$?" 'environment definition'
  image="$(substrate_image_ref "demo-app:$BRZL_DEMO_APP_TAG")"
  kiesei="$(kiesei_ref)"
  phase_header "$run_dir"
  printf '{ # kiesei image (the conductor runs it) into the registry the cluster pulls from\n'
  printf '  docker tag %q %q\n' "$BRZL_KIESEI_IMAGE" "$kiesei"
  printf '  docker push %q\n' "$kiesei"
  printf '}\n'
  printf '{ # demo-app image: build it here, push it to the registry the cluster pulls from\n'
  printf '  docker build --build-arg TARGETARCH=%q -t %q apps/demo-app\n' "$(host_arch)" "$image"
  printf '  docker push %q\n' "$image"
  printf '}\n'
  end_function 0 'emitted 20-images up'
}

phase_check() {
  local env="$1" run_dir="$2" image rc=0
  phase_init "$env" || return 1
  for image in "$(kiesei_ref)" "$(substrate_image_ref "demo-app:$BRZL_DEMO_APP_TAG")"; do
    if ! docker manifest inspect --insecure "$image" >/dev/null 2>&1; then
      printf 'fix: %s is not in the registry; run the 20-images phase again\n' "$image" >&2
      rc=1
    fi
  done
  (( rc == 0 )) && printf 'kiesei and demo-app images are in the registry\n'
  return "$rc"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,11p' "${BASH_SOURCE[0]}"; fi
fi
