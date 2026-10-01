# Installation Guide

ingress-nginx-neo can be installed in two ways:

- with [Helm](https://helm.sh), using the chart published as an OCI artifact (recommended);
- with `kubectl apply`, using the static manifests attached to every release.

Both methods install the same resources into the namespace `ingress-nginx-neo` with the release name
`ingress-nginx-neo`, so the controller Deployment and Service are named `ingress-nginx-neo-controller`.

Every command below uses `<version>` as a placeholder. Pick a version from the
[releases page](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases): Helm takes the chart version
without the `v` prefix (`X.Y.Z`), release asset URLs take the release tag (`vX.Y.Z`).

## Contents

<!-- Quick tip: run `grep '^##' index.md` to check that the table of contents is up-to-date. -->

- [Prerequisites](#prerequisites)
- [Supported Kubernetes versions](#supported-kubernetes-versions)
- [Install with Helm](#install-with-helm)
- [Install with static manifests](#install-with-static-manifests)
- [Verify the installation](#verify-the-installation)
- [Environment-specific instructions](#environment-specific-instructions)
- [Miscellaneous](#miscellaneous)

## Prerequisites

- A Kubernetes cluster in the [supported version range](#supported-kubernetes-versions) and `kubectl`
  configured for it.
- [Helm](https://helm.sh/docs/intro/install/) 3.8 or newer for the Helm installation (OCI registry support).
- Network access from the cluster nodes to `ghcr.io`, or a mirror of the images
  (see [Artifacts and verification](./artifacts.md#mirroring)).
- Permissions to create cluster-scoped resources (ClusterRole, ClusterRoleBinding, IngressClass,
  ValidatingWebhookConfiguration).

### Firewall configuration

In general, you need:

- Port 8443 open from the Kubernetes API server to the nodes running the controller. It is used by the
  [admission webhook](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/) served
  by the controller.
- Port 80 (HTTP) and/or 443 (HTTPS) open to the clients, on the load balancer or on the nodes your DNS
  records point to.

To check which ports your installation uses, look at the output of
`kubectl get pod --namespace ingress-nginx-neo -o yaml`.

## Supported Kubernetes versions

ingress-nginx-neo supports the Kubernetes versions of the
[Amazon EKS standard support window](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html).
Every change is tested in CI on [kind](https://kind.sigs.k8s.io/) clusters with these versions:

| Kubernetes | Tested in CI |
|------------|--------------|
| 1.36       | yes          |
| 1.35       | yes          |
| 1.34       | yes          |

The static manifests are rendered for the oldest version in this list. Only `networking.k8s.io/v1` Ingress and
IngressClass resources are supported.

## Install with Helm

The chart is published at `oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo`. A released
chart pins every image by digest, so no image overrides are needed.

### Install

```console
helm install ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
  --version <version> \
  --namespace ingress-nginx-neo --create-namespace
```

To make the command idempotent (install if missing, upgrade otherwise), use `helm upgrade --install` with the same
arguments.

### Values

Show the chart metadata and the full list of values:

```console
helm show chart oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo --version <version>
helm show values oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo --version <version>
```

All values are documented in the
[chart README](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/blob/main/charts/ingress-nginx-neo/README.md).
Pass your own values with `--values my-values.yaml` or `--set key=value`.

!!! attention "Cloud provider settings"
    The default chart values are generic and not tuned for any infrastructure provider. Load balancer annotations
    for your cloud provider have to be set in `controller.service.annotations`. The
    [static manifests](#install-with-static-manifests) show the settings used for each provider; see also the
    [environment-specific instructions](#environment-specific-instructions).

    For example, these annotations configure an AWS NLB with IP targets through the
    [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/annotations/)
    (the health check annotations are required for target type `ip`):

    ```yaml
    controller:
      service:
        annotations:
          service.beta.kubernetes.io/aws-load-balancer-type: nlb
          service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
          service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
          service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
          service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
          service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: deregistration_delay.timeout_seconds=270
          service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: /healthz
          service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "10254"
          service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: http
          service.beta.kubernetes.io/aws-load-balancer-healthcheck-success-codes: 200-299
          service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules: "true"
    ```

### Upgrade

```console
helm upgrade ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
  --version <version> \
  --namespace ingress-nginx-neo
```

Read the release notes before upgrading. See [Upgrade](./upgrade.md) for the versioning policy and rollback.

### Uninstall

```console
helm uninstall ingress-nginx-neo --namespace ingress-nginx-neo
kubectl delete namespace ingress-nginx-neo
```

## Install with static manifests

Every release attaches one manifest per provider, rendered from the released chart with the release name and
namespace `ingress-nginx-neo`. The manifests create the namespace and pin every image by digest:

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-<provider>.yaml
```

| `<provider>` | Service | Settings |
|--------------|---------|----------|
| `cloud` | `LoadBalancer` | generic cloud provider (GKE, AKS, ...), `externalTrafficPolicy: Local` |
| `aws` | `LoadBalancer` | AWS NLB (in-tree service load balancer annotations) |
| `aws-nlb-with-tls-termination` | `LoadBalancer` | AWS NLB terminating TLS with an ACM certificate (needs editing, see [below](#tls-termination-in-aws-load-balancer-nlb)) |
| `do` | `LoadBalancer` | DigitalOcean load balancer with PROXY protocol |
| `scw` | `LoadBalancer` | Scaleway load balancer with PROXY protocol v2 |
| `exoscale` | `LoadBalancer` | Exoscale load balancer, controller as a DaemonSet |
| `oracle` | `LoadBalancer` | Oracle Cloud Infrastructure flexible load balancer |
| `baremetal` | `NodePort` | bare-metal clusters, see [bare-metal considerations](./baremetal.md) |
| `kind` | `LoadBalancer` + `hostPort` | local [kind](https://kind.sigs.k8s.io/) clusters |

The SHA-256 checksums of all manifests of a release are in `deploy-manifests.sha256`, attached to the same release:

```console
curl -fsSLO https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-cloud.yaml
curl -fsSLO https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-manifests.sha256
sha256sum --check --ignore-missing deploy-manifests.sha256
kubectl apply -f deploy-cloud.yaml
```

!!! info
    The static manifests are generated with `helm template`, so they create the same resources as a Helm
    installation with the provider settings listed above. To change other settings, install with Helm instead.

To upgrade, apply the manifest of the new release (see [Upgrade](./upgrade.md)). To uninstall, delete the
resources of the manifest you applied:

```console
kubectl delete -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-<provider>.yaml
```

## Verify the installation

### Pre-flight check

A few pods start in the `ingress-nginx-neo` namespace:

```console
kubectl get pods --namespace ingress-nginx-neo
```

The following command waits until the controller pod is up, running and ready:

```console
kubectl wait --namespace ingress-nginx-neo \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=ingress-nginx-neo,app.kubernetes.io/component=controller \
  --timeout=120s
```

!!! attention "Admission webhook certificate"
    On the first installation, two [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
    create the TLS certificate used by the admission webhook. Until the controller pod is ready, which can take up
    to two minutes, creating Ingress resources may fail with a webhook error.

### Local testing

Create a simple web server and the associated service:

```console
kubectl create deployment demo --image=httpd --port=80
kubectl expose deployment demo
```

Then create an Ingress resource. The following example uses a host that maps to `localhost`:

```console
kubectl create ingress demo-localhost --class=nginx \
  --rule="demo.localdev.me/*=demo:80"
```

Forward a local port to the ingress controller:

```console
kubectl port-forward --namespace=ingress-nginx-neo service/ingress-nginx-neo-controller 8080:80
```

!!! info
    `kubectl port-forward` forwards port 8080 on the machine where the command runs to port 80 of the controller
    Service. Traffic sent to `localhost:8080` reaches the controller as if it came from outside the cluster.
    Port forwarding is a quick way to test the controller; it is not meant for production traffic, where DNS
    records point to the external address of the controller (see [Online testing](#online-testing)).

Then send a request:

```console
curl --resolve demo.localdev.me:8080:127.0.0.1 http://demo.localdev.me:8080
```

You should see an HTML response containing text like **"It works!"**.

### Online testing

If your Kubernetes cluster supports Services of type `LoadBalancer`, it allocates an external IP address or FQDN
to the ingress controller. Show it with:

```console
kubectl get service ingress-nginx-neo-controller --namespace=ingress-nginx-neo
```

The address is in the `EXTERNAL-IP` column. If it shows `<pending>`, the cluster was not able to provision the
load balancer (generally because it does not support Services of type `LoadBalancer`; see
[bare-metal considerations](./baremetal.md)).

Once you have the external IP address (or FQDN), set up a DNS record pointing to it. Then create an Ingress
resource. The following example assumes a DNS record for `www.demo.io`:

```console
kubectl create ingress demo --class=nginx \
  --rule="www.demo.io/*=demo:80"
```

You should then see the "It works!" page at <http://www.demo.io/>.

## Environment-specific instructions

### Cloud deployments

If the load balancers of your cloud provider do active health checks on their backends (most do), set the
`externalTrafficPolicy` of the controller Service to `Local` (instead of the default `Cluster`) to save an extra
hop and keep the client source IP. With Helm, add `--set controller.service.externalTrafficPolicy=Local`. The
cloud provider manifests already set it.

If the load balancers of your cloud provider support the PROXY protocol, you can enable it to let the controller
see the real IP address of the clients. Otherwise it generally sees the IP address of the load balancer. The PROXY
protocol must be enabled both in the controller (for example with `--set controller.config.use-proxy-protocol=true`)
and in the load balancer configuration of your cloud provider.

#### AWS

In AWS, a Network Load Balancer (NLB) exposes the controller behind a Service of type `LoadBalancer`:

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-aws.yaml
```

!!! info
    The `aws` manifests use the annotations of the in-tree service load balancer for AWS NLB. AWS documents
    [Network load balancing on Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/network-load-balancing.html)
    with the [AWS Load Balancer Controller](https://github.com/kubernetes-sigs/aws-load-balancer-controller); for that
    setup, install with Helm and set the annotations shown in [Values](#values).

##### TLS termination in AWS Load Balancer (NLB)

By default, TLS is terminated in the ingress controller. It is also possible to terminate TLS in the NLB with a
certificate from AWS Certificate Manager (ACM):

1. Download the manifest:

    ```console
    curl -fsSLO https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-aws-nlb-with-tls-termination.yaml
    ```

2. Edit the file and set the VPC CIDR of the Kubernetes cluster in the controller ConfigMap:

    ```
    proxy-real-ip-cidr: XXX.XXX.XXX/XX
    ```

3. Set the ACM certificate ARN in the Service annotation `service.beta.kubernetes.io/aws-load-balancer-ssl-cert`:

    ```
    arn:aws:acm:us-west-2:XXXXXXXX:certificate/XXXXXX-XXXXXXX-XXXXXXX-XXXXXXXX
    ```

4. Deploy the manifest:

    ```console
    kubectl apply -f deploy-aws-nlb-with-tls-termination.yaml
    ```

In this manifest the NLB forwards HTTPS (decrypted) to the controller's HTTP port, and plain HTTP to an extra port
`2443` on which the controller redirects to HTTPS.

##### NLB idle timeouts

The default idle timeout for TCP flows is 350 seconds and
[can be modified to any value between 60 and 6000 seconds](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/network-load-balancers.html#connection-idle-timeout).
Make sure the NGINX [keepalive_timeout](https://nginx.org/en/docs/http/ngx_http_core_module.html#keepalive_timeout)
is lower than the configured idle timeout. The default NGINX `keepalive_timeout` is `75s`
(ConfigMap key [`keep-alive`](../user-guide/nginx-configuration/configmap.md#keep-alive)).

#### GCE - GKE

> **Note:** The default GKE load balancer (Service type `LoadBalancer`) does not support the PROXY protocol.
> Enabling `use-proxy-protocol` does not work with the default GKE load balancer.

Your user needs `cluster-admin` permissions on the cluster to create the cluster-scoped resources:

```console
kubectl create clusterrolebinding cluster-admin-binding \
  --clusterrole cluster-admin \
  --user $(gcloud config get-value account)
```

Then install with Helm or with the `cloud` manifest:

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-cloud.yaml
```

!!! warning
    For private clusters, either add a firewall rule that allows the control plane to reach port `8443/tcp` on the
    worker nodes, or change the existing rule that allows access to ports `80/tcp`, `443/tcp` and `10254/tcp` to
    also allow port `8443/tcp`. See the
    [GKE documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/private-clusters#add_firewall_rules)
    on adding firewall rules and the [Kubernetes issue](https://github.com/kubernetes/kubernetes/issues/79739) for
    more detail.

#### Azure

Install with Helm or with the `cloud` manifest:

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-cloud.yaml
```

More information about Azure load balancer annotations is in the
[AKS documentation](https://learn.microsoft.com/en-us/azure/aks/ingress-internal-ip).

#### DigitalOcean

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-do.yaml
```

The `do` manifest sets one Service annotation, `service.beta.kubernetes.io/do-loadbalancer-enable-proxy-protocol: "true"`,
and enables `use-proxy-protocol` in the controller. With only this annotation the DigitalOcean load balancer graphs
show `no data`; populating them needs further annotations with values specific to your setup, which are discussed in
[this issue](https://github.com/kubernetes/ingress-nginx/issues/8965). Add them with Helm in
`controller.service.annotations`.

#### Scaleway

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-scw.yaml
```

The `scw` manifest enables PROXY protocol v2 on the Scaleway load balancer and in the controller. See the
[Scaleway tutorial](https://www.scaleway.com/en/docs/tutorials/proxy-protocol-v2-load-balancer/#configuring-proxy-protocol-for-ingress-nginx)
for details.

#### Exoscale

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-exoscale.yaml
```

The `exoscale` manifest runs the controller as a DaemonSet and configures the load balancer health check. The full
list of annotations supported by Exoscale is in the Exoscale Cloud Controller Manager
[documentation](https://github.com/exoscale/exoscale-cloud-controller-manager/blob/master/docs/service-loadbalancer.md).

#### Oracle Cloud Infrastructure

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-oracle.yaml
```

The `oracle` manifest uses a flexible load balancer shape (10 to 100 Mbps). A
[complete list of available annotations for Oracle Cloud Infrastructure](https://github.com/oracle/oci-cloud-controller-manager/blob/master/docs/load-balancer-annotations.md)
is in the [OCI Cloud Controller Manager](https://github.com/oracle/oci-cloud-controller-manager) documentation.

### Local development clusters

#### kind

The `kind` manifest binds ports 80 and 443 of the node with `hostPort`, tolerates the control-plane taints and
reports `localhost` as the Ingress address. Create the cluster with port mappings for these ports, as described in
the [kind ingress guide](https://kind.sigs.k8s.io/docs/user/ingress/), then apply the manifest:

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-kind.yaml
```

The `kind` manifest also handles Ingress resources without an `ingressClassName`.

#### Docker Desktop

First, make sure that Kubernetes is enabled in the Docker Desktop settings. The command `kubectl get nodes` should
show a single node called `docker-desktop`.

Install the controller with [Helm](#install-with-helm) or the `cloud` manifest. If no other Service of type
`LoadBalancer` is bound to port 80, the controller gets the `EXTERNAL-IP` `localhost` and is reachable on
`localhost:80`. Otherwise use the `kubectl port-forward` method described in [Local testing](#local-testing).

#### Rancher Desktop

Rancher Desktop uses K3s, which installs Traefik as its default ingress controller. Disable Traefik in
*Preferences > Kubernetes*, then install the controller with [Helm](#install-with-helm) or the `cloud` manifest
and follow [Local testing](#local-testing) to try a sample.

### Bare-metal clusters

This section applies to Kubernetes clusters deployed on bare-metal servers, as well as "raw" VMs where Kubernetes was
installed manually on generic Linux distributions.

For quick testing, use the `baremetal` manifest. It exposes the controller with a
[NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport) Service, which works on
almost every cluster but uses a port in the range 30000-32767:

```console
kubectl apply -f https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/deploy-baremetal.yaml
```

For other options (MetalLB, host network, using ports 80 and 443), see
[bare-metal considerations](./baremetal.md).

## Miscellaneous

### Checking the controller version

Run `/nginx-ingress-controller --version` in the controller pod:

```console
kubectl exec --namespace ingress-nginx-neo deploy/ingress-nginx-neo-controller -- /nginx-ingress-controller --version
```

For a DaemonSet installation, use `ds/ingress-nginx-neo-controller` instead. The
[kubectl plugin](../kubectl-plugin.md) finds the controller pod for you, for example
`kubectl ingress-nginx-neo exec --namespace ingress-nginx-neo -- /nginx-ingress-controller --version`.

### Scope

By default, the controller watches Ingress objects in all namespaces. To limit it to a single namespace, use the
flag `--watch-namespace` or the Helm value `controller.scope`. The secret referenced by `--default-ssl-certificate`
must then be present in the watched namespace(s).

See [Multiple Ingress controllers](../user-guide/multiple-ingress.md) to run several controllers in one cluster.

### Webhook network access

!!! warning
    The controller uses an
    [admission webhook](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/)
    to validate Ingress definitions. Make sure that no
    [network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
    or additional firewalls block connections from the API server to the `ingress-nginx-neo-controller-admission`
    Service.
