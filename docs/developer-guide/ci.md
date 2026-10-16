# CI

CI runs on GitHub Actions with standard runners (`ubuntu-latest`, `ubuntu-24.04-arm`). Every step
calls a `make` target, so each check can be reproduced locally with the same command and the same
pinned tools. Workflows authenticate with `GITHUB_TOKEN` only and sign with cosign keyless signing.

CI gives make only the environment (the runner, tokens, OIDC for signing, push access). It also
decides when and in which order targets run. What to do and with which values is defined by the
Makefile. Every value CI passes to make has a default or a derivation rule in the Makefile. The only
intent the publishing jobs state explicitly is `CHANNEL` (see [Release](release.md)).

A workflow change can be checked before a push with act, see
[Running CI workflows locally](local-ci.md).

## Workflows

| Workflow | Trigger | Make targets |
|----------|---------|--------------|
| `ci.yaml` | pull requests; pushes to `main` and `release-*`; manually | see below |
| `deps.yaml` | called by `ci.yaml` and `release.yaml` | `docker-publish-deps`, `docker-publish-deps-manifest` or `docker-build-deps docker-save` |
| `release.yaml` | push of a `v*` tag | `release-verify`, `docker-publish`, `docker-promote`, `docker-sign`, `code-build-plugin`, `code-sign-plugin`, `helm-package`, `helm-publish`, `manifests-generate`, `release-notes`, `release-publish`, `docs-publish`, `release-finalize` |
| `security.yaml` | weekly, after a release, manually | `security-container-scan` (Trivy, one code-scanning category per image) |
| `e2e-report.yaml` | after a CI run | publishes the e2e junit reports as check runs |
| `scorecards.yml` | weekly, pushes to `main` | OpenSSF Scorecard |
| `depreview.yaml` | pull requests | dependency review |

## ci.yaml

| Job | Command | Runs |
|-----|---------|------|
| Dependency images | `deps.yaml` | always; publishes missing `src-*` images on pushes to `main` and manual runs on `main` |
| Lint | `make docker-load code-lint` (+ `make code-lint-commits BASE=<base>` on pull requests) | always |
| Unit tests | `make docker-load test-unit test-unit-lua` | always |
| Generated files | `make docs-verify helm-docs-verify` | always |
| Helm chart | `make helm-lint helm-test` | always |
| Docs | `make docs-build docs-publish-check` | groups `docs`, `build-system`, `workflow`; always outside pull requests |
| Dependency scan | `make security-dependency-scan` | always |
| Build images | `make docker-load docker-build docker-build-e2e docker-save` | any group except `docs` and `certgen`; always outside pull requests |
| E2E | `make docker-load test-e2e SKIP_BUILD=1 K8S_VERSION=… E2E_VARIANT=…` | every Kubernetes version × every variant |
| Chart e2e | `make docker-load test-e2e-chart SKIP_BUILD=1 K8S_VERSION=…` | every Kubernetes version |
| kube-webhook-certgen e2e | `make test-e2e-certgen` | groups `certgen`, `e2e`, `build-system`, `workflow`; always outside pull requests |
| **CI result** | `make ci-result` | always (not when the run is cancelled) |
| Publish latest | `make docker-publish docker-promote docker-sign helm-package helm-publish CHANNEL=latest`, `make code-build-plugin CHANNEL=latest` | pushes to `main` and manual runs on `main`, after CI result passed |
| Publish docs (latest) | `make docs-publish CHANNEL=latest` | after Publish latest |

The Kubernetes matrix comes from `make -s print-k8s-versions`, the e2e variants from
`make -s print-e2e-variants`, the dependency image platforms from `make -s print-deps-platforms`.

**CI result** is the only required status check of `main` and `release-*`: it fails when any job
failed or was cancelled; skipped jobs count as passed. A release is published only from a commit
whose CI result passed.

