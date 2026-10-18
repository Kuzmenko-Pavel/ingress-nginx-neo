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

## Test first

A bug fix or a change of behavior starts with a test that fails without it: a Go unit, Lua, chart
or e2e test, or a lint rule when a test cannot express the defect. The code is then changed until
the test passes, so the test proves both the defect and the fix. A change of behavior without such
a test states the reason in the pull request.

## Which test

A test is written at the lowest level that catches the defect. e2e is needed only for behavior that
shows only on a running NGINX in a cluster. A test of a lower level runs in milliseconds instead of
tens of seconds, points to the cause of a failure more precisely and does not fail because of the
cluster. e2e checks what happens only on the path of a request through NGINX and Lua to a backend.

| What changes | Required test | e2e is needed as well when | Why |
|--------------|---------------|----------------------------|-----|
| parsing of an annotation or a ConfigMap key (`internal/ingress/annotations/*`, `internal/ingress/controller/config`) | Go unit: parsing, default value, errors, risk level | the annotation changes the handling of requests. One spec per behavior, not per value | the parser is a pure function, every branch is checked in milliseconds. e2e only confirms that the behavior reaches the traffic |
| the template `rootfs/etc/nginx/template/nginx.tmpl` | Go unit on the rendered result (`internal/ingress/controller/template`) | the behavior of a request or a response changes | which line ends up in nginx.conf is decided by rendering, not by the cluster |
| Lua (`rootfs/etc/nginx/lua`) | busted test `*_test.lua` | the synchronization of the configuration or the balancing on a running NGINX changes | busted checks the Lua logic, e2e is needed only for the integration with NGINX |
| store, synchronization, admission (`internal/ingress/controller/store`, `internal/admission`) | Go unit, envtest where a real API server is needed (as in the store tests) | an end-to-end path changes, for example admission rejects an Ingress | envtest gives a real kube-apiserver without NGINX and a cluster |
| chart templates and values | helm-unittest (`charts/ingress-nginx-neo/tests`) | a new installation mode appears. It gets a values file in `charts/ingress-nginx-neo/ci/`, and chart e2e checks it | templates are checked by rendering, chart e2e checks that the configuration installs and works |
| a controller flag | Go unit on the parsing of the flag (`pkg/flags`) | the flag changes the handling of requests | |
| kubectl plugin (`cmd/plugin`) | Go unit | no | the plugin does not handle traffic |
| a bug fix | a test that reproduces the bug at the lowest level where it shows | the bug shows only on traffic | the test fails without the fix and so proves both the bug and the fix |

For a change that is not in the table, the level follows from the column "Why".

### Example: a new annotation

1. The parser in `internal/ingress/annotations/<name>/` and a unit test of parsing, the default value and errors.
2. The risk level of the annotation (`Risk` in the annotation description).
3. The use in the template and a unit test of the rendering.
4. One e2e spec with an HTTP request, when the annotation changes the handling of requests.
5. `make docs-generate`, it updates `annotations-risk.md`.
6. `make check` and `make test-e2e FOCUS=<name>`.

## Unit tests

Go and Lua unit tests run in the `e2e-test-runner` image (`tools/run-in-container.sh`), with the
repository mounted at `/src`, Go caches in `.cache/container` and a writable
`/etc/ingress-controller`. The image provides the Go toolchain of `go.mod`, the envtest binaries
(etcd, kube-apiserver) used by the store tests, and the Lua test tools (resty, busted, luacheck,
luacov).

Lua tests live in `rootfs/etc/nginx/lua/test`; test files are named `<name>_test.lua`.

`TEST_ARGS` passes extra arguments to `go test`:

```console
make test-unit TEST_ARGS='-run TestStore -v'
```

## Test reports and coverage

`make test-unit`, `make test-unit-lua` and `make helm-test` write reports to `dist/test-reports/`
(`TEST_REPORTS`, a directory inside the repository, because the tests run in a container with the
repository at `/src`):

| File | Target | Content |
|------|--------|---------|
| `unit-go.xml`, `unit-go-<module>.xml` | `make test-unit` | JUnit of the Go tests of the root module and of every module in `images/*/rootfs` |
| `coverage-go.out`, `coverage-go-<module>.out` | `make test-unit` | coverage in the Go `coverprofile` format |
| `unit-lua.xml` | `make test-unit-lua` | JUnit of the Lua tests |
| `coverage-lua.lcov` | `make test-unit-lua` | coverage of the Lua code in `rootfs/etc/nginx/lua` in the LCOV format |
| `unit-helm.xml` | `make helm-test` | JUnit of the chart tests |

gotestsum (pinned in `tools/go.mod`, built in the container) runs the Go tests. It prints one line
per package, the full output of failed tests and the number of tests at the end. `make test-unit`
prints the total coverage of every module. The uncovered lines are shown by

