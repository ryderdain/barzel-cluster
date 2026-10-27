#!/usr/bin/env bash
# driver.sh — the driver: puts an environment's phases in sequence. It is an
# EMIT script: it prints a procedure with one group per phase, and never runs
# or asks anything itself. Running its output IS the approval.
#
#   bash driver/driver.sh <env> next            # preview the next unfinished phase
#   bash driver/driver.sh <env> next | bash     # ...and run it (careful mode)
#   bash driver/driver.sh <env> up              # preview all unfinished phases
#   bash driver/driver.sh <env> up | bash       # ...and run them all at once
#                                               #    (only for local-only effects)
#   bash driver/driver.sh <env> down | bash     # remove the environment's cluster
#   bash driver/driver.sh local fast_on | bash  # fast mode: Argo CD holds
#   bash driver/driver.sh local apply | bash    # ...apply the working tree
#   bash driver/driver.sh local fast_off | bash # ...back to the pushed branch
#   bash driver/driver.sh <env> hold '<reason>' | bash driver/kiesei.sh
#                                               # break-glass mode: Argo CD holds,
#                                               #    the admins are cluster-admin
#   bash driver/driver.sh <env> release [confirm] | bash driver/kiesei.sh
#                                               # ...back to git (docs/BREAK-GLASS.md)
#   bash driver/driver.sh <env> status          # GENERATOR: the current run
#   bash driver/driver.sh <env> check <phase> <run_dir> [down]   # GENERATOR;
#                                               #    the emitted groups call this
#
# Each phase group: (1) the phase's emitter writes its commands to a run sheet,
# var/run/<env>/cluster-<UTC>Z/<NN>-<phase>.sh; (2) the run sheet runs at the
# phase's locus — here, or on the conductor via driver/conductor.sh — its output
# goes to <NN>-<phase>.out, after a header line that names the environment, the
# run, the phase and the start time (ADR-0027), and its exit status to .rc; (3) the phase's check
# runs and, if it passes, writes .ok. A failed check stops the stream with
# `error 3`. Resume = run `up` or `next` again: it continues at the first phase
# with no .ok. Rules: ryderdain/bash STYLE.md §1.11–§1.12; ADR-0022.
#
# A run sheet and a check run with stdin from /dev/null. The procedure itself
# arrives on stdin (`| bash`, `| bash driver/kiesei.sh`), so any command in a
# run sheet that reads stdin without a pipe or heredoc of its own (docker exec
# -i, kubectl exec -i, cat, ssh) would swallow the rest of the procedure, and
# the stream would end silently. Data reaches a command by pipe or heredoc.
#
# Fast mode (GLOSSARY; local only; ADR-0025): fast_on / fast_off / apply write
# their run sheets into the current run (fast-on-<HHMMSS>Z.sh, ..., in UTC) with
# driver/fast-mode.sh and need a run that has passed 30-gitops.
#
# Break-glass mode (GLOSSARY; any environment; ADR-0037): hold / release
# write their run sheets the same way (break-glass-hold-<HHMMSS>Z.sh, ...) with
# driver/modes/break-glass.sh. Its emit step reads only; what it prints (the
# person, the reason, the differences from git) goes to <name>-emit.out, so a
# refused release is on record too. hold takes the reason, and a declared
# name only when Dex is down; release takes `confirm` to accept the undo.
#
# Inputs: <env> selects env/<env>.env. Needs the tools of each phase (k3d,
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
run_output_header() {
  # shellcheck disable=SC2016  # the $(...) is for the emitted stream to run
  printf 'printf '\''# brzl run-output env=%s run=%s phase=%s start=%%s\\n'\'' "$(date -u +%%Y-%%m-%%dT%%H:%%M:%%SZ)"' \
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
  printf '  bash driver/driver.sh %q check %q %q%s < /dev/null \\\n' "$env" "$phase" "$run_dir" "$checker"
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
  local action=up; [[ "$only_next" == true ]] && action=next
  end_function 0 "emitted $env $action for $run_dir"
}

