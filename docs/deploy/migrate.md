# Migrate from kubernetes/ingress-nginx

ingress-nginx-neo is based on the kubernetes/ingress-nginx codebase and keeps its user-facing API. This page
describes how to move an existing kubernetes/ingress-nginx installation to ingress-nginx-neo.

## What stays the same

Your Ingress resources and controller configuration keep working without changes:

- annotations with the prefix `nginx.ingress.kubernetes.io/*`;
- the IngressClass `nginx` and the controller value `k8s.io/ingress-nginx`;
- the [ConfigMap keys](../user-guide/nginx-configuration/configmap.md);
- the [command line arguments](../user-guide/cli-arguments.md) of the controller binary `/nginx-ingress-controller`;
- the Prometheus metrics `nginx_ingress_controller_*`, so dashboards and alerts keep working.

## What changes

| | kubernetes/ingress-nginx | ingress-nginx-neo |
|---|---|---|
| Helm chart | chart `ingress-nginx` from a Helm repository | `oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo` |
| Images | `registry.k8s.io` | `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/<name>`, see [Artifacts](./artifacts.md) |
| Chart name | `ingress-nginx` | `ingress-nginx-neo` |
| Resource names and `app.kubernetes.io/name` label | derived from `ingress-nginx` | derived from `ingress-nginx-neo` |
| Static manifests | namespace `ingress-nginx` | namespace and release name `ingress-nginx-neo` |
| kubectl plugin | plugin `ingress-nginx` | command `kubectl ingress-nginx-neo`, see [kubectl plugin](../kubectl-plugin.md) |

Version numbers are independent: pick a version from the
[releases page](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases) and read its release notes, in
particular the **Breaking changes** section.

### Resource names

Resource names and labels derive from the chart name. A release `ingress-nginx` of the ingress-nginx-neo chart
creates, for example, the Deployment `ingress-nginx-ingress-nginx-neo-controller` with the label
`app.kubernetes.io/name: ingress-nginx-neo`.

The selector labels of a Deployment or DaemonSet are immutable. Upgrading an existing release to a chart that
changes its names or labels would fail, or would replace the resources (with a new Service and therefore a new
load balancer address). To keep the names and labels of an existing kubernetes/ingress-nginx installation, the chart
name has to stay `ingress-nginx`:

- release installed directly with Helm: `--set nameOverride=ingress-nginx`;
- chart used as a dependency of your own chart: `alias: ingress-nginx` in the dependency.

## Direct Helm release

The steps below upgrade an existing release in place. Names, labels, the Service and its load balancer address
stay the same.

1. Save the values of the current release:

    ```console
    helm get values <release> --namespace <namespace> --output yaml > values.yaml
    ```

