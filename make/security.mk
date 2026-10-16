# SPDX-License-Identifier: Apache-2.0
#
# Security scans. Included by the root Makefile.

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
	version='$(if $(filter command line environment,$(origin VERSION)),$(VERSION))'; \
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
