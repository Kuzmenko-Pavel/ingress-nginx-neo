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
| `make test-load` | k6 load test of the dev environment, memory and CPU of the controller; not run in CI | Docker, `make dev-env-up` |

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
package with the locally built images in a namespace of its own, waits until the release is ready,
uninstalls it and deletes the namespace without waiting (`tools/e2e-chart.sh`). The controller runs
with `terminationGracePeriodSeconds: 0`: the test checks installations, not the draining of
connections. The output shows the duration of every installation.

## kube-webhook-certgen e2e

`make test-e2e-certgen` creates a kind cluster and runs
`images/kube-webhook-certgen/hack/e2e.sh`, which creates a certificate Secret and patches
ValidatingWebhookConfiguration, MutatingWebhookConfiguration and APIService objects.

## Load tests

`make test-load` loads the installation of `make dev-env-up`: the chart `ingress-nginx-neo` with the
images of the current tree, the default backend (custom-error-pages) and metrics enabled. k6
([test/k6/load.js](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/blob/main/test/k6/load.js),
image `K6_IMAGE` of `tools/versions.env`) runs in a container on the developer machine, in the
Docker network of kind, and sends requests to the kind node:

```text
k6 -> node port 80/443 -> controller pod: NGINX (base image, patches, TLS),
      nginx.conf rendered from Ingress and ConfigMap, Lua balancer and monitor
   -> backends of test/k6/workload.yaml (namespace ingress-nginx-neo-load)
```

The backends are `e2e-test-echo` (`load.local`, NGINX with Lua, faster than the controller, so that
the controller is the measured component) and `httpbun` (`errors.load.local`, whose 404 and 503
responses the controller replaces with pages of the default backend). Both hosts answer HTTP and HTTPS
without a redirect, so `PROTOCOL` selects what is measured.

```console
make dev-env-up
make test-load                                          # steady, http, 500 requests/s, 1m
make test-load PROTOCOL=https REUSE=false               # TLS handshake per request
make test-load BODY_SIZE=65536                          # POST with a 64 KiB body
make test-load LOAD_SCENARIO=limit RATE=5000 DURATION=3m
make test-load LOAD_SCENARIO=reload
make test-load LOAD_SCENARIO=soak MEM_GROWTH_MAX_PCT=10
make test-load LOAD_SCENARIO=default-backend
```

| Scenario | Load | Question |
|----------|------|----------|
| `steady` | `RATE` requests/s for `DURATION` | latency and errors at a given rate |
| `limit` | from `RATE`/20 to `RATE` requests/s over `DURATION`; stops at the first sustained threshold violation | the request rate this setup sustains |
| `reload` | as `steady`, while the echo Deployment scales between 2 and 4 replicas (endpoints applied by Lua) and an annotation of the Ingress changes (NGINX reload) every `CHURN_INTERVAL` seconds | errors and latency during configuration changes |
| `soak` | as `reload`, 30m by default | memory and CPU growth over time |
| `default-backend` | `RATE` requests/s to an unknown host and to intercepted 404 and 503 responses | status codes and pages of the default backend under load |

The requests follow an open model: they start at the configured rate whatever the response times,
so saturation shows up as latency, failed requests and dropped iterations. Thresholds: failed
requests below 1% (0.1% for `reload` and `soak`), `p(95)` below `P95_MS` (500), `p(99)` below
`P99_MS` (1500), no dropped iterations, checks above 99%; k6 fails the run when one is violated.

Parameters (make variables or environment): `LOAD_SCENARIO`, `PROTOCOL` (`http`, `https`), `RATE`,
`DURATION`, `BODY_SIZE` (bytes of a POST body, 0 sends GET), `REUSE` (`false` opens a connection
per request), `P95_MS`, `P99_MS`, `MAX_VUS` (concurrent requests, 2000), `CHURN_INTERVAL` (10),
`SAMPLE_INTERVAL` (10), `WARMUP` (seconds; 60 for `soak`, 10 otherwise), `MEM_GROWTH_MAX_PCT`.

### Memory and CPU

Every `SAMPLE_INTERVAL` seconds the test reads the metrics of the controller pod through the
Kubernetes API (`/api/v1/namespaces/<namespace>/pods/<pod>:10254/proxy/metrics`) and the cgroup of
the controller container:

- NGINX processes: `nginx_ingress_controller_nginx_process_resident_memory_bytes`,
  `nginx_ingress_controller_nginx_process_cpu_seconds_total`,
  `nginx_ingress_controller_nginx_process_num_procs`;
- controller process: `process_resident_memory_bytes`, `go_memstats_heap_inuse_bytes`,
  `process_cpu_seconds_total`, `go_goroutines`;
- container: `memory.current`, `usage_usec` of `cpu.stat`.

The summary compares the last sample with the first one after `WARMUP` seconds: memory at both
points, maximum, growth, average CPU in cores and restarts of the controller container. Memory that
keeps growing after the warm-up instead of reaching a plateau, above all in `soak`, points to a leak;
with `MEM_GROWTH_MAX_PCT` a larger growth of the NGINX or controller memory fails the run. The
`[Memory Leak]` specs of the e2e suite (`test/e2e/leaks`) cover reloads without traffic.

### Results

`dist/load/` keeps every run under `<scenario>-<protocol>-<commit>-<time>`:

- `.json` — the k6 summary (`--summary-export`): request rate, latency percentiles, failed requests;
- `-resources.csv` — the samples;
- `-resources.txt` — the resource summary.

Generator, kind node, controller and backends share one machine, and the dev environment runs one
controller replica with `worker-processes=1`. The numbers are therefore not the capacity of a
production installation; they compare builds: run the same scenario on two commits on the same
machine and compare the files of both runs.

## Kubernetes versions

`K8S_VERSIONS` in the Makefile lists the tested Kubernetes versions: the EKS standard support
window, each as a `kindest/node` tag with the digest built by the pinned kind version. CI runs the
e2e jobs for every entry. To change the window, edit `K8S_VERSIONS` (take the digests from the
release notes of the kind version in `tools/go.mod`) and the supported versions on the
[installation page](../deploy/index.md).

## Architectures

The suite runs on `linux/amd64` and `linux/arm64` hosts: every image it uses is published for both,
and local builds target the host platform. CI runs it on amd64.
