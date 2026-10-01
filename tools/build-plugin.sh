#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build the kubectl plugin for every platform, package each binary with the
# LICENSE, and write checksums.sha256 and the krew manifest ingress-nginx-neo.yaml.
# Called by `make code-build-plugin`.
#
# Usage: tools/build-plugin.sh <output dir> <os/arch>...
# Environment: VERSION, LDFLAGS, RELEASE_URL (base URL of the release assets).

set -euo pipefail

out="${1:?usage: $0 <output dir> <os/arch>...}"
shift
: "${VERSION:?}" "${LDFLAGS:?}" "${RELEASE_URL:?}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary=kubectl-ingress_nginx_neo
rm -rf "$out"
mkdir -p "$out"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

platforms=""
for platform in "$@"; do
  os="${platform%/*}"
  arch="${platform#*/}"
  exe="$binary"
  [[ "$os" == windows ]] && exe="${binary}.exe"

  dir="${work}/${os}_${arch}"
  mkdir -p "$dir"
  GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 go build -trimpath -buildvcs=false \
    -ldflags "-s -w ${LDFLAGS}" -o "${dir}/${exe}" "${root}/cmd/plugin"
  cp "${root}/LICENSE" "$dir/"

  if [[ "$os" == windows ]]; then
    archive="${binary}_${os}_${arch}.zip"
    (cd "$dir" && zip -q -X "${root}/${out}/${archive}" "$exe" LICENSE)
  else
    archive="${binary}_${os}_${arch}.tar.gz"
    tar -C "$dir" -czf "${out}/${archive}" "$exe" LICENSE
  fi
  echo "built ${out}/${archive}"

  digest="$(sha256 "${out}/${archive}" | cut -d' ' -f1)"
  platforms+="  - selector:
      matchLabels:
        os: ${os}
        arch: ${arch}
    uri: ${RELEASE_URL}/${archive}
    sha256: ${digest}
    bin: ${exe}
    files:
      - from: ${exe}
        to: .
      - from: LICENSE
        to: .
"
done

(cd "$out" && sha256 ${binary}_* >checksums.sha256)

template="${root}/tools/release/krew-manifest.yaml.tmpl"
while IFS= read -r line; do
  case "$line" in
    @PLATFORMS@) printf '%s' "$platforms" ;;
    *) printf '%s\n' "${line//@VERSION@/${VERSION}}" ;;
  esac
done <"$template" >"${out}/ingress-nginx-neo.yaml"
echo "wrote ${out}/checksums.sha256 and ${out}/ingress-nginx-neo.yaml"
