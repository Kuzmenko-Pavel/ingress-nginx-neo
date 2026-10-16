#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Create the signed annotated release tag. The tag message is the changelog,
# generated from the Conventional Commits since the previous release tag (the
# whole history for the first release) and edited in the editor. Called by
# `make release-tag`; it never pushes. Branch, signer, CI result and version
# order are checked by CI when the tag is pushed (tools/release/verify-tag.sh).
#
# Environment:
#   RELEASE_TAG_PATTERN  glob of release tags (v[0-9]*.[0-9]*.[0-9]*)
#   RELEASE_VERSION      version to tag (vX.Y.Z); asked in a terminal, otherwise
#                        proposed from the commits when empty
#   PROJECT              product name used in the tag title

set -euo pipefail

: "${RELEASE_TAG_PATTERN:?}" "${PROJECT:?}"
RELEASE_VERSION="${RELEASE_VERSION:-}"

die() {
  echo "release-tag: $*" >&2
  exit 1
}

semver_re='^v([0-9]+)\.([0-9]+)\.([0-9]+)$'

[[ -z "$(git status --porcelain)" ]] ||
  die "There are uncommitted changes. Commit them before creating the release tag"

# --- range ------------------------------------------------------------------

previous="$(git describe --tags --abbrev=0 --match "${RELEASE_TAG_PATTERN}" 2>/dev/null || true)"
range="${previous:+${previous}..}HEAD"
count="$(git rev-list --count --no-merges "$range")"
[[ "$count" -gt 0 ]] || die "no commits since ${previous}"
echo "Previous release: ${previous:-none}. Changelog: ${count} commits."

# --- commits ----------------------------------------------------------------

types='feat|fix|perf|refactor|docs|test|build|ci|chore|revert|style'
subject_re="^(${types})(\(([a-z0-9._/-]+)\))?(!)?: (.+)$"

breaking=() features=() fixes=() performance=() other=()
has_breaking=false has_feat=false

while IFS= read -r sha; do
  short="$(git rev-parse --short=7 "$sha")"
  subject="$(git log -1 --format=%s "$sha")"
  body="$(git log -1 --format=%b "$sha")"
  if [[ "$subject" =~ $subject_re ]]; then
    type="${BASH_REMATCH[1]}"
    scope="${BASH_REMATCH[3]}"
    bang="${BASH_REMATCH[4]}"
    description="${BASH_REMATCH[5]}"
    entry="- ${scope:+${scope}: }${description} (${short})"
    if [[ -n "$bang" ]] || grep -qE '^BREAKING[ -]CHANGE: ' <<<"$body"; then
      breaking+=("$entry")
      has_breaking=true
      continue
    fi
    case "$type" in
      feat) features+=("$entry"); has_feat=true ;;
      fix) fixes+=("$entry") ;;
      perf) performance+=("$entry") ;;
      *) other+=("- ${subject} (${short})") ;;
    esac
  else
    other+=("- ${subject} (${short})")
  fi
done < <(git rev-list --reverse --no-merges "$range")

# --- version ----------------------------------------------------------------

branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ "$branch" =~ ^release-([0-9]+)\.([0-9]+)$ ]]; then
  # A release branch only ships patch releases of its own line.
  line_max="$(git tag --list "v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.*" | { grep -E "$semver_re" || true; } | sort -V | tail -n1)"
fi
if [[ "${line_max:-}" =~ $semver_re ]]; then
  proposed="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
elif [[ -z "$previous" ]]; then
  proposed=v0.1.0
else
  [[ "$previous" =~ $semver_re ]] || die "previous tag ${previous} is not vX.Y.Z"
  major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
  if $has_breaking && [[ "$major" -eq 0 ]]; then
    proposed="v0.$((minor + 1)).0"
  elif $has_breaking; then
    proposed="v$((major + 1)).0.0"
  elif $has_feat; then
    proposed="v${major}.$((minor + 1)).0"
  else
    proposed="v${major}.${minor}.$((patch + 1))"
  fi
fi

if [[ -z "$RELEASE_VERSION" && -t 0 ]]; then
  read -r -p "Version (previous release ${previous:-none}) [${proposed}]: " RELEASE_VERSION
fi
RELEASE_VERSION="${RELEASE_VERSION:-$proposed}"
[[ "$RELEASE_VERSION" =~ $semver_re ]] || die "${RELEASE_VERSION} is not vX.Y.Z"

# --- message ----------------------------------------------------------------

message="$(mktemp)"
trap 'rm -f "$message"' EXIT

section() {
  local title="$1"
  shift
  [[ $# -gt 0 ]] || return 0
  printf '\n### %s\n' "$title"
  printf '%s\n' "$@"
}

{
  printf '%s %s\n' "$PROJECT" "$RELEASE_VERSION"
  section "Breaking changes" "${breaking[@]}"
  section "Features" "${features[@]}"
  section "Fixes" "${fixes[@]}"
  section "Performance" "${performance[@]}"
  section "Other" "${other[@]}"
} >"$message"

# The changelog uses "###" headings: keep "#" lines out of the comment cleanup.
git -c core.commentChar=';' tag -s -a -e -F "$message" "$RELEASE_VERSION"

echo
echo "created signed tag ${RELEASE_VERSION} on $(git rev-parse --short HEAD); publish it with:"
echo "  git push origin ${RELEASE_VERSION}"
