#!/usr/bin/env bash
# conductor.sh — the conductor locus: send one run sheet to the conductor pod in
# the cluster, run it there detached, follow its output, and collect its exit
# status. The driver's phase groups call it for phases whose locus is the
# conductor; it is not meant to be run by hand.
#
#   bash driver/conductor.sh <run_dir> <name>
#
# Steps (ryderdain/bash STYLE.md §1.11, "remote execution"):
#   1. wake the conductor (scale to 1), wait until it is ready, and claim a
#      pod: a Ready one that is not terminating, whose idle timer is reset at
#      once (the conductor scales itself to zero when idle; if that happens
#      while it is woken, the old pod is going away: wake it again);
#   2. if an earlier run of <name>.sh still runs in the pod (a driver that
#      was interrupted leaves its run going), follow that run when it has
#      the same commands, and stop otherwise; else copy <run_dir>/<name>.sh
#      into the pod and verify the copy by checksum;
#   3. run it detached in the pod: its output goes to a log file in the pod and
#      to the pod's stdout (so the cluster's log collector sees it), and its exit
#      status to <name>.rc in the pod;
#   4. follow the log, reattaching if the connection drops, until the .rc
#      exists; if the pod no longer exists, the run sheet stopped with it:
#      stop, so the phase can run again (it is safe to);
#   5. copy the .rc to <run_dir>/<name>.rc and exit with it.
#
# Execution-locus script (like driver/kiesei.sh: it runs what it is given).
# Inputs: <run_dir>/kubeconfig (from phase 10); the conductor from phase
# 25-bootstrap; BRZL_CONDUCTOR_WAIT_SECONDS (default 3600) caps step 4. Needs
# kubectl, jq and sha256sum. No credentials beyond the kubeconfig.

(( BASH_VERSINFO[0] < 4 )) && { printf 'error: bash >= 4 required\n' >&2; exit 1; }

run_dir="${1:-}" name="${2:-}"
if [[ -z "$run_dir" || -z "$name" || ! -r "$run_dir/$name.sh" ]]; then
  printf 'usage: bash driver/conductor.sh <run_dir> <name>  (needs <run_dir>/<name>.sh)\n' >&2
  exit 2
fi
export KUBECONFIG="$run_dir/kubeconfig"
ns=brzl-system
remote="/work/run/$name"
wait_limit="${BRZL_CONDUCTOR_WAIT_SECONDS:-3600}"

say() { printf 'conductor: %s\n' "$*" >&2; }

# 1. Wake, wait, and claim a pod (seen 2026-10-22: the conductor scaled itself
#    to zero in the second it was woken, and the run sheet went to the
#    terminating pod).
pod=''
for attempt in 1 2 3; do
  if ! kubectl -n "$ns" scale deployment/conductor --replicas=1 >/dev/null; then
    say 'cannot scale deployment/conductor; is phase 25-bootstrap done?'
    exit 1
  fi
  if ! kubectl -n "$ns" rollout status deployment/conductor --timeout=300s >/dev/null; then
    say 'conductor did not become ready; see: kubectl -n brzl-system describe deployment/conductor'
    exit 1
  fi
  pod="$(kubectl -n "$ns" get pods -l app.kubernetes.io/name=conductor -o json \
    | jq -r '[.items[] | select(.metadata.deletionTimestamp == null
                and any(.status.conditions[]?; .type == "Ready" and .status == "True"))][0].metadata.name // empty')"
  if [[ -n "$pod" ]] && kubectl -n "$ns" exec "$pod" -- touch /work/run/.activity \
      && [[ "$(kubectl -n "$ns" get deployment/conductor -o jsonpath='{.spec.replicas}')" == 1 ]]; then
    break
  fi
  say "the conductor was scaling down while it was woken; waking it again ($attempt)"
  pod=''
  sleep 5
done
if [[ -z "$pod" ]]; then
  say 'no ready conductor pod after three attempts; see: kubectl -n brzl-system get pods'
  exit 1
fi

