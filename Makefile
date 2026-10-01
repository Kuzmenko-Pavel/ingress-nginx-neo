# SPDX-License-Identifier: Apache-2.0
#
# The project API: humans, agents and CI call the same targets.
# Run `make help` for the list of targets.

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:
MAKEFLAGS += --no-builtin-rules
-include .env # optional local overrides, gitignored

# ---------------------------------------------------------------------------
# Project coordinates
# ---------------------------------------------------------------------------

PROJECT := ingress-nginx-neo
REPO_URL := https://github.com/Kuzmenko-Pavel/ingress-nginx-neo
GO_PACKAGE := k8s.io/ingress-nginx

REGISTRY ?= ghcr.io/kuzmenko-pavel/ingress-nginx-neo
CHART_REGISTRY ?= oci://$(REGISTRY)/charts
CHART_NAME ?= ingress-nginx-neo
CHART_DIR ?= charts/$(CHART_NAME)
RELEASE_NAME ?= ingress-nginx-neo
NAMESPACE ?= ingress-nginx-neo

DIST := dist
CACHE := .cache
TOOLS_DIR := $(CURDIR)/$(CACHE)/tools

# ---------------------------------------------------------------------------
# Versions: the git tag is the only version source
# ---------------------------------------------------------------------------

RELEASE_TAG_PATTERN := v[0-9]*.[0-9]*.[0-9]*
CHANNEL ?= dev
ifeq ($(filter $(CHANNEL),dev latest release),)
$(error CHANNEL must be one of dev, latest, release (got "$(CHANNEL)"))
endif

ifeq ($(CHANNEL),release)
RELEASE_TAG ?= $(or $(GITHUB_REF_NAME),$(if $(filter command line environment,$(origin VERSION)),$(VERSION)))
ifeq ($(filter command line environment,$(origin VERSION)),)
VERSION := $(RELEASE_TAG)
endif
ifneq ($(shell [[ "$(VERSION)" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$$ ]] && echo ok),ok)
$(error CHANNEL=release needs a release tag vX.Y.Z in RELEASE_TAG (got "$(VERSION)"))
endif
else ifeq ($(origin VERSION),undefined)
VERSION := $(or $(shell git describe --tags --match '$(RELEASE_TAG_PATTERN)' 2>/dev/null),v0.0.0-dev)
endif

ifeq ($(CHANNEL),release)
IMAGE_TAG := $(VERSION)
CHART_VERSION := $(VERSION:v%=%)
APP_VERSION := $(VERSION)
DOCS_VERSION := $(word 1,$(subst ., ,$(CHART_VERSION))).$(word 2,$(subst ., ,$(CHART_VERSION)))
else ifeq ($(CHANNEL),latest)
IMAGE_TAG := latest
CHART_VERSION := 0.0.0-latest
APP_VERSION := latest
DOCS_VERSION := latest
else
IMAGE_TAG := dev
CHART_VERSION := 0.0.0-dev
APP_VERSION := dev
DOCS_VERSION :=
endif

COMMIT := $(shell git rev-parse HEAD 2>/dev/null)

# Go version: toolchain line of go.mod, else its go line. Used for every Go
# build, native or in a container.
GO_VERSION := $(or $(shell awk '$$1 == "toolchain" { sub(/^go/, "", $$2); print $$2; exit }' go.mod),$(shell awk '$$1 == "go" { print $$2; exit }' go.mod))
ifeq ($(GO_VERSION),)
$(error cannot read the Go version from go.mod)
endif
export GOTOOLCHAIN := go$(GO_VERSION)

ARCH ?= $(shell go env GOARCH)
PLATFORM ?= linux/$(ARCH)
PLATFORMS ?= linux/amd64,linux/arm64

# Kubernetes versions under test: the EKS standard support window. Each entry
# is a kindest/node tag with the digest built by the pinned kind version.
K8S_VERSIONS := \
	v1.34.11@sha256:44e222ee2132dab25ff87301682f89eb82c7880ea3a1bf543bfe9708fd08d67d \
	v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 \
	v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
K8S_VERSION ?= $(lastword $(K8S_VERSIONS))
K8S_MINOR = $(shell sed -E 's/^v([0-9]+\.[0-9]+).*/\1/' <<< '$(K8S_VERSION)')

