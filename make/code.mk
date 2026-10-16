# SPDX-License-Identifier: Apache-2.0
#
# Go code: format, lint, build, kubectl plugin. Included by the root Makefile.

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
code-sign-plugin: publish-guard $(COSIGN)
	$(if $(filter release,$(CHANNEL)),,$(error code-sign-plugin signs a release: checkout a vX.Y.Z tag))
	$(COSIGN) sign-blob --yes --bundle $(PLUGIN_DIR)/checksums.sha256.sigstore.json $(PLUGIN_DIR)/checksums.sha256
