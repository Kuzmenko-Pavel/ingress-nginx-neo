# SPDX-License-Identifier: Apache-2.0
#
# Unit and e2e tests. Included by the root Makefile.

.PHONY: test-unit
## Go unit tests: root module (excluding test/e2e, images, docs/examples) + images/{kube-webhook-certgen,custom-error-pages,fastcgi-helloserver}/rootfs. | Test
test-unit: deps-runner
	tools/run-in-container.sh $(RUNNER_IMAGE) test/test.sh

.PHONY: test-unit-lua
## Lua unit tests inside e2e-test-runner.
test-unit-lua: deps-runner
	tools/run-in-container.sh $(RUNNER_IMAGE) test/test-lua.sh

E2E_CONTROLLER := $(if $(filter chroot,$(E2E_VARIANT)),controller-chroot,controller)
E2E_KIND_CLUSTER ?= $(PROJECT)-e2e
REGISTRY_HOST = $(firstword $(subst /, ,$(REGISTRY)))
REGISTRY_PATH = $(patsubst $(REGISTRY_HOST)/%,%,$(REGISTRY))

# Every image the e2e suite runs: the controller of the variant under test,
# certgen, the default backend, the suite itself and the test dependencies.
E2E_LOAD_IMAGES = $(REGISTRY)/$(E2E_CONTROLLER):$(IMAGE_TAG) $(CERTGEN_IMAGE):$(IMAGE_TAG) \
	$(ERROR_PAGES_IMAGE):$(IMAGE_TAG) $(E2E_IMAGE) $(NGINX_IMAGE) $(ECHO_IMAGE) $(HTTPBUN_IMAGE) \
	$(FASTCGI_IMAGE) $(CFSSL_IMAGE)

.PHONY: test-e2e
## Controller e2e on kind (E2E_VARIANT=default or chroot, K8S_VERSION, FOCUS, E2E_NODES; SKIP_BUILD=1 uses already loaded images).
test-e2e: $(KIND) $(KUBECTL)
	$(if $(filter-out $(E2E_VARIANTS),$(E2E_VARIANT)),$(error E2E_VARIANT must be one of $(E2E_VARIANTS)))
	$(MAKE) --no-print-directory docker-build-deps
ifeq ($(SKIP_BUILD),)
	$(MAKE) --no-print-directory docker-build IMAGES="$(E2E_CONTROLLER) kube-webhook-certgen custom-error-pages"
	$(MAKE) --no-print-directory docker-build-e2e
endif
	KIND=$(KIND) KUBECTL=$(KUBECTL) KIND_CLUSTER_NAME=$(E2E_KIND_CLUSTER) K8S_VERSION=$(K8S_VERSION) \
	E2E_IMAGE=$(E2E_IMAGE) LOAD_IMAGES='$(E2E_LOAD_IMAGES)' \
	E2E_VARIANT=$(E2E_VARIANT) E2E_IMAGE_REGISTRY=$(REGISTRY_HOST) E2E_IMAGE_PREFIX=$(REGISTRY_PATH) E2E_IMAGE_TAG=$(IMAGE_TAG) \
	NGINX_BASE_IMAGE=$(NGINX_IMAGE) E2E_ECHO_IMAGE=$(ECHO_IMAGE) E2E_HTTPBUN_IMAGE=$(HTTPBUN_IMAGE) \
	E2E_FASTCGI_IMAGE=$(FASTCGI_IMAGE) E2E_CFSSL_IMAGE=$(CFSSL_IMAGE) \
	E2E_NODES=$(E2E_NODES) FOCUS='$(FOCUS)' E2E_CHECK_LEAKS=$(E2E_CHECK_LEAKS) \
	REPORTS_DIR=$(CURDIR)/test/junitreports \
		test/e2e/run-kind-e2e.sh

.PHONY: test-e2e-chart
## Install every ci/*-values.yaml on one kind cluster in parallel, check traffic and isolation (SKIP_BUILD=1 supported).
test-e2e-chart: helm-package $(KIND) $(KUBECTL) $(HELM) $(CERT_MANAGER_MANIFEST)
ifeq ($(SKIP_BUILD),)
	$(MAKE) --no-print-directory docker-build IMAGES="controller kube-webhook-certgen custom-error-pages"
endif
	$(HELM_ENV) KIND=$(KIND) KUBECTL=$(KUBECTL) HELM=$(HELM) KIND_CLUSTER_NAME=$(PROJECT)-chart \
	K8S_VERSION=$(K8S_VERSION) CERT_MANAGER_MANIFEST=$(CERT_MANAGER_MANIFEST) \
	NAMESPACE=$(NAMESPACE) \
	LOAD_IMAGES='$(CONTROLLER_IMAGE):$(IMAGE_TAG) $(CERTGEN_IMAGE):$(IMAGE_TAG) $(ERROR_PAGES_IMAGE):$(IMAGE_TAG)' \
	IMAGE_REGISTRY=$(REGISTRY_HOST) IMAGE_PREFIX=$(REGISTRY_PATH) IMAGE_TAG=$(IMAGE_TAG) \
		tools/e2e-chart.sh $(CHART_PACKAGE) $(STAGED_CHART)/ci

.PHONY: test-e2e-certgen
## kube-webhook-certgen e2e on kind.
test-e2e-certgen: $(KIND) $(KUBECTL)
	KIND=$(KIND) KUBECTL=$(KUBECTL) KIND_CLUSTER_NAME=$(PROJECT)-certgen K8S_VERSION=$(K8S_VERSION) \
		tools/e2e-certgen.sh
