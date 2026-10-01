# Artifacts and verification

Every ingress-nginx-neo release publishes container images and a Helm chart to the GitHub Container Registry
(`ghcr.io`) and attaches static manifests, the kubectl plugin and checksum files to the GitHub release. All
artifacts of a release share one version `vX.Y.Z`; the chart version is the same number without the `v` prefix.
Releases are listed on the [releases page](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases).

## Artifacts

### Images

All images share the prefix `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/` and are published for `linux/amd64` and
`linux/arm64`.

| Image | Purpose |
|-------|---------|
| `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/controller` | the ingress controller |
| `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/controller-chroot` | the ingress controller running NGINX in a chroot (`controller.image.chroot=true`) |
| `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/kube-webhook-certgen` | creates and patches the admission webhook certificate (chart hook jobs) |
| `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/custom-error-pages` | default backend with custom error pages (`defaultBackend.enabled=true`) |

Build and test images, published under the same prefix and also tagged with each release version:

| Image | Purpose |
|-------|---------|
| `nginx` | NGINX base image of the controller images |
| `e2e-test-runner` | build, lint and test environment |
| `e2e-test-echo` | echo backend for end-to-end tests |
| `httpbun` | HTTP test backend for end-to-end tests |
| `fastcgi-helloserver` | FastCGI test backend for end-to-end tests |
| `cfssl` | certificate tooling for end-to-end tests |

### Helm chart, manifests and plugin

| Artifact | Location |
|----------|----------|
| Helm chart (OCI) | `oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo`, version `X.Y.Z` |
| Static manifests | release assets `deploy-<provider>.yaml` for the providers `aws`, `aws-nlb-with-tls-termination`, `baremetal`, `cloud`, `do`, `exoscale`, `kind`, `oracle`, `scw` |
| Manifest checksums | release asset `deploy-manifests.sha256` |
| kubectl plugin | release assets `kubectl-ingress_nginx_neo_<os>_<arch>.tar.gz` (`.zip` for Windows) for `linux`, `darwin` and `windows` on `amd64` and `arm64` |
| Plugin checksums | release asset `checksums.sha256` with its signature bundle `checksums.sha256.sigstore.json` |
| krew manifest | release asset `ingress-nginx-neo.yaml` |

Release assets are downloaded from
`https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/<file>`, where `<version>` is the
release tag `vX.Y.Z`. See [Installation](./index.md) for the manifests and [kubectl plugin](../kubectl-plugin.md)
for the plugin.

## Tags and digests

- Image tags are the release version `vX.Y.Z`. The released chart has the appVersion `vX.Y.Z` and pins the digest of
  every image it deploys, so a chart version always deploys exactly the images built for its release. The static
  manifests are rendered from that chart and pin the same digests.
- The release notes list every artifact of the release with its digest.
- Published versions are immutable: an image tag, chart version or release asset is never overwritten.

### The `latest` channel

The `main` branch is published continuously as images with the tag `latest` and the chart version `0.0.0-latest`.
The chart of this channel references the `latest` images. Select it explicitly with `--version 0.0.0-latest`; it
is a prerelease version, so Helm never picks it by default and `--devel` picks the newest release instead. Use this
channel for testing only. See [Upgrade](./upgrade.md#the-000-latest-channel).

## Verify signatures

Images, the chart and the plugin checksums of a release are signed with [cosign](https://docs.sigstore.dev/)
keyless signing by the release workflow of the repository. The signing identity is the release workflow at the
release tag.

### Images

```console
cosign verify ghcr.io/kuzmenko-pavel/ingress-nginx-neo/controller:<version> \
  --certificate-identity-regexp '^https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/\.github/workflows/release\.yaml@refs/tags/<version>$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The same command verifies every image of the release: replace `controller` with the image name. To verify the exact
image you run, use its digest reference (`ghcr.io/kuzmenko-pavel/ingress-nginx-neo/controller@sha256:...`) from the
release notes or from the running pod.

### Helm chart

The chart is verified like an image, with the chart version (`X.Y.Z`) as the tag and the release tag (`vX.Y.Z`) in
the identity:

```console
cosign verify ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo:<chart version> \
  --certificate-identity-regexp '^https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/\.github/workflows/release\.yaml@refs/tags/<version>$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### kubectl plugin

Download `checksums.sha256`, `checksums.sha256.sigstore.json` and the archive for your platform from the release,
verify the signature of the checksum file, then the archive:

```console
cosign verify-blob checksums.sha256 --bundle checksums.sha256.sigstore.json \
  --certificate-identity-regexp '^https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/\.github/workflows/release\.yaml@refs/tags/<version>$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
sha256sum --check --ignore-missing checksums.sha256
```

### Static manifests

The static manifests are covered by `deploy-manifests.sha256`:

```console
sha256sum --check --ignore-missing deploy-manifests.sha256
```

## SBOM and provenance

The delivered images (`controller`, `controller-chroot`, `kube-webhook-certgen`, `custom-error-pages`) carry an SBOM
and a provenance attestation. Inspect them with Docker Buildx:

```console
docker buildx imagetools inspect ghcr.io/kuzmenko-pavel/ingress-nginx-neo/controller:<version> --format '{{ json .SBOM }}'
docker buildx imagetools inspect ghcr.io/kuzmenko-pavel/ingress-nginx-neo/controller:<version> --format '{{ json .Provenance }}'
```

## Mirroring

All images share the prefix `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/`. To pull them from your own registry:

1. Mirror the prefix and keep the paths below the registry host, for example
   `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/controller` to
   `registry.example.com/kuzmenko-pavel/ingress-nginx-neo/controller`. Copy the multi-platform image indexes
   unchanged (for example with `crane copy` or `skopeo copy --all`), so that the digests stay the same.
2. Install the released chart with the registry of the mirror:

    ```console
    helm install ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
      --version <version> \
      --namespace ingress-nginx-neo --create-namespace \
      --set global.image.registry=registry.example.com
    ```

The image paths `kuzmenko-pavel/ingress-nginx-neo/<name>` stay the same, and the digests pinned by the chart stay
valid because an unchanged copy keeps its digest. The chart itself can be mirrored the same way and installed from
`oci://registry.example.com/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo`.

The signatures stay valid for the mirrored images; `cosign copy` copies an image together with its signatures and
attestations, so `cosign verify` also works against the mirror.
