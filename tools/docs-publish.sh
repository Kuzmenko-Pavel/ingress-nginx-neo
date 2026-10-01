#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Publish a documentation version to the gh-pages branch with mike.
#   CHANNEL=latest:  version "latest"; the site root points to it until a
#                    release publishes "stable".
#   CHANNEL=release: version X.Y; when the tag is the highest release, the
#                    alias "stable" moves to it and the site root points to
#                    "stable".
# Called by `make docs-publish`, and by `make docs-publish-check` with
# DOCS_BRANCH set to a local branch and DOCS_PUSH=false.
#
# Environment: MIKE (mike binary), CHANNEL, VERSION (tag), DOCS_VERSION,
# DOCS_BRANCH (default gh-pages), DOCS_PUSH (default true).

set -euo pipefail

: "${MIKE:?}" "${CHANNEL:?}" "${VERSION:?}" "${DOCS_VERSION:?}"
DOCS_BRANCH="${DOCS_BRANCH:-gh-pages}"
DOCS_PUSH="${DOCS_PUSH:-true}"

export GIT_AUTHOR_NAME="github-actions[bot]"
export GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}"
export GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"

push=()
if [[ "$DOCS_PUSH" == true ]]; then
  push=(--push)
  if git ls-remote --exit-code --heads origin "$DOCS_BRANCH" >/dev/null; then
    git fetch --quiet origin "+refs/heads/${DOCS_BRANCH}:refs/heads/${DOCS_BRANCH}"
  fi
fi

mike() {
  "$MIKE" "$1" --branch "$DOCS_BRANCH" "${@:2}"
}

has_alias() {
  mike list --json 2>/dev/null | jq -e --arg alias "$1" 'any(.[]; .aliases | index($alias))' >/dev/null
}

case "$CHANNEL" in
  latest)
    mike deploy "${push[@]}" latest
    if ! has_alias stable; then
      mike set-default "${push[@]}" latest
    fi
    ;;
  release)
    highest="$(git ls-remote --tags --refs origin 'v*' | sed 's#.*refs/tags/##' |
      grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)"
    if [[ "$highest" == "$VERSION" ]]; then
      mike deploy "${push[@]}" --update-aliases "$DOCS_VERSION" stable
      mike set-default "${push[@]}" stable
    else
      mike deploy "${push[@]}" "$DOCS_VERSION"
    fi
    ;;
  *)
    echo "docs-publish needs CHANNEL=latest or CHANNEL=release" >&2
    exit 1
    ;;
esac
