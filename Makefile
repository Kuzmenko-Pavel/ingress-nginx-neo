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

# Tools live in a directory named after the hash of their pins, so a changed
# pin builds a new set and a restored CI cache is used as is.
TOOLS_HASH := $(shell cat tools/go.mod tools/go.sum tools/actionlint/go.mod tools/actionlint/go.sum tools/versions.env | \
	{ sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-12)
TOOLS_DIR := $(CURDIR)/$(CACHE)/tools/$(TOOLS_HASH)-go$(GO_VERSION)

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
GINKGO = $(CURDIR)/$(CACHE)/tools/ginkgo-$(GINKGO_VERSION)-go$(GO_VERSION)/ginkgo
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
# Inputs: the image build context (rootfs/), its build-args.env and every
# value passed as a build argument. Documentation files are not inputs.
dep-inputs = $(wildcard images/$(1)/rootfs images/$(1)/build-args.env)
NGINX_TAG := $(shell $(CONTENT_TAG) $(call dep-inputs,nginx))
RUNNER_TAG := $(shell $(CONTENT_TAG) $(call dep-inputs,test-runner) -- $(NGINX_TAG) $(GO_VERSION) $(GINKGO_VERSION) $(HELM_VERSION))
ECHO_TAG := $(shell $(CONTENT_TAG) $(call dep-inputs,e2e-test-echo) -- $(NGINX_TAG))
HTTPBUN_TAG := $(shell $(CONTENT_TAG) $(call dep-inputs,httpbun) -- $(GO_VERSION))
FASTCGI_TAG := $(shell $(CONTENT_TAG) $(call dep-inputs,fastcgi-helloserver) -- $(GO_VERSION))
CFSSL_TAG := $(shell $(CONTENT_TAG) $(call dep-inputs,cfssl) -- $(GO_VERSION))

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
DEP_ARGS_nginx := --secret id=github_token,env=GITHUB_TOKEN
DEP_ARGS_e2e-test-runner := --build-arg GOLANG_VERSION=$(GO_VERSION) --build-arg GINKGO_VERSION=$(GINKGO_VERSION) --build-arg HELM_VERSION=$(HELM_VERSION)
DEP_ARGS_e2e-test-echo :=
DEP_ARGS_httpbun := --build-arg GOLANG_VERSION=$(GO_VERSION)
DEP_ARGS_fastcgi-helloserver := --build-arg GOLANG_VERSION=$(GO_VERSION)
DEP_ARGS_cfssl := --build-arg GOLANG_VERSION=$(GO_VERSION)
# Images built FROM the nginx base.
DEPS_ON_BASE := e2e-test-runner e2e-test-echo
# Images whose build downloads sources from GitHub with GITHUB_TOKEN (BuildKit
# secret github_token): anonymous clones are refused or rate limited on some
# networks. The token is not an image input.
DEPS_GITHUB_TOKEN := nginx
export GITHUB_TOKEN

define github-token-check
if [ -z "$${GITHUB_TOKEN:-}" ]; then \
	echo "Error: GITHUB_TOKEN is not set" >&2; \
	echo 'Please add: export GITHUB_TOKEN="$$(gh auth token)"' >&2; \
	exit 1; \
fi
endef

# Digests published by docker-publish and docker-promote: <name>=<repository>@<digest>.
DIGESTS_FILE := $(DIST)/digests.env

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

E2E_VARIANT ?= default
FOCUS ?=
E2E_NODES ?= 7
E2E_CHECK_LEAKS ?=
SKIP_BUILD ?=
BASE ?= origin/main


# Colors of make help; empty when tput is missing.
GREEN  := $(shell tput -Txterm setaf 2 2>/dev/null || true)
YELLOW := $(shell tput -Txterm setaf 3 2>/dev/null || true)
GRAY   := $(shell tput -Txterm setaf 6 2>/dev/null || true)
RESET  := $(shell tput -Txterm sgr0 2>/dev/null || true)
TARGET_MAX_CHAR_NUM ?= 30

# A target is listed when the line above it is "## <description>"; a
# description ending in "| <group>" starts a new group. Targets without such a
# line are internal.
.PHONY: help
## Show this help. | General
help:
	@printf '\nUsage:\n\n  %smake%s %s<target>%s [VAR=value ...]\n\nTargets:\n' '$(YELLOW)' '$(RESET)' '$(GREEN)' '$(RESET)'
	@awk -v width='$(TARGET_MAX_CHAR_NUM)' -v yellow='$(YELLOW)' -v green='$(GREEN)' -v gray='$(GRAY)' -v reset='$(RESET)' ' \
		/^[a-zA-Z0-9_-]+:/ && last ~ /^## / { \
			text = substr(last, 4); group = ""; \
			bar = index(text, "|"); \
			if (bar > 0) { group = substr(text, bar + 1); text = substr(text, 1, bar - 1); } \
			sub(/[ \t]+$$/, "", text); sub(/^[ \t]+/, "", group); \
			if (group != "") printf "\n %s%s:%s\n\n", gray, group, reset; \
			printf "  %s%-" width "s%s %s%s%s\n", yellow, substr($$1, 1, index($$1, ":") - 1), reset, green, text, reset; \
		} \
		{ last = $$0 }' $(MAKEFILE_LIST)
	@echo

.PHONY: version
## Print VERSION, CHANNEL and derived IMAGE_TAG/CHART_VERSION/APP_VERSION/DOCS_VERSION.
version:
	@printf '%-14s %s\n' VERSION '$(VERSION)' CHANNEL '$(CHANNEL)' IMAGE_TAG '$(IMAGE_TAG)' \
		CHART_VERSION '$(CHART_VERSION)' APP_VERSION '$(APP_VERSION)' DOCS_VERSION '$(DOCS_VERSION)' \
		GO_VERSION '$(GO_VERSION)' COMMIT '$(COMMIT)'

.PHONY: tools
## Build/download all pinned tools into .cache/tools.
tools: $(addprefix $(TOOLS_DIR)/,$(GO_TOOLS) actionlint $(DOWNLOADED_TOOLS)) $(GINKGO) $(CERT_MANAGER_MANIFEST)

$(addprefix $(TOOLS_DIR)/,$(GO_TOOLS)): $(TOOLS_DIR)/%:
	go -C tools build -o $@ $(TOOL_PKG_$*)

$(ACTIONLINT):
	go -C tools/actionlint build -o $@ github.com/rhysd/actionlint/cmd/actionlint

$(GINKGO):
	go build -o $@ github.com/onsi/ginkgo/v2/ginkgo

$(addprefix $(TOOLS_DIR)/,$(DOWNLOADED_TOOLS)): $(TOOLS_DIR)/%:
	tools/install.sh $* $(TOOLS_DIR)

$(CERT_MANAGER_MANIFEST):
	tools/install.sh cert-manager $(TOOLS_DIR)

$(DOCS_VENV)/bin/mkdocs: docs/requirements.txt
	python3 -m venv $(DOCS_VENV)
	$(DOCS_VENV)/bin/pip install --quiet --require-virtualenv -r docs/requirements.txt
	touch $@

.PHONY: clean
## Remove dist/, build outputs and local images built by this Makefile.
clean:
	rm -rf $(DIST) rootfs/bin site test/e2e/e2e.test test/junitreports
	-docker image rm --force $(foreach i,controller controller-chroot kube-webhook-certgen custom-error-pages,$(REGISTRY)/$(i):$(IMAGE_TAG)) $(E2E_IMAGE) 2>/dev/null

.PHONY: check
## Fast local checks: code-lint test-unit test-unit-lua docs-verify helm-docs-verify helm-lint helm-test.
check: code-lint test-unit test-unit-lua docs-verify helm-docs-verify helm-lint helm-test

# CI matrices: [{"version": "<kindest/node tag@digest>", "name": "<tag>"}].
.PHONY: print-k8s-versions
print-k8s-versions:
	@printf '%s\n' $(K8S_VERSIONS) | jq -R '{version: ., name: (. | split("@")[0])}' | jq -cs .

# "true" when a dependency image src-* is not published for every platform.
.PHONY: print-deps-missing
print-deps-missing:
	@missing=false; \
	for image in $(foreach d,$(DEPS_ALL),$(DEP_IMAGE_$(d))); do \
		rc=0; tools/image-exists.sh "$$image" $(DEPS_PLATFORMS) 2>/dev/null || rc=$$?; \
		case $$rc in 0) ;; 1 | 3) missing=true ;; *) echo "cannot query $$image" >&2; exit $$rc ;; esac; \
	done; \
	echo "$$missing"

