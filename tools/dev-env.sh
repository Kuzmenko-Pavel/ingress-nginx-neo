#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Create (or reuse) the development kind cluster, load the locally built
# images and install the staged chart. The controller listens on localhost:80
# and localhost:443. Called by `make dev-env-up`.
#
# Usage: tools/dev-env.sh <staged chart dir>

set -euo pipefail

chart="${1:?usage: $0 <staged chart dir>}"
: "${KIND:?}" "${KUBECTL:?}" "${HELM:?}" "${KIND_CLUSTER_NAME:?}" "${K8S_VERSION:?}"
: "${RELEASE_NAME:?}" "${NAMESPACE:?}" "${LOAD_IMAGES:?}" "${IMAGE_REGISTRY:?}" "${IMAGE_PREFIX:?}" "${IMAGE_TAG:?}"

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/kind-config-${KIND_CLUSTER_NAME}}"
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if "$KIND" get clusters | grep -qx "${KIND_CLUSTER_NAME}"; then
  echo "using the existing kind cluster ${KIND_CLUSTER_NAME}"
else
  "$KIND" create cluster --name "${KIND_CLUSTER_NAME}" --image "kindest/node:${K8S_VERSION}" \
    --config "${dir}/kind-dev.yaml" --wait 2m
fi

for image in ${LOAD_IMAGES}; do
  "$KIND" load docker-image --name "${KIND_CLUSTER_NAME}" "${image}"
done

"$HELM" upgrade --install "${RELEASE_NAME}" "${chart}" \
  --namespace "${NAMESPACE}" --create-namespace \
  --set "global.image.registry=${IMAGE_REGISTRY}" \
  --set "controller.image.image=${IMAGE_PREFIX}/controller" \
  --set "controller.image.tag=${IMAGE_TAG}" \
  --set "controller.image.pullPolicy=Never" \
  --set "controller.admissionWebhooks.patch.image.image=${IMAGE_PREFIX}/kube-webhook-certgen" \
  --set "controller.admissionWebhooks.patch.image.tag=${IMAGE_TAG}" \
  --set "controller.admissionWebhooks.patch.image.pullPolicy=Never" \
  --set-string "controller.config.worker-processes=1" \
  --set-string "controller.podLabels.deploy-date=$(date +%s)" \
  --set "controller.updateStrategy.type=RollingUpdate" \
  --set "controller.updateStrategy.rollingUpdate.maxUnavailable=1" \
  --set "controller.hostPort.enabled=true" \
  --set "controller.terminationGracePeriodSeconds=0" \
  --set "controller.service.type=NodePort" \
  --wait --timeout 5m

cat <<MESSAGE

The kind cluster ${KIND_CLUSTER_NAME} is ready; the controller listens on localhost:80 and localhost:443.
kubeconfig: ${KUBECONFIG}
Rebuild and redeploy: make dev-env-up    Delete the cluster: make dev-env-down
MESSAGE
