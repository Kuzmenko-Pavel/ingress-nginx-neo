#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Render the static install manifests deploy-<provider>[-<variant>].yaml from a
# packaged chart, one per values.yaml under tools/manifest-templates/provider,
# plus deploy-manifests.sha256.
#
# Usage: tools/generate-manifests.sh <chart.tgz> <output dir>
# Environment: HELM, KUSTOMIZE (binaries), RELEASE_NAME, NAMESPACE, CHART_NAME,
#              K8S_MINOR (oldest supported Kubernetes minor, e.g. 1.34).

set -euo pipefail

chart="$(realpath "${1:?usage: $0 <chart.tgz> <output dir>}")"
out="${2:?usage: $0 <chart.tgz> <output dir>}"
: "${HELM:?}" "${KUSTOMIZE:?}" "${RELEASE_NAME:?}" "${NAMESPACE:?}" "${CHART_NAME:?}" "${K8S_MINOR:?}"

templates="$(cd "$(dirname "${BASH_SOURCE[0]}")/manifest-templates" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

rm -rf "$out"
mkdir -p "$out"
cp -R "${templates}/." "${work}/"

cat >"${work}/common/namespace.yaml" <<NAMESPACE
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${CHART_NAME}
    app.kubernetes.io/instance: ${RELEASE_NAME}
NAMESPACE

while IFS= read -r values; do
  target="$(dirname "${values#"${work}/provider/"}")"
  name="deploy-${target//\//-}.yaml"
  "$HELM" template "$RELEASE_NAME" "$chart" \
    --values "$values" \
    --namespace "$NAMESPACE" \
    --kube-version "$K8S_MINOR" |
    sed -e '/app.kubernetes.io\/managed-by: Helm/d' -e '/helm.sh\//d' >"${work}/common/manifest.yaml"
  "$KUSTOMIZE" build --load-restrictor=LoadRestrictionsNone "$(dirname "$values")" >"${out}/${name}"
  echo "rendered ${out}/${name}"
done < <(find "${work}/provider" -name values.yaml | LC_ALL=C sort)

(cd "$out" && if command -v sha256sum >/dev/null; then sha256sum deploy-*.yaml; else shasum -a 256 deploy-*.yaml; fi >deploy-manifests.sha256)
