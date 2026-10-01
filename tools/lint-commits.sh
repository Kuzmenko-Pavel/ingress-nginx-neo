#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Check that every non-merge commit in <base>..HEAD follows Conventional
# Commits 1.0.0 with the project's types. `Revert "<subject>"` subjects (as
# created by git and GitHub) are accepted as reverts.
#
# Usage: tools/lint-commits.sh <base>

set -euo pipefail

base="${1:?usage: $0 <base>}"

types='feat|fix|perf|refactor|docs|test|build|ci|chore|revert|style'
pattern="^(${types})(\([a-z0-9._/-]+\))?!?: [^[:space:]].*$"
revert='^Revert ".+"$'

if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  echo "base revision ${base} not found (fetch it or set BASE=<rev>)" >&2
  exit 1
fi

bad=0
while IFS=$'\t' read -r sha subject; do
  if [[ ! "$subject" =~ $pattern && ! "$subject" =~ $revert ]]; then
    echo "not a Conventional Commit: ${sha} ${subject}" >&2
    bad=1
  fi
done < <(git log --no-merges --format='%h%x09%s' "${base}..HEAD")

if [[ $bad -ne 0 ]]; then
  cat >&2 <<EOF

Commit subjects must look like "<type>[(scope)][!]: <description>"
with type one of: ${types//|/, }. See CONTRIBUTING.md.
EOF
  exit 1
fi
echo "all commits in ${base}..HEAD follow Conventional Commits"
