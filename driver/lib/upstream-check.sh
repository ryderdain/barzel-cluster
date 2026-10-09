#!/usr/bin/env bash
# upstream-check.sh — report whether the vendored doctrine helpers in
# driver/lib/ still match their upstream in ryderdain/bash.
#
# Read-only generator: compares each file named in driver/lib/UPSTREAM with the
# same file in a local checkout of ryderdain/bash. Prints one line per file and
# exits 1 if any file differs or cannot be compared.
#
#   bash driver/lib/upstream-check.sh
#
# Inputs: BASH_DOCTRINE_DIR (default: the sibling checkout ../bash). No
# credentials.

(( BASH_VERSINFO[0] < 4 )) && { printf 'error: bash >= 4 required\n' >&2; exit 1; }

lib_dir="${BASH_SOURCE[0]%/*}"
repo_root="$(cd -- "$lib_dir/../.." && pwd -P)" || exit 1
upstream_dir="${BASH_DOCTRINE_DIR:-$repo_root/../bash}"

files=""
while IFS='=' read -r key value; do
  [[ "$key" == files ]] && files="$value"
done < "$lib_dir/UPSTREAM"

if [[ -z "$files" ]]; then
  printf 'error: no files= line in %s/UPSTREAM\n' "$lib_dir" >&2
  exit 1
fi
if [[ ! -d "$upstream_dir" ]]; then
  printf 'error: no ryderdain/bash checkout at %s (set BASH_DOCTRINE_DIR)\n' "$upstream_dir" >&2
  exit 1
fi

rc=0
read -r -a file_list <<< "$files"
for upstream_path in "${file_list[@]}"; do
  name="${upstream_path##*/}"
  if cmp -s "$lib_dir/$name" "$upstream_dir/$upstream_path"; then
    printf 'same     %s\n' "$name"
  else
    printf 'DIFFERS  %s\n' "$name"
    printf 'fix: review the change, then: cp %q %q and update commit= in UPSTREAM\n' \
      "$upstream_dir/$upstream_path" "$lib_dir/$name" >&2
    rc=1
  fi
done
exit "$rc"