.PHONY: print-scan-images
print-scan-images:
	@printf '%s\n' $(SCAN_IMAGES) | jq -R . | jq -cs .

# The "CI result" check: RESULTS is the JSON of the needs context of the job.
.PHONY: ci-result
ci-result:
	@jq -r 'to_entries[] | "\(.key): \(.value.result)"' <<< "$$RESULTS"
	@if jq -e 'to_entries | any(.value.result == "failure" or .value.result == "cancelled")' <<< "$$RESULTS" > /dev/null; then \
		echo "at least one job failed or was cancelled" >&2; exit 1; \
	fi

.PHONY: print-deps-platforms
print-deps-platforms:
	@jq -cn '[{arch: "amd64", platform: "linux/amd64", runner: "ubuntu-latest"}, {arch: "arm64", platform: "linux/arm64", runner: "ubuntu-24.04-arm"}]'

.PHONY: print-%
print-%:
	@echo '$($*)'


.PHONY: code-fmt
## Format Go code. | Code
code-fmt: $(GOLANGCI_LINT)
	$(GOLANGCI_LINT) fmt

.PHONY: code-lint
## golangci-lint, luacheck, actionlint.
code-lint: $(GOLANGCI_LINT) $(ACTIONLINT) deps-runner
	$(GOLANGCI_LINT) run
	tools/run-in-container.sh $(RUNNER_IMAGE) tools/lint-lua.sh
	$(ACTIONLINT)