# ---------------------------------------------------------------------------
# Tools (pinned in tools/)
# ---------------------------------------------------------------------------

include tools/versions.env

GO_TOOLS := helm kind helm-docs yq kustomize kubeconform cosign crane govulncheck
TOOL_PKG_helm := helm.sh/helm/v4/cmd/helm
TOOL_PKG_kind := sigs.k8s.io/kind
TOOL_PKG_helm-docs := github.com/norwoodj/helm-docs/cmd/helm-docs
TOOL_PKG_yq := github.com/mikefarah/yq/v4
TOOL_PKG_kustomize := sigs.k8s.io/kustomize/kustomize/v5
TOOL_PKG_kubeconform := github.com/yannh/kubeconform/cmd/kubeconform
TOOL_PKG_cosign := github.com/sigstore/cosign/v3/cmd/cosign
TOOL_PKG_crane := github.com/google/go-containerregistry/cmd/crane
TOOL_PKG_govulncheck := golang.org/x/vuln/cmd/govulncheck
DOWNLOADED_TOOLS := golangci-lint kubectl helm-unittest

HELM := $(TOOLS_DIR)/helm
KIND := $(TOOLS_DIR)/kind
HELM_DOCS := $(TOOLS_DIR)/helm-docs
YQ := $(TOOLS_DIR)/yq
KUSTOMIZE := $(TOOLS_DIR)/kustomize
KUBECONFORM := $(TOOLS_DIR)/kubeconform
COSIGN := $(TOOLS_DIR)/cosign
CRANE := $(TOOLS_DIR)/crane
GOVULNCHECK := $(TOOLS_DIR)/govulncheck
ACTIONLINT := $(TOOLS_DIR)/actionlint
GINKGO := $(TOOLS_DIR)/ginkgo
GOLANGCI_LINT := $(TOOLS_DIR)/golangci-lint
KUBECTL := $(TOOLS_DIR)/kubectl
HELM_UNITTEST := $(TOOLS_DIR)/helm-unittest
CERT_MANAGER_MANIFEST := $(TOOLS_DIR)/cert-manager.yaml
DOCS_VENV := $(CACHE)/docs-venv

HELM_VERSION := $(shell awk '$$1 == "helm.sh/helm/v4" { print $$2; exit }' tools/go.mod)
GINKGO_VERSION := $(shell awk '$$1 == "github.com/onsi/ginkgo/v2" { print $$2; exit }' go.mod)

# Helm keeps its configuration and caches inside the repository.
HELM_ENV := HELM_CACHE_HOME=$(CURDIR)/$(CACHE)/helm/cache HELM_CONFIG_HOME=$(CURDIR)/$(CACHE)/helm/config HELM_DATA_HOME=$(CURDIR)/$(CACHE)/helm/data

# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

# Delivered images: tagged with IMAGE_TAG, rebuilt for every channel.
IMAGES ?= controller controller-chroot kube-webhook-certgen custom-error-pages
CONTROLLER_IMAGE := $(REGISTRY)/controller
CERTGEN_IMAGE := $(REGISTRY)/kube-webhook-certgen
ERROR_PAGES_IMAGE := $(REGISTRY)/custom-error-pages
E2E_IMAGE := $(PROJECT)-e2e:$(IMAGE_TAG)

# Dependency images: content addressed (src-<hash of their inputs>), built once
# per source state and reused. Listed in build order.
DEPS ?= nginx e2e-test-runner e2e-test-echo httpbun fastcgi-helloserver cfssl
DEPS_ALL := nginx e2e-test-runner e2e-test-echo httpbun fastcgi-helloserver cfssl
DEPS_PLATFORMS := linux/amd64 linux/arm64

CONTENT_TAG := tools/content-tag.sh
NGINX_TAG := $(shell $(CONTENT_TAG) images/nginx)
RUNNER_TAG := $(shell $(CONTENT_TAG) images/test-runner -- $(NGINX_TAG) $(GO_VERSION) $(GINKGO_VERSION) $(HELM_VERSION))
ECHO_TAG := $(shell $(CONTENT_TAG) images/e2e-test-echo -- $(NGINX_TAG))
HTTPBUN_TAG := $(shell $(CONTENT_TAG) images/httpbun -- $(GO_VERSION))
FASTCGI_TAG := $(shell $(CONTENT_TAG) images/fastcgi-helloserver -- $(GO_VERSION))
CFSSL_TAG := $(shell $(CONTENT_TAG) images/cfssl -- $(GO_VERSION))

