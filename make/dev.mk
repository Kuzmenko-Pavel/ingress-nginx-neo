# SPDX-License-Identifier: Apache-2.0
#
# Local development environment and load tests. Included by the root Makefile.

DEV_KIND_CLUSTER ?= $(PROJECT)-dev

.PHONY: dev-env-up
## kind cluster with locally built images and the staged chart installed. | Development
dev-env-up: helm-stage $(KIND) $(KUBECTL) $(HELM)
	$(MAKE) --no-print-directory docker-build IMAGES="controller kube-webhook-certgen custom-error-pages"
	$(HELM_ENV) KIND=$(KIND) KUBECTL=$(KUBECTL) HELM=$(HELM) KIND_CLUSTER_NAME=$(DEV_KIND_CLUSTER) \
	K8S_VERSION=$(K8S_VERSION) RELEASE_NAME=$(RELEASE_NAME) NAMESPACE=$(NAMESPACE) \
	LOAD_IMAGES='$(CONTROLLER_IMAGE):$(IMAGE_TAG) $(CERTGEN_IMAGE):$(IMAGE_TAG) $(ERROR_PAGES_IMAGE):$(IMAGE_TAG)' \
	IMAGE_REGISTRY=$(REGISTRY_HOST) IMAGE_PREFIX=$(REGISTRY_PATH) IMAGE_TAG=$(IMAGE_TAG) \
		tools/dev-env.sh $(STAGED_CHART)

.PHONY: dev-env-down
## Delete the dev kind cluster.
dev-env-down: $(KIND)
	$(KIND) delete cluster --name $(DEV_KIND_CLUSTER)

# Load test parameters, see docs/developer-guide/testing.md.
LOAD_SCENARIO ?= steady
PROTOCOL ?= http
RATE ?= 500
DURATION ?= $(if $(filter soak,$(LOAD_SCENARIO)),30m,1m)
WARMUP ?= $(if $(filter soak,$(LOAD_SCENARIO)),60,10)

.PHONY: test-load
## k6 load test of the dev environment, memory and CPU of the controller (LOAD_SCENARIO: steady, limit, reload, soak, default-backend; PROTOCOL, RATE, DURATION).
test-load: $(KIND) $(KUBECTL)
	@if ! $(KIND) get clusters 2>/dev/null | grep -qx '$(DEV_KIND_CLUSTER)'; then \
		echo "Error: the kind cluster $(DEV_KIND_CLUSTER) does not exist"; \
		echo "Please run: make dev-env-up"; \
		exit 1; \
	fi
	$(MAKE) --no-print-directory docker-build-deps DEPS="e2e-test-echo httpbun"
	KIND=$(KIND) KUBECTL=$(KUBECTL) KIND_CLUSTER_NAME=$(DEV_KIND_CLUSTER) \
	NAMESPACE=$(NAMESPACE) RELEASE_NAME=$(RELEASE_NAME) \
	ECHO_IMAGE=$(ECHO_IMAGE) HTTPBUN_IMAGE=$(HTTPBUN_IMAGE) K6_IMAGE=$(K6_IMAGE) OUT_DIR=$(DIST)/load \
	LOAD_SCENARIO=$(LOAD_SCENARIO) PROTOCOL=$(PROTOCOL) RATE=$(RATE) DURATION=$(DURATION) WARMUP=$(WARMUP) \
		tools/load-test.sh
