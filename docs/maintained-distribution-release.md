# Maintained ingress-nginx Distribution

This repository is a self-maintained distribution based on the ingress-nginx codebase.
It is developed and released independently, with its own runtime artifacts published to
GitHub Container Registry (GHCR). It is not a contribution fork: pull requests are not
sent to `kubernetes/ingress-nginx`, and the project is free to evolve its Go code, Lua
code, nginx templates, the NGINX base image, Helm chart, Dockerfiles, GitHub Actions, and
documentation.

## Ownership model

- This is an independently maintained codebase, not a release-only mirror.
- `main` in this repository is the single source of truth.
- Feature work happens on branches and is merged into `main` via pull requests **within
  this repository**. Pull requests are never opened against `kubernetes/ingress-nginx`.
- The maintainer owns all runtime code, the NGINX base image, chart, build logic, and
  release process. Nothing is pulled from `registry.k8s.io/ingress-nginx` at release time.

## Artifacts

| Artifact | Location | Version source |
|----------|----------|----------------|
| Controller image | `ghcr.io/kuzmenko-pavel/ingress-nginx/controller` | release tag `vX.Y.Z` |
| Controller-chroot image | `ghcr.io/kuzmenko-pavel/ingress-nginx/controller-chroot` | release tag `vX.Y.Z` |
| kube-webhook-certgen | `ghcr.io/kuzmenko-pavel/ingress-nginx/kube-webhook-certgen` | `images/kube-webhook-certgen/TAG` |
| custom-error-pages (chart default backend) | `ghcr.io/kuzmenko-pavel/ingress-nginx/custom-error-pages` | `images/custom-error-pages/TAG` |
| Static manifests per provider | GitHub Release assets `deploy-<provider>.yaml` | release tag |
| Helm chart (OCI) | `oci://ghcr.io/kuzmenko-pavel/charts/ingress-nginx` | `charts/ingress-nginx/Chart.yaml` `.version` |
| NGINX base image | `ghcr.io/kuzmenko-pavel/ingress-nginx/nginx` | `images/nginx/TAG` |
| e2e test runner | `ghcr.io/kuzmenko-pavel/ingress-nginx/e2e-test-runner` | `images/test-runner/TAG` |

**Published tags are immutable.** Workflows never overwrite an existing image tag or chart
version; every content change needs a new version. The only exception is the explicit
`force` input of the release workflow, meant to recover from a partially failed release.

## NGINX base image

The controller and controller-chroot images are built `FROM` the NGINX base image built
from `images/nginx` (nginx, LuaJIT, modules and the patches in
`images/nginx/rootfs/patches`).

`images/nginx/TAG` is the **single source of truth** for its version.
`hack/nginx-base-image.sh` prints the reference every consumer uses
(`ghcr.io/kuzmenko-pavel/ingress-nginx/nginx:<TAG>`): the root `Makefile`, `images/Makefile`,
the test runner, the e2e scripts, CI and the release workflow. There is no separately pinned
digest to keep in sync; the digest used by a release is recorded in the release notes and
in the controller image label `org.opencontainers.image.base.name`.

### Changing nginx (patches, modules, versions)

1. Change `images/nginx/rootfs/**` (for example add a patch to
   `images/nginx/rootfs/patches/`; `build.sh` applies all of them in lexical order).
2. Bump `images/nginx/TAG`. CI fails a pull request that changes `images/nginx/rootfs`
   without a TAG bump.
3. Change the controller side (template, Go, Lua) in the **same pull request** if it depends
   on the new nginx behaviour. CI builds the base image from source for that pull request and
   runs unit, chart and e2e tests on top of it, so the controller and its base are always
   tested together.
4. After merge, the **Base Images** workflow publishes the new tag. A release also publishes
   it first if it is missing, so `main` is releasable right after the merge.

Rebasing the patches onto a new `NGINX_VERSION` (in `images/nginx/rootfs/build.sh`) is the
maintainer's responsibility: bump the version, rebase or drop every file in `patches/`,
bump `images/nginx/TAG`, and let CI run the full e2e suite.

