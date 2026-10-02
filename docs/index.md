# ingress-nginx-neo

**ingress-nginx-neo** is an NGINX Ingress controller for Kubernetes. It is built around the
[Kubernetes Ingress resource](https://kubernetes.io/docs/concepts/services-networking/ingress/) and uses a
[ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/) to store the controller configuration.

ingress-nginx-neo is a distribution based on the
[kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx) codebase and is licensed under the
Apache License 2.0. It is not affiliated with the Kubernetes project, the CNCF or F5. NGINX is a trademark of F5.

You can learn more about using [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) in the
official [Kubernetes documentation](https://docs.k8s.io).

## API compatibility

The user-facing API is compatible with kubernetes/ingress-nginx. Existing Ingress resources and controller
configuration work unchanged:

- annotations with the prefix `nginx.ingress.kubernetes.io/*`;
- the IngressClass `nginx` with the controller value `k8s.io/ingress-nginx`;
- the [ConfigMap keys](./user-guide/nginx-configuration/configmap.md);
- the [command line arguments](./user-guide/cli-arguments.md) of the controller binary `/nginx-ingress-controller`;
- the Prometheus metrics `nginx_ingress_controller_*`.

Chart, image and resource names are specific to ingress-nginx-neo. See
[Migrate from kubernetes/ingress-nginx](./deploy/migrate.md) for the details.

## Quick start

Install the release `<version>` of the Helm chart from the OCI registry (other versions are on the
[releases page](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases)):

```console
helm install ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
  --version <version> \
  --namespace ingress-nginx-neo --create-namespace
```

Then set `spec.ingressClassName: nginx` on your Ingress resources.

See the [installation guide](./deploy/index.md) for static manifests, provider-specific settings and how to
verify the installation.

## Where to go next

- [Deploy](./deploy/index.md): installation, [upgrade](./deploy/upgrade.md),
  [migration](./deploy/migrate.md) and [artifacts and verification](./deploy/artifacts.md).
- [User guide](./user-guide/nginx-configuration/index.md): annotations, ConfigMap, TLS, monitoring and more.
- [kubectl plugin](./kubectl-plugin.md): inspect a running controller with `kubectl ingress-nginx-neo`.
- [Releases](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases): release notes, static manifests
  and plugin binaries.
- [GitHub repository](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo): source code and issues.
