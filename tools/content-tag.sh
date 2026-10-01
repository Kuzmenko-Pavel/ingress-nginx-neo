#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Print the content-addressed tag (src-<12 hex>) of an image built from the
# given source paths. The tag is the sha256 of the sorted list of
# "<path> <mode> <sha256 of content>" for every tracked or untracked, not ignored file
# under the paths, followed by every extra input string.
#
# Usage: tools/content-tag.sh <path>... [-- <extra input>...]

set -euo pipefail
export LC_ALL=C

paths=()
while [[ $# -gt 0 && "$1" != "--" ]]; do
  paths+=("$1")
  shift
done
[[ $# -gt 0 ]] && shift
[[ ${#paths[@]} -gt 0 ]] || { echo "usage: $0 <path>... [-- <extra input>...]" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

{
  git ls-files -z -co --exclude-standard -- "${paths[@]}" |
    sort -z |
    while IFS= read -r -d '' file; do
      [[ -f "$file" ]] || continue
      mode=644
      [[ -x "$file" ]] && mode=755
      printf '%s %s %s\n' "$file" "$mode" "$(sha256 "$file" | cut -d' ' -f1)"
    done
  for extra in "$@"; do
    printf 'input %s\n' "$extra"
  done
} | sha256 | cut -c1-12 | sed 's/^/src-/'
