#!/usr/bin/env bash
# conductor.sh — the conductor locus: send one run-log to the conductor pod in
# the cluster, run it there detached, follow its output, and collect its exit
# status. The driver's phase groups call it for phases whose locus is the
# conductor; it is not meant to be run by hand.
#
#   bash driver/conductor.sh <run_dir> <name>
#
# Steps (ryderdain/bash STYLE.md §1.11, "remote execution"):
#   1. wake the conductor (scale to 1) and wait until it is ready;
#   2. copy <run_dir>/<name>.sh into the pod and verify the copy by checksum;
#   3. run it detached in the pod: its output goes to a log file in the pod and
#      to the pod's stdout (so the cluster's log collector sees it), and its exit
#      status to <name>.rc in the pod;
#   4. follow the log, reattaching if the connection drops, until the .rc exists;
#   5. copy the .rc to <run_dir>/<name>.rc and exit with it.
#
# Execution-locus script (like driver/kiesei.sh: it runs what it is given).
# Inputs: <run_dir>/kubeconfig (from phase 10); the conductor from phase
# 15-conductor; BRZL_CONDUCTOR_WAIT_SECONDS (default 3600) caps step 4. Needs
# kubectl and sha256sum. No credentials beyond the kubeconfig.

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

# 1. Wake and wait.
if ! kubectl -n "$ns" scale deployment/conductor --replicas=1 >/dev/null; then
  say 'cannot scale deployment/conductor; is phase 15-conductor done?'
  exit 1
fi
if ! kubectl -n "$ns" rollout status deployment/conductor --timeout=300s >/dev/null; then
  say 'conductor did not become ready; see: kubectl -n brzl-system describe deployment/conductor'
  exit 1
fi
pod="$(kubectl -n "$ns" get pods -l app.kubernetes.io/name=conductor \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "$pod" ]]; then
  say 'no running conductor pod'
  exit 1
fi

# 2. Copy and verify.
local_sum="$(sha256sum < "$run_dir/$name.sh")"
if ! kubectl -n "$ns" exec -i "$pod" -- sh -c "cat > '$remote.sh'" < "$run_dir/$name.sh"; then
  say "could not copy $name.sh to $pod"
  exit 1
fi
remote_sum="$(kubectl -n "$ns" exec "$pod" -- sh -c "sha256sum < '$remote.sh'")"
if [[ "$local_sum" != "$remote_sum" ]]; then
  say "copy of $name.sh in $pod does not match; not running it"
  exit 1
fi
say "running $name.sh in $pod"

# 3. Run detached. The commands go to the pod's shell on stdin, so they are
#    parsed once, there (STYLE.md §1.8). A small launcher file holds the
#    detached part; setsid + nohup keep it alive if this session drops.
if ! kubectl -n "$ns" exec -i "$pod" -- bash -s <<EOF
touch /work/run/.activity
rm -f '$remote.rc' '$remote.log'
cat > '$remote.launch' <<'LAUNCH'
bash "\$1.sh" > >(tee "\$1.log" > /proc/1/fd/1) 2>&1
printf '%s\n' "\$?" > "\$1.rc"
touch /work/run/.activity
LAUNCH
setsid nohup bash '$remote.launch' '$remote' > /dev/null 2>&1 < /dev/null &
EOF
then
  say "could not start $name.sh in $pod"
  exit 1
fi

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
