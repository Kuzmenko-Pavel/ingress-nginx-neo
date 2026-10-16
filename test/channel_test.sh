#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# The publishing channel and the release tag derived by the Makefile from the
# git state. The Makefile of the working tree runs against a scratch git
# repository (GIT_DIR), so every state is set up without touching the real one.
# Called by test/test.sh.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

export GIT_DIR="${scratch}/.git" GIT_WORK_TREE="${root}"
git init --quiet
git -c user.name=test -c user.email=test@example.com commit --quiet --allow-empty --message one
git -c user.name=test -c user.email=test@example.com commit --quiet --allow-empty --message two

failures=0

# check <name> <got> <want> [contains]: got equals want, or contains it.
check() {
  local name="$1" got="$2" want="$3" mode="${4:-equals}"
  if [[ "${got}" == "${want}" || ("${mode}" == contains && "${got}" == *"${want}"*) ]]; then
    echo "ok   ${name}"
  else
    printf 'FAIL %s\n  want: %q\n  got:  %q\n' "${name}" "${want}" "${got}" >&2
    failures=$((failures + 1))
  fi
}

# expect <name> <want> <make arguments...>: the output of make equals want.
expect() {
  local name="$1" want="$2"
  shift 2
  check "${name}" "$(make --no-print-directory -s -C "${root}" "$@" 2>/dev/null || true)" "${want}"
}

expect "no tag, no origin/main: dev" dev print-CHANNEL print-RELEASE_TAG
check "dev: docs-publish stops in publish-guard" \
  "$(make --no-print-directory -s -C "${root}" docs-publish 2>&1 || true)" \
  "publishing runs from the tip of main (latest) or from a release tag; HEAD is neither" contains

git update-ref refs/remotes/origin/main HEAD~1
expect "origin/main behind HEAD: dev" dev print-CHANNEL

git update-ref refs/remotes/origin/main HEAD
expect "HEAD is the tip of origin/main: latest" $'latest\n\nlatest' print-CHANNEL print-RELEASE_TAG print-IMAGE_TAG

git tag v9.9.9
expect "release tag on HEAD: release" $'release\nv9.9.9\nv9.9.9' print-CHANNEL print-RELEASE_TAG print-VERSION
expect "CHANNEL on the command line wins" dev print-CHANNEL CHANNEL=dev

git tag --delete v9.9.9 >/dev/null
git tag v9.9.9 HEAD~1
expect "release tag below HEAD: latest" latest print-CHANNEL print-RELEASE_TAG

# print-main-tip fetches main from origin. Commits are created with
# commit-tree, so HEAD and the work tree (the real repository) stay as they are.
env -u GIT_DIR -u GIT_WORK_TREE git init --quiet --bare "${scratch}/origin.git"
git remote add origin "${scratch}/origin.git"
git push --quiet origin HEAD:refs/heads/main
expect "HEAD is the tip of main on origin" true print-main-tip
newer="$(git -c user.name=test -c user.email=test@example.com commit-tree 'HEAD^{tree}' -p HEAD -m three)"
git push --quiet origin "${newer}:refs/heads/main"
expect "main on origin moved past HEAD" false print-main-tip

[[ "${failures}" -eq 0 ]] || { echo "${failures} channel test(s) failed" >&2; exit 1; }
