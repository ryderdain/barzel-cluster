#!/usr/bin/env bash
# driver.sh — the driver: puts an environment's phases in sequence. It is an
# EMIT script: it prints a procedure with one group per phase, and never runs
# or asks anything itself. Running its output IS the approval. The grammar
# (GLOSSARY "Driver command"; ADR-0038) is `<mode> <verb>`, and BRZL_ENV
# selects the environment (default: local, until BACKLOG 38).
#
#   BRZL_ENV=<env> bash driver/driver.sh cluster bootstrap        # preview the unfinished phases
#   BRZL_ENV=<env> bash driver/driver.sh cluster bootstrap | bash driver/kiesei.sh   # ...and run them
#   BRZL_ENV=<env> bash driver/driver.sh cluster teardown | sed 's/^## ⚠ ##//' | bash driver/kiesei.sh
#                                               # remove the environment's cluster
#   BRZL_ENV=<env> bash driver/driver.sh cluster status           # GENERATOR: the current run
#   BRZL_ENV=<env> bash driver/driver.sh cluster check <phase> <run_dir> [down]   # GENERATOR;
#                                               #    the emitted groups call this
#   BRZL_ENV=<env> bash driver/driver.sh break-glass open '<reason>' | bash driver/kiesei.sh
#                                               # break-glass mode: Argo CD pauses,
#                                               #    the admins are cluster-admin
#   BRZL_ENV=<env> bash driver/driver.sh break-glass apply [<dir>] | bash driver/kiesei.sh
#                                               # ...apply the working tree (local)
#   BRZL_ENV=<env> bash driver/driver.sh break-glass close [confirm] | bash driver/kiesei.sh
#                                               # ...back to git (docs/BREAK-GLASS.md)
#   BRZL_ENV=<env> bash driver/driver.sh audit bootstrap | bash driver/kiesei.sh
#                                               # the reader of the admin log
#                                               #    store, on 127.0.0.1, also
#                                               #    without a cluster
#   BRZL_ENV=<env> bash driver/driver.sh audit teardown | sed 's/^## ⚠ ##//' | bash driver/kiesei.sh
#                                               # ...stop it
#
# `start` and `stop` are synonyms of `bootstrap` and `teardown`, in both modes.
# A teardown (cluster or audit) is guarded: every emitted line is behind the
# prefix `## ⚠ ##`, so a pipe without the `sed` runs nothing: its last line
# prints how to strip it, to stderr, and exits 2.
#
# Each phase group: (1) the phase's emitter writes its commands to a run sheet,
# var/run/<env>/cluster-<UTC>Z/<NN>-<phase>.sh; (2) the run sheet runs at the
# phase's locus — here, or on the conductor via driver/conductor.sh — its output
# goes to <NN>-<phase>.out, after a header line that names the environment, the
# run, the phase and the start time (ADR-0027), and its exit status to .rc; (3) the phase's check
# runs and, if it passes, writes .ok. A failed check stops the stream with
# `error 3`. Resume = run `cluster bootstrap` again: it continues at the first
# phase with no .ok. Rules: ryderdain/bash STYLE.md §1.11–§1.12; ADR-0022.
#
# A run sheet and a check run with stdin from /dev/null. The procedure itself
# arrives on stdin (`| bash`, `| bash driver/kiesei.sh`), so any command in a
# run sheet that reads stdin without a pipe or heredoc of its own (docker exec
# -i, kubectl exec -i, cat, ssh) would swallow the rest of the procedure, and
# the stream would end silently. Data reaches a command by pipe or heredoc.
#
# Break-glass mode (GLOSSARY; any environment; ADR-0037, ADR-0038): open /
# apply / close write their run sheets into the current run
# (break-glass-open-<HHMMSS>Z.sh, ..., in UTC) with driver/modes/break-glass.sh
# and need a run that has passed 30-gitops. The emit step reads only; what it
# prints (the person, the reason, the differences from git) goes to
# <name>-emit.out, so a refused close is on record too. open takes the
# reason, and a declared name when sign-on does not answer; apply takes the
# source tree (default: the working tree); close takes `confirm` to accept
# the undo.
#
# Audit mode (GLOSSARY; ADR-0037): the reader of the admin log store needs no
# cluster and no current run. Each action writes its run sheet in a new run
# directory, var/run/<env>/audit-<UTC>Z, with driver/modes/audit.sh.
#
# Inputs: BRZL_ENV selects env/<env>.env. Needs the tools of each phase (k3d,
# docker, kubectl, helm, jq, yq, git for local). Credentials for local: phase
# 25 reads the bootstrap secret source BRZL_REPO_DEPLOY_KEY where it runs.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1

