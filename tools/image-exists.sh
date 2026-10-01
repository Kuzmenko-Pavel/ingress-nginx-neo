#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

# Usage: tools/image-exists.sh <image:tag> [os/arch ...]
#
# Checks whether an image tag is published in its registry and, optionally, whether it
# provides every listed platform. Used by CI to keep published tags immutable.
#
# Exit codes:
#   0  the tag exists (and provides all listed platforms)
#   1  the tag does not exist
#   2  the registry could not be queried (never treat this as "missing")
#   3  the tag exists but lacks at least one of the listed platforms

set -o nounset
set -o pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <image:tag> [os/arch ...]" >&2
  exit 2
fi

REF=$1
shift

if ! OUT=$(docker buildx imagetools inspect "${REF}" --format '{{json .Manifest}}' 2>&1); then
  # GHCR answers "denied" / 403 for packages that do not exist yet; a real permission problem
  # surfaces later as a failed push, so it cannot lead to an overwrite.
  if grep -qiE 'not found|manifest unknown|name unknown|denied|403 Forbidden' <<< "${OUT}"; then
    echo "${REF}: not published" >&2
    exit 1
  fi
  echo "${REF}: registry query failed: ${OUT}" >&2
  exit 2
fi

if [ $# -eq 0 ]; then
  exit 0
fi

PLATFORMS=$(echo "${OUT}" | jq -r '.manifests[]?.platform | select(. != null) | "\(.os)/\(.architecture)"')
if [ -z "${PLATFORMS}" ]; then
  # Single-platform manifest: read the platform from the image config.
  PLATFORMS=$(docker buildx imagetools inspect "${REF}" --format '{{json .Image}}' | jq -r '"\(.os)/\(.architecture)"')
fi

rc=0
for platform in "$@"; do
  if ! echo "${PLATFORMS}" | grep -qx "${platform}"; then
    echo "${REF}: platform ${platform} is not published (available: ${PLATFORMS//$'\n'/ })" >&2
    rc=3
  fi
done
exit ${rc}
