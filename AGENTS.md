# AGENTS.md

Guidance for AI agents and automation working in this repository.

## What this repository is

This is a **self-maintained, standalone distribution** of ingress-nginx (a "sovereign fork"),
based on the historical `kubernetes/ingress-nginx` codebase. It is **not** a contribution
fork: pull requests are never sent upstream, and upstream (which is
[being retired](https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)) is kept
only as a read-only historical reference.

Consequences for how you work here:

- `main` in this repository is the single source of truth. Feature branches merge into `main`
  via pull requests **within this repo** (`Kuzmenko-Pavel/ingress-nginx`).
- Runtime changes are allowed and expected: Go code, Lua, nginx templates, Helm chart,
  Dockerfiles, GitHub Actions, docs.
- Do **not** open PRs against `kubernetes/ingress-nginx`, do not rebase onto upstream as a
  standard process, and do not reintroduce upstream-only bindings (see "Hard rules").
- The original upstream remote is kept locally as `upstream-archive` for occasional manual
  cherry-picks only: `git fetch upstream-archive --tags && git cherry-pick <sha>`.

The Go module path is still `k8s.io/ingress-nginx` (don't rename it — it's an internal import
path, not a provenance claim). Provenance is recorded via OCI image labels and release notes.

See `docs/maintained-distribution-release.md` for the full distribution/release model.

## Codebase map

| Area | Path | Notes |
|------|------|-------|
| Controller entrypoint | `cmd/nginx/` | `main` package; starts the controller |
| Other binaries | `cmd/{dbg,waitshutdown,annotations,plugin}/` | `cmd/plugin` = `kubectl ingress-nginx` |
| Core logic | `internal/ingress/controller/` | sync loop, store, template rendering, config |
| Annotations | `internal/ingress/annotations/<name>/` | one package per supported annotation |
| Admission webhook | `internal/admission/` | validates Ingress objects before accept |
| Helpers | `internal/{k8s,net,nginx,task}/`, `pkg/` | k8s parsing, networking, queue, public apis/flags/metrics |
| Go types for templates | `internal/ingress/types.go` | structures fed into the nginx template |
| nginx template | `rootfs/etc/nginx/template/nginx.tmpl` | Go template → final `nginx.conf` (~60K) |
| Lua | `rootfs/etc/nginx/lua/` | `balancer.lua`, `certificate.lua`, `configuration.lua`, `monitor.lua`, `lua_ingress.lua` — dynamic endpoints/certs, LB, monitoring |
| Controller image | `rootfs/Dockerfile`, `rootfs/Dockerfile-chroot` | built by `make image` / `make release` |
| Helm chart | `charts/ingress-nginx/` | `Chart.yaml`, `values.yaml`, `templates/`, helm-unittest `tests/` |
| Aux/base images | `images/` (`images/Makefile`, `images/nginx/Makefile`) | nginx base (patches in `images/nginx/rootfs/patches`), kube-webhook-certgen, test runner, e2e helper images |
| E2E + unit test harness | `test/` | `test/e2e/` (ginkgo, kind), `test/test.sh`, `test/k6/` |
| Docs (mkdocs) | `docs/` | `how-it-works.md`, `developer-guide/`, `user-guide/`, `maintained-distribution-release.md` |
| CI/CD | `.github/workflows/` | see "CI/CD & release" below |

Architecture in one paragraph: the controller builds an in-memory model from Ingresses,
Services, Endpoints, Secrets and ConfigMaps; on change it diffs against the running model.
Endpoint/certificate changes are pushed dynamically to Lua inside nginx (no reload); other
changes regenerate `nginx.conf` from `nginx.tmpl` and trigger a reload. Read `docs/how-it-works.md`
and `docs/developer-guide/code-overview.md` before touching core logic.

## Build, test, lint

Common targets (`make help` lists all; most run inside a build container via
`build/run-in-docker.sh`). Key versions: Go from `GOLANG_VERSION` (1.26.1), nginx base from
`images/nginx/TAG` (reference printed by `hack/nginx-base-image.sh`).

```bash
make build                # build controller binaries
make test                 # Go unit tests
make lua-test             # Lua unit tests
make helm-test            # helm-unittest for the chart
make verify-docs          # regenerate/verify annotation docs
make image image-chroot   # build controller images locally (single-arch)
make dev-env              # local kind cluster with the controller deployed
make kind-e2e-test        # full e2e on kind
make kind-e2e-chart-tests # helm chart e2e on kind
```

