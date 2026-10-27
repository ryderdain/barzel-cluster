#!/usr/bin/env bash
# kiesei-shell.sh — the start-up of the interactive kiesei shell (driver/kiesei.sh
# shell; Q193): a person in the shell is themselves. KUBECONFIG is the sign-on
# kubeconfig of the current run, so kubectl acts as the person, and the shell
# signs in through Dex at its start when no session is cached (kubelogin prints
# a URL to open). `argocd` signs in through Dex on its first use, with the CLI's
# config in the run directory, so its session outlives the shell; on an
# authentication error it removes that config, so the next use signs in again.
# The cluster-admin kubeconfig is the driver's, and the emergency path (Q175):
# name it on purpose:
#   KUBECONFIG=var/run/<env>/current/kubeconfig kubectl ...
#
# Interactive run-once script (bash-doctrine core): bash reads it as its rc
# file (`bash --rcfile driver/lib/kiesei-shell.sh -i`); never run it. Inputs:
# BRZL_RUN (the current run directory, absolute) and BRZL_PORTAL_HOST, from
# driver/kiesei.sh. No credentials of its own: the sessions are the person's.

[[ -r /etc/profile ]] && source /etc/profile

if [[ -z "${BRZL_RUN:-}" || ! -s "$BRZL_RUN/kubeconfig-sign-on" ]]; then
  printf 'kiesei shell: no current run with a sign-on kubeconfig (%s); kubectl has no kubeconfig\n' \
    "${BRZL_RUN:-BRZL_RUN unset}/kubeconfig-sign-on" >&2
  return 0 2>/dev/null
fi

export KUBECONFIG="$BRZL_RUN/kubeconfig-sign-on"

# argocd <args> — the Argo CD CLI as the person: its config (the session from
# `argocd login`) is in the run directory. The first use signs in through
# Dex, in the browser (the callback is on localhost:8085).
argocd() {
  local cfg="$BRZL_RUN/argocd-config" err rc
  if [[ "${1:-}" != login && ! -s "$cfg" ]]; then
    command argocd --config "$cfg" login "$BRZL_PORTAL_HOST" \
      --grpc-web-root-path argocd --sso --sso-launch-browser=false || return
  fi
  err="$(mktemp)" || return
  command argocd --config "$cfg" "$@" 2>"$err"
  rc=$?
  cat "$err" >&2
  if (( rc != 0 )) && grep -qiE 'unauthenticated|unauthorized|session|token' "$err"; then
    rm -f "$cfg"
    printf 'argocd: the session ended, so the next argocd command signs in again\n' >&2
  fi
  rm -f "$err"
  return "$rc"
}

printf 'kiesei shell: kubectl is you (KUBECONFIG=%s)\n' "$KUBECONFIG"
printf '              the cluster-admin kubeconfig, for the driver and emergencies: %s/kubeconfig\n' "$BRZL_RUN"
if ! kubectl auth whoami -o json 2>/dev/null | jq -r '"              you are " + .status.userInfo.username'; then
  printf 'kiesei shell: no sign-on session (is Dex or GitHub down?); in an emergency: KUBECONFIG=%s/kubeconfig kubectl ...\n' \
    "$BRZL_RUN" >&2
fi