.PHONY: code-lint-commits
## Check Conventional Commits in BASE..HEAD (BASE ?= origin/main).
code-lint-commits:
	tools/lint-commits.sh '$(BASE)'

.PHONY: code-build
## Build controller, dbg, wait-shutdown (GOOS=linux, ARCH) into rootfs/bin/$(ARCH).
code-build:
	for cmd in nginx:nginx-ingress-controller dbg:dbg waitshutdown:wait-shutdown; do \
		GOOS=linux GOARCH=$(ARCH) CGO_ENABLED=0 go build -trimpath -buildvcs=false \
			-ldflags '-buildid= -s -w $(VERSION_LDFLAGS)' \
			-o rootfs/bin/$(ARCH)/$${cmd#*:} ./cmd/$${cmd%%:*}; \
	done

VERSION_LDFLAGS = -X $(GO_PACKAGE)/version.RELEASE=$(VERSION) -X $(GO_PACKAGE)/version.COMMIT=$(COMMIT) -X $(GO_PACKAGE)/version.REPO=$(REPO_URL)

PLUGIN_PLATFORMS ?= linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64
PLUGIN_DIR := $(DIST)/plugin

.PHONY: code-build-plugin
## Build kubectl-ingress_nginx_neo for PLUGIN_PLATFORMS into dist/plugin (+ checksums.sha256, krew manifest).
code-build-plugin:
	VERSION=$(VERSION) LDFLAGS='$(VERSION_LDFLAGS)' RELEASE_URL=$(REPO_URL)/releases/download/$(VERSION) \
		tools/build-plugin.sh $(PLUGIN_DIR) $(PLUGIN_PLATFORMS)

.PHONY: code-sign-plugin
## cosign sign-blob the plugin checksums (CHANNEL=release).
code-sign-plugin: $(COSIGN)
	$(if $(filter release,$(CHANNEL)),,$(error code-sign-plugin needs CHANNEL=release))
	$(COSIGN) sign-blob --yes --bundle $(PLUGIN_DIR)/checksums.sha256.sigstore.json $(PLUGIN_DIR)/checksums.sha256


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
	$(if $(filter-out default chroot,$(E2E_VARIANT)),$(error E2E_VARIANT must be default or chroot))
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
## Install the chart on kind for every ci/*-values.yaml (SKIP_BUILD=1 supported).
test-e2e-chart: helm-package $(KIND) $(KUBECTL) $(HELM) $(CERT_MANAGER_MANIFEST)
ifeq ($(SKIP_BUILD),)
	$(MAKE) --no-print-directory docker-build IMAGES="controller kube-webhook-certgen custom-error-pages"
endif
	$(HELM_ENV) KIND=$(KIND) KUBECTL=$(KUBECTL) HELM=$(HELM) KIND_CLUSTER_NAME=$(PROJECT)-chart \
	K8S_VERSION=$(K8S_VERSION) CERT_MANAGER_MANIFEST=$(CERT_MANAGER_MANIFEST) \
	RELEASE_NAME=$(RELEASE_NAME) NAMESPACE=$(NAMESPACE) \
	LOAD_IMAGES='$(CONTROLLER_IMAGE):$(IMAGE_TAG) $(CERTGEN_IMAGE):$(IMAGE_TAG) $(ERROR_PAGES_IMAGE):$(IMAGE_TAG)' \
	IMAGE_REGISTRY=$(REGISTRY_HOST) IMAGE_PREFIX=$(REGISTRY_PATH) IMAGE_TAG=$(IMAGE_TAG) \
		tools/e2e-chart.sh $(CHART_PACKAGE) $(STAGED_CHART)/ci

.PHONY: test-e2e-certgen
## kube-webhook-certgen e2e on kind.
test-e2e-certgen: $(KIND) $(KUBECTL)
	KIND=$(KIND) KUBECTL=$(KUBECTL) KIND_CLUSTER_NAME=$(PROJECT)-certgen K8S_VERSION=$(K8S_VERSION) \
		tools/e2e-certgen.sh


.PHONY: docker-build-deps
## Ensure every dependency image src-* (DEPS ?= nginx e2e-test-runner e2e-test-echo httpbun fastcgi-helloserver cfssl): pull if published, otherwise build for the host platform, in dependency order. | Images
docker-build-deps:
	for dep in $(filter $(DEPS),$(DEPS_ALL)); do \
		$(MAKE) --no-print-directory deps-ensure-$$dep; \
	done

# Make a dependency image available locally: present, pulled or built.
deps-ensure-%:
	image='$(DEP_IMAGE_$*)'; \
	if docker image inspect "$$image" >/dev/null 2>&1; then \
		echo "$$image: present"; \
	else \
		rc=0; tools/image-exists.sh "$$image" $(PLATFORM) || rc=$$?; \
		case $$rc in \
			0) docker pull --platform $(PLATFORM) "$$image" ;; \
			1 | 3) $(MAKE) --no-print-directory deps-build-$* ;; \
			*) exit $$rc ;; \
		esac; \
	fi

