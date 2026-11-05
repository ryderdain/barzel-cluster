#!/usr/bin/env bash
# audit.sh — audit mode (GLOSSARY; ADR-0037, ADR-0038, BACKLOG 28, Q197,
# Q238; docs/BREAK-GLASS.md): the reader of the admin log store, a Loki and
# a Grafana in two containers on the operator's machine, which read the
# admin log store's data. For a cluster that is down, out of reach or gone,
# or whose Grafana cannot help; it also runs beside a running cluster. The
# driver's `audit bootstrap` / `audit teardown` call this script; it writes
# run sheets, which the driver runs at its own locus.
#
#   bash driver/modes/audit.sh audit_bootstrap <env> <run_dir>          # EMIT a run sheet
#   bash driver/modes/audit.sh audit_bootstrap_check <env> <run_dir>    # GENERATOR
#   bash driver/modes/audit.sh audit_teardown <env> <run_dir>           # EMIT a run sheet
#   bash driver/modes/audit.sh audit_teardown_check <env> <run_dir>     # GENERATOR
#
# audit_bootstrap: the Loki reads the store's directory read-only, as a
# querier alone (driver/modes/audit-loki.yaml), so it cannot change the
# store. The Grafana shares the Loki container's network and has the data
# source "Admin log store" (audit-datasources.yaml). It has no sign-on (Dex
# is in the cluster): anyone on this machine who reaches
# 127.0.0.1:BRZL_READER_PORT can read the store, and nobody else can. The
# containers stay until audit_teardown; they do not stop by themselves.
#
# While the cluster runs, its admin Loki writes the same directory and
# builds its index every 15 minutes, so the reader sees records up to about
# 15 minutes late. The emitter says so on stderr.
#
# Local only: the store is the host directory BRZL_LOG_STORE_DIR/admin. A
# store in a bucket (pass 8) needs its own storage settings here.
# Inputs: env/<env>.env (BRZL_LOG_STORE_DIR, BRZL_READER_PORT,
# BRZL_READER_LOKI_IMAGE, BRZL_READER_GRAFANA_IMAGE, BRZL_K3D_CLUSTER). Needs
# docker and curl. No credentials.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

# audit_init <env> — load the environment; set the globals loki, grafana
# (the container names) and store (the store's directory, from the repo root).
audit_init() {
  local env="$1" name
  phase_init "$env" || return 1
  for name in BRZL_LOG_STORE_DIR BRZL_READER_PORT BRZL_READER_LOKI_IMAGE BRZL_READER_GRAFANA_IMAGE; do
    if [[ -z "${!name:-}" ]]; then
      printf 'error: env/%s.env has no %s; the reader reads only a local admin log store (a bucket comes with pass 8)\n' "$env" "$name" >&2
      return 2
    fi
  done
  loki="brzl-audit-$env-loki"
  grafana="brzl-audit-$env-grafana"
  store="$BRZL_LOG_STORE_DIR/admin"
}

# audit_header — the top of a run sheet: the resolved inputs (no
# kubeconfig: the reader does not use the cluster).
audit_header() {
  printf '# resolved environment definition:\n'
  env_definition_record
}

# present <container> — is the container there (running or not)?
present() { docker inspect --format '{{.Id}}' "$1" >/dev/null 2>&1; }