```console
go tool cover -html=dist/test-reports/coverage-go.out
```

luacov counts the Lua coverage (`busted --coverage`), luacov-reporter-lcov writes the LCOV report.

In CI the jobs Unit tests and Helm chart keep `dist/test-reports/` as artifacts (see
[CI](ci.md#caches-and-artifacts)).

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

### Writing an e2e spec

1. **Check the behavior with a request.** The spec sends a request (`f.HTTPTestClient()`) and checks
   the response: status, headers, body. A check that a line is in nginx.conf is fine as an
   intermediate wait, but not as the only check. Otherwise it is a unit test of the rendering, only
   a thousand times slower. The model is `test/e2e/annotations/approot.go`. It creates an Ingress
   with `app-root: /foo`, sends a request to `/` and expects `302` with
   `Location: http://approot.bar.com/foo`.
2. **Wait for a condition, not for time.** `f.WaitForNginxServer`, `f.WaitForNginxConfiguration`,
   `f.WaitForReload` and the other `Wait*` of `test/e2e/framework` instead of `framework.Sleep` and
   `time.Sleep`. A sleep is either too long, and the spec is slow, or too short, and the spec is
   flaky on a slow runner. It also hides races. When a sleep is really needed (a check that nothing
   happens within N seconds), a comment next to it states the reason:

   ```go
   time.Sleep(5 * time.Second) //nolint:forbidigo // the spec checks that no reload happens within 5s
   ```

   `make code-lint` reports new and changed calls of `framework.Sleep` and `time.Sleep` in
   `test/e2e` (except `test/e2e/framework`). An existing call is reported when its line changes,
   because only the code changed against `main` is checked.
3. **Self-contained.** The spec creates its own resources and does not depend on other specs or
   their order. The suite runs the specs in parallel and in random order (`--randomize-all`).
4. **A separate installation only when needed.** `framework.IngressNginxDescribeSerial` runs the specs
   one at a time. A namespace overlay (`test/e2e-image/namespace-overlays/<name>/values.yaml`, used
   when the name of the framework equals `<name>`) changes the chart values of the controller of the
   spec. They are needed only when the spec changes global state: controller flags, cluster-scoped
   resources. A comment at the describe states the reason. Serial specs run one at a time and make
   the whole run longer.
5. **Time budget.** A spec longer than 60 seconds states the reason in the pull request. Every
   second of a spec is multiplied by the number of variants and Kubernetes versions in CI.
6. **A flaky spec does not hide behind a retry.** The suite makes up to two attempts
   (`--flake-attempts=2`). A spec that passes on the second attempt is a defect. It gets an issue
   and is fixed.

## Chart e2e

`make test-e2e-chart` packages the chart, creates a kind cluster with cert-manager (pinned manifest
from `tools/versions.env`) and installs every `charts/ingress-nginx-neo/ci/*-values.yaml` at the
same time, with the locally built images, each as a release `ci-<N>` in a namespace of its own
(`tools/e2e-chart.sh`). Several controllers thus run in one cluster, as described in
[Multiple Ingress controllers](../user-guide/multiple-ingress.md). Every release gets its own
IngressClass `ci-<N>` and `controller.admissionWebhooks.matchIngressClass`. A values file that sets
`controller.ingressClassResource` itself keeps its class and serves the Ingresses without a class.

The test then checks:
- every controller answers an Ingress of its class with a redirect 301, which NGINX sends itself
  without a backend, and answers 404 to the Ingress of the neighbouring release
- with the controller of one release scaled to 0, an Ingress of another release is created and
  served
- a second release with the IngressClass `nginx` stops with a hint which values to set

A readiness probe every second, `worker-processes=1` and `terminationGracePeriodSeconds: 0` are
settings of the test, not of the chart. The output shows the time until every release is ready. A
new values file in `ci/` joins the same parallel installation, so it has to coexist with the others:
no NodePorts that are taken and no cluster-scoped objects with fixed names.

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
window, each as a `kindest/node` tag with the digest built by the pinned kind version.
`make test-e2e` locally and e2e in CI on pull requests use the newest entry. Pushes to `main` and
`release-*`, manual runs and pull requests labeled `full-e2e` check every entry, see
[CI](ci.md#kubernetes-versions). `K8S_VERSION` selects another version locally (see the example
above). To change the window, edit `K8S_VERSIONS` (take the digests from the release notes of the
kind version in `tools/go.mod`) and the supported versions on the
[installation page](../deploy/index.md).

## Architectures

The suite runs on `linux/amd64` and `linux/arm64` hosts: every image it uses is published for both,
and local builds target the host platform. CI runs it on amd64.
