# SPDX-License-Identifier: Apache-2.0
#
# Documentation. Included by the root Makefile.

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
	DOCS_RELEASE_TAG=$(DOCS_RELEASE_TAG) $(DOCS_VENV)/bin/mkdocs build --strict --site-dir $(DIST)/site

.PHONY: docs-serve
## Serve the site locally with live reload.
docs-serve: $(DOCS_VENV)/bin/mkdocs
	DOCS_RELEASE_TAG=$(DOCS_RELEASE_TAG) $(DOCS_VENV)/bin/mkdocs serve

.PHONY: docs-publish
## Publish the docs version for CHANNEL via mike.
docs-publish: publish-guard $(DOCS_VENV)/bin/mkdocs
	$(DOCS_PATH) DOCS_RELEASE_TAG=$(DOCS_RELEASE_TAG) MIKE=$(DOCS_VENV)/bin/mike CHANNEL=$(CHANNEL) VERSION=$(VERSION) DOCS_VERSION=$(DOCS_VERSION) \
		tools/docs-publish.sh

.PHONY: docs-publish-check
## Run docs-publish for CHANNEL=latest into the local branch docs-publish-check, without pushing.
docs-publish-check: $(DOCS_VENV)/bin/mkdocs
	git branch -D docs-publish-check 2>/dev/null || true
	$(DOCS_PATH) DOCS_RELEASE_TAG=$(DOCS_RELEASE_TAG) MIKE=$(DOCS_VENV)/bin/mike CHANNEL=latest VERSION=$(VERSION) DOCS_VERSION=latest \
		DOCS_BRANCH=docs-publish-check DOCS_PUSH=false tools/docs-publish.sh
	git branch -D docs-publish-check
