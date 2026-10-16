# SPDX-License-Identifier: Apache-2.0
#
# Release tag, notes and GitHub Release. Included by the root Makefile.

GITHUB_REPO ?= Kuzmenko-Pavel/ingress-nginx-neo
RELEASE_NOTES := $(DIST)/release-notes.md

.PHONY: release-tag
## Create the signed annotated release tag: asks the version, opens the changelog in the editor. | Release
release-tag:
	RELEASE_TAG_PATTERN='$(RELEASE_TAG_PATTERN)' RELEASE_VERSION='$(RELEASE_VERSION)' PROJECT=$(PROJECT) \
		tools/release/changelog.sh

.PHONY: release-verify
## Verify RELEASE_TAG: format, annotated, trusted signature, branch, CI result, not released.
release-verify: $(YQ)
	test -n '$(RELEASE_TAG)' || { echo "set RELEASE_TAG=vX.Y.Z or checkout a release tag" >&2; exit 1; }
	@$(gh-auth-check)
	YQ=$(YQ) GITHUB_REPO=$(GITHUB_REPO) tools/release/verify-tag.sh '$(RELEASE_TAG)'

.PHONY: release-notes
## Render dist/release-notes.md.
release-notes: publish-guard
	$(if $(filter release,$(CHANNEL)),,$(error release-notes renders a release: checkout a vX.Y.Z tag))
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
release-publish: publish-guard
	$(if $(filter release,$(CHANNEL)),,$(error release-publish publishes a release: checkout a vX.Y.Z tag))
	@$(gh-auth-check)
	GITHUB_REPO=$(GITHUB_REPO) tools/release/publish.sh publish $(VERSION) $(RELEASE_NOTES) $(RELEASE_ASSETS)

.PHONY: release-finalize
## Publish the draft GitHub Release.
release-finalize: publish-guard
	$(if $(filter release,$(CHANNEL)),,$(error release-finalize publishes a release: checkout a vX.Y.Z tag))
	@$(gh-auth-check)
	GITHUB_REPO=$(GITHUB_REPO) tools/release/publish.sh finalize $(VERSION)

define gh-auth-check
if ! gh auth token >/dev/null 2>&1; then \
	echo "Error: gh is not authenticated" >&2; \
	echo "Please run: gh auth login   (or export GH_TOKEN=...)" >&2; \
	exit 1; \
fi
endef
