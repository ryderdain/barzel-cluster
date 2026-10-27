#!/usr/bin/env bash
# kiesei.sh — the kiesei locus: the right-hand side of the driver's pipe. It
# reads a command stream on stdin and runs it with bash inside the kiesei image,
# so the procedure uses the image's pinned toolchain, not the host's tools.
#
#   bash driver/driver.sh local next | bash driver/kiesei.sh   # careful
#   bash driver/driver.sh local up   | bash driver/kiesei.sh   # all at once
#   bash driver/kiesei.sh shell                                # an interactive
#                                 shell in the image, for the CLI tools (argocd,
#                                 kubectl, helm, cnpg, ...); docs/guide/kiesei.md.
#                                 In it you are yourself: kubectl uses the sign-on
#                                 kubeconfig of the current run, and the shell
#                                 signs in through Dex at its start
#                                 (driver/kiesei-shell.sh, Q193)
#
# Compare `| bash`, which runs the same stream with the host's tools. The stream
# is identical either way: the locus is chosen by the pipe, not by the script.
#
# The container runs with:
#   - the host engine's socket, so docker and k3d inside drive the host engine;
#   - the host network, so the k3d API (127.0.0.1:<port>) and published ports
#     are reachable with the same kubeconfig the host uses;
#   - the repo mounted at its own host path, so every path in the stream is the
#     same inside and out, and run sheets land in the host's var/run/; the
#     example app's checkout (BRZL_EXAMPLE_APP_SRC, beside the repo) the same
#     way, when it exists, so phase 20 builds it and fast mode renders it;
#   - user root, because the engine socket in the engine's VM is root-only;
#   - every exported BRZL_* variable, so a one-off override reaches the phase
#     emitters that run inside;
#   - the admin portal's host name mapped to 127.0.0.1 (--add-host), so the
#     CLI tools reach the portal without any DNS inside the container;
#   - the store's CA certificate (local-ca mode, BRZL_SECRET_STORE_DIR/ca.crt)
#     in the container's trust store, so argocd, curl and kubectl trust the
#     portal without a flag.
#
# When the stream ends, a phase may have left a host run sheet
# (var/run/<env>/current/<NN>-host.sh, Q180): steps for this machine that
# kiesei cannot do, such as name resolution and trust of the store's CA.
# This script then runs it on the host, with the terminal as its input: the
# sheet shows its steps and asks once before it uses sudo. Its output and exit
# status go beside it (.out with the run-output header, .rc), as a phase's
# do. A sheet runs again only when a phase writes it anew. Without a
# terminal, this script names the sheet and leaves it.
#
# Execution-locus script (neither emit nor generator: like `bash`, it runs what
# it is given). Inputs: BRZL_KIESEI_IMAGE (exported, or from env/local.env).
# Needs only the docker CLI on the host. Credentials: only what a BRZL_*
# bootstrap secret source carries (phase 25), passed by name, never in argv.

(( BASH_VERSINFO[0] < 4 )) && { printf 'error: bash >= 4 required\n' >&2; exit 1; }

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)" || exit 1

image="${BRZL_KIESEI_IMAGE:-}"
portal_host="${BRZL_PORTAL_HOST:-}"
store_dir="${BRZL_SECRET_STORE_DIR:-}"
app_src="${BRZL_EXAMPLE_APP_SRC:-}"
while IFS='=' read -r key value; do
  [[ "$key" == BRZL_KIESEI_IMAGE && -z "$image" ]] && image="$value"
  [[ "$key" == BRZL_PORTAL_HOST && -z "$portal_host" ]] && portal_host="$value"
  [[ "$key" == BRZL_SECRET_STORE_DIR && -z "$store_dir" ]] && store_dir="$value"
  [[ "$key" == BRZL_EXAMPLE_APP_SRC && -z "$app_src" ]] && app_src="$value"
done < "$repo_root/env/local.env"

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

[[ -n "$portal_host" ]] && env_args+=(--add-host "$portal_host:127.0.0.1")

# The example app's checkout, at its own host path too (relative paths in the
# stream, such as ../chofesh, then resolve the same inside). Absent: phase 20
# says what to clone.
if [[ -n "$app_src" ]] && app_src="$(cd -- "$repo_root/$app_src" 2>/dev/null && pwd -P)"; then
  env_args+=(-v "$app_src:$app_src")
fi

# The CA, when the store is one (after phase 25): mounted where Debian's
# update-ca-certificates picks it up; `prelude` runs that at start.
prelude=:
if [[ -n "$store_dir" && -s "$repo_root/$store_dir/ca.crt" ]]; then
  env_args+=(-v "$repo_root/$store_dir/ca.crt:/usr/local/share/ca-certificates/brzl-${portal_host:-local}.crt:ro")
  prelude='update-ca-certificates >/dev/null 2>&1'
fi

# BRZL_HOST_OS: the checks print steps for the operator's machine, and inside
# the container uname says Linux.
if [[ "${1:-}" == shell ]]; then
  tty_args=(-i); [[ -t 0 && -t 1 ]] && tty_args=(-it)   # a terminal, when there is one
  # The shell's rc file makes the person themselves (kiesei-shell.sh): it
  # needs the current run and the portal's host name.
  exec docker run --rm "${tty_args[@]}" \
    --network host \
    --user 0:0 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$repo_root:$repo_root" -w "$repo_root" \
    "${env_args[@]}" -e "BRZL_HOST_OS=$(uname)" \
    -e "BRZL_RUN=$repo_root/var/run/local/current" -e "BRZL_PORTAL_HOST=$portal_host" \
    "$image" -c "$prelude; exec bash --rcfile $repo_root/driver/kiesei-shell.sh -i"
fi
docker run --rm -i \
  --network host \
  --user 0:0 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$repo_root:$repo_root" -w "$repo_root" \
  "${env_args[@]}" -e "BRZL_HOST_OS=$(uname)" \
  "$image" -c "$prelude; exec bash -s"
rc=$?

# The host run sheets (see the header), newer than their .rc.
for sheet in "$repo_root"/var/run/*/current/*-host.sh; do
  [[ -e "$sheet" ]] || continue
  base="${sheet%.sh}"
  [[ -e "$base.rc" && ! "$sheet" -nt "$base.rc" ]] && continue
  if ! { : < /dev/tty; } 2>/dev/null; then
    printf 'kiesei: the host run sheet %s waits for you: bash %q\n' "${sheet#"$repo_root"/}" "$sheet" >&2
    continue
  fi
  env="${sheet#"$repo_root"/var/run/}"; env="${env%%/*}"
  run="$(cd -- "${sheet%/*}" && pwd -P)"; run="${run##*/}"
  printf '\nkiesei: steps on your machine, from %s\n' "${sheet#"$repo_root"/}" >&2
  {
    printf '# brzl run-output env=%s run=%s phase=%s start=%s\n' \
      "$env" "$run" "${base##*/}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    bash "$sheet" < /dev/tty
    printf '%s\n' "$?" > "$base.rc"
  } 2>&1 | tee "$base.out"
done
exit "$rc"