audit_bootstrap() {
  local env="$1" node running
  audit_init "$env" || return
  if [[ ! -d "$repo_root/$store/chunks/index" ]]; then
    printf 'error: no admin log store data in %s (no chunks/index); nothing to read\n' "$store" >&2
    return 1
  fi
  node="k3d-${BRZL_K3D_CLUSTER:-}-server-0"
  running="$(docker inspect --format '{{.State.Running}}' "$node" 2>/dev/null)"
  if [[ "$running" == true ]]; then
    printf 'note: the cluster runs: its admin Loki writes %s too. The reader only reads it,\n' "$store" >&2
    printf '      and it sees records up to about 15 minutes late (the index is built every 15 minutes).\n' >&2
  fi
  audit_header
  if present "$loki" || present "$grafana"; then
    printf '{ # the reader from before: remove it, then start it again (the store is not touched)\n'
    present "$grafana" && printf '  docker rm -f %q\n' "$grafana"
    present "$loki" && printf '  docker rm -f %q\n' "$loki"
    printf '}\n'
  fi
  printf '{ # the reader'"'"'s Loki: the admin log store, read-only, as a querier alone\n'
  printf '  # (driver/modes/audit-loki.yaml). It publishes Grafana'"'"'s port, on 127.0.0.1 only:\n'
  printf '  # the Grafana below shares this container'"'"'s network.\n'
  printf '  docker run -d --name %q -p %q \\\n' "$loki" "127.0.0.1:$BRZL_READER_PORT:3000"
  printf '    -v %q \\\n' "$repo_root/$store:/store:ro" "$repo_root/driver/modes/audit-loki.yaml:/etc/loki/config.yaml:ro"
  printf '    %q -config.file=/etc/loki/config.yaml\n' "$BRZL_READER_LOKI_IMAGE"
  printf '}\n'
  printf '{ # the reader'"'"'s Grafana: no sign-on (an anonymous Editor, for Explore), the data source\n'
  printf '  # "Admin log store" (driver/modes/audit-datasources.yaml)\n'
  printf '  docker run -d --name %q --network %q \\\n' "$grafana" "container:$loki"
  printf '    -e GF_AUTH_ANONYMOUS_ENABLED=true -e GF_AUTH_ANONYMOUS_ORG_ROLE=Editor -e GF_AUTH_DISABLE_LOGIN_FORM=true \\\n'
  printf '    -e GF_ANALYTICS_REPORTING_ENABLED=false -e GF_ANALYTICS_CHECK_FOR_UPDATES=false -e GF_NEWS_NEWS_FEED_ENABLED=false \\\n'
  printf '    -v %q \\\n' "$repo_root/driver/modes/audit-datasources.yaml:/etc/grafana/provisioning/datasources/reader.yaml:ro"
  printf '    %q\n' "$BRZL_READER_GRAFANA_IMAGE"
  printf '}\n'
}

# audit_bootstrap_check — GENERATOR: Grafana answers, and its data source reaches
# the reader's Loki. Waits up to 90 s (the first start pulls the images).
audit_bootstrap_check() {
  local env="$1" waited=0 url
  audit_init "$env" || return
  url="http://127.0.0.1:$BRZL_READER_PORT"
  while (( waited <= 90 )); do
    if curl -fsS "$url/api/datasources/uid/admin-log-store/health" >/dev/null 2>&1; then
      printf 'the reader of the admin log store: %s/explore (data source "Admin log store", %s)\n' "$url" "$store"
      printf 'stop it after use: BRZL_ENV=%s bash driver/driver.sh audit teardown | sed %s | bash driver/kiesei.sh\n' "$env" "'s/^## ⚠ ##//'"
      return 0
    fi
    sleep 3
    waited=$(( waited + 3 ))
  done
  printf 'fix: after 90 s, Grafana at %s does not reach the store; see: docker logs %s; docker logs %s\n' "$url" "$loki" "$grafana" >&2
  return 1
}

audit_teardown() {
  local env="$1"
  audit_init "$env" || return
  audit_header
  if ! present "$loki" && ! present "$grafana"; then
    printf '# the reader of %s is not running: nothing to stop\n' "$env"
    return 0
  fi
  printf '{ # stop the reader of the admin log store (the store is not touched)\n'
  present "$grafana" && printf '  docker rm -f %q\n' "$grafana"
  present "$loki" && printf '  docker rm -f %q\n' "$loki"
  printf '}\n'
}

audit_teardown_check() {
  local env="$1"
  audit_init "$env" || return
  if present "$loki" || present "$grafana"; then
    printf 'fix: docker rm -f %q %q\n' "$grafana" "$loki" >&2
    return 1
  fi
  printf 'the reader of %s is stopped\n' "$env"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,31p' "${BASH_SOURCE[0]}"; fi
fi
