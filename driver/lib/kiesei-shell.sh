#!/usr/bin/env bash
# kiesei-shell.sh — the start-up of the interactive kiesei shell (driver/kiesei.sh
# shell; Q193): a person in the shell is themselves. KUBECONFIG is the sign-on
# kubeconfig of the current run, so kubectl acts as the person, and the shell
# signs in through Dex at its start when no session is cached (kubelogin prints
# a URL to open). `argocd` signs in through Dex on its first use, with the CLI's
# config in the run directory, so its session outlives the shell; on an
# authentication error it removes that config, so the next use signs in again.
# The cluster-admin kubeconfig is the driver's, and the emergency path when
# Dex is down (Q175, Q201): `as_admin` switches kubectl to it, with a red
# prompt and a warning, and `as_me` switches back (docs/BREAK-GLASS.md, "When
# Dex is down"). The audit log then names system:admin, not the person.
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
brzl_ps1="$PS1"

# as_admin — kubectl as system:admin (the cluster-admin kubeconfig), for a
# break-glass open when Dex is down; the prompt says so until as_me.
as_admin() {
  export KUBECONFIG="$BRZL_RUN/kubeconfig"
  PS1='\[\e[1;37;41m\][cluster-admin]\[\e[0m\] '"$brzl_ps1"
  printf 'kiesei shell: kubectl is system:admin now. The audit log does not name you,\n' >&2
  printf '              and records no request body. Only in an open break-glass when\n' >&2
  printf '              Dex is down (docs/BREAK-GLASS.md); write down each change. Back: as_me\n' >&2
}

# as_me — kubectl as the person again (the sign-on kubeconfig).
as_me() {
  export KUBECONFIG="$BRZL_RUN/kubeconfig-sign-on"
  PS1="$brzl_ps1"
  printf 'kiesei shell: kubectl is you again (%s)\n' "$KUBECONFIG" >&2
}

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
printf '              the cluster-admin kubeconfig is the driver'"'"'s; when Dex is down: as_admin, then as_me\n'
if ! kubectl auth whoami -o json 2>/dev/null | jq -r '"              you are " + .status.userInfo.username'; then
  printf 'kiesei shell: no sign-on session (is Dex or GitHub down?); in an emergency: as_admin (docs/BREAK-GLASS.md)\n' >&2
fi