# 2. An earlier run of this run sheet that still runs (seen 2026-10-23: the
#    driver was interrupted, its run went on, and it wrote its .rc during the
#    next run, which took that status as its own). The launcher keeps its
#    process id in <name>.pid while it runs.
local_sum="$(sha256sum < "$run_dir/$name.sh")"
follow_only=false
# shellcheck disable=SC2016  # $(cat ...) is for the pod's shell
if kubectl -n "$ns" exec "$pod" -- sh -c "[ -s '$remote.pid' ] && kill -0 \"\$(cat '$remote.pid')\" 2>/dev/null"; then
  if [[ "$(kubectl -n "$ns" exec "$pod" -- sh -c "sha256sum < '$remote.sh'")" == "$local_sum" ]]; then
    say "an earlier run of $name.sh still runs in $pod, with the same commands; following it"
    follow_only=true
  else
    say "an earlier run of $name.sh, with other commands, still runs in $pod. Wait until it ends, or stop it, then run the phase again:"
    say "  kubectl -n $ns exec $pod -- sh -c 'kill \$(cat $remote.pid)'"
    exit 1
  fi
fi

# 2b, 3. start_run — copy the run sheet, verify the copy, and run it
# detached. The commands go to the pod's shell on stdin, so they are parsed
# once, there (STYLE.md §1.8). A small launcher file holds the detached
# part; setsid + nohup keep it alive if this session drops. The launcher
# keeps its process id in <name>.pid while it runs (step 2).
start_run() {
  if ! kubectl -n "$ns" exec -i "$pod" -- sh -c "cat > '$remote.sh'" < "$run_dir/$name.sh"; then
    say "could not copy $name.sh to $pod"
    return 1
  fi
  local remote_sum
  remote_sum="$(kubectl -n "$ns" exec "$pod" -- sh -c "sha256sum < '$remote.sh'")"
  if [[ "$local_sum" != "$remote_sum" ]]; then
    say "copy of $name.sh in $pod does not match; not running it"
    return 1
  fi
  say "running $name.sh in $pod"

  if ! kubectl -n "$ns" exec -i "$pod" -- bash -s <<EOF
touch /work/run/.activity
rm -f '$remote.rc' '$remote.log'
cat > '$remote.launch' <<'LAUNCH'
printf '%s\n' "\$\$" > "\$1.pid"
bash "\$1.sh" > >(tee "\$1.log" > /proc/1/fd/1) 2>&1
printf '%s\n' "\$?" > "\$1.rc"
rm -f "\$1.pid"
touch /work/run/.activity
LAUNCH
setsid nohup bash '$remote.launch' '$remote' > /dev/null 2>&1 < /dev/null &
EOF
  then
    say "could not start $name.sh in $pod"
    return 1
  fi
}
[[ "$follow_only" == true ]] || start_run || exit 1

# 4. Follow until the .rc exists. Each round streams only the bytes added since
#    the last round (tracked by the log's size), so a dropped connection costs
#    one round, not the output.
offset=0 waited=0
while (( waited < wait_limit )); do
  if size="$(kubectl -n "$ns" exec "$pod" -- sh -c "stat -c %s '$remote.log' 2>/dev/null || echo 0")"; then
    if (( size > offset )); then
      kubectl -n "$ns" exec "$pod" -- sh -c "tail -c +$(( offset + 1 )) '$remote.log' | head -c $(( size - offset ))" \
        && offset="$size"
    fi
    if kubectl -n "$ns" exec "$pod" -- test -e "$remote.rc" 2>/dev/null; then
      # One last round for output written just before the .rc.
      size="$(kubectl -n "$ns" exec "$pod" -- stat -c %s "$remote.log" 2>/dev/null || echo "$offset")"
      (( size > offset )) && kubectl -n "$ns" exec "$pod" -- sh -c "tail -c +$(( offset + 1 )) '$remote.log'"
      break
    fi
  else
    if kubectl -n "$ns" get pod "$pod" 2>&1 | grep -q NotFound; then
      say "the conductor pod $pod went away while $name.sh ran, and the run sheet stopped with it; run the phase again (up or next): it is safe to run again"
      exit 1
    fi
    say 'lost the connection; reattaching'
  fi
  sleep 3
  waited=$(( waited + 3 ))
done

# 5. Collect.
if ! rc="$(kubectl -n "$ns" exec "$pod" -- cat "$remote.rc" 2>/dev/null)"; then
  say "no exit status from $name.sh after ${waited}s; it may still run in $pod (see: kubectl -n $ns logs $pod)"
  exit 1
fi
printf '%s\n' "$rc" > "$run_dir/$name.rc"
say "$name.sh finished in $pod with status $rc"
exit "$rc"