Linting: `golangci-lint` (config `.golangci.yml`), `luacheck` (`.luacheckrc`), chart lint via
`ct` (`.ct.yaml`) + Artifact Hub `ah`, and `helm-docs` (chart `README.md` is generated from
`README.md.gotmpl` — regenerate, don't hand-edit). CI (`ci.yaml`) runs all of these on PRs;
run the relevant target locally before pushing.

## CI/CD & release

All image builds go through the repository `Makefile` / `images/Makefile` /
`images/nginx/Makefile` (native logic); their default `REGISTRY` is our GHCR namespace
`ghcr.io/kuzmenko-pavel`. There is **no** custom build-push wrapper. Upstream shipped via
Google Cloud Build (`cloudbuild.yaml`, removed here); the release workflow drives
`make release` instead.

The NGINX base image (`images/nginx`) is ours: `images/nginx/TAG` is the single source of
its version and `hack/nginx-base-image.sh` derives the reference used by the Makefiles, e2e
scripts, CI and release. Default architecture is `linux/amd64`; `linux/arm64` is opt-in via
the repository variable `ENABLE_ARM64=true`; armv7 is not supported. Details:
`docs/maintained-distribution-release.md`.

Workflows in `.github/workflows/`:

- `release.yaml` — on tag push `vX.Y.Z` (or manual `workflow_dispatch`): preflight in the
  `release` environment (tag format, `appVersion` == tag, tagged commit on `main`, no
  overwrite of published controller tag / chart version), NGINX base via `base-images.yaml`
  (no-op if published), `make release` on the base pinned by digest with SBOM + provenance,
  certgen only when its `TAG` is new, cosign keyless signing, `values.yaml` patched in the
  workspace only, chart OCI to `oci://ghcr.io/kuzmenko-pavel/charts`, GitHub Release via `gh`.
- `base-images.yaml` — NGINX base (per-arch native runners, merged by digest) and e2e test
  runner; publishes only tags that are not published yet. Also called by `release.yaml`.
- `images.yaml` + `zz-tmpl-images.yaml` — aux images, pushed to GHCR via `GITHUB_TOKEN`.
- `ci.yaml` + `zz-tmpl-k8s-e2e.yaml` — lint, unit, build, chart lint/test, kind e2e matrix.
- `golangci-lint.yml`, `junit-reports.yaml`, `depreview.yaml`, `scorecards.yml`,
  `perftest.yaml` — lint/reporting/security/perf, all self-owned.
- `vulnerability-scans.yaml` — Trivy scans of our published GHCR images / our `v*` tags.

Published artifacts:

| Artifact | Location |
|----------|----------|
| controller | `ghcr.io/kuzmenko-pavel/ingress-nginx/controller` |
| controller-chroot | `ghcr.io/kuzmenko-pavel/ingress-nginx/controller-chroot` |
| kube-webhook-certgen | `ghcr.io/kuzmenko-pavel/ingress-nginx/kube-webhook-certgen` |
| Helm chart (OCI) | `oci://ghcr.io/kuzmenko-pavel/charts/ingress-nginx` |
| NGINX base | `ghcr.io/kuzmenko-pavel/ingress-nginx/nginx` |
| e2e test runner | `ghcr.io/kuzmenko-pavel/ingress-nginx/e2e-test-runner` |

## Versioning

- Plain SemVer release tags only: `v1.15.1`, `v1.16.0`. **No vendor suffixes** (no `-kp.N`).
- Image tags equal the release tag. Helm chart version is plain SemVer in
  `charts/ingress-nginx/Chart.yaml` `.version` (bump every release); `appVersion` must equal
  the release tag without `v`. certgen tag from `images/kube-webhook-certgen/TAG`.
- Published tags and chart versions are immutable. Any change under `images/nginx/rootfs`
  requires an `images/nginx/TAG` bump (CI enforces it); ship dependent template/Go changes
  in the same PR — CI builds the base from source for it.
- Record the upstream base tag/commit in release notes when known (workflow `upstream_base`
  input or an `UPSTREAM_BASE` file at the repo root).

## Typical workflow for a change

```bash
git checkout -b feature/<short-name>
# edit code / lua / template / chart / docs
make test           # plus lua-test / helm-test / verify-docs as relevant
git commit -m "<conventional message>"
git push origin feature/<short-name>
# open a PR into main within this repo; cut a tag vX.Y.Z to release
```

## Hard rules (do not violate)

- Do not reintroduce upstream-only bindings in workflows: `github.repository ==
  'kubernetes/ingress-nginx'` guards, DockerHub secrets (`DOCKERHUB_*`), `PROJECT_WRITER`
  (k8s org project board), krew-index publishing, or pushes to `registry.k8s.io` /
  `ingressnginx/*`. (`registry.k8s.io/.../nginx` as a *base image pull* in `ci.yaml` is fine.)
- Do not commit registry/tag/digest edits to `charts/ingress-nginx/values.yaml`: the release
  workflow patches it at runtime only. The committed file keeps generic defaults.
- Do not force-push and do not rewrite history.
- Commit messages and PR descriptions contain no AI attribution: no `Co-Authored-By`,
  `Claude-Session` or "Generated with Claude Code" trailers/footers.
- Keep the Go module path `k8s.io/ingress-nginx`.
- Never overwrite a published image tag or chart version; bump the version instead.
- Do not reintroduce `registry.k8s.io/ingress-nginx/nginx` or a separately pinned base image
  file: the base reference comes from `hack/nginx-base-image.sh`.
- Don't hand-edit generated files: chart `README.md` (from `README.md.gotmpl` via helm-docs),
  annotation docs (via `make verify-docs`).
- Prefer pinned action SHAs and the project's existing tool versions when editing workflows.
