#!/usr/bin/env bash
# seed_demo_data.sh — populate the demo-app's database with a slew of Sefaria searches
# (+ a few items) by driving the app's OWN endpoints (POST /search, POST /items) — so
# every row travels the real app→Sefaria→Postgres path (searches, search_results,
# api_calls) exactly as a human clicking the UI would. Nothing touches Postgres directly.
#
# TWO ways to run it:
#
#   1) EMIT (the previewable primitive — repo convention: print, review, pipe to bash).
#      Target ANY base URL reached directly (NOT the SSO-gated host — curl has no GitHub
#      session): a port-forward, in-cluster service DNS, a public URL, whatever.
#        bash gitops/tools/seed_demo_data.sh                          # preview (default target)
#        bash gitops/tools/seed_demo_data.sh http://localhost:8088 | bash
#        # in-cluster (from a toolbox pod): … seed_demo_data.sh http://demo-app.demo.svc.cluster.local | bash
#
#   2) PF (self-contained convenience): establish the demo-app port-forward itself —
#      BACKGROUNDED, waited-for, and TORN DOWN on exit — then run the seeds against it.
#      No second terminal, no dangling forward. This is the one-liner for a cluster you
#      reach over a port-forward (local k3d, or AWS via the conductor/SSM).
#        bash gitops/tools/seed_demo_data.sh pf            # forward :8088 → svc/demo-app:80, seed, clean up
#        bash gitops/tools/seed_demo_data.sh pf 18088      # pick a different local port
#      Override the target with SEED_NAMESPACE / SEED_SVC if they differ from demo/demo-app.
#
# The app needs egress to www.sefaria.org (NAT on AWS; Docker on k3d) for each search.
# Each search/item is emitted on its OWN line (not &&-chained): a single failed call
# prints "… FAILED" and the rest continue — a seeder should be resilient, not fail-fast.
# Re-run to add more; searches are not deduplicated (the dataset is cumulative).
#
# No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): the only logic here is an arg
# default, a tool check, and the pf lifecycle (checked explicitly); the emitted curls
# each carry their own || fallback. Sourceable (CLAUDE.md): `source` it to get
# emit_seed / seed_pf without running anything.

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  printf 'error: curl not found on PATH\n' >&2
  exit 1
fi

# emit_seed [base-url] — PRINT the seeding curls for a base URL (default localhost:8088).
# The target-agnostic primitive; prints nothing else, so it composes (`| bash`, review).
emit_seed() {
  local base="${1:-http://localhost:8088}"
  base="${base%/}"   # strip any trailing slash
  local size="${SEARCH_SIZE:-5}"   # results per search (demo-app clamps 1..25)

  # A few items for the read/write demo (items table).
  local -a items=(
    "Shabbat reading group"
    "Tikkun olam study circle"
    "Daf yomi cohort"
    "Pirkei Avot discussion"
  )

  # A spread of Sefaria search terms (transliterated themes from the Jewish library).
  local -a terms=(
    shalom moshe "tikkun olam" shabbat torah tzedakah chesed teshuva simcha emunah
    kavanah mitzvah neshama ruach halacha aggadah midrash kabbalah gematria tefillah
    brachot kashrut sukkah etrog lulav shofar "yom kippur" pesach matzah seder
    haggadah omer shavuot sinai covenant exodus jerusalem zion mashiach redemption
    exile prophecy wisdom justice mercy righteousness light creation jubilee manna
  )

  printf '# seed → %s   (%d items, %d searches, size=%d)\n' "$base" "${#items[@]}" "${#terms[@]}" "$size"

  local name q
  for name in "${items[@]}"; do
    printf 'curl -fsS -X POST %q -H %q --data %q -o /dev/null -w %q || echo %q\n' \
      "${base}/items" "Content-Type: application/json" "{\"name\":\"${name}\"}" \
      "item    ${name} -> HTTP %{http_code}\n" "item    ${name} -> FAILED"
  done

  for q in "${terms[@]}"; do
    printf 'curl -fsS -X POST %q --data-urlencode %q --data %q -o /dev/null -w %q || echo %q\n' \
      "${base}/search" "q=${q}" "size=${size}" \
      "search  ${q} -> HTTP %{http_code}\n" "search  ${q} -> FAILED"
  done

  printf 'echo %q\n' "seed complete → check: GET ${base}/items  ·  the demo-app Recent searches  ·  Grafana brzl-demo overview"
}

# seed_pf [local-port] — self-contained: open the demo-app port-forward (backgrounded,
# torn down on exit via the trap), wait for it to answer, then run the emitted seeds
# against it. Namespace/service overridable via SEED_NAMESPACE / SEED_SVC.
seed_pf() {
  command -v kubectl >/dev/null 2>&1 || { printf 'error: kubectl required for pf mode\n' >&2; return 1; }
  local lport="${1:-8088}" ns="${SEED_NAMESPACE:-demo}" svc="${SEED_SVC:-demo-app}"

  printf '# port-forward svc/%s -n %s %s:80 (backgrounded; torn down on exit)\n' "$svc" "$ns" "$lport" >&2
  kubectl -n "$ns" port-forward "svc/${svc}" "${lport}:80" >/dev/null 2>&1 &
  local pf_pid=$!
  # Reap the forward whenever this shell exits (normal end, Ctrl-C, kill).
  trap 'kill "$pf_pid" 2>/dev/null; wait "$pf_pid" 2>/dev/null' EXIT INT TERM

  # Wait for the local listener AND the app behind it to answer (any HTTP code = up;
  # connection-refused keeps us waiting). Bail early if the forward process died.
  local i ready=false
  for ((i = 0; i < 30; i++)); do
    if ! kill -0 "$pf_pid" 2>/dev/null; then
      printf 'error: port-forward exited early — is local port %s in use, or svc/%s missing in ns %s?\n' \
        "$lport" "$svc" "$ns" >&2
      return 1
    fi
    if curl -s -o /dev/null "http://localhost:${lport}/" 2>/dev/null; then ready=true; break; fi
    sleep 1
  done
  if [[ "$ready" != true ]]; then
    printf 'error: demo-app not reachable on localhost:%s after 30s\n' "$lport" >&2
    return 1
  fi

  printf '# forward up — seeding http://localhost:%s ...\n' "$lport" >&2
  set -o pipefail
  emit_seed "http://localhost:${lport}" | bash
}

# CLI dispatch — only when run directly (sourceable otherwise). Default = emit (the
# previewable primitive); `pf` = the self-contained port-forward-and-seed convenience.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false
if [[ "$is_sourced" == false ]]; then
  case "${1:-}" in
    pf) shift; seed_pf "$@" ;;
    *)  emit_seed "$@" ;;
  esac
fi
