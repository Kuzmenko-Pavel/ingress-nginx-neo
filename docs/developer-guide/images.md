# Images

All images are published under one prefix, `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/`
(`REGISTRY` in the Makefile), for `linux/amd64` and `linux/arm64`.

## Delivered images

| Image | Sources | Purpose |
|-------|---------|---------|
| `controller` | `rootfs/Dockerfile` | the controller: NGINX base + controller binaries, template and Lua code |
| `controller-chroot` | `rootfs/Dockerfile-chroot` | the controller with NGINX in a chroot |
| `kube-webhook-certgen` | `images/kube-webhook-certgen` | admission webhook certificate jobs of the chart |
| `custom-error-pages` | `images/custom-error-pages` | default backend of the chart |

They carry the version of their channel as tag: `dev` for local builds, `latest` on `main`,
`vX.Y.Z` for a release; every channel builds them from source (see [Release](release.md)). Build
arguments and OCI labels are set by the Makefile; published builds add SBOM and provenance
attestations and a cosign signature.

```console
make docker-build                      # all four for the host platform, tag dev
make docker-build IMAGES=controller    # only the controller
```

The controller binaries are built by `make code-build` (`GOOS=linux`, `ARCH`) into
`rootfs/bin/<arch>`, which is the context of the controller Dockerfiles.

## Dependency images

| Image | Sources | Used by |
|-------|---------|---------|
| `nginx` | `images/nginx` | base of the controller images, the test runner and the echo image |
| `e2e-test-runner` | `images/test-runner` | Go and Lua unit tests, Lua lint, base of the e2e suite image |
| `e2e-test-echo` | `images/e2e-test-echo` | echo backend of the e2e suite |
| `httpbun` | `images/httpbun` | HTTP test backend of the e2e suite |
| `fastcgi-helloserver` | `images/fastcgi-helloserver` | FastCGI backend of the e2e suite |
| `cfssl` | `images/cfssl` | OCSP responder of the e2e suite; source of `cfssl` in the suite image |

Dependency images are **content addressed**: their tag is `src-<12 hex>`, computed by
`tools/content-tag.sh` from every file of `images/<name>/rootfs`, `images/<name>/build-args.env`
and every value passed as a build argument (for example the Go version, the base image tag, the
ginkgo and helm versions of the runner). The same sources always give the same tag, a change
always gives a new one, and there is no version to bump by hand.

```console
make print-NGINX_IMAGE          # references of this tree
make print-RUNNER_IMAGE
make docker-build-deps          # pull each src-* image, or build it for the host platform
make docker-build-deps DEPS=nginx
```

All build arguments of a dependency image live in its `build-args.env` (pinned versions and
checksums of downloaded components); the Go version is the toolchain of `go.mod`.

CI publishes a missing `src-*` image on `main` before the checks run, building each architecture on
a native runner and merging them into one index. A pull request that changes a dependency image
builds it locally for its own checks. After the checks of `main` pass, the dependency images are
also tagged `latest`; a release tags them with the release version. Both are new tags of the
digest that was tested, without a rebuild, so the e2e suite of any release can be run again later
with exactly its images.

The `e2e` image (the suite binary `e2e.test`, `make docker-build-e2e`) is built locally in every
e2e run and never published: it is the test itself.

## NGINX base

`images/nginx/rootfs/build.sh` downloads, patches and compiles NGINX, its modules, LuaJIT and the
Lua libraries; `images/nginx/rootfs/patches` holds the patches applied to the NGINX sources. See
[images/nginx/README.md](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/blob/main/images/nginx/README.md)
for its contents and for adding a patch or backporting an NGINX security fix. A change of the base
produces a new `src-*` tag; the controller images of the same commit are built from it.

## Architectures

Every image is published for `linux/amd64` and `linux/arm64`. Dependency images are built
natively per architecture (the NGINX build takes long under emulation); the delivered images are
built with QEMU for the foreign architecture, which only runs package installation steps.
