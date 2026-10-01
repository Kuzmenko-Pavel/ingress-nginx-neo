#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Download a pinned tool listed in tools/versions.env into a directory and
# verify its sha256. Idempotent: a tool already installed at the pinned
# version is left as is.
#
# Usage: tools/install.sh <golangci-lint|kubectl|helm-unittest|cert-manager> <dir>

set -euo pipefail

name="${1:?usage: $0 <tool> <dir>}"
dir="${2:?usage: $0 <tool> <dir>}"

# shellcheck source=versions.env
source "$(dirname "${BASH_SOURCE[0]}")/versions.env"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

sha_var() {
  local var="$1_SHA256_${os}_${arch}"
  if [[ -z "${!var:-}" ]]; then
    echo "no checksum for $name on ${os}/${arch} in tools/versions.env" >&2
    exit 1
  fi
  echo "${!var}"
}

case "$name" in
  golangci-lint)
    version="$GOLANGCI_LINT_VERSION"
    sha="$(sha_var GOLANGCI_LINT)"
    url="https://github.com/golangci/golangci-lint/releases/download/v${version}/golangci-lint-${version}-${os}-${arch}.tar.gz"
    member="golangci-lint-${version}-${os}-${arch}/golangci-lint"
    ;;
  kubectl)
    version="$KUBECTL_VERSION"
    sha="$(sha_var KUBECTL)"
    url="https://dl.k8s.io/release/${version}/bin/${os}/${arch}/kubectl"
    member=""
    ;;
  helm-unittest)
    version="$HELM_UNITTEST_VERSION"
    sha="$(sha_var HELM_UNITTEST)"
    asset_os="$os"
    [[ "$os" == darwin ]] && asset_os=macos
    url="https://github.com/helm-unittest/helm-unittest/releases/download/v${version}/helm-unittest-${asset_os}-${arch}-${version}.tgz"
    member="untt-${asset_os}-${arch}"
    ;;
  cert-manager)
    version="$CERT_MANAGER_VERSION"
    sha="$CERT_MANAGER_SHA256"
    url="https://github.com/cert-manager/cert-manager/releases/download/${version}/cert-manager.yaml"
    member=""
    ;;
  *)
    echo "unknown tool: $name" >&2
    exit 1
    ;;
esac

target="${dir}/${name}"
[[ "$name" == cert-manager ]] && target="${dir}/cert-manager.yaml"
stamp="${dir}/.${name}.version"

if [[ -e "$target" && "$(cat "$stamp" 2>/dev/null)" == "$version" ]]; then
  exit 0
fi

mkdir -p "$dir"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "downloading ${name} ${version}"
curl -fsSL --retry 3 -o "${tmp}/download" "$url"
actual="$( (command -v sha256sum >/dev/null && sha256sum "${tmp}/download" || shasum -a 256 "${tmp}/download") | cut -d' ' -f1)"
if [[ "$actual" != "$sha" ]]; then
  echo "sha256 mismatch for ${url}: expected ${sha}, got ${actual}" >&2
  exit 1
fi

if [[ -n "$member" ]]; then
  tar -xzf "${tmp}/download" -C "$tmp" "$member"
  install -m 0755 "${tmp}/${member}" "$target"
elif [[ "$name" == cert-manager ]]; then
  install -m 0644 "${tmp}/download" "$target"
else
  install -m 0755 "${tmp}/download" "$target"
fi
echo "$version" >"$stamp"
