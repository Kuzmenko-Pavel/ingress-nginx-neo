# SPDX-License-Identifier: Apache-2.0
#
# Dependency and delivered images. Included by the root Makefile.

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
docker-publish: publish-guard $(CRANE)
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
docker-promote: publish-guard $(CRANE)
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
docker-sign: publish-guard $(COSIGN)
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
	cp test/e2e/settings/geoip/GeoLite2-Country-Test.mmdb $(E2E_CONTEXT)/
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