up_phases=(10-substrate 20-images 25-bootstrap 30-gitops 40-workloads)
down_phases=(10-substrate)

# current_run <env> — print the run directory to use for `up`/`next`: the
# current run if it still has an unfinished phase, otherwise a new one.
current_run() {
  local env="$1" link="var/run/$1/current" phase
  if [[ -L "$repo_root/$link" ]]; then
    local dir
    dir="var/run/$env/$(readlink "$repo_root/$link")"
    for phase in "${up_phases[@]}"; do
      if [[ ! -e "$repo_root/$dir/$phase.ok" ]]; then
        printf '%s' "$dir"
        return 0
      fi
    done
  fi
  new_run_dir "$env" cluster
}

# utc <strftime format> — the time now in UTC (ADR-0027: UTC everywhere).
utc() { TZ=UTC0 printf "%($1)T" -1; }

# new_run_dir <env> <cluster|teardown> — print a run directory that does not
# exist yet: var/run/<env>/<kind>-<YYYYmmddTHHMM>Z, with -2, -3, ... if that
# minute is taken.
new_run_dir() {
  local env="$1" kind="$2" base n=1 dir
  base="var/run/$env/$kind-$(utc '%Y%m%dT%H%M')Z"
  dir="$base"
  while [[ -e "$repo_root/$dir" ]]; do
    n=$(( n + 1 ))
    dir="$base-$n"
  done
  printf '%s' "$dir"
}

# run_output_header <env> <run_dir> <name> — the emitted command that starts a
# run output with its header line (logfmt; ADR-0027). The start time is taken
# when the line runs, not when it is emitted. The collector tells files apart
# by their first bytes, so two outputs with the same text need this line.
# The person is the account on the operator's machine (Q208): BRZL_HOST_USER
# from driver/kiesei.sh, else the account that runs the line. It is declared,
# not verified: every phase still acts as system:admin.
run_output_header() {
  # shellcheck disable=SC2016  # the $(...) is for the emitted stream to run
  printf 'printf '\''# brzl run-output env=%s run=%s phase=%s start=%%s person=%%s person_verified=false\\n'\'' "$(date -u +%%Y-%%m-%%dT%%H:%%M:%%SZ)" "${BRZL_HOST_USER:-$(id -un)}"' \
    "$1" "${2##*/}" "$3"
}

# squote <text> — single-quote text for the emitted stream, readably (plain
# POSIX quoting, unlike printf %q's backslashes).
squote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

emit_prelude() {
  local run_dir="$1"
  printf 'cd %q || exit 1\n' "$repo_root"
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
  printf '{ # run directory %s (the current run of this environment)\n' "$run_dir"
  printf '  mkdir -p %q\n' "$run_dir"
  printf '  ln -sfn %q %q\n' "${run_dir##*/}" "${run_dir%/*}/current"
  printf '}\n'
}

# emit_phase <env> <run_dir> <phase> <up|down>
emit_phase() {
  local env="$1" run_dir="$2" phase="$3" mode="$4" name emitter checker locus
  name="$phase"; emitter=phase_up; checker=''
  if [[ "$mode" == down ]]; then
    name="$phase-down"; emitter=phase_down; checker=' down'
  fi
  locus="$(bash "$repo_root/driver/phases/$phase.sh" phase_locus 2>/dev/null)"
  [[ "$mode" == down ]] && locus=driver   # removing a cluster is never the conductor's job
  printf '{ # phase %s (%s, locus: %s)\n' "$name" "$env" "${locus:-driver}"
  printf '  bash driver/phases/%s.sh %s %q %q > %q \\\n' "$phase" "$emitter" "$env" "$run_dir" "$run_dir/$name.sh"
  printf '    || error 3 %s\n' "$(squote "phase $name could not be emitted (the message above says what is missing; the stream belongs in kiesei: | bash driver/kiesei.sh); nothing ran")"
  if [[ "$locus" == conductor ]]; then
    printf '  { %s; bash driver/conductor.sh %q %q < /dev/null; } 2>&1 | tee %q\n' \
      "$(run_output_header "$env" "$run_dir" "$name")" "$run_dir" "$name" "$run_dir/$name.out"
  else
    printf '  { %s; bash %q < /dev/null; printf '\''%%s\\n'\'' "$?" > %q; } 2>&1 | tee %q\n' \
      "$(run_output_header "$env" "$run_dir" "$name")" "$run_dir/$name.sh" "$run_dir/$name.rc" "$run_dir/$name.out"
  fi
  printf '  BRZL_ENV=%q bash driver/driver.sh cluster check %q %q%s < /dev/null \\\n' "$env" "$phase" "$run_dir" "$checker"
  printf '    || error 3 %s\n' "$(squote "phase $name did not pass its check; read $run_dir/$name.sh and $name.out, fix, then run again")"
  printf '}\n'
}

