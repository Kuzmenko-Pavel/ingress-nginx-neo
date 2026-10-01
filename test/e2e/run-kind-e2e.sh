#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Run the controller e2e suite on a fresh kind cluster. Called by `make test-e2e`,
# which builds the images and passes every reference below.

set -o errexit
set -o nounset
set -o pipefail

: "${KIND:?}" "${KUBECTL:?}" "${KIND_CLUSTER_NAME:?}" "${K8S_VERSION:?}" "${E2E_IMAGE:?}" "${LOAD_IMAGES:?}"
: "${E2E_VARIANT:?}" "${E2E_IMAGE_REGISTRY:?}" "${E2E_IMAGE_PREFIX:?}" "${E2E_IMAGE_TAG:?}"
: "${NGINX_BASE_IMAGE:?}" "${E2E_ECHO_IMAGE:?}" "${E2E_HTTPBUN_IMAGE:?}" "${E2E_FASTCGI_IMAGE:?}" "${E2E_CFSSL_IMAGE:?}"
: "${E2E_NODES:?}"
FOCUS="${FOCUS:-}"
E2E_CHECK_LEAKS="${E2E_CHECK_LEAKS:-}"
DEBUG="${DEBUG:-false}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="${REPORTS_DIR:-${DIR}/../junitreports}"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/kind-config-${KIND_CLUSTER_NAME}}"

cleanup() {
  "$KIND" delete cluster --name "${KIND_CLUSTER_NAME}"
}

if [[ "${DEBUG}" == "true" ]]; then
  set -x
  echo "DEBUG=true: the cluster ${KIND_CLUSTER_NAME} is kept"
else
  trap cleanup EXIT
fi

echo "creating kind cluster ${KIND_CLUSTER_NAME} (kindest/node:${K8S_VERSION})"
if "$KIND" get clusters | grep -qx "${KIND_CLUSTER_NAME}"; then
  "$KIND" delete cluster --name "${KIND_CLUSTER_NAME}"
fi
"$KIND" create cluster \
  --name "${KIND_CLUSTER_NAME}" \
  --config "${DIR}/kind.yaml" \
  --retain \
  --image "kindest/node:${K8S_VERSION}"
"$KUBECTL" get nodes -o wide

workers="$("$KIND" get nodes --name "${KIND_CLUSTER_NAME}" | grep worker | paste -sd, -)"
for image in ${LOAD_IMAGES}; do
  echo "loading ${image}"
  "$KIND" load docker-image --name "${KIND_CLUSTER_NAME}" --nodes "${workers}" "${image}"
done

echo "granting permissions to the e2e service account"
"$KUBECTL" create serviceaccount ingress-nginx-e2e
"$KUBECTL" create clusterrolebinding permissive-binding \
  --clusterrole=cluster-admin \
  --user=admin \
  --user=kubelet \
  --serviceaccount=default:ingress-nginx-e2e

echo "starting the e2e test pod"
status=0
"$KUBECTL" run e2e \
  --rm \
  --attach \
  --restart=Never \
  --image="${E2E_IMAGE}" \
  --image-pull-policy=IfNotPresent \
  --env="E2E_NODES=${E2E_NODES}" \
  --env="FOCUS=${FOCUS}" \
  --env="E2E_CHECK_LEAKS=${E2E_CHECK_LEAKS}" \
  --env="E2E_VARIANT=${E2E_VARIANT}" \
  --env="E2E_IMAGE_REGISTRY=${E2E_IMAGE_REGISTRY}" \
  --env="E2E_IMAGE_PREFIX=${E2E_IMAGE_PREFIX}" \
  --env="E2E_IMAGE_TAG=${E2E_IMAGE_TAG}" \
  --env="NGINX_BASE_IMAGE=${NGINX_BASE_IMAGE}" \
  --env="E2E_ECHO_IMAGE=${E2E_ECHO_IMAGE}" \
  --env="E2E_HTTPBUN_IMAGE=${E2E_HTTPBUN_IMAGE}" \
  --env="E2E_FASTCGI_IMAGE=${E2E_FASTCGI_IMAGE}" \
  --env="E2E_CFSSL_IMAGE=${E2E_CFSSL_IMAGE}" \
  --overrides='{ "apiVersion": "v1", "spec": { "serviceAccountName": "ingress-nginx-e2e" } }' || status=$?

# The suite stores its junit report in a ConfigMap.
report="report-e2e-test-suite.xml.gz"
mkdir -p "${REPORTS_DIR}"
if "$KUBECTL" get configmap "${report}" >/dev/null 2>&1; then
  "$KUBECTL" get configmap "${report}" -o "jsonpath={.binaryData['${report//./\\.}']}" |
    base64 -d | gunzip >"${REPORTS_DIR}/${report%.gz}"
  echo "junit report: ${REPORTS_DIR}/${report%.gz}"
fi

exit "${status}"
