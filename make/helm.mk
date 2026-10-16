# SPDX-License-Identifier: Apache-2.0
#
# Helm chart. Included by the root Makefile.

STAGED_CHART := $(DIST)/chart/$(CHART_NAME)
CHART_PACKAGE := $(DIST)/$(CHART_NAME)-$(CHART_VERSION).tgz

# Copy the chart into dist/chart and set its version; the source chart is
# never modified.
.PHONY: helm-stage
helm-stage: $(YQ)
	rm -rf $(STAGED_CHART)
	mkdir -p $(dir $(STAGED_CHART))
	cp -R $(CHART_DIR) $(STAGED_CHART)
	rm -rf $(STAGED_CHART)/tests
	$(YQ) -i '.version = "$(CHART_VERSION)" | .appVersion = "$(APP_VERSION)"' $(STAGED_CHART)/Chart.yaml

.PHONY: helm-lint
## helm lint --strict + kubeconform on the staged chart for every ci values file. | Helm
helm-lint: helm-stage $(HELM) $(KUBECONFORM)
	for values in $(STAGED_CHART)/ci/*-values.yaml; do \
		echo "--- $$values"; \
		$(HELM_ENV) $(HELM) lint --strict --values "$$values" $(STAGED_CHART); \
		$(HELM_ENV) $(HELM) template $(RELEASE_NAME) $(STAGED_CHART) --namespace $(NAMESPACE) \
			--kube-version $(K8S_MINOR) --values "$$values" | \
			$(KUBECONFORM) -strict -ignore-missing-schemas -summary -kubernetes-version $(K8S_MINOR).0; \
	done

.PHONY: helm-test
## helm-unittest; JUnit in dist/test-reports.
helm-test: $(HELM_UNITTEST)
	mkdir -p $(TEST_REPORTS)
	$(HELM_UNITTEST) --file 'tests/**/*_test.yaml' --output-type JUnit --output-file $(TEST_REPORTS)/unit-helm.xml $(CHART_DIR)

.PHONY: helm-template
## Render the staged chart into dist/rendered/.
helm-template: helm-stage $(HELM)
	mkdir -p $(DIST)/rendered
	$(HELM_ENV) $(HELM) template $(RELEASE_NAME) $(STAGED_CHART) --namespace $(NAMESPACE) \
		--kube-version $(K8S_MINOR) > $(DIST)/rendered/$(CHART_NAME).yaml
	@echo "rendered $(DIST)/rendered/$(CHART_NAME).yaml"

.PHONY: helm-docs-generate
## Regenerate charts/ingress-nginx-neo/README.md.
helm-docs-generate: $(HELM_DOCS)
	$(HELM_DOCS) --chart-search-root charts

.PHONY: helm-docs-verify
## Fail if the chart README is stale.
helm-docs-verify: helm-docs-generate
	git diff --exit-code -- $(CHART_DIR)/README.md || \
		{ echo "$(CHART_DIR)/README.md is stale: run make helm-docs-generate" >&2; exit 1; }

HELM_REGISTRY_CONFIG ?= $(or $(DOCKER_CONFIG),$(HOME)/.docker)/config.json

.PHONY: helm-package
## Stage, (release: pin digests), package into dist/.
helm-package: helm-stage $(HELM) $(YQ)
ifeq ($(CHANNEL),release)
	test -s $(DIGESTS_FILE) || { echo "$(DIGESTS_FILE) is missing: run make docker-publish first" >&2; exit 1; }
	digest() { sed -n "s/^$$1=.*@//p" $(DIGESTS_FILE); }; \
	$(YQ) -i ".controller.image.digest = \"$$(digest controller)\" | \
		.controller.image.digestChroot = \"$$(digest controller-chroot)\" | \
		.controller.admissionWebhooks.patch.image.digest = \"$$(digest kube-webhook-certgen)\" | \
		.defaultBackend.image.digest = \"$$(digest custom-error-pages)\"" $(STAGED_CHART)/values.yaml
	$(HELM_ENV) $(HELM) template $(RELEASE_NAME) $(STAGED_CHART) --set controller.admissionWebhooks.enabled=true | \
		grep -q '$(CONTROLLER_IMAGE):$(IMAGE_TAG)@sha256:' || { echo "the packaged chart does not pin the controller digest" >&2; exit 1; }
endif
	$(HELM_ENV) $(HELM) package $(STAGED_CHART) --version $(CHART_VERSION) --app-version $(APP_VERSION) --destination $(DIST)

.PHONY: helm-publish
## Push dist/*.tgz to CHART_REGISTRY and sign it.
helm-publish: publish-guard $(HELM) $(COSIGN)
	test -s $(CHART_PACKAGE) || { echo "$(CHART_PACKAGE) is missing: run make helm-package first" >&2; exit 1; }
	$(HELM_ENV) HELM_REGISTRY_CONFIG=$(HELM_REGISTRY_CONFIG) $(HELM) push $(CHART_PACKAGE) $(CHART_REGISTRY) 2>&1 | tee $(DIST)/helm-push.log
	digest="$$(sed -n 's/^Digest: //p' $(DIST)/helm-push.log)"; \
	test -n "$$digest" || { echo "helm push printed no digest; see $(DIST)/helm-push.log" >&2; exit 1; }; \
	echo "chart=$(REGISTRY)/charts/$(CHART_NAME)@$$digest" > $(DIST)/chart-digest.env; \
	$(COSIGN) sign --yes "$(REGISTRY)/charts/$(CHART_NAME)@$$digest"
