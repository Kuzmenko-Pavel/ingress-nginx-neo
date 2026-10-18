#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Check that the shards of test/e2e-image/shards.sh run every spec of the e2e
# suite exactly once and that no shard is empty. ginkgo --dry-run lists the
# specs without running them, so no cluster is needed. Called by
# `make docker-build-e2e` inside the e2e-test-runner image.
#
# Usage: test/e2e/check-shards.sh <e2e.test> <shard>...

set -euo pipefail

suite="$(realpath "${1:?usage: $0 <e2e.test> <shard>...}")"
shift
[[ $# -gt 0 ]] || { echo "usage: $0 <e2e.test> <shard>..." >&2; exit 1; }

# shellcheck source=../e2e-image/shards.sh
source "$(dirname "${BASH_SOURCE[0]}")/../e2e-image/shards.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# The suite refuses to start without the images; a dry run does not use them.
for image in E2E_ECHO_IMAGE E2E_HTTPBUN_IMAGE E2E_FASTCGI_IMAGE E2E_CFSSL_IMAGE NGINX_BASE_IMAGE; do
  export "${image}=dry-run"
done

# specs <name> [ginkgo args]: the specs a run with these arguments would run,
# one "file classname and spec text" per line, sorted.
specs() {
  local name="$1"
  shift
  (cd "${work}" && ginkgo --dry-run --silence-skips --junit-report="${name}.xml" "$@" "${suite}" >/dev/null)
  grep -o '<testcase name="[^"]*" classname="[^"]*" status="passed"' "${work}/${name}.xml" | sort >"${work}/${name}.txt"
}

specs all
total=$(wc -l <"${work}/all.txt")
: >"${work}/shards.txt"
for shard in "$@"; do
  shard_args "${shard}"
  specs "shard-${shard}" "${SHARD_ARGS[@]}"
  count=$(wc -l <"${work}/shard-${shard}.txt")
  if [[ "${count}" -eq 0 ]]; then
    echo "shard ${shard} runs no spec" >&2
    exit 1
  fi
  echo "shard ${shard}: ${count} specs"
  cat "${work}/shard-${shard}.txt" >>"${work}/shards.txt"
done
sort -o "${work}/shards.txt" "${work}/shards.txt"

if ! diff -u "${work}/all.txt" "${work}/shards.txt" >"${work}/diff.txt"; then
  echo "the shards do not run every spec exactly once (- missing, + run twice):" >&2
  cat "${work}/diff.txt" >&2
  exit 1
fi
echo "every one of ${total} specs runs in exactly one shard"