NGINX_IMAGE := $(REGISTRY)/nginx:$(NGINX_TAG)
BASE_IMAGE := $(NGINX_IMAGE)
RUNNER_IMAGE := $(REGISTRY)/e2e-test-runner:$(RUNNER_TAG)
ECHO_IMAGE := $(REGISTRY)/e2e-test-echo:$(ECHO_TAG)
HTTPBUN_IMAGE := $(REGISTRY)/httpbun:$(HTTPBUN_TAG)
FASTCGI_IMAGE := $(REGISTRY)/fastcgi-helloserver:$(FASTCGI_TAG)
CFSSL_IMAGE := $(REGISTRY)/cfssl:$(CFSSL_TAG)

DEP_DIR_nginx := images/nginx
DEP_DIR_e2e-test-runner := images/test-runner
DEP_DIR_e2e-test-echo := images/e2e-test-echo
DEP_DIR_httpbun := images/httpbun
DEP_DIR_fastcgi-helloserver := images/fastcgi-helloserver
DEP_DIR_cfssl := images/cfssl
DEP_IMAGE_nginx := $(NGINX_IMAGE)
DEP_IMAGE_e2e-test-runner := $(RUNNER_IMAGE)
DEP_IMAGE_e2e-test-echo := $(ECHO_IMAGE)
DEP_IMAGE_httpbun := $(HTTPBUN_IMAGE)
DEP_IMAGE_fastcgi-helloserver := $(FASTCGI_IMAGE)
DEP_IMAGE_cfssl := $(CFSSL_IMAGE)
DEP_ARGS_nginx :=
DEP_ARGS_e2e-test-runner := --build-arg GOLANG_VERSION=$(GO_VERSION) --build-arg GINKGO_VERSION=$(GINKGO_VERSION) --build-arg HELM_VERSION=$(HELM_VERSION)
DEP_ARGS_e2e-test-echo :=
DEP_ARGS_httpbun := --build-arg GOLANG_VERSION=$(GO_VERSION)
DEP_ARGS_fastcgi-helloserver := --build-arg GOLANG_VERSION=$(GO_VERSION)
DEP_ARGS_cfssl := --build-arg GOLANG_VERSION=$(GO_VERSION)
# Images built FROM the nginx base.
DEPS_ON_BASE := e2e-test-runner e2e-test-echo

DOCKER_CACHE_ARGS ?=

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

E2E_VARIANT ?= default
FOCUS ?=
E2E_NODES ?= 7
E2E_CHECK_LEAKS ?=
SKIP_BUILD ?=
BASE ?= origin/main

##@ General

.PHONY: help
help: ## Show this help
	@awk 'BEGIN { FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m [VAR=value ...]\n" } \
		/^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

.PHONY: version
version: ## Print VERSION, CHANNEL and derived IMAGE_TAG/CHART_VERSION/APP_VERSION/DOCS_VERSION
	@printf '%-14s %s\n' VERSION '$(VERSION)' CHANNEL '$(CHANNEL)' IMAGE_TAG '$(IMAGE_TAG)' \
		CHART_VERSION '$(CHART_VERSION)' APP_VERSION '$(APP_VERSION)' DOCS_VERSION '$(DOCS_VERSION)' \
		GO_VERSION '$(GO_VERSION)' COMMIT '$(COMMIT)'

.PHONY: tools
tools: $(addprefix $(TOOLS_DIR)/,$(GO_TOOLS) actionlint ginkgo $(DOWNLOADED_TOOLS)) $(CERT_MANAGER_MANIFEST) ## Build/download all pinned tools into .cache/tools

$(addprefix $(TOOLS_DIR)/,$(GO_TOOLS)): $(TOOLS_DIR)/%: tools/go.mod tools/go.sum
	go -C tools build -o $@ $(TOOL_PKG_$*)

$(ACTIONLINT): tools/actionlint/go.mod tools/actionlint/go.sum
	go -C tools/actionlint build -o $@ github.com/rhysd/actionlint/cmd/actionlint

$(GINKGO): go.mod go.sum
	go build -o $@ github.com/onsi/ginkgo/v2/ginkgo