emit_down() {
  local env="$1" run_dir phase i
  run_dir="$(new_run_dir "$env" teardown)"
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

# emit_fast <env> <on|off|apply> — one group for a fast-mode action, in the
# current run. Switching runs here (driver locus); apply runs on the conductor.
emit_fast() {
  local env="$1" what="$2" link="$repo_root/var/run/$1/current" run_dir name
  if [[ ! -L "$link" ]]; then
    printf 'error: %s has no current run; bring it up first\n' "$env" >&2
    return 2
  fi
  run_dir="var/run/$env/$(readlink "$link")"
  if [[ ! -e "$repo_root/$run_dir/30-gitops.ok" ]]; then
    printf 'error: fast mode needs Argo CD: phase 30-gitops has not passed in %s\n' "$run_dir" >&2
    return 2
  fi
  name="fast-$what-$(utc '%H%M%S')Z"
  printf 'cd %q || exit 1\n' "$repo_root"
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
  if [[ "$what" == apply ]]; then
    printf '{ # fast mode: apply the working tree (%s, locus: conductor)\n' "$env"
    printf '  bash driver/fast-mode.sh fast_apply %q %q > %q \\\n' "$env" "$run_dir" "$run_dir/$name.sh"
    printf '    || error 3 %s\n' "$(squote "nothing applied: is fast mode on? (bash driver/driver.sh $env fast_on)")"
    printf '  { %s; bash driver/conductor.sh %q %q < /dev/null; } 2>&1 | tee %q\n' \
      "$(run_output_header "$env" "$run_dir" "$name")" "$run_dir" "$name" "$run_dir/$name.out"
    # shellcheck disable=SC2016  # the $(...) is for the emitted stream to run
    printf '  [[ "$(cat %q 2>/dev/null)" == 0 ]] \\\n' "$run_dir/$name.rc"
    printf '    || error 3 %s\n' "$(squote "apply failed (fast mode stays on); read $run_dir/$name.out, fix, then apply again")"
    printf '}\n'
  else
    printf '{ # fast mode %s (%s, locus: driver)\n' "$what" "$env"
    printf '  bash driver/fast-mode.sh fast_switch %q %q %q > %q \\\n' "$what" "$env" "$run_dir" "$run_dir/$name.sh"
    printf '    || error 3 %s\n' "$(squote "fast mode not switched: see the message above")"
    printf '  { %s; bash %q < /dev/null; printf '\''%%s\\n'\'' "$?" > %q; } 2>&1 | tee %q\n' \
      "$(run_output_header "$env" "$run_dir" "$name")" "$run_dir/$name.sh" "$run_dir/$name.rc" "$run_dir/$name.out"
    printf '  bash driver/fast-mode.sh fast_check %q %q %q < /dev/null \\\n' "$what" "$env" "$run_dir"
    printf '    || error 3 %s\n' "$(squote "fast mode $what did not take effect; read $run_dir/$name.out")"
    printf '}\n'
  fi
  end_function 0 "emitted $env fast $what for $run_dir"
}

# emit_break_glass <env> <hold|release> [args] — one group for a break-glass
# action, in the current run, at the driver locus. Three steps, each recorded:
# the emitter (it reads the cluster and stops, with error 3, when the action
# must not run), the run sheet, the check.
emit_break_glass() {
  local env="$1" what="$2" link="$repo_root/var/run/$1/current" run_dir name arg args=''
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
  if [[ "$what" == hold && -z "${1:-}" ]]; then
    printf "usage: bash driver/driver.sh %s hold '<reason>' ['<your name>', only when Dex is down] | bash driver/kiesei.sh\n" "$env" >&2
    return 2
  fi
  for arg in "$@"; do args+=" $(squote "$arg")"; done
  name="break-glass-$what-$(utc '%H%M%S')Z"
  printf 'cd %q || exit 1\n' "$repo_root"
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
  printf '{ # break-glass %s (%s, locus: driver; docs/BREAK-GLASS.md)\n' "$what" "$env"
  printf '  { %s; bash driver/modes/break-glass.sh %s %q %q%s > %q < /dev/null; printf '\''%%s\\n'\'' "$?" > %q; } 2>&1 | tee %q\n' \
    "$(run_output_header "$env" "$run_dir" "$name-emit")" "$what" "$env" "$run_dir" "$args" \
    "$run_dir/$name.sh" "$run_dir/$name-emit.rc" "$run_dir/$name-emit.out"
  # shellcheck disable=SC2016  # the $(...) is for the emitted stream to run
  printf '  [[ "$(cat %q 2>/dev/null)" == 0 ]] \\\n' "$run_dir/$name-emit.rc"
  printf '    || error 3 %s\n' "$(squote "break-glass $what stopped before any change: read the lines above (kept in $run_dir/$name-emit.out)")"
  printf '  { %s; bash %q < /dev/null; printf '\''%%s\\n'\'' "$?" > %q; } 2>&1 | tee %q\n' \
    "$(run_output_header "$env" "$run_dir" "$name")" "$run_dir/$name.sh" "$run_dir/$name.rc" "$run_dir/$name.out"
  printf '  bash driver/modes/break-glass.sh %s_check %q %q < /dev/null \\\n' "$what" "$env" "$run_dir"
  printf '    || error 3 %s\n' "$(squote "break-glass $what did not take effect; read $run_dir/$name.out, then run $what again")"
  printf '}\n'
  end_function 0 "emitted $env break-glass $what for $run_dir"
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
    sed -n '2,53p' "${BASH_SOURCE[0]}" >&2
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
    fast_on)  emit_fast "$env" on ;;
    fast_off) emit_fast "$env" off ;;
    apply)    emit_fast "$env" apply ;;
    hold)     emit_break_glass "$env" hold "$@" ;;
    release)  emit_break_glass "$env" release "$@" ;;
    *) printf 'error: unknown action %q (up, next, down, status, check, fast_on, fast_off, apply, hold, release)\n' "$action" >&2; return 2 ;;
  esac
}

if [[ "$is_sourced" == false ]]; then
  main "$@"
fi
