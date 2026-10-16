#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Install the packaged chart on a fresh kind cluster once per CI values file,
# all releases at the same time, each with its own IngressClass, the way
# several controllers run in one cluster. Then check that every controller
# serves its own Ingress, does not serve the Ingress of another release, and
# that a controller that is down does not block the Ingresses of the others.
# Called by `make test-e2e-chart`.
#
# Usage: tools/e2e-chart.sh <chart.tgz> <ci values dir>

set -euo pipefail

chart="${1:?usage: $0 <chart.tgz> <ci values dir>}"
values_dir="${2:?usage: $0 <chart.tgz> <ci values dir>}"
: "${KIND:?}" "${KUBECTL:?}" "${HELM:?}" "${KIND_CLUSTER_NAME:?}" "${K8S_VERSION:?}"
: "${CERT_MANAGER_MANIFEST:?}" "${NAMESPACE:?}" "${LOAD_IMAGES:?}"
: "${IMAGE_REGISTRY:?}" "${IMAGE_PREFIX:?}" "${IMAGE_TAG:?}"

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/kind-config-${KIND_CLUSTER_NAME}}"

work="$(mktemp -d)"
cleanup() {
  jobs -p | xargs -r kill 2>/dev/null || true
  "$KIND" delete cluster --name "${KIND_CLUSTER_NAME}"
  rm -rf "${work}"
}
trap cleanup EXIT

start_all=$SECONDS

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

common_args=(
  --set "global.image.registry=${IMAGE_REGISTRY}"
  --set "controller.image.image=${IMAGE_PREFIX}/controller"
  --set "controller.image.tag=${IMAGE_TAG}"
  --set "controller.admissionWebhooks.patch.image.image=${IMAGE_PREFIX}/kube-webhook-certgen"
  --set "controller.admissionWebhooks.patch.image.tag=${IMAGE_TAG}"
  --set "defaultBackend.image.image=${IMAGE_PREFIX}/custom-error-pages"
  --set "defaultBackend.image.tag=${IMAGE_TAG}"
  # Settings of the test, not of the chart: the controllers share one node,
  # readiness is checked every second instead of waiting for the probe
  # schedule, and connections are not drained.
  --set "controller.config.worker-processes=1"
  --set "controller.readinessProbe.initialDelaySeconds=1"
  --set "controller.readinessProbe.periodSeconds=1"
  --set "controller.terminationGracePeriodSeconds=0"
  # Several controllers in one cluster, as docs/user-guide/multiple-ingress.md
  # recommends.
  --set "controller.admissionWebhooks.matchIngressClass=true"
)

