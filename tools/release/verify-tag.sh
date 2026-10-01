#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Verify that a release tag may be published:
#   1. the name is vX.Y.Z;
#   2. the tag exists and is annotated;
#   3. it carries an OpenPGP signature made by a key listed in
#      trusted_release_managers.yml of origin/main (matched by fingerprint);
#   4. the tagged commit is on origin/main or origin/release-X.Y;
#   5. the "CI result" check passed on the tagged commit;
#   6. the GitHub Release of the tag is not published yet.
# Called by `make release-verify`.
#
# Usage: tools/release/verify-tag.sh <tag>
# Environment: YQ (yq binary), GITHUB_REPO (owner/name), GH_TOKEN for steps 5-6.

set -euo pipefail

tag="${1:?usage: $0 <tag>}"
: "${YQ:?}" "${GITHUB_REPO:?}"

die() {
  echo "release-verify: $*" >&2
  exit 1
}

# 1. format (offline)
[[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "${tag} is not a release tag vX.Y.Z"
line="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"

# Refresh the tag and the release branches explicitly: a CI checkout is shallow,
# lacks the other refs and may not carry the annotated tag object.
git fetch --quiet --force --no-tags origin \
  "+refs/tags/${tag}:refs/tags/${tag}" \
  "+refs/heads/main:refs/remotes/origin/main" \
  "+refs/heads/release-*:refs/remotes/origin/release-*" ||
  die "cannot fetch ${tag}, main and release-* from origin"
if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then
  git fetch --quiet --unshallow origin
fi

# 2. annotated tag
git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null || die "tag ${tag} does not exist"
[[ "$(git cat-file -t "refs/tags/${tag}")" == tag ]] || die "${tag} is a lightweight tag; release tags are annotated and signed"

# 3. signature
tag_object="$(git cat-file -p "refs/tags/${tag}")"
if grep -q -- '-----BEGIN PGP SIGNATURE-----' <<<"$tag_object"; then
  :
elif grep -qE -- '-----BEGIN (SSH SIGNATURE|SIGNED MESSAGE)-----' <<<"$tag_object"; then
  die "${tag} is not signed with OpenPGP; SSH and X.509 signatures are not accepted"
else
  die "${tag} is not signed"
fi

trusted="$(git show origin/main:trusted_release_managers.yml 2>/dev/null)" ||
  die "trusted_release_managers.yml is missing on origin/main"

gnupghome="$(mktemp -d)"
trap 'rm -rf "$gnupghome"' EXIT
chmod 700 "$gnupghome"
export GNUPGHOME="$gnupghome"

fingerprints=()
while IFS= read -r email; do
  [[ -n "$email" ]] || continue
  key="$(EMAIL="$email" "$YQ" '.[strenv(EMAIL)]' <<<"$trusted")"
  [[ "$key" == *"BEGIN PGP PUBLIC KEY BLOCK"* ]] || die "the entry ${email} in trusted_release_managers.yml is not an armored public key"
  imported="$(gpg --batch --quiet --import-options show-only --import --with-colons <<<"$key" 2>/dev/null |
    awk -F: '$1 == "pub" { want = 1 } $1 == "fpr" && want { print $10; want = 0 }')"
  [[ -n "$imported" ]] || die "cannot read the key of ${email}"
  gpg --batch --quiet --import <<<"$key" 2>/dev/null
  while IFS= read -r fpr; do fingerprints+=("$fpr"); done <<<"$imported"
done < <("$YQ" 'keys | .[]' <<<"$trusted" 2>/dev/null | grep -v '^null$' || true)

[[ ${#fingerprints[@]} -gt 0 ]] || die "no trusted release signers configured in trusted_release_managers.yml"

status="$(git -c gpg.format=openpgp verify-tag --raw "refs/tags/${tag}" 2>&1 >/dev/null || true)"
validsig="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' <<<"$status")"
[[ -n "$validsig" ]] || die "the signature of ${tag} is not valid or not made by a trusted key:
${status}"
signer=""
for fpr in "${fingerprints[@]}"; do
  [[ "$fpr" == "$validsig" ]] && signer="$fpr"
done
[[ -n "$signer" ]] || die "${tag} is signed by ${validsig}, which is not in trusted_release_managers.yml"
echo "${tag}: signed by trusted key ${signer}"

# 4. branch
commit="$(git rev-parse "refs/tags/${tag}^{commit}")"
on_branch=""
for ref in origin/main "origin/release-${line}"; do
  if git rev-parse --verify --quiet "$ref" >/dev/null && git merge-base --is-ancestor "$commit" "$ref"; then
    on_branch="$ref"
    break
  fi
done
[[ -n "$on_branch" ]] || die "${commit} is neither on origin/main nor on origin/release-${line}"
echo "${tag}: ${commit} is on ${on_branch}"

# 5. tested commit
conclusions="$(gh api "repos/${GITHUB_REPO}/commits/${commit}/check-runs?check_name=CI%20result&per_page=100" \
  --jq '.check_runs[].conclusion')" || die "cannot read the check runs of ${commit}"
grep -qx success <<<"$conclusions" || die "the \"CI result\" check of ${commit} did not succeed (got: ${conclusions:-none})"
echo "${tag}: CI result succeeded on ${commit}"

# 6. not released yet
draft="$(gh api --paginate "repos/${GITHUB_REPO}/releases?per_page=100" \
  --jq ".[] | select(.tag_name == \"${tag}\") | .draft")" || die "cannot list the releases of ${GITHUB_REPO}"
[[ "$draft" != false ]] || die "${tag} is already released"
echo "${tag}: ${draft:+draft release exists, }ready to publish"
