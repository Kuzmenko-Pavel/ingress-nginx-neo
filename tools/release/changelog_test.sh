#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# tools/release/changelog.sh against scratch repositories: the script runs as
# is, including `git tag -s -a -e`; only the signing program and the editor are
# replaced. Called by test/test.sh.

set -euo pipefail

script="$(git rev-parse --show-toplevel)/tools/release/changelog.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

# git reads the signature from stdout and waits for SIG_CREATED on the status fd.
cat >"${scratch}/fake-gpg" <<'EOF'
#!/bin/sh
cat >/dev/null
echo '[GNUPG:] SIG_CREATED D 1 8 00 0 0' >&2
printf '%s\n' '-----BEGIN PGP SIGNATURE-----' '' 'test' '-----END PGP SIGNATURE-----'
EOF
chmod +x "${scratch}/fake-gpg"

export RELEASE_TAG_PATTERN='v[0-9]*.[0-9]*.[0-9]*' PROJECT=ingress-nginx-neo GIT_EDITOR=true
unset GIT_DIR GIT_WORK_TREE RELEASE_VERSION

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

# repository <name> <subject>...: a repository with one commit per subject.
repository() {
  local dir="${scratch}/$1"
  shift
  git init --quiet --initial-branch=main "${dir}"
  git -C "${dir}" config user.name test
  git -C "${dir}" config user.email test@example.com
  git -C "${dir}" config gpg.program "${scratch}/fake-gpg"
  for subject in "$@"; do
    git -C "${dir}" commit --quiet --allow-empty --message "${subject}"
  done
  echo "${dir}"
}

run() {
  (cd "$1" && shift && env "$@" "${script}" </dev/null 2>&1) || true
}

# The first release: no tag yet, the changelog covers the whole history.
repo="$(repository first 'feat: first feature' 'fix(chart): first fix' 'docs: first page')"
out="$(run "${repo}" RELEASE_VERSION=v0.1.0)"
message="$(git -C "${repo}" tag --list --format='%(contents)' v0.1.0)"
check "first release: tag created" "${out}" "git push origin v0.1.0"
check "first release: feature" "${message}" "- first feature"
check "first release: fix" "${message}" "- chart: first fix"
check "first release: other" "${message}" "- docs: first page"
check "first release: signed" "${message}" "-----BEGIN PGP SIGNATURE-----"

# The next version is proposed from the commits since the previous release.
git -C "${repo}" commit --quiet --allow-empty --message 'feat: second feature'
out="$(run "${repo}")"
check "proposed version: feat gives the next minor" "${out}" "git push origin v0.2.0"
check "changelog starts after the previous release" \
  "$(git -C "${repo}" tag --list --format='%(contents)' v0.2.0 | grep -c '^- ')" 1

git -C "${repo}" commit --quiet --allow-empty --message 'fix: third fix'
out="$(run "${repo}" RELEASE_VERSION=0.3)"
check "a version that is not vX.Y.Z is refused" "${out}" "0.3 is not vX.Y.Z"

# Uncommitted changes stop before anything is asked.
repo="$(repository dirty 'feat: one')"
touch "${repo}/file"
out="$(run "${repo}" RELEASE_VERSION=v0.1.0)"
check "dirty tree" "${out}" "There are uncommitted changes. Commit them before creating the release tag"

[[ "${failures}" -eq 0 ]] || { echo "${failures} changelog test(s) failed" >&2; exit 1; }
