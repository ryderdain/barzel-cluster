#!/usr/bin/env bash
# driver-cases.sh — checks the driver's own mechanics with no cluster: run-logs,
# .rc and .ok files, resume at the first unfinished phase, the `error 3` stop on
# a failed check, and `down`.
#
# Read-only check archetype (it writes only to a temporary directory). It copies
# driver/ into a scratch tree, swaps in a fake substrate and two trivial phases,
# pipes the driver's output to bash, and inspects the result. One line per
# case; exits non-zero if any case fails.
#
#   bash driver/tests/driver-cases.sh        # report
#   bash driver/tests/driver-cases.sh -q     # exit code only
#
# No credentials, no network, no container engine.

(( BASH_VERSINFO[0] < 4 )) && { printf 'error: bash >= 4 required\n' >&2; exit 1; }

src="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
quiet=false
[[ "${1:-}" == "-q" ]] && quiet=true
failures=0
case_num=0

report() {
  local claim="$1" expected="$2" actual="$3"
  case_num=$(( case_num + 1 ))
  if [[ "$expected" == "$actual" ]]; then
    "$quiet" || printf '  ok %d — %s\n' "$case_num" "$claim"
    return 0
  fi
  failures=$(( failures + 1 ))
  printf 'FAIL %d — %s\n      expected: %s\n      actual:   %s\n' \
    "$case_num" "$claim" "$expected" "$actual" >&2
}

scratch="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/env" || exit 1
cp -R "$src/driver" "$scratch/driver" || exit 1
printf 'BRZL_SUBSTRATE=fake\n' > "$scratch/env/test.env"

# A fake substrate: "up" leaves a marker file; the check looks for it. A
# marker named BREAK in the scratch root makes the check fail on purpose.
cat > "$scratch/driver/substrates/fake.sh" <<'EOF'
substrate_up() { printf '{ # fake cluster\n  : > %s\n}\n' "$1/cluster"; }
substrate_down() { printf '{ # remove fake cluster\n  rm -f var/run/test/*/cluster\n}\n'; }
substrate_load_image() { :; }
substrate_check() { [[ -e "$1/cluster" && ! -e BREAK ]]; }
substrate_check_down() { ! compgen -G 'var/run/test/*/cluster' >/dev/null; }
EOF
# Phases 20 and 30 become trivial, so the driver's sequencing is what is tested.
for phase in 20-platform 30-workloads; do
  cat > "$scratch/driver/phases/$phase.sh" <<EOF
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false
repo_root="\$(cd -- "\${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
source "\$repo_root/driver/lib/runlib.sh" || exit 1
source "\$repo_root/driver/lib/phase-common.sh" || exit 1
phase_up() { phase_init "\$1" || return 1; phase_header "\$2"; printf '{ # %s\n  : > %s\n}\n' $phase "\$2/$phase.done"; }
phase_check() { [[ -e "\$2/$phase.done" ]]; }
if [[ "\$is_sourced" == false ]]; then "\$@"; fi
EOF
done

drive() { (cd "$scratch" && bash driver/driver.sh test "$@" 2>/dev/null); }
run_dir() { readlink "$scratch/var/run/test/current"; }

"$quiet" || printf 'driver mechanics (bash %s)\n\n' "$BASH_VERSION"

# 1. A preview changes nothing: emitting `up` creates no run directory.
drive up >/dev/null
report 'previewing up creates nothing' 'absent' "$([[ -e "$scratch/var" ]] && printf present || printf absent)"

# 2. `next | bash` runs exactly one phase and records it: run-log, .rc, .ok.
drive next | (cd "$scratch" && bash >/dev/null 2>&1)
dir="$scratch/var/run/test/$(run_dir)"
files=("$dir"/10-substrate.*); got="$(printf '%s ' "${files[@]##*/}")"
report 'next runs one phase and records .sh .out .rc .ok' '10-substrate.ok 10-substrate.out 10-substrate.rc 10-substrate.sh ' "$got"
report 'next runs only that phase' 'no' "$([[ -e "$dir/20-platform.sh" ]] && printf yes || printf no)"

# 3. The run-log starts with the resolved inputs.
report 'the run-log records the resolved environment' '# BRZL_SUBSTRATE=fake' "$(sed -n 2p "$dir/10-substrate.sh")"

# 4. Resume: `up` continues at the first phase without .ok, in the same run.
before="$(run_dir)"
drive up | (cd "$scratch" && bash >/dev/null 2>&1)
report 'up resumes in the same run directory' "$before" "$(run_dir)"
report 'up finishes the remaining phases' 'ok ok' \
  "$([[ -e "$dir/20-platform.ok" ]] && printf ok) $([[ -e "$dir/30-workloads.ok" ]] && printf ok)"

# 5. When every phase is complete, `up` starts a new run (a fresh, idempotent pass).
got="$(drive up | grep -c '^{ # phase ')"
report 'a complete run makes up start a new run with all phases' '3' "$got"

# 6. A failed check stops the stream with code 3, and later phases do not run.
rm -rf "${scratch:?}/var"; : > "$scratch/BREAK"
drive up | (cd "$scratch" && bash >/dev/null 2>&1); rc=$?
dir="$scratch/var/run/test/$(run_dir)"
report 'a failed check stops the stream with exit 3' '3' "$rc"
report 'no .ok for the failed phase, and the next phase never ran' 'none none' \
  "$([[ -e "$dir/10-substrate.ok" ]] && printf ok || printf none) $([[ -e "$dir/20-platform.sh" ]] && printf ran || printf none)"
rm -f "$scratch/BREAK"

# 7. `down` removes the cluster, passes its check, and drops the current run.
drive up | (cd "$scratch" && bash >/dev/null 2>&1)
drive down | (cd "$scratch" && bash >/dev/null 2>&1); rc=$?
report 'down succeeds and passes its check' '0' "$rc"
report 'down drops the current-run pointer' 'absent' \
  "$([[ -L "$scratch/var/run/test/current" ]] && printf present || printf absent)"

"$quiet" || printf '\n%d case(s), %d failure(s)\n' "$case_num" "$failures"
(( failures == 0 ))
