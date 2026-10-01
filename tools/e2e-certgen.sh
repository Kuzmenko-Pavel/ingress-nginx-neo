#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Run the kube-webhook-certgen e2e test (images/kube-webhook-certgen/hack/e2e.sh)
# against a fresh kind cluster. Called by `make test-e2e-certgen`.

set -euo pipefail

: "${KIND:?}" "${KUBECTL:?}" "${KIND_CLUSTER_NAME:?}" "${K8S_VERSION:?}"

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/kind-config-${KIND_CLUSTER_NAME}}"
bin="$(mktemp -d)"

cleanup() {
  "$KIND" delete cluster --name "${KIND_CLUSTER_NAME}"
  rm -rf "${bin}"
}
trap cleanup EXIT

if "$KIND" get clusters | grep -qx "${KIND_CLUSTER_NAME}"; then
  "$KIND" delete cluster --name "${KIND_CLUSTER_NAME}"
fi
"$KIND" create cluster --name "${KIND_CLUSTER_NAME}" --image "kindest/node:${K8S_VERSION}" --wait 2m

ln -s "${KUBECTL}" "${bin}/kubectl"
cd "$(dirname "${BASH_SOURCE[0]}")/../images/kube-webhook-certgen"
PATH="${bin}:${PATH}" hack/e2e.sh