# Build one dependency image for the host platform into the local image store.
deps-build-%:
	$(if $(filter $*,$(DEPS_GITHUB_TOKEN)),@$(github-token-check))
	$(if $(filter $*,$(DEPS_ON_BASE)),$(MAKE) --no-print-directory deps-ensure-nginx)
	docker buildx build --builder $(LOCAL_BUILDER) --load \
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

# Delivered images: build context, Dockerfile and build arguments.
IMAGE_CONTEXT_controller := rootfs
IMAGE_CONTEXT_controller-chroot := rootfs
IMAGE_CONTEXT_kube-webhook-certgen := images/kube-webhook-certgen/rootfs
IMAGE_CONTEXT_custom-error-pages := images/custom-error-pages/rootfs
IMAGE_DOCKERFILE_controller := rootfs/Dockerfile
IMAGE_DOCKERFILE_controller-chroot := rootfs/Dockerfile-chroot
IMAGE_DOCKERFILE_kube-webhook-certgen := images/kube-webhook-certgen/rootfs/Dockerfile
IMAGE_DOCKERFILE_custom-error-pages := images/custom-error-pages/rootfs/Dockerfile
IMAGE_DESCRIPTION_controller := NGINX Ingress controller for Kubernetes
IMAGE_DESCRIPTION_controller-chroot := NGINX Ingress controller for Kubernetes, NGINX in a chroot
IMAGE_DESCRIPTION_kube-webhook-certgen := Admission webhook certificate generator and patcher
IMAGE_DESCRIPTION_custom-error-pages := Default backend serving custom error pages
IMAGE_ON_BASE := controller controller-chroot

image-build-args = \
	--file $(IMAGE_DOCKERFILE_$(1)) \
	--build-arg GOLANG_VERSION=$(GO_VERSION) \
	--build-arg VERSION=$(IMAGE_TAG) \
	--build-arg COMMIT_SHA=$(COMMIT) \
	$(if $(filter $(1),$(IMAGE_ON_BASE)),--build-arg BASE_IMAGE=$(2)) \
	--label org.opencontainers.image.source=$(REPO_URL) \
	--label org.opencontainers.image.revision=$(COMMIT) \
	--label org.opencontainers.image.version=$(IMAGE_TAG) \
	--label org.opencontainers.image.licenses=Apache-2.0 \
	--label org.opencontainers.image.title=$(PROJECT)-$(1) \
	--label 'org.opencontainers.image.description=$(IMAGE_DESCRIPTION_$(1))'

.PHONY: docker-build
## Build delivered images for the host platform (IMAGES ?= controller controller-chroot kube-webhook-certgen custom-error-pages), load locally, tag IMAGE_TAG.
docker-build:
	$(if $(filter $(IMAGE_ON_BASE),$(IMAGES)),$(MAKE) --no-print-directory code-build deps-ensure-nginx)
	$(foreach i,$(IMAGES),docker buildx build --builder $(LOCAL_BUILDER) --load --platform $(PLATFORM) \
		$(call image-build-args,$(i),$(BASE_IMAGE)) \
		--tag $(REGISTRY)/$(i):$(IMAGE_TAG) $(IMAGE_CONTEXT_$(i))$(newline))

define newline


endef