# Release i is ci-i in namespace ${NAMESPACE}-i with the IngressClass ci-i, as
# docs/user-guide/multiple-ingress.md describes. A values file that sets its
# own ingressClassResource keeps it: it is the release of the default class
# and serves the Ingresses without a class.
releases=()
default_release=""
declare -A values_of namespace_of
for values in "${values_dir}"/*-values.yaml; do
  release="ci-$(( ${#releases[@]} + 1 ))"
  releases+=("${release}")
  values_of[${release}]="${values}"
  namespace_of[${release}]="${NAMESPACE}-${release#ci-}"
  if grep -q '^  ingressClassResource:' "${values}"; then
    default_release="${release}"
  fi
done
: "${default_release:?no values file sets controller.ingressClassResource}"

install() {
  local release="$1" class_args=() start=$SECONDS
  if [[ "${release}" != "${default_release}" ]]; then
    class_args=(
      --set "controller.ingressClassResource.name=${release}"
      --set "controller.ingressClass=${release}"
      --set "controller.ingressClassResource.controllerValue=k8s.io/${release}"
    )
  fi
  "$HELM" install "${release}" "${chart}" \
    --namespace "${namespace_of[${release}]}" --create-namespace \
    --values "${values_of[${release}]}" \
    "${common_args[@]}" "${class_args[@]}" \
    --hide-notes --wait --timeout 5m
  echo "ready in $((SECONDS - start))s"
}

echo "installing ${#releases[@]} releases in parallel"
declare -A pid_of
for release in "${releases[@]}"; do
  install "${release}" >"${work}/${release}.log" 2>&1 &
  pid_of[${release}]=$!
done
failed=0
for release in "${releases[@]}"; do
  if wait "${pid_of[${release}]}"; then
    printf '  %-6s %-50s %s\n' "${release}" "$(basename "${values_of[${release}]}")" "$(tail -n 1 "${work}/${release}.log")"
  else
    failed=1
    printf '  %-6s %-50s FAILED\n' "${release}" "$(basename "${values_of[${release}]}")"
    cat "${work}/${release}.log"
    "$KUBECTL" get pods --namespace "${namespace_of[${release}]}" || true
  fi
done
[[ "${failed}" -eq 0 ]] || exit 1

# ingress <release> <name> <host> [class]: an Ingress that redirects the host;
# NGINX answers the redirect itself, the backend Service does not exist.
ingress() {
  local release="$1" name="$2" host="$3" class="${4:-}"
  "$KUBECTL" apply --namespace "${namespace_of[${release}]}" --filename - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${name}
  annotations:
    nginx.ingress.kubernetes.io/permanent-redirect: https://example.test/${host}
spec:
  ${class:+ingressClassName: ${class}}
  rules:
    - host: ${host}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: absent
                port:
                  number: 80
EOF
}

# Every controller is reached through a port-forward of its Service.
# kubectl port-forward exits after some connection errors; expect starts it
# again and prints why it exited.
declare -A port_of proxy_protocol_of forward_pid_of
forward() {
  local release="$1"
  "$KUBECTL" port-forward --namespace "${namespace_of[${release}]}" \
    "service/${release}-ingress-nginx-neo-controller" "${port_of[${release}]}:80" \
    >>"${work}/${release}-port-forward.log" 2>&1 &
  forward_pid_of[${release}]=$!
}
port=18080
for release in "${releases[@]}"; do
  port=$((port + 1))
  port_of[${release}]=${port}
  forward "${release}"
  config="$("$KUBECTL" get configmap --namespace "${namespace_of[${release}]}" \
    "${release}-ingress-nginx-neo-controller" --output 'jsonpath={.data.use-proxy-protocol}')"
  proxy_protocol_of[${release}]="${config}"
done

# expect <release> <host> <status> [location]: the controller of the release
# answers a request for the host with the status (and Location), within 60s.
expect() {
  local release="$1" host="$2" status="$3" location="${4:-}" args=() got=""
  [[ "${proxy_protocol_of[${release}]}" != true ]] || args=(--haproxy-protocol)
  for _ in $(seq 60); do
    if ! kill -0 "${forward_pid_of[${release}]}" 2>/dev/null; then
      echo "  port-forward of ${release} exited, starting it again:" >&2
      sed 's/^/    /' "${work}/${release}-port-forward.log" >&2
      : >"${work}/${release}-port-forward.log"
      forward "${release}"
      sleep 1
    fi
    got="$(curl --silent --output /dev/null --max-time 2 "${args[@]}" --header "Host: ${host}" \
      --write-out '%{http_code} %{redirect_url}' "http://127.0.0.1:${port_of[${release}]}/" || true)"
    [[ "${got}" == "${status} ${location}" ]] && return 0
    sleep 1
  done
  echo "  ${release}: ${host} answered '${got}', want '${status} ${location}'" >&2
  cat "${work}/${release}-port-forward.log" >&2
  "$KUBECTL" get pods --namespace "${namespace_of[${release}]}" --output wide >&2
  "$KUBECTL" describe pods --namespace "${namespace_of[${release}]}" \
    --selector app.kubernetes.io/component=controller | sed -n '/^Events:/,$p' >&2
  return 1
}

echo "checking traffic"
for release in "${releases[@]}"; do
  if [[ "${release}" == "${default_release}" ]]; then
    ingress "${release}" own "${release}.test" >/dev/null
  else
    ingress "${release}" own "${release}.test" "${release}" >/dev/null
  fi
done
for i in "${!releases[@]}"; do
  release="${releases[$i]}"
  neighbour="${releases[$(( (i + 1) % ${#releases[@]} ))]}"
  expect "${release}" "${release}.test" 301 "https://example.test/${release}.test"
  expect "${neighbour}" "${release}.test" 404
  echo "  ${release}  own host 301, ${neighbour} 404"
done
echo "  ${default_release} serves the Ingress without a class"

# A controller that is down must not block the Ingresses of other classes.
victim=""
for release in "${releases[@]}"; do
  namespace="${namespace_of[${release}]}"
  if "$KUBECTL" get deployment --namespace "${namespace}" "${release}-ingress-nginx-neo-controller" >/dev/null 2>&1 &&
    [[ -z "$("$KUBECTL" get hpa --namespace "${namespace}" --output name)" ]]; then
    victim="${release}"
    break
  fi
done
: "${victim:?no release with a controller Deployment without HPA}"
for other in "${releases[@]}"; do
  [[ "${other}" == "${victim}" || "${other}" == "${default_release}" ]] || break
done
echo "checking resilience"
"$KUBECTL" scale --namespace "${namespace_of[${victim}]}" --replicas 0 \
  "deployment/${victim}-ingress-nginx-neo-controller"
"$KUBECTL" wait --namespace "${namespace_of[${victim}]}" --for=delete pod \
  --selector app.kubernetes.io/component=controller --timeout 2m
if ! ingress "${other}" resilience "resilience.test" "${other}"; then
  echo "  ${victim} scaled to 0: creating an Ingress of ${other} was rejected" >&2
  exit 1
fi
expect "${other}" resilience.test 301 "https://example.test/resilience.test"
echo "  ${victim} scaled to 0, an Ingress of ${other} was created and is served"

echo "uninstalling"
for release in "${releases[@]}"; do
  "$HELM" uninstall "${release}" --namespace "${namespace_of[${release}]}" >"${work}/${release}-uninstall.log" 2>&1 &
  pid_of[${release}]=$!
done
for release in "${releases[@]}"; do
  wait "${pid_of[${release}]}" || { cat "${work}/${release}-uninstall.log"; exit 1; }
done

echo "chart e2e passed in $((SECONDS - start_all))s"
