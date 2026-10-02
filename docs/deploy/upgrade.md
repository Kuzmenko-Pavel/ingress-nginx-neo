# Upgrading

This page describes how to upgrade an ingress-nginx-neo installation to a newer ingress-nginx-neo version. To move
an installation of kubernetes/ingress-nginx to ingress-nginx-neo, see
[Migrate from kubernetes/ingress-nginx](./migrate.md).

## Before you upgrade

1. Pick the target version on the [releases page](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases).
2. Read the release notes of every release between your current version and the target version, in particular the
   **Breaking changes** section.
3. If you use a [custom NGINX template](../user-guide/nginx-configuration/custom-template.md), make sure it is
   compatible with the new version: the template is tied to the controller version it was written for.

Check the version that is running with:

```console
helm list --namespace ingress-nginx-neo
```

or, for any installation method:

```console
kubectl get pods --namespace ingress-nginx-neo \
  --selector=app.kubernetes.io/name=ingress-nginx-neo,app.kubernetes.io/component=controller \
  -o jsonpath='{.items[*].spec.containers[*].image}'
```

## Versioning policy

- Every release has one version `vX.Y.Z` that applies to all artifacts: images, Helm chart, kubectl plugin,
  static manifests and documentation. Helm accepts it as the chart version.
- ingress-nginx-neo uses 0.x versions. A **minor** release (`0.Y.0`) may contain breaking changes; they are always
  listed in the **Breaking changes** section of its release notes. A **patch** release (`0.Y.Z`) contains only fixes.
- Only the latest minor release is supported. Upgrade to the latest patch release of the latest minor release to
  receive fixes.
- Published versions are immutable: an image tag or chart version is never overwritten. A fix always ships as a new
  version.

## With Helm

Upgrade the release to the target release, here `<version>`:

```console
helm upgrade ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
  --version <version> \
  --namespace ingress-nginx-neo \
  --values my-values.yaml
```

Pass the same values files and `--set` flags as for the installation. To keep the values of the current release
without passing them again, use `--reset-then-reuse-values` (Helm 3.14 or newer): it applies the defaults of the new
chart, then the values you set.

!!! warning
    Do not use `--reuse-values`. With it, Helm keeps the defaults of the chart version of the current release,
    including its image digests, so the images would not be upgraded.

The released chart pins the image digests of its release, so an upgrade of the chart also upgrades all images. Do
not set image tags or digests yourself, unless they point to a mirror (see
[Artifacts and verification](./artifacts.md#mirroring)).

### Rollback

Helm keeps the history of a release. To return to the previous revision:

```console
helm history ingress-nginx-neo --namespace ingress-nginx-neo
helm rollback ingress-nginx-neo <revision> --namespace ingress-nginx-neo
```

A rollback restores the chart, values and image digests of that revision.

## With static manifests

Apply the manifest of the target release, here `<version>`, for the same provider you installed:

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-<provider>.yaml
```

The manifest pins every image by digest, so applying it upgrades the
controller, the admission webhook jobs and all other resources together. `kubectl apply` does not delete resources
that are missing from the new manifest; delete them yourself if the release notes mention such a change.

To roll back, apply the manifest of the release you upgraded from.

If you modified the manifest before applying it (for example `deploy-aws-nlb-with-tls-termination.yaml`), apply the
same modifications to the manifest of the new release.

## The `0.0.0-latest` channel

The `main` branch is published continuously: images with the tag `latest` and the chart version `0.0.0-latest`.
Helm never selects this chart version automatically, it has to be requested explicitly:

```console
helm upgrade --install ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
  --version 0.0.0-latest \
  --namespace ingress-nginx-neo --create-namespace
```

`0.0.0-latest` is a prerelease version, so `--devel` does not select it: `--devel` picks the newest release. The
`latest` channel follows the `main` branch and is meant for testing, not for production clusters.
