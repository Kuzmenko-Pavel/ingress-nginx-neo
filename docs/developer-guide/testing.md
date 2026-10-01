# Testing

| Target | What it runs | Needs |
|--------|--------------|-------|
| `make test-unit` | Go unit tests of the root module (without `test/e2e`, `images`, `docs/examples`) and of `images/{kube-webhook-certgen,custom-error-pages,fastcgi-helloserver}/rootfs` | Docker |
| `make test-unit-lua` | Lua unit tests (busted) of `rootfs/etc/nginx/lua` | Docker |
| `make helm-test` | helm-unittest suites in `charts/ingress-nginx-neo/tests` | — |
| `make helm-lint` | `helm lint --strict` and kubeconform for every `ci/*-values.yaml` | — |
| `make test-e2e` | controller e2e suite on kind | Docker |
| `make test-e2e-chart` | chart installation on kind for every `ci/*-values.yaml` | Docker |
| `make test-e2e-certgen` | kube-webhook-certgen e2e on kind | Docker |

`make check` runs the fast checks (lint, unit tests, generated files, chart lint and tests).

## Unit tests

Go and Lua unit tests run in the `e2e-test-runner` image (`tools/run-in-container.sh`), with the
repository mounted at `/src`, Go caches in `.cache/container` and a writable
`/etc/ingress-controller`. The image provides the Go toolchain of `go.mod`, the envtest binaries
(etcd, kube-apiserver) used by the store tests, and the Lua test tools (resty, busted, luacheck).

Lua tests live in `rootfs/etc/nginx/lua/test`; test files are named `<name>_test.lua`.

## Controller e2e

```console
make test-e2e                                     # all specs, default variant, newest Kubernetes
make test-e2e E2E_VARIANT=chroot                  # the controller-chroot image
make test-e2e FOCUS='default backend' E2E_NODES=4
make test-e2e K8S_VERSION=$(make -s print-K8S_VERSIONS | cut -d' ' -f1)   # oldest supported Kubernetes
```

The target:

1. ensures the dependency images (`make docker-build-deps`);
2. builds the controller image of the variant, kube-webhook-certgen, custom-error-pages and the
   suite image (`make docker-build`, `make docker-build-e2e`), unless `SKIP_BUILD=1`;
3. creates the kind cluster `ingress-nginx-neo-e2e` (`test/e2e/kind.yaml`, one control plane and
   two workers) with `kindest/node:<K8S_VERSION>`, loads every image into it and runs the suite in a
   pod (`test/e2e/run-kind-e2e.sh`);
4. writes the junit report to `test/junitreports/` and deletes the cluster (`DEBUG=true` keeps it).

The suite installs the chart from the image (`test/e2e/wait-for-nginx.sh`) into each test namespace
with the images of this run: the Makefile passes the registry, the image tag (`dev` locally), the
variant (`E2E_VARIANT=default|chroot`) and the references of the helper images (`E2E_ECHO_IMAGE`,
`E2E_HTTPBUN_IMAGE`, `E2E_FASTCGI_IMAGE`, `E2E_CFSSL_IMAGE`, `NGINX_BASE_IMAGE`). The suite fails
at start when one of them is missing. Namespace overlays in `test/e2e-image/namespace-overlays`
adjust the chart values for specific specs. Third-party images of the suite are pinned by digest
in `test/e2e/framework/images.go`.

| Variable | Default | Meaning |
|----------|---------|---------|
| `E2E_VARIANT` | `default` | `default` or `chroot` |
| `K8S_VERSION` | newest entry of `K8S_VERSIONS` | `kindest/node` tag with digest |
| `FOCUS` | empty | Ginkgo focus regular expression |
| `E2E_NODES` | `7` | parallel Ginkgo processes |
| `E2E_CHECK_LEAKS` | empty | non-empty runs the memory leak specs |
| `SKIP_BUILD` | empty | `1` uses images that are already present locally |

The specs are Ginkgo specs in `test/e2e`; `FOCUS` matches their descriptions, for example the
`Describe` texts of [test/e2e/defaultbackend](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/tree/main/test/e2e/defaultbackend).

## Chart e2e

`make test-e2e-chart` packages the chart, creates a kind cluster with cert-manager (pinned manifest
from `tools/versions.env`) and, for every `charts/ingress-nginx-neo/ci/*-values.yaml`, installs the
package with the locally built images, waits until the release is ready and uninstalls it
(`tools/e2e-chart.sh`).

## kube-webhook-certgen e2e

`make test-e2e-certgen` creates a kind cluster and runs
`images/kube-webhook-certgen/hack/e2e.sh`, which creates a certificate Secret and patches
ValidatingWebhookConfiguration, MutatingWebhookConfiguration and APIService objects.

## Kubernetes versions

`K8S_VERSIONS` in the Makefile lists the tested Kubernetes versions: the EKS standard support
window, each as a `kindest/node` tag with the digest built by the pinned kind version. CI runs the
e2e jobs for every entry. To change the window, edit `K8S_VERSIONS` (take the digests from the
release notes of the kind version in `tools/go.mod`) and the supported versions on the
[installation page](../deploy/index.md).

## Architectures

The suite runs on `linux/amd64` and `linux/arm64` hosts: every image it uses is published for both,
and local builds target the host platform. CI runs it on amd64.
