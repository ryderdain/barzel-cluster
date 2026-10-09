#!/usr/bin/env bash
# driver.sh — the driver: puts an environment's phases in sequence. It is an
# EMIT script: it prints a procedure with one group per phase, and never runs
# or asks anything itself. Running its output IS the approval.
#
#   bash driver/driver.sh <env> next            # preview the next unfinished phase
#   bash driver/driver.sh <env> next | bash     # ...and run it (careful mode)
#   bash driver/driver.sh <env> up              # preview all unfinished phases
#   bash driver/driver.sh <env> up | bash       # ...and run them (fast mode:
#                                               #    only for local-only effects)
#   bash driver/driver.sh <env> down | bash     # remove the environment's cluster
#   bash driver/driver.sh <env> status          # GENERATOR: the current run
#   bash driver/driver.sh <env> check <phase> <run_dir> [down]   # GENERATOR;
#                                               #    the emitted groups call this
#
# Each phase group: (1) the phase's emitter writes its commands to a run-log,
# var/run/<env>/<YYYYmmddHHMM>/<NN>-<phase>.sh; (2) the run-log runs at the
# phase's locus — here, or on the conductor via driver/conductor.sh — its output
# goes to <NN>-<phase>.out and its exit status to .rc; (3) the phase's check
# runs and, if it passes, writes .ok. A failed check stops the stream with
# `error 3`. Resume = run `up` or `next` again: it continues at the first phase
# with no .ok. Rules: ryderdain/bash STYLE.md §1.11–§1.12; ADR-0022.
#
# Inputs: <env> selects env/<env>.env. Needs the tools of each phase (k3d,
# docker, kubectl, helm, jq for local). No credentials for local.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1

up_phases=(10-substrate 15-conductor 20-platform 30-images 40-workloads)
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
  new_run_dir "$env"
}

# new_run_dir <env> [suffix] — print a run directory that does not exist yet:
# var/run/<env>/<YYYYmmddHHMM>[-suffix], with -2, -3, ... if that minute is taken.
new_run_dir() {
  local env="$1" suffix="${2:+-$2}" base n=1 dir
  base="var/run/$env/$(printf '%(%Y%m%d%H%M)T' -1)"
  dir="$base$suffix"
  while [[ -e "$repo_root/$dir" ]]; do
    n=$(( n + 1 ))
    dir="$base-$n$suffix"
  done
  printf '%s' "$dir"
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
  printf '  bash driver/phases/%s.sh %s %q %q > %q\n' "$phase" "$emitter" "$env" "$run_dir" "$run_dir/$name.sh"
  if [[ "$locus" == conductor ]]; then
    printf '  bash driver/conductor.sh %q %q 2>&1 | tee %q\n' "$run_dir" "$name" "$run_dir/$name.out"
  else
    printf '  { bash %q; printf '\''%%s\\n'\'' "$?" > %q; } 2>&1 | tee %q\n' \
      "$run_dir/$name.sh" "$run_dir/$name.rc" "$run_dir/$name.out"
  fi
  printf '  bash driver/driver.sh %q check %q %q%s \\\n' "$env" "$phase" "$run_dir" "$checker"
  printf '    || error 3 %s\n' "$(squote "phase $name did not pass its check; read $run_dir/$name.sh and $name.out, fix, then run again")"
  printf '}\n'
}

emit_up() {
  local env="$1" only_next="$2" run_dir phase emitted=0
  run_dir="$(current_run "$env")"
  emit_prelude "$run_dir"
  for phase in "${up_phases[@]}"; do
    [[ -e "$repo_root/$run_dir/$phase.ok" ]] && continue
    emit_phase "$env" "$run_dir" "$phase" up
    emitted=1
    [[ "$only_next" == true ]] && break
  done
  (( emitted )) || printf '# all phases of %s are complete in %s\n' "$env" "$run_dir"
  end_function 0 "emitted $env ${only_next/true/next}${only_next/false/up} for $run_dir"
}

emit_down() {
  local env="$1" run_dir phase i
  run_dir="$(new_run_dir "$env" down)"
  printf 'cd %q || exit 1\n' "$repo_root"
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
  printf '{ # run directory %s; the next up starts a new run\n' "$run_dir"
  printf '  mkdir -p %q\n' "$run_dir"
  printf '  rm -f %q\n' "var/run/$env/current"
  printf '}\n'
  for (( i = ${#down_phases[@]} - 1; i >= 0; i-- )); do
    phase="${down_phases[i]}"
    emit_phase "$env" "$run_dir" "$phase" down
  done
  end_function 0 "emitted $env down for $run_dir"
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

main() {
  local env="${1:-}" action="${2:-}"
  if [[ -z "$env" || -z "$action" ]]; then
    sed -n '2,24p' "${BASH_SOURCE[0]}" >&2
    return 2
  fi
  if [[ ! -r "$repo_root/env/$env.env" ]]; then
    printf 'error: no environment definition env/%s.env\n' "$env" >&2
    return 2
  fi
  shift 2
  case "$action" in
    up)     emit_up "$env" false ;;
    next)   emit_up "$env" true ;;
    down)   emit_down "$env" ;;
    check)  check "$env" "$@" ;;
    status) status "$env" ;;
    *) printf 'error: unknown action %q (up, next, down, status, check)\n' "$action" >&2; return 2 ;;
  esac
}

if [[ "$is_sourced" == false ]]; then
  main "$@"
fi