.PHONY: docker-publish
## Build and push delivered images for PLATFORMS with IMAGE_TAG (CHANNEL=latest or release), write dist/digests.env.
docker-publish: $(CRANE)
	$(if $(filter dev,$(CHANNEL)),$(error docker-publish needs CHANNEL=latest or CHANNEL=release))
	$(foreach p,$(subst $(comma), ,$(PLATFORMS)),$(MAKE) --no-print-directory code-build ARCH=$(notdir $(p))$(newline))
	mkdir -p $(DIST)
	base="$(REGISTRY)/nginx@$$($(CRANE) digest $(NGINX_IMAGE))"; \
	for image in $(IMAGES); do \
		ref="$(REGISTRY)/$$image:$(IMAGE_TAG)"; \
		exists=1; \
		if [[ "$(CHANNEL)" == release ]]; then tools/image-exists.sh "$$ref" || exists=$$?; fi; \
		[[ $$exists -le 1 ]] || exit $$exists; \
		if [[ $$exists -eq 0 ]]; then \
			revision="$$($(CRANE) config "$$ref" | jq -r '.config.Labels["org.opencontainers.image.revision"] // ""')"; \
			if [[ "$$revision" != "$(COMMIT)" ]]; then \
				echo "$$ref is published from $$revision, not $(COMMIT); release tags are immutable" >&2; exit 1; \
			fi; \
			echo "$$ref: already published from $(COMMIT)"; \
		else \
			$(MAKE) --no-print-directory docker-publish-image-$$image BASE_REF="$$base"; \
		fi; \
		sed -i "/^$$image=/d" $(DIGESTS_FILE) 2>/dev/null || true; \
		echo "$$image=$(REGISTRY)/$$image@$$($(CRANE) digest "$$ref")" >> $(DIGESTS_FILE); \
	done
	cat $(DIGESTS_FILE)

docker-publish-image-%: $(CRANE)
	docker buildx build --push --platform $(PLATFORMS) \
		--sbom=true --provenance=mode=max \
		$(call image-build-args,$*,$(BASE_REF)) \
		$(call cache-args,$*) \
		--label org.opencontainers.image.base.name=$(BASE_REF) \
		--tag $(REGISTRY)/$*:$(IMAGE_TAG) $(IMAGE_CONTEXT_$*)

comma := ,
# DOCKER_CACHE=gha enables the GitHub Actions build cache, one scope per image and platform.
DOCKER_CACHE ?=
# Local builds use the docker-driver builder of the current context, which
# sees the images in the local store (default on Linux, desktop-linux on
# Docker Desktop).
LOCAL_BUILDER ?= $(shell docker context show 2>/dev/null || echo default)
cache-args = $(if $(DOCKER_CACHE),--cache-from type=$(DOCKER_CACHE),scope=$(1) --cache-to type=$(DOCKER_CACHE),mode=max,scope=$(1))

.PHONY: docker-publish-deps
## Build and push one PLATFORM of every missing dependency src-* by digest, in dependency order; digests into dist/digests/.
docker-publish-deps: $(CRANE)
	for dep in $(filter $(DEPS),$(DEPS_ALL)); do \
		$(MAKE) --no-print-directory deps-publish-$$dep; \
	done

deps-publish-%:
	image='$(DEP_IMAGE_$*)'; arch='$(notdir $(PLATFORM))'; \
	rc=0; tools/image-exists.sh "$$image" $(DEPS_PLATFORMS) || rc=$$?; \
	case $$rc in 0) echo "$$image: published"; exit 0 ;; 1) ;; *) exit $$rc ;; esac; \
	$(if $(filter $*,$(DEPS_GITHUB_TOKEN)),$(github-token-check);) \
	base=''; \
	if [[ " $(DEPS_ON_BASE) " == *" $* "* ]]; then \
		if tools/image-exists.sh '$(NGINX_IMAGE)' $(PLATFORM); then \
			base="$(REGISTRY)/nginx@$$($(CRANE) digest '$(NGINX_IMAGE)')"; \
		else \
			base="$(REGISTRY)/nginx@$$(cat $(DIST)/digests/nginx/$$arch)"; \
		fi; \
	fi; \
	mkdir -p $(DIST)/digests/$*; \
	docker buildx build --platform $(PLATFORM) \
		$(call dep-build-args,$*) \
		$${base:+--build-arg BASE_IMAGE=$$base --label org.opencontainers.image.base.name=$$base} \
		$(call cache-args,$*-$(notdir $(PLATFORM))) \
		--metadata-file $(DIST)/digests/$*/$$arch.json \
		--output type=image,name=$(REGISTRY)/$*,push-by-digest=true,name-canonical=true,push=true \
		$(DEP_DIR_$*)/rootfs; \
	jq -r '."containerimage.digest"' $(DIST)/digests/$*/$$arch.json > $(DIST)/digests/$*/$$arch

.PHONY: docker-publish-deps-manifest
## Create the multi-platform src-* indexes from dist/digests/ (no-op for published ones).
docker-publish-deps-manifest:
	for dep in $(filter $(DEPS),$(DEPS_ALL)); do \
		$(MAKE) --no-print-directory deps-manifest-$$dep; \
	done

