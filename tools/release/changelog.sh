#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Create the signed annotated release tag. The tag message is the changelog,
# generated from the Conventional Commits since the previous release tag.
# Called by `make release-tag`; it never pushes.
#
# Environment:
#   RELEASE_TAG_PATTERN  glob of release tags (v[0-9]*.[0-9]*.[0-9]*)
#   RELEASE_VERSION      version to tag (vX.Y.Z); proposed from the commits when empty
#   NOTES_FROM           first excluded revision of the changelog when there is no previous tag
#   REPO_SLUG            owner/name the origin remote must point to
#   PROJECT              product name used in the tag title

set -euo pipefail

: "${RELEASE_TAG_PATTERN:?}" "${REPO_SLUG:?}" "${PROJECT:?}"
RELEASE_VERSION="${RELEASE_VERSION:-}"
NOTES_FROM="${NOTES_FROM:-}"

die() {
  echo "release-tag: $*" >&2
  exit 1
}

semver_re='^v([0-9]+)\.([0-9]+)\.([0-9]+)$'

# --- preconditions ----------------------------------------------------------

[[ -z "$(git status --porcelain)" ]] || die "the working tree is not clean"

branch="$(git symbolic-ref --quiet --short HEAD || true)"
[[ "$branch" == main || "$branch" =~ ^release-[0-9]+\.[0-9]+$ ]] ||
  die "release tags are created on main or release-X.Y, not on '${branch:-detached HEAD}'"

origin="$(git remote get-url origin 2>/dev/null || true)"
[[ "$origin" =~ [:/]${REPO_SLUG}(\.git)?/?$ ]] ||
  die "origin is '${origin}', expected the ${REPO_SLUG} repository"

git fetch --quiet --tags origin "+refs/heads/${branch}:refs/remotes/origin/${branch}"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/${branch}")" ]] ||
  die "HEAD is not the tip of origin/${branch}; pull or push first"

[[ "$(git config --get gpg.format || echo openpgp)" == openpgp ]] ||
  die "release tags are signed with OpenPGP; set gpg.format=openpgp"
signing_key="$(git config --get user.signingkey || true)"
if [[ -z "$signing_key" ]]; then
  gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec' ||
    die "no OpenPGP signing key: set user.signingkey or create a secret key"
fi

# --- range ------------------------------------------------------------------

previous="$(git describe --tags --abbrev=0 --match "${RELEASE_TAG_PATTERN}" 2>/dev/null || true)"
if [[ -n "$previous" ]]; then
  from="$previous"
elif [[ -n "$NOTES_FROM" ]]; then
  git rev-parse --verify --quiet "${NOTES_FROM}^{commit}" >/dev/null || die "NOTES_FROM=${NOTES_FROM} is not a commit"
  from="$NOTES_FROM"
else
  die "no previous release tag is reachable from HEAD; set NOTES_FROM=<rev> (the changelog starts after it)"
fi
range="${from}..HEAD"
[[ -n "$(git rev-list --no-merges "$range")" ]] || die "no commits in ${range}"

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

release_tags() {
  git tag --list "${RELEASE_TAG_PATTERN}" | grep -E "$semver_re" || true
}
max_tag() {
  sort -V | tail -n1
}

if [[ -z "$RELEASE_VERSION" ]]; then
  if [[ -z "$previous" ]]; then
    RELEASE_VERSION=v0.1.0
  else
    [[ "$previous" =~ $semver_re ]] || die "previous tag ${previous} is not vX.Y.Z"
    major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
    if $has_breaking && [[ "$major" -eq 0 ]]; then
      RELEASE_VERSION="v0.$((minor + 1)).0"
    elif $has_breaking; then
      RELEASE_VERSION="v$((major + 1)).0.0"
    elif $has_feat; then
      RELEASE_VERSION="v${major}.$((minor + 1)).0"
    else
      RELEASE_VERSION="v${major}.${minor}.$((patch + 1))"
    fi
  fi
  if [[ "$branch" =~ ^release-([0-9]+)\.([0-9]+)$ ]]; then
    # A release branch only ships patch releases of its own line.
    line_max="$(release_tags | grep "^v${BASH_REMATCH[1]}\.${BASH_REMATCH[2]}\." | max_tag)"
    [[ "$line_max" =~ $semver_re ]] || die "no v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.* tag to continue on ${branch}"
    RELEASE_VERSION="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
  fi
  echo "proposed version: ${RELEASE_VERSION} (previous release: ${previous:-none}); override with RELEASE_VERSION=vX.Y.Z"
fi

[[ "$RELEASE_VERSION" =~ $semver_re ]] || die "RELEASE_VERSION=${RELEASE_VERSION} is not vX.Y.Z"
! git rev-parse --verify --quiet "refs/tags/${RELEASE_VERSION}" >/dev/null || die "tag ${RELEASE_VERSION} already exists"

if [[ "$branch" =~ ^release-([0-9]+)\.([0-9]+)$ ]]; then
  line="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}."
  [[ "$RELEASE_VERSION" == "${line}"* ]] || die "${branch} releases ${line}*, not ${RELEASE_VERSION}"
  ceiling="$(release_tags | grep "^${line//./\\.}" | max_tag)"
else
  ceiling="$(release_tags | max_tag)"
fi
if [[ -n "$ceiling" ]]; then
  [[ "$(printf '%s\n%s\n' "$ceiling" "$RELEASE_VERSION" | max_tag)" == "$RELEASE_VERSION" ]] ||
    die "${RELEASE_VERSION} is not greater than the existing release ${ceiling}"
fi

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