Images built in one job reach the others as workflow artifacts (`docker-save`, `docker-load`). On
pull requests the dependency images are pulled when published and built locally otherwise; on
`main` they are published before the checks, so the first push to an empty repository works.

The `latest` channel is published only from the tip of `main` (`publish-guard`, a prerequisite of
every publishing target). Before publishing, Publish latest and Publish docs (latest) ask
`make -s print-main-tip`. When `main` already has a newer commit, the job skips the publication with
a notice and stays green, the run of that commit publishes `latest`. A newer publication cancels an
older one that is still running. Jobs that write to `gh-pages` share one concurrency group and never
cancel each other.

## When jobs run

On pull requests the `Changes` job (`dorny/paths-filter`) sorts the changed files into groups. The
cheap jobs (Lint, Unit tests, Generated files, Helm chart, Dependency scan, CI result) always run.
Image builds and e2e (E2E and Chart e2e follow Build images) run only when the change can affect
them. Pushes and manual runs have no filters and run everything.

| Group | Paths |
|-------|-------|
| `go` | `**/*.go`, `**/go.mod`, `**/go.sum` |
| `lua` | `rootfs/etc/nginx/lua/**` |
| `template` | `rootfs/**` |
| `chart` | `charts/**`, `make/helm.mk`, `make/manifests.mk`, `tools/manifest-templates/**`, `tools/generate-manifests.sh` |
| `images-deps` | `images/` of the dependency images (`nginx`, `test-runner`, `e2e-test-echo`, `httpbun`, `fastcgi-helloserver`, `cfssl`) |
| `images-delivered` | `rootfs/**`, `images/kube-webhook-certgen/**`, `images/custom-error-pages/**` |
| `certgen` | `images/kube-webhook-certgen/**`, `tools/e2e-certgen.sh` |
| `docs` | `docs/**`, `mkdocs.yml`, `charts/**`, `make/docs.mk`, `tools/docs/**`, `tools/docs-publish.sh` |
| `e2e` | `test/**`, `make/test.mk`, `make/images.mk`, `tools/content-tag.sh`, `tools/image-exists.sh`, `tools/e2e-chart.sh` |
| `build-system` | `Makefile`, `make/code.mk`, `tools/go.mod`, `tools/go.sum`, `tools/versions.env`, `tools/install.sh`, `tools/actionlint/**` |
| `workflow` | `.github/**`, any workflow change runs the whole CI |

Paths outside the groups (for example `tools/release/**`, `make/release.mk`, `AGENTS.md`) run only
the cheap jobs. Unit tests and lint check them; they do not affect the build or e2e.

## Caches and artifacts

- `.cache/tools` is cached under a key of the hashes of `tools/**/go.mod`, `tools/**/go.sum`,
  `tools/versions.env` and `go.mod`.
- Image builds that publish use the GitHub Actions build cache with one scope per image and platform
  (`DOCKER_CACHE=gha`).
- Artifacts are kept for at most 7 days.

## Conventional Commits

Every non-merge commit of a pull request follows
[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>[(scope)][!]: <description>

[body]

[BREAKING CHANGE: <description>]
```

Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`, `revert`, `style`.
The scope is optional (`[a-z0-9._/-]+`); `!` or a `BREAKING CHANGE:` footer marks a breaking
change. `Revert "<subject>"` (as created by git and GitHub) counts as a revert. The release
changelog is generated from these subjects (see [Release](release.md)). Dependabot uses the `build`
prefix.

```console
make code-lint-commits                 # BASE ?= origin/main
make code-lint-commits BASE=<rev>
```

## Repository settings

The workflows expect: workflow permissions "Read repository contents"; actions pinned to full
commit SHAs; merge commits and rebase merges enabled, squash merges disabled; rulesets on `main`
and `release-*` requiring pull requests and the **CI result** check; tag rules for `v*` (created by
release managers only, no update or deletion); the environment `release` with a required reviewer
and deployment tags `v*`; release immutability; GitHub Pages deployed from the `gh-pages` branch.