deps-manifest-%:
	image='$(DEP_IMAGE_$*)'; \
	rc=0; tools/image-exists.sh "$$image" $(DEPS_PLATFORMS) || rc=$$?; \
	case $$rc in 0) echo "$$image: published"; exit 0 ;; 1) ;; *) exit $$rc ;; esac; \
	refs=(); \
	for platform in $(DEPS_PLATFORMS); do \
		file="$(DIST)/digests/$*/$${platform#*/}"; \
		test -s "$$file" || { echo "missing $$file: run docker-publish-deps PLATFORM=$$platform" >&2; exit 1; }; \
		refs+=("$(REGISTRY)/$*@$$(cat "$$file")"); \
	done; \
	docker buildx imagetools create \
		--annotation "index:org.opencontainers.image.source=$(REPO_URL)" \
		--annotation "index:org.opencontainers.image.licenses=Apache-2.0" \
		--tag "$$image" "$${refs[@]}"

.PHONY: docker-promote
## Point latest (CHANNEL=latest) / vX.Y.Z (CHANNEL=release) of every dependency image to its src-* digest.
docker-promote: $(CRANE)
	$(if $(filter dev,$(CHANNEL)),$(error docker-promote needs CHANNEL=latest or CHANNEL=release))
	mkdir -p $(DIST)
	for dep in $(DEPS_ALL); do \
		$(MAKE) --no-print-directory deps-promote-$$dep; \
	done

deps-promote-%:
	source='$(DEP_IMAGE_$*)'; target='$(REGISTRY)/$*:$(IMAGE_TAG)'; \
	digest="$$($(CRANE) digest "$$source")"; \
	exists=1; \
	if [[ "$(CHANNEL)" == release ]]; then tools/image-exists.sh "$$target" || exists=$$?; fi; \
	[[ $$exists -le 1 ]] || exit $$exists; \
	if [[ $$exists -eq 0 ]]; then \
		current="$$($(CRANE) digest "$$target")"; \
		[[ "$$current" == "$$digest" ]] || { echo "$$target points to $$current, not $$source ($$digest)" >&2; exit 1; }; \
		echo "$$target: already $$digest"; \
	else \
		docker buildx imagetools create --tag "$$target" "$$source"; \
	fi; \
	sed -i "/^$*=/d" $(DIGESTS_FILE) 2>/dev/null || true; \
	echo "$*=$(REGISTRY)/$*@$$digest" >> $(DIGESTS_FILE)

.PHONY: docker-sign
## cosign keyless sign every digest in dist/digests.env (delivered images, promoted dependency images).
docker-sign: $(COSIGN)
	test -s $(DIGESTS_FILE) || { echo "$(DIGESTS_FILE) is missing: run docker-publish/docker-promote first" >&2; exit 1; }
	cut -d= -f2- $(DIGESTS_FILE) | sort -u | xargs -r -n1 $(COSIGN) sign --yes --recursive

E2E_CONTEXT := $(DIST)/e2e-image

.PHONY: docker-build-e2e
## Build the e2e suite image (e2e.test of this commit, FROM e2e-test-runner); local only.
docker-build-e2e: $(GINKGO) helm-stage
	$(MAKE) --no-print-directory docker-build-deps DEPS="e2e-test-runner cfssl"
	rm -rf $(E2E_CONTEXT)
	mkdir -p $(E2E_CONTEXT)/charts
	cp -R test/e2e-image/. $(E2E_CONTEXT)/
	cp test/e2e/wait-for-nginx.sh $(E2E_CONTEXT)/
	cp -R $(STAGED_CHART) $(E2E_CONTEXT)/charts/
	cp test/e2e/settings/ocsp/*.json test/e2e/settings/ocsp/*.db $(E2E_CONTEXT)/
	GOOS=linux GOARCH=$(ARCH) CGO_ENABLED=0 $(GINKGO) build -trimpath -o $(CURDIR)/$(E2E_CONTEXT)/e2e.test ./test/e2e
	docker buildx build --builder $(LOCAL_BUILDER) --load --platform $(PLATFORM) \
		--build-arg E2E_BASE_IMAGE=$(RUNNER_IMAGE) \
		--build-arg CFSSL_IMAGE=$(CFSSL_IMAGE) \
		--tag $(E2E_IMAGE) $(E2E_CONTEXT)

# The runner image backs code-lint, test-unit and test-unit-lua.
.PHONY: deps-runner
deps-runner:
	$(MAKE) --no-print-directory docker-build-deps DEPS=e2e-test-runner

SAVE ?= deps controller controller-chroot kube-webhook-certgen custom-error-pages e2e
SAVE_IMAGES_deps = $(foreach d,$(DEPS),$(DEP_IMAGE_$(d)))
SAVE_IMAGES_controller = $(CONTROLLER_IMAGE):$(IMAGE_TAG)
SAVE_IMAGES_controller-chroot = $(CONTROLLER_IMAGE)-chroot:$(IMAGE_TAG)
SAVE_IMAGES_kube-webhook-certgen = $(CERTGEN_IMAGE):$(IMAGE_TAG)
SAVE_IMAGES_custom-error-pages = $(ERROR_PAGES_IMAGE):$(IMAGE_TAG)
SAVE_IMAGES_e2e = $(E2E_IMAGE)

.PHONY: docker-save
## Save images listed by SAVE ?= (default: everything e2e needs) into dist/images-<name>.tar.
docker-save:
	mkdir -p $(DIST)
	$(foreach s,$(SAVE),docker save --output $(DIST)/images-$(s).tar $(SAVE_IMAGES_$(s));)

.PHONY: docker-load
## Load dist/images-*.tar.
docker-load:
	for f in $(wildcard $(DIST)/images-*.tar); do docker load --input "$$f"; done


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
## helm-unittest.
helm-test: $(HELM_UNITTEST)
	$(HELM_UNITTEST) --file 'tests/**/*_test.yaml' $(CHART_DIR)

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
helm-publish: $(HELM) $(COSIGN)
	test -s $(CHART_PACKAGE) || { echo "$(CHART_PACKAGE) is missing: run make helm-package first" >&2; exit 1; }
	$(HELM_ENV) HELM_REGISTRY_CONFIG=$(HELM_REGISTRY_CONFIG) $(HELM) push $(CHART_PACKAGE) $(CHART_REGISTRY) 2>&1 | tee $(DIST)/helm-push.log
	digest="$$(sed -n 's/^Digest: //p' $(DIST)/helm-push.log)"; \
	test -n "$$digest"; \
	echo "chart=$(REGISTRY)/charts/$(CHART_NAME)@$$digest" > $(DIST)/chart-digest.env; \
	$(COSIGN) sign --yes "$(REGISTRY)/charts/$(CHART_NAME)@$$digest"


