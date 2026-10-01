#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Publish a documentation version to the gh-pages branch with mike.
#   CHANNEL=latest:  version "latest"; the site root points to it until a
#                    release publishes "stable".
#   CHANNEL=release: version X.Y; when the tag is the highest release, the
#                    alias "stable" moves to it and the site root points to
#                    "stable".
# Called by `make docs-publish`.
#
# Environment: MIKE (mike binary), CHANNEL, VERSION (tag), DOCS_VERSION.

set -euo pipefail

: "${MIKE:?}" "${CHANNEL:?}" "${VERSION:?}" "${DOCS_VERSION:?}"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git ls-remote --exit-code --heads origin gh-pages >/dev/null; then
  git fetch --quiet origin "+refs/heads/gh-pages:refs/heads/gh-pages"
fi

has_alias() {
  "$MIKE" list --json 2>/dev/null | jq -e --arg alias "$1" 'any(.[]; .aliases | index($alias))' >/dev/null
}

case "$CHANNEL" in
  latest)
    "$MIKE" deploy --push latest
    if ! has_alias stable; then
      "$MIKE" set-default --push latest
    fi
    ;;
  release)
    highest="$(git ls-remote --tags --refs origin 'v*' | sed 's#.*refs/tags/##' |
      grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)"
    if [[ "$highest" == "$VERSION" ]]; then
      "$MIKE" deploy --push --update-aliases "$DOCS_VERSION" stable
      "$MIKE" set-default --push stable
    else
      "$MIKE" deploy --push "$DOCS_VERSION"
    fi
    ;;
  *)
    echo "docs-publish needs CHANNEL=latest or CHANNEL=release" >&2
    exit 1
    ;;
esac
