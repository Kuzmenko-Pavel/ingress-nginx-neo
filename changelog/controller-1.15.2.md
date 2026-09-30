# Changelog

### controller-v1.15.2

First release of the self-maintained distribution built entirely from this repository
(no `registry.k8s.io` images at build or release time).

Images:

* ghcr.io/kuzmenko-pavel/ingress-nginx/controller:v1.15.2
* ghcr.io/kuzmenko-pavel/ingress-nginx/controller-chroot:v1.15.2
* ghcr.io/kuzmenko-pavel/ingress-nginx/kube-webhook-certgen:v1.6.10
* ghcr.io/kuzmenko-pavel/ingress-nginx/custom-error-pages:v1.3.0 (chart default backend)
* NGINX base: ghcr.io/kuzmenko-pavel/ingress-nginx/nginx:v2.2.10

All images are published for `linux/amd64` and `linux/arm64`. Digests, signatures (cosign
keyless) and SBOM/provenance are listed in the GitHub Release, together with static manifests
per provider (`deploy-<provider>.yaml`).

### Security

nginx 1.27.1 backports (taken from chainguard-forks/ingress-nginx):

* CVE-2026-42945 — rewrite: escaping / heap buffer overrun
* CVE-2026-9256 — rewrite: overlapping captures heap overflow
* CVE-2026-49975 — header flood DoS over HTTP/1.x, HTTP/2, HTTP/3; adds `max_headers` (default 1000)
* CVE-2026-42055 — gRPC / HTTP/2 upstream header length overflow
* CVE-2026-48142 — `charset_map` UTF-8 recode overread
* CVE-2026-42533 — script engine buffer-overrun protection (`map` with regex)

Go:

* Go 1.26.1 → 1.26.8 (standard library fixes)
* golang.org/x/net v0.59.0, x/crypto v0.57.0, x/sys v0.48.0, x/text v0.42.0, x/mod v0.41.0,
  helm.sh/helm/v4 v4.1.4, google.golang.org/grpc v1.83.2 (all reachable govulncheck findings)

### Behaviour changes

* The Helm chart defaults to this distribution's images (`ghcr.io/kuzmenko-pavel/ingress-nginx`);
  the default backend (when enabled) is `custom-error-pages` instead of `defaultbackend-amd64`.

* Requests with more than 1000 header lines are rejected with HTTP 400 (`max_headers`).
* The NGINX base is ABI-incompatible with third-party dynamic modules built against stock nginx 1.27.1.

### Build and release

* NGINX base image, e2e test runner and all release artifacts are built by this repository's
  GitHub Actions; images and chart are signed with cosign and carry SBOM and provenance.
* `linux/amd64` and `linux/arm64` for every image (the NGINX base is built on native runners).
* Static manifests per provider are generated from the chart and attached to the release.
* CI tests Kubernetes 1.34, 1.35 and 1.36 (EKS standard support window).

**Full Changelog**: https://github.com/Kuzmenko-Pavel/ingress-nginx/compare/v1.15.1...v1.15.2