2. Remove your own image settings from `values.yaml`, unless they point to a
   [mirror](./artifacts.md#mirroring) of the ingress-nginx-neo images: `global.image.registry`, and
   `registry`, `image`, `repository`, `tag`, `digest` and `digestChroot` under `controller.image`,
   `controller.admissionWebhooks.patch.image` and `defaultBackend.image`. The released chart pins the digests of
   its images, so no image settings are needed.

3. Compare the remaining values with the values of the new chart:

    ```console
    helm show values oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo --version <version>
    ```

4. Upgrade the release to the ingress-nginx-neo chart and keep the chart name `ingress-nginx`:

    ```console
    helm upgrade <release> oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
      --version <version> \
      --namespace <namespace> \
      --values values.yaml \
      --set nameOverride=ingress-nginx
    ```

    Add `--dry-run` first to review the rendered resources. Keep `--set nameOverride=ingress-nginx` (or put
    `nameOverride: ingress-nginx` into `values.yaml`) in every later upgrade of this release.

    !!! warning "Do not use `--reuse-values` for this upgrade"
        With `--reuse-values`, Helm takes the defaults of the chart of the current release instead of the
        defaults of the new chart. The release would keep the image references of the kubernetes/ingress-nginx
        chart. Pass the values file as shown above, or use `--reset-then-reuse-values` (Helm 3.14 or newer), which
        applies the defaults of the new chart and then your own values. Remove your own image settings in both
        cases.

5. Check the rollout:

    ```console
    kubectl get pods --namespace <namespace> \
      --selector=app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller \
      -o jsonpath='{.items[*].spec.containers[*].image}'
    ```

    The controller image is `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/controller` (or your mirror).

To roll back, run `helm rollback <release> <revision> --namespace <namespace>` with the revision shown by
`helm history`.

## Chart dependency

If your own chart includes the kubernetes/ingress-nginx chart as a dependency, replace the dependency in your
`Chart.yaml` and keep the alias `ingress-nginx`:

```yaml
dependencies:
  - name: ingress-nginx-neo
    version: <version>
    repository: oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts
    alias: ingress-nginx
```

With the alias, the subchart is named `ingress-nginx`: its values stay under the key `ingress-nginx:` in the values
of your chart, and the names and labels of its resources stay the same. Remove your own image settings from these
values as described in step 2 above, then update the dependency and upgrade your release:

```console
helm dependency update
helm upgrade <release> . --namespace <namespace> --values <your values>
```

## Static manifests

The static manifests of ingress-nginx-neo are rendered with the release name and namespace `ingress-nginx-neo`.
They create the namespace `ingress-nginx-neo` and resources such as `ingress-nginx-neo-controller` and
`ingress-nginx-neo-controller-admission`. They do not replace the resources of a kubernetes/ingress-nginx manifest,
which live in the namespace `ingress-nginx`. The new controller gets a new Service and therefore a new load
balancer address. Choose one of the two approaches below.

### Side-by-side installation

Run both controllers in parallel with different IngressClasses, then move the Ingress resources one by one. This
approach avoids downtime.

1. Install ingress-nginx-neo with its own IngressClass. With Helm:

    ```console
    helm install ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
      --version <version> \
      --namespace ingress-nginx-neo --create-namespace \
      --set controller.ingressClassResource.name=nginx-neo \
      --set controller.ingressClassResource.controllerValue=k8s.io/ingress-nginx-neo \
      --set controller.ingressClass=nginx-neo
    ```

    With a static manifest, download `deploy-<provider>.yaml` and change, before applying it, the IngressClass
    `metadata.name` (`nginx`) and `spec.controller` (`k8s.io/ingress-nginx`), and the controller arguments
    `--ingress-class` and `--controller-class` to the same new values.

2. Find the address of the new controller with
   `kubectl get service ingress-nginx-neo-controller --namespace ingress-nginx-neo`.
3. Change `spec.ingressClassName` of each Ingress to `nginx-neo` and move its DNS records to the new address.
4. When no Ingress uses the class `nginx` anymore, delete the kubernetes/ingress-nginx installation with
   `kubectl delete -f <the manifest you applied>`.

See [Multiple Ingress controllers](../user-guide/multiple-ingress.md) for details on IngressClasses.

### Delete and re-apply

Replace the controller in one step. Ingress traffic is interrupted until the new controller is ready and DNS points
to its address.

1. Delete the kubernetes/ingress-nginx installation with `kubectl delete -f <the manifest you applied>`. This also
   deletes the IngressClass `nginx`; your Ingress resources stay.
2. Apply the ingress-nginx-neo manifest for your provider (see
   [Install with static manifests](./index.md#install-with-static-manifests)):

    ```console
    kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-<provider>.yaml
    ```

3. Point your DNS records to the address of `ingress-nginx-neo-controller` in the namespace `ingress-nginx-neo`.

Settings you made in the `ingress-nginx` namespace, such as the controller ConfigMap or TLS secrets used by
`--default-ssl-certificate`, have to be created again in the `ingress-nginx-neo` namespace, for example in the
ConfigMap `ingress-nginx-neo-controller`.

## kubectl plugin

The kubectl plugin of ingress-nginx-neo is invoked as `kubectl ingress-nginx-neo` (binary
`kubectl-ingress_nginx_neo`). Without `--pod`, `--deployment` or `--selector` it finds controller pods labeled
`app.kubernetes.io/name` `ingress-nginx-neo` or `ingress-nginx`, so it also works with a release that keeps the name
`ingress-nginx`. See [kubectl plugin](../kubectl-plugin.md).
