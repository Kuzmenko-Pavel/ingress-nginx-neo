#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Run a command inside a container image with the repository mounted at /src.
# Go build and module caches live in .cache/container/ so repeated runs are fast.
# /etc/ingress-controller is a fresh writable directory, as in the controller
# image.
#
# Usage: tools/run-in-container.sh <image> <command> [args...]

set -euo pipefail

image="${1:?usage: $0 <image> <command> [args...]}"
shift
[[ $# -gt 0 ]] || { echo "usage: $0 <image> <command> [args...]" >&2; exit 1; }

root="$(git rev-parse --show-toplevel)"
cache="${root}/.cache/container"
mkdir -p "${cache}/go-build" "${cache}/go-mod" "${root}/.cache/tmp"

controller_dir="$(mktemp -d "${root}/.cache/tmp/ingress-controller.XXXXXX")"
trap 'rm -rf "${controller_dir}"' EXIT
mkdir -p "${controller_dir}/ssl" "${controller_dir}/auth" "${controller_dir}/geoip"

tty=()
[[ -t 0 && -t 1 ]] && tty=(--tty --interactive)

user=()
if [[ "$(uname -s)" == Linux ]]; then
  user=(--user "$(id -u):$(id -g)")
fi

docker run --rm "${tty[@]}" "${user[@]}" \
  --env HOME=/tmp \
  --env GOCACHE=/cache/go-build \
  --env GOMODCACHE=/cache/go-mod \
  --env GOTOOLCHAIN=local \
  --env GOFLAGS=-buildvcs=false \
  --volume "${root}:/src" \
  --volume "${cache}:/cache" \
  --volume "${controller_dir}:/etc/ingress-controller" \
  --workdir /src \
  "${image}" "$@"