$(addprefix $(TOOLS_DIR)/,$(DOWNLOADED_TOOLS)): $(TOOLS_DIR)/%: tools/versions.env
	tools/install.sh $* $(TOOLS_DIR)
	touch $@

$(CERT_MANAGER_MANIFEST): tools/versions.env
	tools/install.sh cert-manager $(TOOLS_DIR)
	touch $@

$(DOCS_VENV)/bin/mkdocs: docs/requirements.txt
	python3 -m venv $(DOCS_VENV)
	$(DOCS_VENV)/bin/pip install --quiet --require-virtualenv -r docs/requirements.txt
	touch $@

.PHONY: clean
clean: ## Remove dist/, build outputs and local images built by this Makefile
	rm -rf $(DIST) rootfs/bin site test/e2e/e2e.test test/junitreports
	-docker image rm --force $(foreach i,controller controller-chroot kube-webhook-certgen custom-error-pages,$(REGISTRY)/$(i):$(IMAGE_TAG)) $(E2E_IMAGE) 2>/dev/null

.PHONY: check
check: code-lint test-unit test-unit-lua docs-verify helm-docs-verify helm-lint helm-test ## Fast local checks: code-lint test-unit test-unit-lua docs-verify helm-docs-verify helm-lint helm-test

.PHONY: print-k8s-versions
print-k8s-versions:
	@printf '%s\n' $(K8S_VERSIONS) | jq -R . | jq -cs .

.PHONY: print-deps-platforms
print-deps-platforms:
	@jq -cn '[{arch: "amd64", platform: "linux/amd64", runner: "ubuntu-latest"}, {arch: "arm64", platform: "linux/arm64", runner: "ubuntu-24.04-arm"}]'

.PHONY: print-%
print-%:
	@echo '$($*)'

##@ Code

.PHONY: code-fmt
code-fmt: $(GOLANGCI_LINT) ## Format Go code
	$(GOLANGCI_LINT) fmt

.PHONY: code-lint
code-lint: $(GOLANGCI_LINT) $(ACTIONLINT) deps-runner ## golangci-lint, luacheck, actionlint
	$(GOLANGCI_LINT) run
	tools/run-in-container.sh $(RUNNER_IMAGE) tools/lint-lua.sh
	$(ACTIONLINT)

.PHONY: code-lint-commits
code-lint-commits: ## Check Conventional Commits in BASE..HEAD (BASE ?= origin/main)
	tools/lint-commits.sh '$(BASE)'