MANIFESTS_K8S_MINOR = $(shell sed -E 's/^v([0-9]+\.[0-9]+).*/\1/' <<< '$(firstword $(K8S_VERSIONS))')

.PHONY: manifests-generate
## Render deploy-<provider>.yaml from the packaged chart into dist/manifests (+ sha256). | Manifests
manifests-generate: helm-package $(HELM) $(KUSTOMIZE)
	$(HELM_ENV) HELM=$(HELM) KUSTOMIZE=$(KUSTOMIZE) RELEASE_NAME=$(RELEASE_NAME) NAMESPACE=$(NAMESPACE) \
		CHART_NAME=$(CHART_NAME) K8S_MINOR=$(MANIFESTS_K8S_MINOR) \
		tools/generate-manifests.sh $(CHART_PACKAGE) $(DIST)/manifests


.PHONY: docs-generate
## Regenerate annotations-risk.md and cli-arguments.md. | Docs
docs-generate:
	go run ./cmd/annotations -output docs/user-guide/nginx-configuration/annotations-risk.md
	go run ./cmd/flagsdoc -output docs/user-guide/cli-arguments.md

.PHONY: docs-verify
## Fail if generated docs are stale.
docs-verify: docs-generate
	git diff --exit-code -- docs/ || \
		{ echo "generated docs are stale: run make docs-generate" >&2; exit 1; }

.PHONY: docs-build
## mkdocs build --strict.
docs-build: $(DOCS_VENV)/bin/mkdocs
	$(DOCS_VENV)/bin/mkdocs build --strict --site-dir $(DIST)/site

.PHONY: docs-serve
## Serve the site locally with live reload.
docs-serve: $(DOCS_VENV)/bin/mkdocs
	$(DOCS_VENV)/bin/mkdocs serve

.PHONY: docs-publish
## Publish the docs version for CHANNEL via mike.
docs-publish: $(DOCS_VENV)/bin/mkdocs
	MIKE=$(DOCS_VENV)/bin/mike CHANNEL=$(CHANNEL) VERSION=$(VERSION) DOCS_VERSION=$(DOCS_VERSION) \
		tools/docs-publish.sh


GITHUB_REPO ?= Kuzmenko-Pavel/ingress-nginx-neo
DELIVERED_IMAGES := controller controller-chroot kube-webhook-certgen custom-error-pages
RELEASE_NOTES := $(DIST)/release-notes.md

.PHONY: release-tag
## Create the signed annotated release tag with a generated changelog (interactive). | Release
release-tag:
	RELEASE_TAG_PATTERN='$(RELEASE_TAG_PATTERN)' RELEASE_VERSION='$(RELEASE_VERSION)' NOTES_FROM='$(NOTES_FROM)' \
	REPO_SLUG=$(GITHUB_REPO) PROJECT=$(PROJECT) \
		tools/release/changelog.sh

.PHONY: release-verify
## Verify RELEASE_TAG: format, annotated, trusted signature, branch, CI result, not released.
release-verify: $(YQ)
	test -n '$(RELEASE_TAG)' || { echo "set RELEASE_TAG=vX.Y.Z" >&2; exit 1; }
	YQ=$(YQ) GITHUB_REPO=$(GITHUB_REPO) tools/release/verify-tag.sh '$(RELEASE_TAG)'

