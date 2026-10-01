#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Manage the GitHub Release of a tag with gh.
#   publish:  create the draft release, or update an existing draft, with the
#             notes and all assets; verify that every asset is attached.
#   finalize: publish the draft; it becomes the latest release only when the
#             tag is the highest release version.
# A published release is never modified. Called by `make release-publish` and
# `make release-finalize`.
#
# Usage: tools/release/publish.sh publish <tag> <notes file> <asset>...
#        tools/release/publish.sh finalize <tag>
# Environment: GITHUB_REPO (owner/name), GH_TOKEN.

set -euo pipefail

action="${1:?usage: $0 publish|finalize <tag> ...}"
tag="${2:?usage: $0 publish|finalize <tag> ...}"
shift 2
: "${GITHUB_REPO:?}"

die() {
  echo "release-${action}: $*" >&2
  exit 1
}

release_state() {
  gh api --paginate "repos/${GITHUB_REPO}/releases?per_page=100" \
    --jq ".[] | select(.tag_name == \"${tag}\") | if .draft then \"draft\" else \"published\" end"
}

state="$(release_state)" || die "cannot list the releases of ${GITHUB_REPO}"
[[ "$state" != published ]] || die "${tag} is already released"

case "$action" in
  publish)
    notes="${1:?usage: $0 publish <tag> <notes file> <asset>...}"
    shift
    [[ $# -gt 0 ]] || die "no assets"
    for asset in "$@"; do
      test -s "$asset" || die "asset ${asset} is missing"
    done
    title="$(head -n1 "$notes")"
    if [[ "$state" == draft ]]; then
      gh release edit "$tag" --repo "$GITHUB_REPO" --title "$title" --notes-file "$notes"
      gh release upload "$tag" --repo "$GITHUB_REPO" --clobber "$@"
    else
      gh release create "$tag" --repo "$GITHUB_REPO" --draft --verify-tag \
        --title "$title" --notes-file "$notes" "$@"
    fi
    attached="$(gh release view "$tag" --repo "$GITHUB_REPO" --json assets --jq '.assets[].name')"
    for asset in "$@"; do
      grep -qxF "$(basename "$asset")" <<<"$attached" || die "asset $(basename "$asset") is not attached to ${tag}"
    done
    echo "draft release ${tag} has $# assets"
    ;;
  finalize)
    [[ "$state" == draft ]] || die "there is no draft release for ${tag}; run release-publish first"
    highest="$(git ls-remote --tags --refs origin 'v*' | sed 's#.*refs/tags/##' |
      grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)"
    latest=false
    [[ "$highest" == "$tag" ]] && latest=true
    gh release edit "$tag" --repo "$GITHUB_REPO" --draft=false --latest="$latest"
    echo "published release ${tag} (latest: ${latest})"
    ;;
  *)
    die "unknown action ${action}"
    ;;
esac
