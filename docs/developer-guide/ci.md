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
| E2E | `make docker-load test-e2e SKIP_BUILD=1 K8S_VERSION=… E2E_VARIANT=… E2E_SHARD=…` | every variant × [Kubernetes versions](#kubernetes-versions) × [shard](testing.md#shards) |
| Chart e2e | `make docker-load test-e2e-chart SKIP_BUILD=1 K8S_VERSION=…` | [Kubernetes versions](#kubernetes-versions) |
| kube-webhook-certgen e2e | `make test-e2e-certgen` | groups `certgen`, `e2e`, `build-system`, `workflow`; always outside pull requests |
| **CI result** | `make ci-result` | always (not when the run is cancelled) |
| Publish latest | `make docker-publish docker-promote docker-sign helm-package helm-publish CHANNEL=latest`, `make code-build-plugin CHANNEL=latest` | pushes to `main` and manual runs on `main`, after CI result passed |
| Publish docs (latest) | `make docs-publish CHANNEL=latest` | after Publish latest |

The Kubernetes matrix comes from `make -s print-k8s-versions` (on pull requests from
`make -s print-k8s-versions-pr`), the e2e variants from
`make -s print-e2e-variants`, the e2e shards from `make -s print-e2e-shards`, the dependency image platforms from `make -s print-deps-platforms`.

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

## Kubernetes versions

On pull requests E2E and Chart e2e run on the newest Kubernetes version, the same as `make test-e2e`
locally. Pushes to `main` and `release-*` and manual runs check every version of `K8S_VERSIONS`.
The variants `default` and `chroot` are different controller images, so both always run.

The versions differ in the APIs the controller uses (Ingress, IngressClass, EndpointSlice, Lease,
admission), and inside the supported window these APIs are stable. A breakage on one version only
is rare, and the run on `main` catches it. A release is tagged only on a commit of `main` or
`release-X.Y` with a passed CI result, so no release ships without a check of every version.

When a change depends on the Kubernetes version, request the full matrix on the pull request:
- the label `full-e2e` on the pull request. The next push, opening or reopening runs every version
  until the label is removed
- a manual run on the branch of the pull request, right away and without a new push:

  ```console
  gh workflow run ci.yaml --ref <branch>
  ```

  Its CI result belongs to the last commit of the branch and shows in the pull request

Adding the label does not start a run by itself. A new run of a pull request cancels the running
one, and the `labeled` event comes for any label, so every label would restart CI. Add `full-e2e`
only when the change depends on the version. It triples the runner time of e2e.

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
| `docs` | `docs/**`, `mkdocs.yml`, `charts/**`, `internal/ingress/controller/testdata/golden/**` (the examples of `annotations.md`), `make/docs.mk`, `tools/docs/**`, `tools/docs-publish.sh` |
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
- Unit tests and Helm chart keep `dist/test-reports/` (JUnit and coverage, see
  [Testing](testing.md#test-reports-and-coverage)) as the artifacts `test-reports-unit` and
  `test-reports-helm`, also when the tests failed.
- Artifacts are kept for at most 7 days.

## Coverage and test results

CI uploads the reports to [Codecov](https://codecov.io/gh/Kuzmenko-Pavel/ingress-nginx-neo)
(`codecov/codecov-action`, settings in `codecov.yml`):

| Job | Coverage | Test results |
|-----|----------|--------------|
| Unit tests | `coverage-go.out`, `coverage-go-kube-webhook-certgen.out`, `coverage-go-custom-error-pages.out` (flag `go`), `coverage-lua.lcov` (flag `lua`) | `unit-go.xml`, `unit-go-kube-webhook-certgen.xml`, `unit-go-custom-error-pages.xml` (`go`), `unit-lua.xml` (`lua`) |
| Helm chart | | `unit-helm.xml` |
| E2E | | `test/junitreports/*.xml` |

The flags `go` and `lua` split the coverage by language. The test results of helm and e2e have no
flag, because no coverage is measured for them, and Codecov shows a flag without coverage as 0%.

Coverage is uploaded only after the tests passed, because the coverage of a failed run is
incomplete. Test results are uploaded also when the tests failed. The module `fastcgi-helloserver`
is not uploaded, it is a helper image of e2e without tests.

Codecov comments on the pull request with the change of coverage against the base, the coverage of
the changed files and the failed tests. It also sets the checks `codecov/project`, which fails when
the coverage drops by more than 1%, and the informational `codecov/patch`. The only required check
stays CI result. The upload uses the secret `CODECOV_TOKEN`. A pull request from a fork has no
secrets, and Codecov accepts the upload of a public repository without a token. A failed upload
does not fail the job (`fail_ci_if_error: false`), because Codecov is an external service.

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
and deployment tags `v*`; release immutability; GitHub Pages deployed from the `gh-pages` branch;
the Codecov app with access to the repository and the Actions secret `CODECOV_TOKEN`.
