#!/usr/bin/env bash
# kiesei.sh — the kiesei locus: the right-hand side of the driver's pipe. It
# reads a command stream on stdin and runs it with bash inside the kiesei image,
# so the procedure uses the image's pinned toolchain, not the host's tools.
#
#   bash driver/driver.sh local next | bash driver/kiesei.sh   # careful
#   bash driver/driver.sh local up   | bash driver/kiesei.sh   # fast
#
# Compare `| bash`, which runs the same stream with the host's tools. The stream
# is identical either way: the locus is chosen by the pipe, not by the script.
#
# The container runs with:
#   - the host engine's socket, so docker and k3d inside drive the host engine;
#   - the host network, so the k3d API (127.0.0.1:<port>) and published ports
#     are reachable with the same kubeconfig the host uses;
#   - the repo mounted at its own host path, so every path in the stream is the
#     same inside and out, and run-logs land in the host's var/run/;
#   - user root, because the engine socket in the engine's VM is root-only;
#   - every exported BRZL_* variable, so a one-off override reaches the phase
#     emitters that run inside.
#
# Execution-locus script (neither emit nor generator: like `bash`, it runs what
# it is given). Inputs: BRZL_KIESEI_IMAGE (exported, or from env/local.env).
# Needs only the docker CLI on the host. No credentials for local.

(( BASH_VERSINFO[0] < 4 )) && { printf 'error: bash >= 4 required\n' >&2; exit 1; }

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)" || exit 1

image="${BRZL_KIESEI_IMAGE:-}"
if [[ -z "$image" ]]; then
  while IFS='=' read -r key value; do
    [[ "$key" == BRZL_KIESEI_IMAGE ]] && image="$value"
  done < "$repo_root/env/local.env"
fi

if ! command -v docker >/dev/null 2>&1; then
  printf 'error: docker CLI not found on PATH (the host needs only the engine and its CLI)\n' >&2
  exit 1
fi
if ! docker image inspect "$image" >/dev/null 2>&1; then
  printf 'error: kiesei image %s is not on this engine\n' "$image" >&2
  printf 'fix: docker build -t %q %q\n' "$image" "$repo_root/containers/kiesei" >&2
  exit 1
fi

env_args=()
while IFS='=' read -r name _; do
  [[ "$name" == BRZL_* ]] && env_args+=(-e "$name")
done < <(env)

exec docker run --rm -i \
  --network host \
  --user 0:0 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$repo_root:$repo_root" -w "$repo_root" \
  "${env_args[@]}" \
  "$image" -s
