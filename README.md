# ingress-nginx-neo

[![CI](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/actions/workflows/ci.yaml?query=branch%3Amain)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Kuzmenko-Pavel/ingress-nginx-neo/badge)](https://scorecard.dev/viewer/?uri=github.com/Kuzmenko-Pavel/ingress-nginx-neo)
[![Release](https://img.shields.io/github/v/release/Kuzmenko-Pavel/ingress-nginx-neo?sort=semver)](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases)
[![License](https://img.shields.io/github/license/Kuzmenko-Pavel/ingress-nginx-neo)](./LICENSE)
[![Docs](https://img.shields.io/badge/docs-latest-blue)](https://kuzmenko-pavel.github.io/ingress-nginx-neo/)

An Ingress controller for Kubernetes using [NGINX](https://nginx.org/) as a reverse proxy and load
balancer.

ingress-nginx-neo is based on the [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx)
codebase and distributed under the [Apache License 2.0](./LICENSE). It is not affiliated with or
endorsed by the Kubernetes project, the CNCF or F5. NGINX is a trademark of F5, Inc.; Kubernetes is
a trademark of the Linux Foundation.

Documentation: <https://kuzmenko-pavel.github.io/ingress-nginx-neo/>

## Compatibility

The user-facing API is the one of kubernetes/ingress-nginx:

- annotations with the prefix `nginx.ingress.kubernetes.io/`;
- the IngressClass `nginx` with the controller value `k8s.io/ingress-nginx`;
- the keys of the controller ConfigMap and the command line arguments;
- the Prometheus metrics `nginx_ingress_controller_*`;
- the controller binary `/nginx-ingress-controller`.

## Install

Releases are listed on <https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases>. Every
release publishes signed images for `linux/amd64` and `linux/arm64` and a Helm chart that pins them
by digest.

Helm (OCI):

```console
helm install ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
  --version <version> \
  --namespace ingress-nginx-neo --create-namespace
```

Static manifests, one per provider (`aws`, `aws-nlb-with-tls-termination`, `baremetal`, `cloud`,
`do`, `exoscale`, `kind`, `oracle`, `scw`), are release assets:

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-cloud.yaml
```

kubectl plugin:

```console
kubectl krew install --manifest-url=https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/ingress-nginx-neo.yaml
kubectl ingress-nginx-neo --help
```

See [Installation](https://kuzmenko-pavel.github.io/ingress-nginx-neo/stable/deploy/) for the
supported Kubernetes versions and provider notes, and
[Artifacts and verification](https://kuzmenko-pavel.github.io/ingress-nginx-neo/stable/deploy/artifacts/)
for image references, signatures and mirroring.

### Resource names

Resource names and the `app.kubernetes.io/name` label derive from the chart name
`ingress-nginx-neo`. To keep the names of an existing kubernetes/ingress-nginx installation, set
`nameOverride=ingress-nginx` on a release installed directly, or use `alias: ingress-nginx` when the
chart is a dependency of another chart. See
[Migrate from kubernetes/ingress-nginx](https://kuzmenko-pavel.github.io/ingress-nginx-neo/stable/deploy/migrate/).

## Usage warning

Do not use the controller in multi-tenant Kubernetes clusters where users who can create Ingress
objects are not cluster administrators: annotations and snippets configure NGINX for the whole
controller. See the [FAQ](https://kuzmenko-pavel.github.io/ingress-nginx-neo/stable/faq/).

## Contributing and security

- [CONTRIBUTING.md](./CONTRIBUTING.md) — workflow, commit rules and checks.
- [SECURITY.md](./SECURITY.md) — reporting vulnerabilities and supported versions.
- [Developer guide](https://kuzmenko-pavel.github.io/ingress-nginx-neo/latest/developer-guide/getting-started/).

## License

[Apache License 2.0](./LICENSE).