emit_up() {
  local env="$1" run_dir phase emitted=0
  run_dir="$(current_run "$env")"
  emit_prelude "$run_dir"
  for phase in "${up_phases[@]}"; do
    [[ -e "$repo_root/$run_dir/$phase.ok" ]] && continue
    emit_phase "$env" "$run_dir" "$phase" up
    emitted=1
  done
  (( emitted )) || printf '# all phases of %s are complete in %s\n' "$env" "$run_dir"
  end_function 0 "emitted $env cluster bootstrap for $run_dir"
}

emit_down() {
  local env="$1" run_dir phase i
  run_dir="$(new_run_dir "$env" teardown)"
  printf 'cd %q || exit 1\n' "$repo_root"
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
  printf '{ # run directory %s; the next bootstrap starts a new run\n' "$run_dir"
  printf '  mkdir -p %q\n' "$run_dir"
  printf '  rm -f %q\n' "var/run/$env/current"
  printf '}\n'
  for (( i = ${#down_phases[@]} - 1; i >= 0; i-- )); do
    phase="${down_phases[i]}"
    emit_phase "$env" "$run_dir" "$phase" down
  done
  end_function 0 "emitted $env cluster teardown for $run_dir"
}

# guarded <emit function> <args> — the teardown guard (Q238, Q244): every
# line of the emitted stream behind the prefix, between a first line that
# sets a variable (behind the prefix too) and a last group, with no prefix,
# that tests it. A pipe without the sed reads only comments, then the last
# group prints the footer to stderr and exits 2. With the sed, the first
# line sets the variable, the teardown runs, and the last group passes.
guarded() {
  local rc
  set -o pipefail   # the emitter's failure must not hide behind sed's success
  { printf 'guard=stripped   # the teardown guard: the last group tests it\n'; "$@"; } | sed 's/^/## ⚠ ##/'
  rc=$?
  set +o pipefail
  (( rc == 0 )) || return "$rc"
  printf '[[ "${guard:-}" == stripped ]] || {   # the prefix was not stripped: nothing ran\n'
  printf "  cat >&2 <<'EOF'\n"
  printf '##    TO TEARDOWN, PASTE `sed '"'"'s/^## ⚠ ##//'"'"'` INTO PIPE    ##\n'
  printf 'EOF\n'
  printf '  exit 2\n'
  printf '}\n'
}

# emit_break_glass <env> <open|close|apply> [args] — one group for a
# break-glass action, in the current run, at the driver locus. Three steps,
# each recorded: the emitter (it reads the cluster and the working tree, and
# stops with error 3 when the action must not run: another person's open, a
# difference from git for close, apply while not open), the run sheet, the
# check (apply has none: Argo CD's own result is in the run output).
emit_break_glass() {
  local env="$1" what="$2" link="$repo_root/var/run/$1/current" run_dir name arg args='' title
  shift 2
  if [[ ! -L "$link" ]]; then
    printf 'error: %s has no current run; bring it up first\n' "$env" >&2
    return 2
  fi
  run_dir="var/run/$env/$(readlink "$link")"
  if [[ ! -e "$repo_root/$run_dir/30-gitops.ok" ]]; then
    printf 'error: break-glass mode needs Argo CD: phase 30-gitops has not passed in %s\n' "$run_dir" >&2
    return 2
  fi
  case "$what" in
    open)
      if [[ -z "${1:-}" ]]; then
        printf "usage: BRZL_ENV=%s bash driver/driver.sh break-glass open '<reason>' ['<your name>', when sign-on does not answer] | bash driver/kiesei.sh\n" "$env" >&2
        return 2
      fi
      title="break-glass open ($env, locus: driver; docs/BREAK-GLASS.md)" ;;
    close)
      if [[ -n "${1:-}" && "$1" != confirm ]]; then
        printf 'usage: BRZL_ENV=%s bash driver/driver.sh break-glass close [confirm] | bash driver/kiesei.sh\n' "$env" >&2
        return 2
      fi
      title="break-glass close ($env, locus: driver; docs/BREAK-GLASS.md)" ;;
    apply)
      if (( $# > 1 )); then
        printf 'usage: BRZL_ENV=%s bash driver/driver.sh break-glass apply [<dir>] | bash driver/kiesei.sh\n' "$env" >&2
        return 2
      fi
      title="break-glass apply: ${1:-the working tree} ($env, locus: driver; docs/LOCAL.md)" ;;
  esac
  for arg in "$@"; do args+=" $(squote "$arg")"; done
  name="break-glass-$what-$(utc '%H%M%S')Z"
  printf 'cd %q || exit 1\n' "$repo_root"
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
  printf '{ # %s\n' "$title"
  printf '  {\n    %s\n' "$(run_output_header "$env" "$run_dir" "$name-emit")"
  printf '    bash driver/modes/break-glass.sh %s %q %q%s > %q < /dev/null\n' "$what" "$env" "$run_dir" "$args" "$run_dir/$name.sh"
  printf '    printf '\''%%s\\n'\'' "$?" > %q\n' "$run_dir/$name-emit.rc"
  printf '  } 2>&1 | tee %q\n' "$run_dir/$name-emit.out"
  # shellcheck disable=SC2016  # the $(...) is for the emitted stream to run
  printf '  [[ "$(cat %q 2>/dev/null)" == 0 ]] \\\n' "$run_dir/$name-emit.rc"
  printf '    || error 3 %s\n' "$(squote "break-glass $what stopped before any change: read the lines above (kept in $run_dir/$name-emit.out)")"
  printf '  {\n    %s\n' "$(run_output_header "$env" "$run_dir" "$name")"
  printf '    bash %q < /dev/null\n' "$run_dir/$name.sh"
  printf '    printf '\''%%s\\n'\'' "$?" > %q\n' "$run_dir/$name.rc"
  printf '  } 2>&1 | tee %q\n' "$run_dir/$name.out"
  if [[ "$what" == apply ]]; then
    # shellcheck disable=SC2016  # the $(...) is for the emitted stream to run
    printf '  [[ "$(cat %q 2>/dev/null)" == 0 ]] \\\n' "$run_dir/$name.rc"
    printf '    || error 3 %s\n' "$(squote "apply failed (break-glass stays open); read $run_dir/$name.out, fix, then apply again")"
  else
    printf '  bash driver/modes/break-glass.sh %s_check %q %q < /dev/null \\\n' "$what" "$env" "$run_dir"
    printf '    || error 3 %s\n' "$(squote "break-glass $what did not take effect; read $run_dir/$name.out, then run $what again")"
  fi
  printf '}\n'
  end_function 0 "emitted $env break-glass $what for $run_dir"
}

# emit_audit <env> <bootstrap|teardown> — one group for the reader of the
# admin log store, in a new run directory (the cluster can be gone), at the
# driver locus.
emit_audit() {
  local env="$1" what="$2" run_dir name
  run_dir="$(new_run_dir "$env" audit)"
  name="audit-$what"
  printf 'cd %q || exit 1\n' "$repo_root"
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
  printf '{ # audit %s: the reader of the admin log store (%s, locus: driver; docs/BREAK-GLASS.md)\n' "$what" "$env"
  printf '  mkdir -p %q\n' "$run_dir"
  printf '  bash driver/modes/audit.sh audit_%s %q %q > %q \\\n' "$what" "$env" "$run_dir" "$run_dir/$name.sh"
  printf '    || error 3 %s\n' "$(squote "audit $what could not be emitted (the message above says why); nothing ran")"
  printf '  {\n    %s\n' "$(run_output_header "$env" "$run_dir" "$name")"
  printf '    bash %q < /dev/null\n' "$run_dir/$name.sh"
  printf '    printf '\''%%s\\n'\'' "$?" > %q\n' "$run_dir/$name.rc"
  printf '  } 2>&1 | tee %q\n' "$run_dir/$name.out"
  printf '  bash driver/modes/audit.sh audit_%s_check %q %q < /dev/null \\\n' "$what" "$env" "$run_dir"
  printf '    || error 3 %s\n' "$(squote "audit $what did not take effect; read $run_dir/$name.out")"
  printf '}\n'
  end_function 0 "emitted $env audit $what for $run_dir"
}

# check <env> <phase> <run_dir> [down] — GENERATOR. Runs the phase's check in a
# subshell (so the phase script's globals stay out of this one) and writes .ok.
check() {
  local env="$1" phase="$2" run_dir="$3" mode="${4:-up}" name="$2" fn=phase_check
  if [[ "$mode" == down ]]; then
    name="$phase-down"; fn=phase_check_down
  fi
  if [[ ! -r "$repo_root/driver/phases/$phase.sh" ]]; then
    printf 'error: no phase %s\n' "$phase" >&2
    return 2
  fi
  # shellcheck source=/dev/null
  if ( source "$repo_root/driver/phases/$phase.sh" && "$fn" "$env" "$run_dir" ); then
    : > "$repo_root/$run_dir/$name.ok"
    return 0
  fi
  return 1
}

# status <env> — GENERATOR: one line per phase of the current run.
status() {
  local env="$1" link="$repo_root/var/run/$1/current" dir phase state
  if [[ ! -L "$link" ]]; then
    printf '%s: no current run\n' "$env"
    return 0
  fi
  dir="var/run/$env/$(readlink "$link")"
  printf '%s: current run %s\n' "$env" "$dir"
  for phase in "${up_phases[@]}"; do
    if [[ -e "$repo_root/$dir/$phase.ok" ]]; then state=ok
    elif [[ -e "$repo_root/$dir/$phase.rc" ]]; then state="ran (rc=$(<"$repo_root/$dir/$phase.rc")), check not passed"
    else state='not run'
    fi
    printf '  %-14s %s\n' "$phase" "$state"
  done
}

usage() {
  printf 'usage: BRZL_ENV=<env> bash driver/driver.sh <mode> <verb>, one of:\n' >&2
  printf '  cluster bootstrap | teardown | status | check <phase> <run_dir> [down]\n' >&2
  printf "  break-glass open '<reason>' | apply [<dir>] | close [confirm]\n" >&2
  printf '  audit bootstrap | teardown\n' >&2
  printf '(start and stop are synonyms of bootstrap and teardown; a teardown needs | sed %s in the pipe)\n' "'s/^## ⚠ ##//'" >&2
}

main() {
  local env="${BRZL_ENV:-local}" mode="${1:-}" verb="${2:-}"
  if [[ -z "$mode" || -z "$verb" ]]; then
    usage
    return 2
  fi
  if [[ ! -r "$repo_root/env/$env.env" ]]; then
    printf 'error: no environment definition env/%s.env (BRZL_ENV selects one of:%s)\n' \
      "$env" "$(for f in "$repo_root"/env/*.env; do printf ' %s' "${f##*/}"; done | sed 's/\.env//g')" >&2
    return 2
  fi
  shift 2
  case "$mode $verb" in
    'cluster bootstrap'|'cluster start') emit_up "$env" ;;
    'cluster teardown'|'cluster stop')   guarded emit_down "$env" ;;
    'cluster status')  status "$env" ;;
    'cluster check')   check "$env" "$@" ;;
    'break-glass open'|'break-glass close'|'break-glass apply') emit_break_glass "$env" "$verb" "$@" ;;
    'audit bootstrap'|'audit start')   emit_audit "$env" bootstrap ;;
    'audit teardown'|'audit stop')     guarded emit_audit "$env" teardown ;;
    *) printf 'error: unknown command %q %q\n' "$mode" "$verb" >&2; usage; return 2 ;;
  esac
}

if [[ "$is_sourced" == false ]]; then
  main "$@"
fi
