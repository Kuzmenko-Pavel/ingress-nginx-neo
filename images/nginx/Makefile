# Copyright 2025 The Kubernetes Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

BUILDER ?= ingress-nginx
# Local default: amd64 only. CI publishes amd64 + arm64 (PLATFORMS=linux/arm64 or
# linux/amd64,linux/arm64); CI builds each architecture on a native runner and merges
# the results with the `manifest` target.
PLATFORMS ?= linux/amd64
REGISTRY ?= ghcr.io/kuzmenko-pavel/ingress-nginx
IMAGE ?= $(REGISTRY)/nginx
TAG ?= $(shell cat TAG)
SOURCE ?= https://github.com/Kuzmenko-Pavel/ingress-nginx
# Extra docker buildx flags (e.g. "--sbom=true --provenance=mode=max").
BUILDX_ARGS ?=
# push-by-digest: file receiving buildx metadata (contains containerimage.digest).
METADATA_FILE ?= metadata.json
# manifest: space separated list of per-platform digests (sha256:...).
DIGESTS ?=

LABELS = \
	--label org.opencontainers.image.title="ingress-nginx nginx base" \
	--label org.opencontainers.image.description="NGINX base image for ingress-nginx" \
	--label org.opencontainers.image.source="$(SOURCE)" \
	--label org.opencontainers.image.licenses="Apache-2.0" \
	--label org.opencontainers.image.version="$(TAG)"

.PHONY: builder
builder:
	docker buildx create --name $(BUILDER) --bootstrap || :
	docker buildx inspect $(BUILDER)

.PHONY: build
build: builder
	docker buildx build \
		--builder $(BUILDER) \
		--platform $(PLATFORMS) \
		$(LABELS) \
		rootfs \
		--tag $(IMAGE):$(TAG)

# Pushing in the `build` target does not work as authentication times out after one hour.
#
# Therefore we need to build and push in separate commands.
.PHONY: push
push: build
	docker buildx build \
		--builder $(BUILDER) \
		--platform $(PLATFORMS) \
		$(LABELS) \
		$(BUILDX_ARGS) \
		rootfs \
		--tag $(IMAGE):$(TAG) \
		--push

# Build a single platform and push it untagged (by digest). Used by CI to build every
# architecture on its own native runner; the digests are combined by `manifest`.
.PHONY: push-by-digest
push-by-digest: build
	docker buildx build \
		--builder $(BUILDER) \
		--platform $(PLATFORMS) \
		$(LABELS) \
		$(BUILDX_ARGS) \
		rootfs \
		--metadata-file $(METADATA_FILE) \
		--output type=image,name=$(IMAGE),push-by-digest=true,name-canonical=true,push=true

# Create the tagged multi-platform index from per-platform digests.
.PHONY: manifest
manifest:
	test -n "$(DIGESTS)"
	docker buildx imagetools create \
		--annotation "index:org.opencontainers.image.source=$(SOURCE)" \
		--annotation "index:org.opencontainers.image.description=NGINX base image for ingress-nginx" \
		--annotation "index:org.opencontainers.image.licenses=Apache-2.0" \
		--tag $(IMAGE):$(TAG) \
		$(foreach d,$(DIGESTS),$(IMAGE)@$(d))

.PHONY: clean
clean:
	docker buildx rm $(BUILDER) || :
