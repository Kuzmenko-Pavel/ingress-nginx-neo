# Static IPs

This example demonstrates how to assign a static-ip to an Ingress through the ingress-nginx-neo controller.

## Prerequisites

You need a [TLS cert](../PREREQUISITES.md#tls-certificates) and a [test HTTP service](../PREREQUISITES.md#test-http-service) for this example.
You will also need to make sure your Ingress targets exactly one Ingress
controller by specifying the [IngressClass](../../user-guide/multiple-ingress.md) with `spec.ingressClassName`,
and that you have an ingress controller [running](../../deploy/index.md) in your cluster
(this example assumes the Helm release `ingress-nginx-neo` in the namespace `ingress-nginx-neo`).

## Acquiring an IP

Since instances of the ingress-nginx-neo controller actually run on nodes in your cluster,
by default Ingresses will only get static IPs if your cloudprovider
supports static IP assignments to nodes. On GKE/GCE for example, even though
nodes get static IPs, the IPs are not retained across upgrades.

To acquire a static IP for the ingress-nginx-neo controller, simply put it
behind a Service of `Type=LoadBalancer`.

First, create a loadbalancer Service ([static-ip-svc.yaml](static-ip-svc.yaml)) and wait for it to acquire an IP:

```console
$ kubectl apply -f static-ip-svc.yaml
service/ingress-nginx-neo-lb created

$ kubectl -n ingress-nginx-neo get svc ingress-nginx-neo-lb
NAME                   TYPE           CLUSTER-IP     EXTERNAL-IP       PORT(S)                      AGE
ingress-nginx-neo-lb   LoadBalancer   10.0.138.113   104.154.109.191   80:31457/TCP,443:32240/TCP   15m
```

Then, update the ingress controller so it adopts the static IP of the Service
by passing the `--publish-service` flag. With the chart, this is the value
`controller.publishService.pathOverride` (set in [static-ip-values.yaml](static-ip-values.yaml)):

```console
$ helm upgrade ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
    --namespace ingress-nginx-neo \
    --reuse-values \
    -f static-ip-values.yaml
```

If you do not need the chart's own controller Service of type `LoadBalancer`, also set
`controller.service.type=ClusterIP`.

## Assigning the IP to an Ingress

From here on every Ingress created with `spec.ingressClassName: nginx`
will get the IP allocated in the previous step.

```console
$ kubectl apply -f nginx-ingress.yaml
ingress.networking.k8s.io/static-ip created

$ kubectl get ing static-ip
NAME        CLASS   HOSTS   ADDRESS           PORTS     AGE
static-ip   nginx   *       104.154.109.191   80, 443   13m

$ curl 104.154.109.191 -kL
Hostname: http-svc-66b7b8b4c6-zv8xl
...
Request Information:
	client_address=10.180.1.25
	method=GET
	real path=/
	query=
	request_version=1.1
	request_scheme=http
	request_uri=http://104.154.109.191:80/
...
```

## Retaining the IP

You can test retention by deleting the Ingress:

```console
$ kubectl delete ing static-ip
ingress.networking.k8s.io "static-ip" deleted

$ kubectl apply -f nginx-ingress.yaml
ingress.networking.k8s.io/static-ip created

$ kubectl get ing static-ip
NAME        CLASS   HOSTS   ADDRESS           PORTS     AGE
static-ip   nginx   *       104.154.109.191   80, 443   13m
```

> Note that unlike the GCE Ingress, the same loadbalancer IP is shared amongst all
> Ingresses, because all requests are proxied through the same set of nginx
> controllers.

## Promote ephemeral to static IP

To promote the allocated IP to static, you can update the Service manifest:

```console
$ kubectl -n ingress-nginx-neo patch svc ingress-nginx-neo-lb -p '{"spec": {"loadBalancerIP": "104.154.109.191"}}'
service/ingress-nginx-neo-lb patched
```

... and promote the IP to static (promotion works differently for cloudproviders,
provided example is for GKE/GCE):

```console
$ gcloud compute addresses create ingress-nginx-neo-lb --addresses 104.154.109.191 --region us-central1
Created [https://www.googleapis.com/compute/v1/projects/kubernetesdev/regions/us-central1/addresses/ingress-nginx-neo-lb].
---
address: 104.154.109.191
creationTimestamp: '2017-01-31T16:34:50.089-08:00'
description: ''
id: '5208037144487826373'
kind: compute#address
name: ingress-nginx-neo-lb
region: us-central1
selfLink: https://www.googleapis.com/compute/v1/projects/kubernetesdev/regions/us-central1/addresses/ingress-nginx-neo-lb
status: IN_USE
users:
- us-central1/forwardingRules/a09f6913ae80e11e6a8c542010af0000
```

Now even if the Service is deleted, the IP will persist, so you can recreate the
Service with `spec.loadBalancerIP` set to `104.154.109.191`
(uncomment `loadBalancerIP` in [static-ip-svc.yaml](static-ip-svc.yaml)).

!!! note
    `spec.loadBalancerIP` is deprecated in Kubernetes and its support depends on the cloud provider.
    Many providers offer an annotation on the Service to select a reserved address instead; check the documentation of your provider.