.PHONY: code-build
code-build: ## Build controller, dbg, wait-shutdown (GOOS=linux, ARCH) into rootfs/bin/$(ARCH)
	for cmd in nginx:nginx-ingress-controller dbg:dbg waitshutdown:wait-shutdown; do \
		GOOS=linux GOARCH=$(ARCH) CGO_ENABLED=0 go build -trimpath -buildvcs=false \
			-ldflags '-buildid= -s -w $(VERSION_LDFLAGS)' \
			-o rootfs/bin/$(ARCH)/$${cmd#*:} ./cmd/$${cmd%%:*}; \
	done

VERSION_LDFLAGS = -X $(GO_PACKAGE)/version.RELEASE=$(VERSION) -X $(GO_PACKAGE)/version.COMMIT=$(COMMIT) -X $(GO_PACKAGE)/version.REPO=$(REPO_URL)

##@ Test

.PHONY: test-unit
test-unit: deps-runner ## Go unit tests: root module (excluding test/e2e, images, docs/examples) + images/{kube-webhook-certgen,custom-error-pages,fastcgi-helloserver}/rootfs
	tools/run-in-container.sh $(RUNNER_IMAGE) test/test.sh

.PHONY: test-unit-lua
test-unit-lua: deps-runner ## Lua unit tests inside e2e-test-runner
	tools/run-in-container.sh $(RUNNER_IMAGE) test/test-lua.sh

##@ Images

.PHONY: docker-build-deps
docker-build-deps: ## Ensure every dependency image src-* (DEPS ?= nginx e2e-test-runner e2e-test-echo httpbun fastcgi-helloserver cfssl): pull if published, otherwise build for the host platform, in dependency order
	for dep in $(filter $(DEPS),$(DEPS_ALL)); do \
		$(MAKE) --no-print-directory deps-ensure-$$dep; \
	done

# Make a dependency image available locally: present, pulled or built.
deps-ensure-%:
	image='$(DEP_IMAGE_$*)'; \
	if docker image inspect "$$image" >/dev/null 2>&1; then \
		echo "$$image: present"; \
	elif tools/image-exists.sh "$$image" $(PLATFORM); then \
		docker pull --platform $(PLATFORM) "$$image"; \
	else \
		rc=$$?; [[ $$rc -eq 1 || $$rc -eq 3 ]] || exit $$rc; \
		$(MAKE) --no-print-directory deps-build-$*; \
	fi

# Build one dependency image for the host platform into the local image store.
deps-build-%:
	$(if $(filter $*,$(DEPS_ON_BASE)),$(MAKE) --no-print-directory deps-ensure-nginx)
	docker buildx build --builder default --load \
		--platform $(PLATFORM) \
		$(call dep-build-args,$*) \
		--tag $(DEP_IMAGE_$*) \
		$(DEP_DIR_$*)/rootfs

dep-build-args = \
	$(DEP_ARGS_$(1)) \
	$(if $(filter $(1),$(DEPS_ON_BASE)),--build-arg BASE_IMAGE=$(or $(DEP_BASE_IMAGE),$(BASE_IMAGE))) \
	$(if $(wildcard $(DEP_DIR_$(1))/build-args.env),$(foreach a,$(shell grep -Ev '^[[:space:]]*(\#|$$)' $(DEP_DIR_$(1))/build-args.env),--build-arg $(a))) \
	--label org.opencontainers.image.source=$(REPO_URL) \
	--label org.opencontainers.image.revision=$(COMMIT) \
	--label org.opencontainers.image.licenses=Apache-2.0 \
	--label org.opencontainers.image.title=$(1) \
	--label org.opencontainers.image.version=$(notdir $(subst :,/,$(DEP_IMAGE_$(1))))

# The runner image backs code-lint, test-unit and test-unit-lua.
.PHONY: deps-runner
deps-runner:
	$(MAKE) --no-print-directory docker-build-deps DEPS=e2e-test-runner

SAVE ?= deps controller controller-chroot kube-webhook-certgen e2e
SAVE_IMAGES_deps = $(foreach d,$(DEPS),$(DEP_IMAGE_$(d)))
SAVE_IMAGES_controller = $(CONTROLLER_IMAGE):$(IMAGE_TAG)
SAVE_IMAGES_controller-chroot = $(CONTROLLER_IMAGE)-chroot:$(IMAGE_TAG)
SAVE_IMAGES_kube-webhook-certgen = $(CERTGEN_IMAGE):$(IMAGE_TAG)
SAVE_IMAGES_custom-error-pages = $(ERROR_PAGES_IMAGE):$(IMAGE_TAG)
SAVE_IMAGES_e2e = $(E2E_IMAGE)

.PHONY: docker-save
docker-save: ## Save images listed by SAVE ?= (default: everything e2e needs) into dist/images-<name>.tar
	mkdir -p $(DIST)
	$(foreach s,$(SAVE),docker save --output $(DIST)/images-$(s).tar $(SAVE_IMAGES_$(s));)

.PHONY: docker-load
docker-load: ## Load dist/images-*.tar
	for f in $(wildcard $(DIST)/images-*.tar); do docker load --input "$$f"; done

##@ Helm

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
helm-lint: helm-stage $(HELM) $(KUBECONFORM) ## helm lint --strict + kubeconform on the staged chart for every ci values file
	for values in $(STAGED_CHART)/ci/*-values.yaml; do \
		echo "--- $$values"; \
		$(HELM_ENV) $(HELM) lint --strict --values "$$values" $(STAGED_CHART); \
		$(HELM_ENV) $(HELM) template $(RELEASE_NAME) $(STAGED_CHART) --namespace $(NAMESPACE) \
			--kube-version $(K8S_MINOR) --values "$$values" | \
			$(KUBECONFORM) -strict -ignore-missing-schemas -summary -kubernetes-version $(K8S_MINOR).0; \
	done

.PHONY: helm-test
helm-test: $(HELM_UNITTEST) ## helm-unittest
	$(HELM_UNITTEST) --file 'tests/**/*_test.yaml' $(CHART_DIR)

.PHONY: helm-template
helm-template: helm-stage $(HELM) ## Render the staged chart into dist/rendered/
	mkdir -p $(DIST)/rendered
	$(HELM_ENV) $(HELM) template $(RELEASE_NAME) $(STAGED_CHART) --namespace $(NAMESPACE) \
		--kube-version $(K8S_MINOR) > $(DIST)/rendered/$(CHART_NAME).yaml
	@echo "rendered $(DIST)/rendered/$(CHART_NAME).yaml"

.PHONY: helm-docs-generate
helm-docs-generate: $(HELM_DOCS) ## Regenerate charts/ingress-nginx-neo/README.md
	$(HELM_DOCS) --chart-search-root charts

.PHONY: helm-docs-verify
helm-docs-verify: helm-docs-generate ## Fail if the chart README is stale
	git diff --exit-code -- $(CHART_DIR)/README.md || \
		{ echo "$(CHART_DIR)/README.md is stale: run make helm-docs-generate" >&2; exit 1; }

# Image digests published by docker-publish: <name>=<repository>@<digest>.
DIGESTS_FILE := $(DIST)/digests.env
HELM_REGISTRY_CONFIG ?= $(or $(DOCKER_CONFIG),$(HOME)/.docker)/config.json

.PHONY: helm-package
helm-package: helm-stage $(HELM) $(YQ) ## Stage, (release: pin digests), package into dist/
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
helm-publish: $(HELM) $(COSIGN) ## Push dist/*.tgz to CHART_REGISTRY and sign it
	test -s $(CHART_PACKAGE) || { echo "$(CHART_PACKAGE) is missing: run make helm-package first" >&2; exit 1; }
	$(HELM_ENV) HELM_REGISTRY_CONFIG=$(HELM_REGISTRY_CONFIG) $(HELM) push $(CHART_PACKAGE) $(CHART_REGISTRY) 2>&1 | tee $(DIST)/helm-push.log
	digest="$$(sed -n 's/^Digest: //p' $(DIST)/helm-push.log)"; \
	test -n "$$digest"; \
	echo "chart=$(REGISTRY)/charts/$(CHART_NAME)@$$digest" > $(DIST)/chart-digest.env; \
	$(COSIGN) sign --yes "$(REGISTRY)/charts/$(CHART_NAME)@$$digest"

##@ Manifests

MANIFESTS_K8S_MINOR = $(shell sed -E 's/^v([0-9]+\.[0-9]+).*/\1/' <<< '$(firstword $(K8S_VERSIONS))')

.PHONY: manifests-generate
manifests-generate: helm-package $(HELM) $(KUSTOMIZE) ## Render deploy-<provider>.yaml from the packaged chart into dist/manifests (+ sha256)
	$(HELM_ENV) HELM=$(HELM) KUSTOMIZE=$(KUSTOMIZE) RELEASE_NAME=$(RELEASE_NAME) NAMESPACE=$(NAMESPACE) \
		CHART_NAME=$(CHART_NAME) K8S_MINOR=$(MANIFESTS_K8S_MINOR) \
		tools/generate-manifests.sh $(CHART_PACKAGE) $(DIST)/manifests

##@ Docs

.PHONY: docs-generate
docs-generate: ## Regenerate annotations-risk.md and cli-arguments.md
	go run ./cmd/annotations -output docs/user-guide/nginx-configuration/annotations-risk.md

.PHONY: docs-verify
docs-verify: docs-generate ## Fail if generated docs are stale
	git diff --exit-code -- docs/ || \
		{ echo "generated docs are stale: run make docs-generate" >&2; exit 1; }

.PHONY: docs-build
docs-build: $(DOCS_VENV)/bin/mkdocs ## mkdocs build --strict
	$(DOCS_VENV)/bin/mkdocs build --strict --site-dir $(DIST)/site

.PHONY: docs-serve
docs-serve: $(DOCS_VENV)/bin/mkdocs ## Serve the site locally with live reload
	$(DOCS_VENV)/bin/mkdocs serve

##@ Security

.PHONY: security-dependency-scan
security-dependency-scan: $(GOVULNCHECK) ## govulncheck for all Go modules
	$(GOVULNCHECK) ./...
	for mod in $(GO_IMAGE_MODULES); do (cd "$$mod" && $(GOVULNCHECK) ./...); done

GO_IMAGE_MODULES := images/kube-webhook-certgen/rootfs images/custom-error-pages/rootfs images/fastcgi-helloserver/rootfs
