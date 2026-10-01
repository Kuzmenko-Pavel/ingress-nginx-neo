# CI

CI runs on GitHub Actions with standard runners (`ubuntu-latest`, `ubuntu-24.04-arm`). Every step
calls a `make` target, so each check can be reproduced locally with the same command and the same
pinned tools. Workflows authenticate with `GITHUB_TOKEN` only and sign with cosign keyless signing.

## Workflows

| Workflow | Trigger | Make targets |
|----------|---------|--------------|
| `ci.yaml` | pull requests; pushes to `main` and `release-*` | see below |
| `deps.yaml` | called by `ci.yaml` and `release.yaml` | `docker-publish-deps`, `docker-publish-deps-manifest` or `docker-build-deps docker-save` |
| `release.yaml` | push of a `v*` tag | `release-verify`, `docker-publish`, `docker-promote`, `docker-sign`, `code-build-plugin`, `code-sign-plugin`, `helm-package`, `helm-publish`, `manifests-generate`, `release-notes`, `release-publish`, `docs-publish`, `release-finalize` |
| `security.yaml` | weekly, after a release, manually | `security-container-scan` (Trivy, one code-scanning category per image) |
| `e2e-report.yaml` | after a CI run | publishes the e2e junit reports as check runs |
| `scorecards.yml` | weekly, pushes to `main` | OpenSSF Scorecard |
| `depreview.yaml` | pull requests | dependency review |

## ci.yaml

| Job | Command | Runs |
|-----|---------|------|
| Dependency images | `deps.yaml` | always; publishes missing `src-*` images on `main` |
| Lint | `make docker-load code-lint` (+ `make code-lint-commits BASE=<base>` on pull requests) | always |
| Unit tests | `make docker-load test-unit test-unit-lua` | always |
| Generated files | `make docs-verify helm-docs-verify` | always |
| Helm chart | `make helm-lint helm-test` | always |
| Docs | `make docs-build` | docs or CI changes; always on pushes |
| Dependency scan | `make security-dependency-scan` | always |
| Build images | `make docker-load docker-build docker-build-e2e docker-save` | code, chart, image or CI changes; always on pushes |
| E2E | `make docker-load test-e2e SKIP_BUILD=1 K8S_VERSION=… E2E_VARIANT=…` | every Kubernetes version × `default`, `chroot` |
| Chart e2e | `make docker-load test-e2e-chart SKIP_BUILD=1 K8S_VERSION=…` | every Kubernetes version |
| kube-webhook-certgen e2e | `make test-e2e-certgen` | certgen changes; always on pushes |
| **CI result** | `make ci-result` | always (not when the run is cancelled) |
| Publish latest | `make publish-guard docker-publish docker-promote docker-sign helm-package helm-publish CHANNEL=latest`, `make code-build-plugin CHANNEL=latest` | pushes to `main` after CI result passed |
| Publish docs (latest) | `make docs-publish CHANNEL=latest` | after Publish latest |

The Kubernetes matrix comes from `make -s print-k8s-versions`, the dependency image platforms from
`make -s print-deps-platforms`.

**CI result** is the only required status check of `main` and `release-*`: it fails when any job
failed or was cancelled; skipped jobs count as passed. A release is published only from a commit
whose CI result passed.

Images built in one job reach the others as workflow artifacts (`docker-save`, `docker-load`). On
pull requests the dependency images are pulled when published and built locally otherwise; on
`main` they are published before the checks, so the first push to an empty repository works.

The `latest` channel is published only from the tip of `main` (`publish-guard`); a newer push
cancels an older publication. Jobs that write to `gh-pages` share one concurrency group and never
cancel each other.

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
