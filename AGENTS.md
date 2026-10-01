# AGENTS.md

## Project

ingress-nginx-neo is an NGINX Ingress controller for Kubernetes, based on the kubernetes/ingress-nginx
codebase (Apache-2.0) and released from this repository (`Kuzmenko-Pavel/ingress-nginx-neo`). It
ships the controller images, kube-webhook-certgen, custom-error-pages, a Helm chart, static
manifests and the kubectl plugin `kubectl ingress-nginx-neo`. The Go module path is
`k8s.io/ingress-nginx`.

## Repository map

| Path | Purpose |
|------|---------|
| `cmd/nginx`, `cmd/dbg`, `cmd/waitshutdown` | controller binaries |
| `cmd/plugin` | kubectl plugin |
| `cmd/annotations`, `cmd/flagsdoc` | generators of docs pages |
| `internal/`, `pkg/` | controller code (sync loop, store, annotations, admission, metrics) |
| `rootfs/` | controller Dockerfiles, `etc/nginx/template/nginx.tmpl`, Lua in `etc/nginx/lua` |
| `charts/ingress-nginx-neo` | Helm chart (`tests/` helm-unittest, `ci/` values for lint and e2e) |
| `images/` | NGINX base (`images/nginx`), test runner, test helpers, certgen, custom-error-pages |
| `test/` | e2e suite (`test/e2e`, Ginkgo), e2e image, unit test entry points |
| `tools/` | pinned tools (`go.mod`, `versions.env`) and the scripts behind the Makefile |
| `docs/` | MkDocs site |
| `.github/workflows` | CI, release, security; every step is a make target |

## Project API

The root `Makefile` is the interface for humans, agents and CI.

```console
make help        # all targets by domain: code, test, images, helm, manifests, docs, security, release, development
make check       # fast checks: lint, unit tests, generated files, chart lint and tests
make test-e2e    # controller e2e on kind (E2E_VARIANT=default|chroot, FOCUS=...)
make docs-serve  # documentation with live reload
```

## Versioning

The release tag `vX.Y.Z` is the only version source. Images, chart, plugin, manifests and docs take
their version from it; the Makefile derives tags from `VERSION` and `CHANNEL`. Never write versions
into files (Chart.yaml stays `0.0.0-latest`/`latest`, image tags in values.yaml stay empty).
Dependency images are content addressed (`src-<hash>`) and need no version bumps.

## Rules

- Keep the user-facing API: annotation prefix `nginx.ingress.kubernetes.io`, IngressClass `nginx`,
  controller value `k8s.io/ingress-nginx`, ConfigMap keys, metrics, command line arguments.
- Test first: before a change of behavior or a bug fix, write a test that fails without it (Go
  unit, Lua, chart or e2e test; a lint rule when a test cannot express the defect), then change
  the code until it passes. A change of behavior without such a test states the reason in the
  pull request.
- Commits follow Conventional Commits (`make code-lint-commits`). No AI attribution trailers or
  footers in commits and pull requests.
- Never force-push or rewrite history. Never publish, tag or push releases or images.
- Never hand-edit generated files: `docs/user-guide/cli-arguments.md`,
  `docs/user-guide/nginx-configuration/annotations-risk.md` (`make docs-generate`), the chart
  `README.md` (`make helm-docs-generate`).
- No changelog files: release notes come from the release tag.
- Documentation describes the current state only; no history of decisions.
- Tools are pinned in `tools/`; image inputs in `images/*/build-args.env`. CI workflows only call
  make targets.

## Read before

| Task | Page |
|------|------|
| any change | `docs/developer-guide/getting-started.md` |
| tests, e2e | `docs/developer-guide/testing.md` |
| images, NGINX base, patches | `docs/developer-guide/images.md`, `images/nginx/README.md` |
| CI workflows | `docs/developer-guide/ci.md` |
| versions, releases, hotfixes | `docs/developer-guide/release.md` |
| kubectl plugin | `docs/kubectl-plugin.md` |
| Helm chart | `charts/ingress-nginx-neo/README.md.gotmpl`, `docs/deploy/index.md` |
| controller internals | `docs/how-it-works.md`, `docs/developer-guide/code-overview.md` |
