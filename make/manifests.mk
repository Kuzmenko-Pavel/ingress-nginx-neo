# SPDX-License-Identifier: Apache-2.0
#
# Static manifests. Included by the root Makefile.

MANIFESTS_K8S_MINOR = $(shell sed -E 's/^v([0-9]+\.[0-9]+).*/\1/' <<< '$(firstword $(K8S_VERSIONS))')

.PHONY: manifests-generate
## Render deploy-<provider>.yaml from the packaged chart into dist/manifests (+ sha256). | Manifests
manifests-generate: helm-package $(HELM) $(KUSTOMIZE)
	$(HELM_ENV) HELM=$(HELM) KUSTOMIZE=$(KUSTOMIZE) RELEASE_NAME=$(RELEASE_NAME) NAMESPACE=$(NAMESPACE) \
		CHART_NAME=$(CHART_NAME) K8S_MINOR=$(MANIFESTS_K8S_MINOR) \
		tools/generate-manifests.sh $(CHART_PACKAGE) $(DIST)/manifests
