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
COMMIT := $(shell git rev-parse HEAD 2>/dev/null)

# The publishing channel follows the git state, the same for a human and CI:
# a release tag on HEAD is that release, the tip of origin/main is latest,
# anything else is a local dev build. CHANNEL=... overrides it.
HEAD_RELEASE_TAG := $(shell git describe --tags --exact-match --match '$(RELEASE_TAG_PATTERN)' HEAD 2>/dev/null)
ORIGIN_MAIN := $(shell git rev-parse --verify --quiet refs/remotes/origin/main 2>/dev/null)
ifneq ($(origin CHANNEL),undefined)
CHANNEL_REASON := $(origin CHANNEL)
else ifneq ($(HEAD_RELEASE_TAG),)
CHANNEL := release
CHANNEL_REASON := tag $(HEAD_RELEASE_TAG) on HEAD
else ifneq ($(and $(COMMIT),$(filter $(COMMIT),$(ORIGIN_MAIN))),)
CHANNEL := latest
CHANNEL_REASON := HEAD is the tip of origin/main
else
CHANNEL := dev
CHANNEL_REASON := HEAD is neither a release tag nor the tip of origin/main
endif
ifeq ($(filter $(CHANNEL),dev latest release),)
$(error CHANNEL must be one of dev, latest, release (got "$(CHANNEL)"))
endif
RELEASE_TAG ?= $(HEAD_RELEASE_TAG)

ifeq ($(CHANNEL),release)
RELEASE_TAG := $(or $(RELEASE_TAG),$(if $(filter command line environment,$(origin VERSION)),$(VERSION)))
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

# The highest published release tag (empty before the first release); queried
# from origin only where it is used.
LATEST_RELEASE = $(shell git ls-remote --tags --refs origin 'v*' 2>/dev/null | sed 's|.*refs/tags/||' | \
	grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' | sort -V | tail -n1)
# The release the documentation describes, substituted for <version> in its pages.
DOCS_RELEASE_TAG = $(if $(filter release,$(CHANNEL)),$(VERSION),$(LATEST_RELEASE))

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
# mike runs mkdocs from PATH.
DOCS_PATH := PATH="$(abspath $(DOCS_VENV))/bin:$$PATH"

HELM_VERSION := $(shell awk '$$1 == "helm.sh/helm/v4" { print $$2; exit }' tools/go.mod)
GINKGO_VERSION := $(shell awk '$$1 == "github.com/onsi/ginkgo/v2" { print $$2; exit }' go.mod)

# Helm keeps its configuration and caches inside the repository.
HELM_ENV := HELM_CACHE_HOME=$(CURDIR)/$(CACHE)/helm/cache HELM_CONFIG_HOME=$(CURDIR)/$(CACHE)/helm/config HELM_DATA_HOME=$(CURDIR)/$(CACHE)/helm/data

# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

# Delivered images: tagged with IMAGE_TAG, rebuilt for every channel.
IMAGES ?= controller controller-chroot kube-webhook-certgen custom-error-pages
DELIVERED_IMAGES := controller controller-chroot kube-webhook-certgen custom-error-pages
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

E2E_VARIANTS := default chroot
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
	@printf '\nOptional variables: K8S_VERSION, E2E_VARIANT (%s), FOCUS; make version shows the channel and versions.\n\n' '$(E2E_VARIANTS)'

.PHONY: version
## Print VERSION, CHANNEL (and why) and derived IMAGE_TAG/CHART_VERSION/APP_VERSION/DOCS_VERSION.
version:
	@printf '%-14s %s\n' VERSION '$(VERSION)' CHANNEL '$(CHANNEL) ($(CHANNEL_REASON))' IMAGE_TAG '$(IMAGE_TAG)' \
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

.PHONY: print-e2e-variants
print-e2e-variants:
	@printf '%s\n' $(E2E_VARIANTS) | jq -R . | jq -cs .

.PHONY: print-scan-images
print-scan-images:
	@printf '%s\n' $(SCAN_IMAGES) | jq -R . | jq -cs .

# The "CI result" check: RESULTS is the JSON of the needs context of the job.
.PHONY: ci-result
ci-result:
	@if [ -z "$${RESULTS:-}" ]; then \
		echo "Error: RESULTS is not set" >&2; \
		echo "Please add: export RESULTS='<JSON of the needs context: {\"job\": {\"result\": \"success\"}, ...}>'" >&2; \
		exit 1; \
	fi
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

# A prerequisite of every publishing target, checked once per make run: the
# tree is committed, latest publishes the tip of main only, release publishes
# the tagged commit only.
.PHONY: publish-guard
publish-guard:
ifeq ($(CHANNEL),dev)
	@echo "publishing runs from the tip of main (latest) or from a release tag; HEAD is neither (checkout main or a vX.Y.Z tag; preview the docs with make docs-serve)" >&2; exit 1
endif
	@test -z "$$(git status --porcelain)" || \
		{ echo "There are uncommitted changes. Commit them before publishing" >&2; exit 1; }
ifeq ($(CHANNEL),latest)
	git fetch --quiet --no-tags origin +refs/heads/main:refs/remotes/origin/main
	test "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/main)" || \
		{ echo "HEAD is not the tip of origin/main: a newer commit publishes latest" >&2; exit 1; }
else ifeq ($(CHANNEL),release)
	git rev-parse --verify --quiet 'refs/tags/$(VERSION)' >/dev/null || \
		{ echo "tag $(VERSION) does not exist" >&2; exit 1; }
	test "$$(git rev-parse HEAD)" = "$$(git rev-parse '$(VERSION)^{commit}')" || \
		{ echo "HEAD is not the commit of $(VERSION)" >&2; exit 1; }
endif

.PHONY: print-latest-release
print-latest-release:
	@echo '$(LATEST_RELEASE)'

# ---------------------------------------------------------------------------
# Targets by domain
# ---------------------------------------------------------------------------

include make/code.mk make/test.mk make/images.mk make/helm.mk make/manifests.mk make/docs.mk make/release.mk make/dev.mk make/security.mk
