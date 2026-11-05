#!/usr/bin/env bash
# driver-cases.sh — checks the driver's own mechanics with no cluster: the
# grammar (`<mode> <verb>`, BRZL_ENV), run sheets, .rc and .ok files, resume
# at the first unfinished phase, the `error 3` stop on a failed check, the
# break-glass and audit emitters, and the teardown guard.
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
substrate_network_up() { printf '{ # fake network\n  :\n}\n'; }
substrate_up() { printf '{ # fake cluster\n  : > %s\n}\n' "$1/cluster"; }
substrate_down() { printf '{ # remove fake cluster\n  rm -f var/run/test/*/cluster\n}\n'; }
substrate_image_ref() { printf 'test/%s' "$1"; }
substrate_check() { [[ -e "$1/cluster" && ! -e BREAK ]]; }
substrate_check_down() { ! compgen -G 'var/run/test/*/cluster' >/dev/null; }
EOF
# Every phase after 10 becomes trivial, so the driver's sequencing is what is
# tested. Each one also reads stdin (`cat`), as docker exec -i or kubectl exec
# -i would: the driver must run a run sheet with stdin from /dev/null, or that
# read swallows the rest of the procedure and the later phases never run. 30-gitops declares the conductor locus; a fake conductor.sh runs the
# run sheet locally and writes the .rc, as the real one does after collecting it.
for phase in 20-images 25-bootstrap 30-gitops 40-workloads; do
  locus=driver; [[ "$phase" == 30-gitops ]] && locus=conductor
  cat > "$scratch/driver/phases/$phase.sh" <<EOF
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false
repo_root="\$(cd -- "\${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
source "\$repo_root/driver/lib/runlib.sh" || exit 1
source "\$repo_root/driver/lib/phase-common.sh" || exit 1
phase_locus() { printf '%s\n' $locus; }
phase_up() { phase_init "\$1" || return 1; phase_header "\$2" $locus; printf '{ # %s\n  cat > /dev/null\n  : > %s\n}\n' $phase "\$2/$phase.done"; }
phase_check() { [[ -e "\$2/$phase.done" ]]; }
if [[ "\$is_sourced" == false ]]; then "\$@"; fi
EOF
done
cat > "$scratch/driver/conductor.sh" <<'EOF'
: > "$1/$2.via-conductor"
bash "$1/$2.sh"; rc=$?
printf '%s\n' "$rc" > "$1/$2.rc"
exit "$rc"
EOF

drive() { (cd "$scratch" && export BRZL_ENV=test && bash driver/driver.sh "$@" 2>/dev/null); }
unguard() { sed 's/^## ⚠ ## //'; }
run_dir() { readlink "$scratch/var/run/test/current"; }

"$quiet" || printf 'driver mechanics (bash %s)\n\n' "$BASH_VERSION"

# 0. The grammar: BRZL_ENV selects the environment (the default is local,
# which the scratch tree does not have); a mode needs its verb; the old verbs
# are gone.
(cd "$scratch" && bash driver/driver.sh cluster status >/dev/null 2>&1); rc=$?
report 'without BRZL_ENV the driver looks for env/local.env and refuses' '2' "$rc"
drive cluster >/dev/null; rc=$?
report 'a mode without a verb refuses' '2' "$rc"
drive break-glass >/dev/null; rc=$?
report 'break-glass without a verb refuses' '2' "$rc"
got=''
for old in 'up' 'next' 'down' 'sync off' 'apply' 'hold x' 'release' 'reader_on' 'reader on' 'pause x' 'resume'; do
  # shellcheck disable=SC2086  # the old verb is one or two words
  drive $old >/dev/null; got+="$? "
done
report 'the old verbs (up, next, down, sync, apply, hold, release, reader, pause, resume) are gone' \
  '2 2 2 2 2 2 2 2 2 2 2 ' "$got"

# 1. A preview changes nothing: emitting `cluster bootstrap` creates no run directory.
drive cluster bootstrap >/dev/null
report 'previewing cluster bootstrap creates nothing' 'absent' "$([[ -e "$scratch/var" ]] && printf present || printf absent)"

# 2. `cluster bootstrap | bash` with a failing first phase runs exactly one
# phase and records it: run sheet, .rc, .ok absent, and stops with exit 3.
: > "$scratch/BREAK"
drive cluster bootstrap | (cd "$scratch" && bash >/dev/null 2>&1); rc=$?
dir="$scratch/var/run/test/$(run_dir)"
files=("$dir"/10-substrate.*); got="$(printf '%s ' "${files[@]##*/}")"
report 'a failed check stops the stream with exit 3' '3' "$rc"
report 'the failed phase records .sh .out .rc and no .ok' '10-substrate.out 10-substrate.rc 10-substrate.sh ' "$got"
report 'the next phase never ran' 'no' "$([[ -e "$dir/20-images.sh" ]] && printf yes || printf no)"
rm -f "$scratch/BREAK"

# 3. The run sheet starts with the resolved inputs.
report 'the run sheet records the resolved environment' '# BRZL_SUBSTRATE=fake' "$(sed -n 2p "$dir/10-substrate.sh")"

# 3a. UTC everywhere (ADR-0027): the run directory is cluster-<UTC>Z, and each
# run output starts with its header line, which names the person (Q208).
report 'the run directory is named cluster-<UTC>Z' 'yes' \
  "$([[ "$(run_dir)" =~ ^cluster-[0-9]{8}T[0-9]{4}Z(-[0-9]+)?$ ]] && printf yes || printf no)"
report 'the run output starts with its header line' 'yes' \
  "$([[ "$(head -n 1 "$dir/10-substrate.out")" =~ ^'# brzl run-output env=test run='"$(run_dir)"' phase=10-substrate start='[0-9-]{10}T[0-9:]{8}Z' person='"$(id -un)"' person_verified=false'$ ]] && printf yes || printf no)"

# 4. Resume: `cluster bootstrap` again continues at the first phase without
# .ok, in the same run, and `start` is the same verb.
before="$(run_dir)"
drive cluster start | (cd "$scratch" && bash >/dev/null 2>&1)
report 'cluster bootstrap (as start) resumes in the same run directory' "$before" "$(run_dir)"
report 'it finishes every phase' 'ok ok ok ok ok' \
  "$(for p in 10-substrate 20-images 25-bootstrap 30-gitops 40-workloads; do [[ -e "$dir/$p.ok" ]] && printf 'ok '; done | sed 's/ $//')"
report 'a conductor-locus phase goes through conductor.sh; others do not' 'yes no' \
  "$([[ -e "$dir/30-gitops.via-conductor" ]] && printf yes || printf no) $([[ -e "$dir/20-images.via-conductor" ]] && printf yes || printf no)"
report 'a conductor run sheet carries no kubeconfig export' '0' "$(grep -c '^export KUBECONFIG' "$dir/30-gitops.sh")"
report 'the emitted check names the environment with BRZL_ENV' '1' \
  "$(drive cluster bootstrap | grep -c '^  BRZL_ENV=test bash driver/driver.sh cluster check 10-substrate ')"

# 5. When every phase is complete, `cluster bootstrap` starts a new run (a
# fresh, idempotent pass).
got="$(drive cluster bootstrap | grep -c '^{ # phase ')"
report 'a complete run makes cluster bootstrap start a new run with all phases' '5' "$got"

# 6. Break-glass mode (ADR-0037, ADR-0038): it needs a run that passed
# 30-gitops; open needs a reason; open, apply and close emit one group each,
# at the driver locus, with the emit step first; the reason reaches the
# emitter quoted; an emit step that refuses stops the stream with exit 3
# before any run sheet runs, and its output is kept (the record of a
# refusal). Here the emitter refuses because the fake environment has no
# BRZL_SIGN_ON_ORG.
rm -rf "${scratch:?}/var"
drive break-glass open 'x' >/dev/null; rc=$?
report 'break-glass open refuses before 30-gitops has passed' '2' "$rc"
drive cluster bootstrap | (cd "$scratch" && bash >/dev/null 2>&1)
drive break-glass open >/dev/null; rc=$?
report 'open without a reason refuses' '2' "$rc"
report 'open emits one group' '1' "$(drive break-glass open 'portal down' | grep -c '^{ # break-glass open')"
report 'open passes the reason to its emitter, quoted' '1' \
  "$(drive break-glass open "it's down" | grep -c "break-glass.sh open test [^ ]* 'it'\\\\''s down' >")"
report 'close emits one group' '1' "$(drive break-glass close | grep -c '^{ # break-glass close')"
report 'close confirm passes confirm to its emitter' '1' "$(drive break-glass close confirm | grep -c "break-glass.sh close test [^ ]* 'confirm' >")"
drive break-glass close no >/dev/null; rc=$?
report 'close with a word other than confirm refuses' '2' "$rc"
report 'apply emits one group with its emit step' '1 1' \
  "$(drive break-glass apply | grep -c '^{ # break-glass apply: the working tree') $(drive break-glass apply | grep -c 'break-glass.sh apply test')"
report 'apply passes the source tree to its emitter' '1' "$(drive break-glass apply /tmp | grep -c "break-glass.sh apply test [^ ]* '/tmp' >")"
drive break-glass open 'portal down' | (cd "$scratch" && bash >/dev/null 2>&1); rc=$?
dir="$scratch/var/run/test/$(run_dir)"
emit_out=("$dir"/break-glass-open-*-emit.out); sheet_rc=("$dir"/break-glass-open-*Z.rc)
report 'a refused open stops with exit 3, keeps its emit output, runs no sheet' '3 kept none' \
  "$rc $([[ -s "${emit_out[0]}" ]] && printf kept || printf none) $([[ -e "${sheet_rc[0]}" ]] && printf ran || printf none)"

# 7. Audit mode (ADR-0037): bootstrap and teardown emit one group each, in a
# new run directory audit-<UTC>Z, not in the current run. Here bootstrap
# refuses because the fake environment has no local admin log store: exit 3,
# and the current run stays. Teardown is guarded (Q238).
report 'audit bootstrap emits one group' '1' "$(drive audit bootstrap | grep -c '^{ # audit bootstrap: the reader of the admin log store')"
report 'audit start is the same verb' '1' "$(drive audit start | grep -c '^{ # audit bootstrap: the reader of the admin log store')"
report 'audit teardown emits one group behind the guard' '1' "$(drive audit teardown | grep -c '^## ⚠ ## { # audit teardown: the reader of the admin log store')"
report 'audit teardown piped without the sed exits 2' '2' "$(drive audit teardown | (cd "$scratch" && bash >/dev/null 2>&1); printf '%s' "$?")"
report 'the reader writes into var/run/<env>/audit-<UTC>Z' '1' \
  "$(drive audit bootstrap | grep -cE '^  mkdir -p var/run/test/audit-[0-9]{8}T[0-9]{4}Z(-[0-9]+)?$')"
before="$(run_dir)"
drive audit bootstrap | (cd "$scratch" && bash >/dev/null 2>&1); rc=$?
report 'audit bootstrap without a local store stops with exit 3; the current run stays' "3 $before" "$rc $(run_dir)"

# 8. The teardown guard (Q238, Q244): every emitted line of a teardown is
# behind the prefix, except the last, which tests the variable that the first
# line sets. A pipe without the sed runs nothing: the last line prints the
# footer to stderr and exits 2. The same stream through the sed removes the
# cluster, passes its check, and drops the current run.
got="$(drive cluster teardown | grep -vc '^## ⚠ ## ')"
report 'every line of cluster teardown but the last is behind the prefix' '1' "$got"
report 'the first line sets the guard, behind the prefix' '## ⚠ ## guard=stripped' "$(drive cluster teardown | head -n 1)"
# shellcheck disable=SC2016  # the expected text is the emitted line, which bash expands later
report 'the last line of cluster teardown tests the guard and carries the footer' 'yes' \
  "$([[ "$(drive cluster teardown | tail -n 1)" == '[[ "${guard:-}" == stripped ]] || { printf '"'"'##    TO TEARDOWN, PASTE `sed '"'"'"'"'"'"'"'"'s/^## ⚠ ## //'"'"'"'"'"'"'"'"'` INTO PIPE    ##\n'"'"' >&2; exit 2; }' ]] && printf yes || printf no)"
out="$(drive cluster teardown | (cd "$scratch" && bash 2>&1 >/dev/null; printf '\n%s' "$?"))"
rc="${out##*$'\n'}"; err="${out%$'\n'*}"; err="${err%$'\n'}"
report 'cluster teardown piped without the sed runs nothing, prints the footer to stderr, exits 2' \
  "2 $before present ##    TO TEARDOWN, PASTE \`sed 's/^## ⚠ ## //'\` INTO PIPE    ##" \
  "$rc $(run_dir) $([[ -L "$scratch/var/run/test/current" ]] && printf present || printf absent) $err"
drive cluster stop | unguard | (cd "$scratch" && bash >/dev/null 2>&1); rc=$?
report 'cluster teardown (as stop) through the sed succeeds and passes its check' '0' "$rc"
report 'it drops the current-run pointer' 'absent' \
  "$([[ -L "$scratch/var/run/test/current" ]] && printf present || printf absent)"

"$quiet" || printf '\n%d case(s), %d failure(s)\n' "$case_num" "$failures"
(( failures == 0 ))