The NGINX base takes a long time to compile (tens of minutes per architecture on a standard
GitHub runner). CI builds it only when `images/nginx/**` changes or its tag is not published
yet.

### Security backports

The base is built on nginx 1.27.1, a branch that no longer receives upstream fixes. Security
fixes are backported as numbered patches (`NN_nginx-1.27.1-CVE-YYYY-NNNNN.patch`); each patch
header names the upstream nginx commit it is derived from. Patches 35–40 are taken unchanged
from [chainguard-forks/ingress-nginx](https://github.com/chainguard-forks/ingress-nginx), which
maintains the same 1.27.1 line and is a good source for further backports until nginx is moved
to a maintained branch.

Patch 37 (CVE-2026-49975) has two consequences worth knowing:

- **`max_headers` (default 1000):** requests with more header lines are rejected with 400.
- **ABI:** it adds a field to `ngx_http_headers_in_t` (embedded in `ngx_http_request_t`). All
  modules in this image are built against the patched headers; third-party dynamic modules
  built against stock nginx 1.27.1 headers are not compatible and must be rebuilt.

## Release model

A release is produced by pushing a Git tag from a commit on `main` (or `release-*`):

```bash
# charts/ingress-nginx/Chart.yaml: appVersion: 1.15.2, version: <new chart version>
# charts/ingress-nginx/values.yaml: controller.image.tag: v1.15.2,
#   controller.admissionWebhooks.patch.image.tag: <images/kube-webhook-certgen/TAG>,
#   defaultBackend.image.tag: <images/custom-error-pages/TAG>
# deploy/static: KUSTOMIZE='kubectl kustomize' hack/generate-deploy-scripts.sh (CI checks it)
git tag v1.15.2
git push origin v1.15.2
```

`.github/workflows/release.yaml` runs three jobs:

1. **Preflight** (runs in the `release` environment, which is where a manual approval gate
   belongs):
   - the tag is `vX.Y.Z` and the tagged commit is on `main` / `release-*`;
   - `Chart.yaml` `appVersion` equals the tag without `v`;
   - `values.yaml` references our images: `global.image.registry` is `ghcr.io`, the controller
     kube-webhook-certgen and custom-error-pages image names are ours, `controller.image.tag`
     equals the tag and the certgen / default backend tags equal their `images/*/TAG`;
   - `controller:vX.Y.Z`, `controller-chroot:vX.Y.Z` and the chart version are not published
     yet;
   - `kube-webhook-certgen` and `custom-error-pages` are rebuilt only if their `TAG` is new; a
     reused tag must already provide every release platform.
2. **NGINX base**: calls `base-images.yaml`, which publishes `nginx:<images/nginx/TAG>` if it
   does not exist (no-op otherwise).
3. **Build and publish**:
   - `make release` builds controller and controller-chroot on the base image pinned by
     digest, with SBOM and provenance attestations;
   - `make -C images push NAME=kube-webhook-certgen` and `NAME=custom-error-pages` (when new);
   - signs every published image with keyless cosign;
   - pins the published image digests into `charts/ingress-nginx/values.yaml` **in the
     workspace only**, then runs `helm lint` / `helm template`;
   - pushes the chart to `oci://ghcr.io/kuzmenko-pavel/charts` and signs it;
   - renders the static manifests (`hack/generate-deploy-scripts.sh`) from the digest-pinned
     values;
   - creates the GitHub Release with provenance, digests, the packaged chart, the
     `deploy-<provider>.yaml` manifests and their checksums.

### Manual trigger

`workflow_dispatch` takes an existing `tag`, an optional `upstream_base` (recorded in the
release notes) and `force`. Use `force` only to re-run a release that failed after
publishing some artifacts; it allows the controller tag and chart version to be pushed again.

## Architectures

| Platform | Status |
|----------|--------|
| `linux/amd64` | published |
| `linux/arm64` | published (e.g. AWS Graviton) |
| `linux/arm` (armv7) | not supported |

Every release image (controller, controller-chroot, kube-webhook-certgen, custom-error-pages)
and the NGINX base are multi-platform `amd64` + `arm64` tags:

- **Base Images** builds the NGINX base on native runners (`ubuntu-latest` and
  `ubuntu-24.04-arm`, no QEMU) and merges both into one tag;
- **Release** builds controller, chroot, certgen and custom-error-pages for
  `linux/amd64,linux/arm64` (cross-compiled Go binaries plus a thin image layer, QEMU for the
  few `RUN` steps);
- the release preflight refuses to reuse a published certgen / custom-error-pages / NGINX base
  tag that lacks one of the platforms (published tags are immutable: bump the `TAG`).

The e2e test runner is CI tooling and is published for `linux/amd64` only.

To publish `linux/amd64` only (for example while debugging an arm64 build problem), set the
repository variable `DISABLE_ARM64` to `true` (*Settings → Secrets and variables → Actions →
Variables*). Base Images can also be run manually with the `arm64` input.

### Mirroring the images

All default chart images are ours and share one registry, so a private mirror only needs
`global.image.registry`:

```bash
# copy (e.g. with crane or skopeo) ghcr.io/kuzmenko-pavel/ingress-nginx/{controller,
# controller-chroot,kube-webhook-certgen,custom-error-pages} to registry.example.com, then:
helm install ingress-nginx oci://ghcr.io/kuzmenko-pavel/charts/ingress-nginx \
  --version 4.15.2 --set global.image.registry=registry.example.com
```

Digests stay pinned, so the mirror must preserve them (`crane copy` / `skopeo copy --all` do).

## Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `release.yaml` | tag `vX.Y.Z`, manual | Release (see above). |
| `base-images.yaml` | push to `main` under `images/nginx/**`, `images/test-runner/**`; manual; called by release | Publishes the NGINX base and the e2e test runner when their tags are new. |
| `images.yaml` + `zz-tmpl-images.yaml` | changes under `images/**` | Builds/tests auxiliary images; pushes them on `main` when their `TAG` changes. |
| `ci.yaml` + `zz-tmpl-k8s-e2e.yaml` | pull requests, push to `main` | Lint, unit, chart and kind e2e tests. |
| `vulnerability-scans.yaml` | weekly, on release | Trivy scan of the three latest controller releases. |

## Supported Kubernetes versions

Supported and tested Kubernetes minor versions follow the Amazon EKS **standard support**
window (currently 1.34, 1.35, 1.36). CI runs the e2e, chart and certgen matrices only
against these versions, using the latest `kindest/node` patch images of the pinned kind
release.

When EKS adds or retires a version in standard support:

1. bump kind in `.github/actions/setup-kind/action.yml` (`version` and the `sha256` of
   `kind-linux-amd64`) if the new node image needs a newer kind;
2. update the `k8s` matrices in `ci.yaml` and `images.yaml`;
3. update the default `K8S_VERSION` in `build/dev-env.sh`, `test/e2e/run-kind-e2e.sh` and
   `test/e2e/run-chart-test.sh` (newest supported version, pinned by digest).

## Versioning policy

- Releases use plain SemVer tags, e.g. `v1.15.1`, `v1.15.2`, `v1.16.0` — no vendor suffixes.
- Controller image tags equal the release tag; `Chart.yaml` `appVersion` equals the tag
  without `v` (enforced).
- The Helm chart uses its own plain SemVer version in `Chart.yaml` `.version` and must be
  bumped for every release (enforced: a published version is never overwritten).
- `images/*/TAG` versions the base, test runner, certgen and auxiliary images.
- When the base upstream commit/tag is known, record it in the release notes (via the
  `upstream_base` input or an `UPSTREAM_BASE` file at the repository root).

## Provenance and verification

- OCI labels: `org.opencontainers.image.source`, `.revision`, `.version`, and
  `.base.name` (the NGINX base reference with digest) on the controller image.
- SBOM and SLSA provenance attestations are attached to the controller, chroot, certgen,
  custom-error-pages and NGINX base images
  (`docker buildx build --sbom=true --provenance=mode=max`).
- Images, the NGINX base, the test runner and the chart are signed with keyless cosign
  (GitHub Actions OIDC; no long-lived keys).

```bash
IMAGE=ghcr.io/kuzmenko-pavel/ingress-nginx/controller:v1.15.2

cosign verify "${IMAGE}" \
  --certificate-identity-regexp '^https://github.com/Kuzmenko-Pavel/ingress-nginx/\.github/workflows/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

docker buildx imagetools inspect "${IMAGE}" --format '{{ json .SBOM }}'
docker buildx imagetools inspect "${IMAGE}" --format '{{ json .Provenance }}'
```

## GitHub settings

Settings required or recommended for this repository:

| Where | Setting |
|-------|---------|
| Package settings of each GHCR package (profile → *Packages* → package → *Package settings*) | *Change visibility → Public* (irreversible). *Manage Actions access*: add `Kuzmenko-Pavel/ingress-nginx` with **Write** (or *Inherit access from source repository*). Applies to `controller`, `controller-chroot`, `kube-webhook-certgen`, `custom-error-pages`, `nginx`, `e2e-test-runner` and `charts/ingress-nginx`. New packages are created on the first push; make them public right after. |
| *Settings → Actions → General* | Workflow permissions: *Read repository contents* (workflows request `packages`/`contents`/`id-token` write explicitly). Optionally *Require actions to be pinned to a full-length commit SHA*. |
| *Settings → Environments → `release`* | Required reviewers (manual approval before publishing); deployment tags `v*`. |
| *Settings → Secrets and variables → Actions → Variables* | `DISABLE_ARM64=true` only to temporarily publish amd64 only (optional). |
| *Settings → Rules → Rulesets* | Tag ruleset for `v*`: restrict creation, update and deletion to maintainers. Branch ruleset for `main`: pull request required, no force-push, required status checks **`CI result`** and **`Images result`** (aggregate jobs of `ci.yaml` / `images.yaml` that always report, even when path filters skip every other job; do not require individual matrix jobs). |
| *Settings → General → Releases* | Enable release immutability. |

CI pulls the NGINX base anonymously, so the `nginx` package must be public for pull
requests to reuse it instead of rebuilding.

## First-time bootstrap

1. Merge the change that introduces `base-images.yaml`; the push to `main` publishes
   `nginx:<images/nginx/TAG>` and then `e2e-test-runner:<images/test-runner/TAG>`
   (or run **Base Images** manually with `images: all`).
2. Make both new packages public and grant the repository write access (see above).
3. Switch the e2e test runner references (`build/run-in-docker.sh`,
   `test/e2e-image/Makefile`, `test/e2e/run-chart-test.sh`) from `registry.k8s.io` to the
   published runner.

## Optional upstream reference

The original `kubernetes/ingress-nginx` remote is kept only as a read-only historical
reference, renamed locally to `upstream-archive`. It is **not** a mandatory base and is not
rebased onto as part of any standard process. It may be used manually to cherry-pick a
specific fix if that is ever desired:

```bash
git fetch upstream-archive --tags
git cherry-pick <commit-sha>
```

## Local development workflow

```bash
git checkout -b feature/my-change
# edit runtime code, chart, build logic, docs as needed
# build/test locally, then open a PR into main within this repository
git push origin feature/my-change
```

- `main` is the source of truth; changes land via PR into `main`.
- Committed chart values (`charts/ingress-nginx/values.yaml`) reference this distribution's
  images with the release tags and empty digests; the release workflow pins the digests at
  packaging time only. Installing the chart from a git checkout therefore uses our images by tag.
  `defaultBackend` uses this distribution's `custom-error-pages` image.
