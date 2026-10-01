#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Install the packaged chart on a fresh kind cluster once per CI values file,
# wait until the release is ready and uninstall it. Called by
# `make test-e2e-chart`.
#
# Usage: tools/e2e-chart.sh <chart.tgz> <ci values dir>

set -euo pipefail

chart="${1:?usage: $0 <chart.tgz> <ci values dir>}"
values_dir="${2:?usage: $0 <chart.tgz> <ci values dir>}"
: "${KIND:?}" "${KUBECTL:?}" "${HELM:?}" "${KIND_CLUSTER_NAME:?}" "${K8S_VERSION:?}"
: "${CERT_MANAGER_MANIFEST:?}" "${RELEASE_NAME:?}" "${NAMESPACE:?}" "${LOAD_IMAGES:?}"
: "${IMAGE_REGISTRY:?}" "${IMAGE_PREFIX:?}" "${IMAGE_TAG:?}"

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/kind-config-${KIND_CLUSTER_NAME}}"

cleanup() {
  "$KIND" delete cluster --name "${KIND_CLUSTER_NAME}"
}
trap cleanup EXIT

if "$KIND" get clusters | grep -qx "${KIND_CLUSTER_NAME}"; then
  "$KIND" delete cluster --name "${KIND_CLUSTER_NAME}"
fi
"$KIND" create cluster --name "${KIND_CLUSTER_NAME}" --image "kindest/node:${K8S_VERSION}" --wait 2m
for image in ${LOAD_IMAGES}; do
  "$KIND" load docker-image --name "${KIND_CLUSTER_NAME}" "${image}"
done

echo "installing cert-manager"
"$KUBECTL" apply --filename "${CERT_MANAGER_MANIFEST}"
"$KUBECTL" wait --namespace cert-manager --for=condition=Available deployment --all --timeout=5m

image_args=(
  --set "global.image.registry=${IMAGE_REGISTRY}"
  --set "controller.image.image=${IMAGE_PREFIX}/controller"
  --set "controller.image.tag=${IMAGE_TAG}"
  --set "controller.admissionWebhooks.patch.image.image=${IMAGE_PREFIX}/kube-webhook-certgen"
  --set "controller.admissionWebhooks.patch.image.tag=${IMAGE_TAG}"
  --set "defaultBackend.image.image=${IMAGE_PREFIX}/custom-error-pages"
  --set "defaultBackend.image.tag=${IMAGE_TAG}"
)

for values in "${values_dir}"/*-values.yaml; do
  echo "--- $(basename "${values}")"
  "$HELM" install "${RELEASE_NAME}" "${chart}" \
    --namespace "${NAMESPACE}" --create-namespace \
    --values "${values}" \
    "${image_args[@]}" \
    --wait --timeout 5m
  "$KUBECTL" get pods --namespace "${NAMESPACE}"
  "$HELM" uninstall "${RELEASE_NAME}" --namespace "${NAMESPACE}" --wait --timeout 5m
done
