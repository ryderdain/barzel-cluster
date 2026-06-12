#!/usr/bin/env bash
# ssm_status.sh — are all dev nodes reachable over SSM yet? This is the
# precondition for any ansible run (ansible tunnels via the SSH-over-SSM
# ProxyCommand). Read-only: prints a per-node ping report to stdout and exits
# non-zero unless every running node is "Online".
#
#   AWS_PROFILE=brzl-apply bash gitops/tools/ssm_status.sh
#   AWS_PROFILE=brzl-apply bash gitops/tools/ssm_status.sh 'brzl-prod-node-*'
#
# We hit this every bring-up: the SSM agent takes a minute to register after an
# instance boots, and a not-yet-Online node makes ansible fail confusingly. Gate
# the playbooks on this returning 0.
#
# No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): the AWS reads whose
# failure matters are checked explicitly; "no instances" (compute down) is a
# real, reported outcome, not a crash.

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi

region="${AWS_REGION:-eu-central-1}"
name_glob="${1:-brzl-dev-node-*}"

if ! command -v aws >/dev/null 2>&1; then
  printf 'error: aws not found on PATH\n' >&2
  exit 1
fi

# Running instances matching the name glob: id + Name tag, tab-separated.
# shellcheck disable=SC2016  # single quotes are intentional: the backticks are JMESPath literals, not shell expansion
if ! instances="$(aws ec2 describe-instances \
  --region "$region" \
  --filters "Name=tag:Name,Values=${name_glob}" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value]' \
  --output text 2>&1)"; then
  printf 'error: ec2 describe-instances failed:\n%s\n' "$instances" >&2
  exit 1
fi
if [[ -z "$instances" ]]; then
  printf 'no running instances matching %s (compute down?)\n' "$name_glob" >&2
  exit 1
fi

# SSM ping status for all managed instances, indexed by id.
declare -A ping
if ! ssm="$(aws ssm describe-instance-information \
  --region "$region" \
  --query 'InstanceInformationList[].[InstanceId,PingStatus]' \
  --output text 2>&1)"; then
  printf 'error: ssm describe-instance-information failed:\n%s\n' "$ssm" >&2
  exit 1
fi
while IFS=$'\t' read -r id status; do
  [[ -n "$id" ]] && ping["$id"]="$status"
done <<< "$ssm"

rc=0
printf '%-22s %-20s %s\n' INSTANCE-ID NAME SSM
while IFS=$'\t' read -r id name; do
  [[ -z "$id" ]] && continue
  status="${ping[$id]:-MISSING}"
  printf '%-22s %-20s %s\n' "$id" "$name" "$status"
  [[ "$status" == "Online" ]] || rc=1
done <<< "$instances"

if (( rc != 0 )); then
  printf '\nnot all nodes Online — wait ~30-60s and re-run before ansible\n' >&2
fi
exit "$rc"