.PHONY: release-notes
## Render dist/release-notes.md.
release-notes:
	$(if $(filter release,$(CHANNEL)),,$(error release-notes needs CHANNEL=release))
	DIGESTS_FILE=$(DIGESTS_FILE) CHART_DIGEST_FILE=$(DIST)/chart-digest.env PLUGIN_DIR=$(PLUGIN_DIR) \
	MANIFESTS_DIR=$(DIST)/manifests CHART_REGISTRY=$(CHART_REGISTRY) CHART_NAME=$(CHART_NAME) \
	RELEASE_NAME=$(RELEASE_NAME) NAMESPACE=$(NAMESPACE) REPO_URL=$(REPO_URL) \
	DELIVERED_IMAGES='$(DELIVERED_IMAGES)' \
		tools/release/notes.sh $(VERSION) $(RELEASE_NOTES)

RELEASE_ASSETS = $(wildcard $(DIST)/manifests/deploy-*.yaml $(DIST)/manifests/deploy-manifests.sha256 \
	$(PLUGIN_DIR)/kubectl-ingress_nginx_neo_* $(PLUGIN_DIR)/checksums.sha256 \
	$(PLUGIN_DIR)/checksums.sha256.sigstore.json $(PLUGIN_DIR)/ingress-nginx-neo.yaml)

.PHONY: release-publish
## Create or update the draft GitHub Release with all assets.
release-publish:
	$(if $(filter release,$(CHANNEL)),,$(error release-publish needs CHANNEL=release))
	GITHUB_REPO=$(GITHUB_REPO) tools/release/publish.sh publish $(VERSION) $(RELEASE_NOTES) $(RELEASE_ASSETS)

.PHONY: release-finalize
## Publish the draft GitHub Release.
release-finalize:
	$(if $(filter release,$(CHANNEL)),,$(error release-finalize needs CHANNEL=release))
	GITHUB_REPO=$(GITHUB_REPO) tools/release/publish.sh finalize $(VERSION)

# Check the invariants of the publishing channel once, before any publishing
# target of the same job: latest publishes the tip of main only, release
# publishes the tagged commit only.
.PHONY: publish-guard
publish-guard:
ifeq ($(CHANNEL),latest)
	git fetch --quiet --no-tags origin +refs/heads/main:refs/remotes/origin/main
	test "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/main)" || \
		{ echo "HEAD is not the tip of origin/main: a newer commit publishes latest" >&2; exit 1; }
else ifeq ($(CHANNEL),release)
	git rev-parse --verify --quiet 'refs/tags/$(VERSION)' >/dev/null || \
		{ echo "tag $(VERSION) does not exist" >&2; exit 1; }
	test "$$(git rev-parse HEAD)" = "$$(git rev-parse '$(VERSION)^{commit}')" || \
		{ echo "HEAD is not the commit of $(VERSION)" >&2; exit 1; }
else
	@echo "publishing needs CHANNEL=latest or CHANNEL=release" >&2; exit 1
endif

.PHONY: print-latest-release
print-latest-release:
	@git ls-remote --tags --refs origin 'v*' | sed 's#.*refs/tags/##' | \
		grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' | sort -V | tail -n1


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


.PHONY: security-dependency-scan
## govulncheck for all Go modules. | Security
security-dependency-scan: $(GOVULNCHECK)
	$(GOVULNCHECK) ./...
	for mod in $(GO_IMAGE_MODULES); do (cd "$$mod" && $(GOVULNCHECK) ./...); done

GO_IMAGE_MODULES := images/kube-webhook-certgen/rootfs images/custom-error-pages/rootfs images/fastcgi-helloserver/rootfs

SCAN_IMAGES := $(DELIVERED_IMAGES) nginx

.PHONY: security-container-scan
## Trivy scan of the latest published release images (or VERSION=) into dist/sarif/.
security-container-scan:
	version='$(if $(filter command line,$(origin VERSION)),$(VERSION))'; \
	version="$${version:-$$($(MAKE) -s print-latest-release)}"; \
	test -n "$$version" || { echo "no release to scan" >&2; exit 1; }; \
	mkdir -p $(DIST)/sarif; \
	for image in $(SCAN_IMAGES); do \
		echo "--- $(REGISTRY)/$$image:$$version"; \
		docker run --rm --volume $(CURDIR)/$(DIST)/sarif:/out --volume $(CURDIR)/$(CACHE)/trivy:/root/.cache/trivy \
			$(if $(wildcard $(HELM_REGISTRY_CONFIG)),--volume $(HELM_REGISTRY_CONFIG):/root/.docker/config.json:ro) \
			$(TRIVY_IMAGE) image --quiet --ignore-unfixed --format sarif \
			--output /out/$$image.sarif "$(REGISTRY)/$$image:$$version"; \
	done
