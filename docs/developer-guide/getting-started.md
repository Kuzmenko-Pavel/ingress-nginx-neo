# Getting started

This page describes the development workflow of ingress-nginx-neo. The root `Makefile` is the
project API: contributors, agents and CI run the same targets with the same pinned tools.

## System requirements

| Tool | Version | Used for |
|------|---------|----------|
| git | any recent | everything |
| bash | 4 or later | Makefile recipes and `tools/*.sh` |
| GNU Make | 4.0 or later (`gmake` on macOS) | the project API |
| Go | any; the toolchain of `go.mod` is downloaded automatically | building code and tools |
| Docker with buildx | any recent | images, Go/Lua unit tests, e2e |
| jq, python3 (3.10+), gpg | any recent | CI helpers, docs, release tags |
| gh | any recent | release targets; `GITHUB_TOKEN` for building the NGINX base |

Everything else (helm, kind, kubectl, golangci-lint, helm-unittest, helm-docs, yq, kustomize,
kubeconform, cosign, crane, govulncheck, actionlint, ginkgo) is pinned in `tools/` and installed into
`.cache/tools` on first use:

- Go tools are built from `tools/go.mod` (`tool` directives; actionlint has its own modfile in
  `tools/actionlint/`), ginkgo from the root `go.mod`;
- other tools are downloaded by `tools/install.sh` and verified against the sha256 in
  `tools/versions.env`.

`make tools` installs all of them at once. The directory of the installed tools is named after the
hash of their pins, so changing a pin installs a new set.

Optional local overrides of Makefile variables go into a gitignored `.env` file at the repository
root (for example `REGISTRY=ghcr.io/<you>/ingress-nginx-neo`).

## First steps

```console
git clone https://github.com/Kuzmenko-Pavel/ingress-nginx-neo.git
cd ingress-nginx-neo
make help        # every target, grouped by domain
make version     # version, channel and derived tags of this checkout
make check       # the fast checks CI runs on every pull request
```

`make check` runs `code-lint`, `test-unit`, `test-unit-lua`, `docs-verify`, `helm-docs-verify`,
`helm-lint` and `helm-test`. Go and Lua unit tests run inside the `e2e-test-runner` image, which
the Makefile pulls (or builds when its sources changed); see [Images](images.md).

## Adding a make target

A target appears in `make help` when the line directly above it is `## <description>`; a
description that ends in `| <group>` starts a new group, and the following targets belong to it
until the next group. Targets without such a line are internal. Recipes longer than a few lines
live in `tools/*.sh`.

```makefile
.PHONY: helm-test
## Run the helm-unittest suites. | Helm
helm-test: $(HELM_UNITTEST)
	$(HELM_UNITTEST) --file 'tests/**/*_test.yaml' $(CHART_DIR)
```

## Development environment

```console
make dev-env-up      # kind cluster with the locally built controller and the chart installed
make dev-env-down    # delete it
```

`dev-env-up` builds the controller, certgen and custom-error-pages images for the host architecture,
creates (or reuses) the kind cluster `ingress-nginx-neo-dev` with ports 80 and 443 mapped to
localhost, and installs the chart from `charts/ingress-nginx-neo` as release `ingress-nginx-neo` in
namespace `ingress-nginx-neo`, with the default backend (custom-error-pages) and metrics enabled.
Run it again after a change to rebuild and redeploy. `make test-load` runs load tests against it,
see [Testing](testing.md#load-tests).

## Typical change

1. Create a branch and make the change.
2. Run `make check`; for changes of the controller, the NGINX template or Lua code also run
   `make test-e2e` (see [Testing](testing.md)).
3. Regenerate generated files when their sources changed: `make docs-generate` (annotation risks,
   command line arguments) and `make helm-docs-generate` (chart README). Generated files are never
   edited by hand.
4. Commit with [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) subjects
   (`make code-lint-commits` checks them) and open a pull request to `main`.

See [CI](ci.md) for the checks of a pull request and [Release](release.md) for versions and releases.

## Repository layout

| Path | Contents |
|------|----------|
| `cmd/nginx`, `cmd/dbg`, `cmd/waitshutdown` | controller binaries |
| `cmd/plugin` | kubectl plugin `kubectl ingress-nginx-neo` |
| `cmd/annotations`, `cmd/flagsdoc` | generators of the annotation risk and command line argument pages |
| `internal/`, `pkg/` | controller code, see [Code overview](code-overview.md) |
| `rootfs/` | controller image: Dockerfiles, NGINX template, Lua code |
| `charts/ingress-nginx-neo` | Helm chart |
| `images/` | base, test and auxiliary images, see [Images](images.md) |
| `test/` | e2e suite and scripts, unit test entry points |
| `tools/` | pinned tools and the scripts behind the Makefile |
| `docs/` | this site (MkDocs) |

## Agents

`AGENTS.md` at the repository root is the contract for coding agents. Project skills live in
`.agents/skills/`; `.claude/skills` links to it. A `CLAUDE.md` or `CLAUDE.local.md` file in the
tree makes Claude Code ignore `AGENTS.md`, so the repository has none.
