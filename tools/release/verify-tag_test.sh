#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# The version order check of tools/release/verify-tag.sh against a local bare
# origin. The tags are annotated but unsigned, so a tag that passes the order
# check stops at the signature check. Called by test/test.sh.

set -euo pipefail

script="$(git rev-parse --show-toplevel)/tools/release/verify-tag.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

export YQ=yq GITHUB_REPO=test/test
unset GIT_DIR GIT_WORK_TREE

failures=0

check() {
  local name="$1" got="$2" want="$3"
  if [[ "${got}" == *"${want}"* ]]; then
    echo "ok   ${name}"
  else
    printf 'FAIL %s\n  want: %q\n  got:  %q\n' "${name}" "${want}" "${got}" >&2
    failures=$((failures + 1))
  fi
}

# setup <name>: a clone of a fresh bare origin with two commits on main.
setup() {
  local dir="${scratch}/$1"
  git init --quiet --bare "${dir}.git"
  git clone --quiet "${dir}.git" "${dir}" 2>/dev/null
  git -C "${dir}" config user.name test
  git -C "${dir}" config user.email test@example.com
  git -C "${dir}" commit --quiet --allow-empty --message one
  git -C "${dir}" commit --quiet --allow-empty --message two
  git -C "${dir}" push --quiet origin HEAD:main
  echo "${dir}"
}

# tag <repo> <tag> <rev>: an annotated tag pushed to origin.
tag() {
  git -C "$1" tag --annotate --message "$2" "$2" "$3"
  git -C "$1" push --quiet origin "refs/tags/$2"
}

verify() {
  (cd "$1" && "${script}" "$2" 2>&1) || true
}

repo="$(setup main)"
tag "${repo}" v0.2.0 HEAD
tag "${repo}" v0.1.5 HEAD~1
check "an older version from main is refused" "$(verify "${repo}" v0.1.5)" \
  "v0.1.5 is not greater than the release v0.2.0"
tag "${repo}" v0.2.1 HEAD
check "a newer version passes the order check" "$(verify "${repo}" v0.2.1)" "v0.2.1 is not signed"

repo="$(setup hotfix)"
tag "${repo}" v0.2.0 HEAD~1
tag "${repo}" v0.3.0 HEAD
git -C "${repo}" push --quiet origin HEAD~1:refs/heads/release-0.2
git -C "${repo}" switch --quiet --create release-0.2 HEAD~1
git -C "${repo}" commit --quiet --allow-empty --message fix
git -C "${repo}" push --quiet origin HEAD:release-0.2
tag "${repo}" v0.2.1 HEAD
check "a hotfix of its release line passes the order check" "$(verify "${repo}" v0.2.1)" "v0.2.1 is not signed"
tag "${repo}" v0.1.9 HEAD
check "a release line without its branch is compared with every release" "$(verify "${repo}" v0.1.9)" \
  "v0.1.9 is not greater than the release v0.3.0"

[[ "${failures}" -eq 0 ]] || { echo "${failures} verify-tag test(s) failed" >&2; exit 1; }
