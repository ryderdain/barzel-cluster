#!/usr/bin/env bash
# upstream-check.sh — report whether the vendored doctrine helpers in
# driver/lib/ still match their upstream in ryderdain/bash.
#
# Read-only generator: compares each file named in driver/lib/UPSTREAM with the
# same file at the pinned tag (or commit) in a local clone of ryderdain/bash,
# and with the same file on the tracked branch. Prints one line per file.
# Exits 1 if a copy differs from the pin or cannot be compared. A newer
# version on the branch is reported, not failed: moving the pin is a choice.
#
#   bash driver/lib/upstream-check.sh
#
# Inputs: BASH_DOCTRINE_DIR (default: the sibling checkout ../bash). No
# credentials.

(( BASH_VERSINFO[0] < 4 )) && { printf 'error: bash >= 4 required\n' >&2; exit 1; }

lib_dir="${BASH_SOURCE[0]%/*}"
repo_root="$(cd -- "$lib_dir/../.." && pwd -P)" || exit 1
upstream_dir="${BASH_DOCTRINE_DIR:-$repo_root/../bash}"

files="" pin="" branch=""
while IFS='=' read -r key value; do
  case "$key" in
    files) files="$value" ;;
    tag) pin="$value" ;;
    commit) [[ -n "$pin" ]] || pin="$value" ;;
    branch) branch="$value" ;;
  esac
done < "$lib_dir/UPSTREAM"

if [[ -z "$files" ]]; then
  printf 'error: no files= line in %s/UPSTREAM\n' "$lib_dir" >&2
  exit 1
fi
if [[ -z "$pin" ]]; then
  printf 'error: no tag= or commit= line in %s/UPSTREAM\n' "$lib_dir" >&2
  exit 1
fi
if ! git -C "$upstream_dir" rev-parse -q --verify "$pin^{commit}" >/dev/null 2>&1; then
  printf 'error: no ryderdain/bash clone with %s at %s (set BASH_DOCTRINE_DIR; git fetch --tags)\n' \
    "$pin" "$upstream_dir" >&2
  exit 1
fi

rc=0
read -r -a file_list <<< "$files"
for upstream_path in "${file_list[@]}"; do
  name="${upstream_path##*/}"
  if git -C "$upstream_dir" show "$pin:$upstream_path" | cmp -s - "$lib_dir/$name"; then
    printf 'same     %s (%s)\n' "$name" "$pin"
  else
    printf 'DIFFERS  %s (%s)\n' "$name" "$pin"
    printf 'fix: the copy must match the pin: git -C %q show %q > %q\n' \
      "$upstream_dir" "$pin:$upstream_path" "$lib_dir/$name" >&2
    rc=1
    continue
  fi
  if [[ -n "$branch" ]] \
    && ! git -C "$upstream_dir" show "$branch:$upstream_path" 2>/dev/null | cmp -s - "$lib_dir/$name"; then
    printf 'NEWER    %s on %s; to move the pin: review, copy, tag, update UPSTREAM\n' \
      "$name" "$branch"
  fi
done
exit "$rc"
