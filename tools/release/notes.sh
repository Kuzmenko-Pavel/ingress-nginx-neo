#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Render the release notes: the subject and body of the annotated release tag
# (the changelog), followed by the published artifacts and the commands to
# install and verify them. Called by `make release-notes`.
#
# Usage: tools/release/notes.sh <tag> <output file>
# Environment: DIGESTS_FILE (dist/digests.env), CHART_DIGEST_FILE, PLUGIN_DIR,
#              MANIFESTS_DIR, CHART_REGISTRY, CHART_NAME, RELEASE_NAME, NAMESPACE,
#              REPO_URL, DELIVERED_IMAGES (names in DIGESTS_FILE).

set -euo pipefail

tag="${1:?usage: $0 <tag> <output file>}"
out="${2:?usage: $0 <tag> <output file>}"
: "${DIGESTS_FILE:?}" "${CHART_DIGEST_FILE:?}" "${PLUGIN_DIR:?}" "${MANIFESTS_DIR:?}"
: "${CHART_REGISTRY:?}" "${CHART_NAME:?}" "${RELEASE_NAME:?}" "${NAMESPACE:?}"
: "${REPO_URL:?}" "${DELIVERED_IMAGES:?}"

die() {
  echo "release-notes: $*" >&2
  exit 1
}

[[ "$(git cat-file -t "refs/tags/${tag}" 2>/dev/null)" == tag ]] || die "${tag} is not an annotated tag"
test -s "$DIGESTS_FILE" || die "${DIGESTS_FILE} is missing: run docker-publish and docker-promote first"

version="${tag#v}"
downloads="${REPO_URL}/releases/download/${tag}"
identity="^${REPO_URL}/\\.github/workflows/release\\.yaml@refs/tags/${tag}\$"
issuer="https://token.actions.githubusercontent.com"

digest_of() {
  sed -n "s/^$1=//p" "$DIGESTS_FILE"
}

delivered=" ${DELIVERED_IMAGES} "
{
  # The tag message: subject, then the changelog body without the signature.
  git tag --list --format='%(contents:subject)' "$tag"
  echo
  git tag --list --format='%(contents:body)' "$tag" | sed '/^-----BEGIN PGP SIGNATURE-----$/,$d'

  echo
  echo "## Artifacts"
  echo
  echo "| Artifact | Reference |"
  echo "|---|---|"
  while IFS='=' read -r name ref; do
    [[ "$delivered" == *" ${name} "* ]] || continue
    printf '| %s | `%s` |\n' "$name" "${ref%@*}:${tag}@${ref#*@}"
  done <"$DIGESTS_FILE"
  if [[ -s "$CHART_DIGEST_FILE" ]]; then
    chart_ref="$(sed -n 's/^chart=//p' "$CHART_DIGEST_FILE")"
    printf '| Helm chart | `%s` (version `%s`) |\n' "$chart_ref" "$version"
  fi
  for file in "$MANIFESTS_DIR"/deploy-*.yaml; do
    [[ -e "$file" ]] || continue
    printf '| static manifest | [%s](%s/%s) |\n' "$(basename "$file")" "$downloads" "$(basename "$file")"
  done
  for file in "$PLUGIN_DIR"/kubectl-ingress_nginx_neo_*; do
    [[ -e "$file" ]] || continue
    printf '| kubectl plugin | [%s](%s/%s) |\n' "$(basename "$file")" "$downloads" "$(basename "$file")"
  done

  echo
  echo "Build and test images of this release, tagged \`${tag}\`:"
  echo
  while IFS='=' read -r name ref; do
    [[ "$delivered" != *" ${name} "* ]] || continue
    printf -- '- `%s`\n' "${ref%@*}:${tag}@${ref#*@}"
  done <"$DIGESTS_FILE"

  cat <<EOF

## Install

Helm:

\`\`\`console
helm install ${RELEASE_NAME} ${CHART_REGISTRY}/${CHART_NAME} --version ${version} \\
  --namespace ${NAMESPACE} --create-namespace
\`\`\`

Static manifests (one per provider, see the artifacts above):

\`\`\`console
kubectl apply -f ${downloads}/deploy-cloud.yaml
\`\`\`

kubectl plugin with krew:

\`\`\`console
kubectl krew install --manifest-url=${downloads}/ingress-nginx-neo.yaml
\`\`\`

## Verify

Images and the chart are signed with cosign keyless signing by the release workflow:

\`\`\`console
cosign verify $(digest_of controller) \\
  --certificate-identity-regexp '${identity}' \\
  --certificate-oidc-issuer ${issuer}
EOF
  if [[ -s "$CHART_DIGEST_FILE" ]]; then
    cat <<EOF
cosign verify ${chart_ref} \\
  --certificate-identity-regexp '${identity}' \\
  --certificate-oidc-issuer ${issuer}
EOF
  fi
  cat <<EOF
\`\`\`

The same command verifies every image listed above. The plugin archives are covered by
\`checksums.sha256\`, signed with its bundle \`checksums.sha256.sigstore.json\`:

\`\`\`console
cosign verify-blob checksums.sha256 --bundle checksums.sha256.sigstore.json \\
  --certificate-identity-regexp '${identity}' \\
  --certificate-oidc-issuer ${issuer}
sha256sum --check --ignore-missing checksums.sha256
\`\`\`

The static manifests are covered by \`deploy-manifests.sha256\`.
EOF
} >"$out"

echo "wrote ${out}"
