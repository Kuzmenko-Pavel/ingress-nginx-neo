# Multiple Ingress controllers

By default, deploying multiple Ingress controllers (e.g., `ingress-nginx-neo` & `gce`) will result in all controllers simultaneously racing to update Ingress status fields in confusing ways.

To fix this problem, use [IngressClasses](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class) and select the class of each Ingress with the field `spec.ingressClassName`.

!!! note
    IngressClass is a cluster-scoped resource. If the controller is not allowed to list IngressClass objects, it ignores
    `spec.ingressClassName` and selects Ingresses only by the `kubernetes.io/ingress.class` annotation
    (see [below](#ingress-class-annotation)).

## Using IngressClasses

You can deploy two Ingress controllers by granting them control over two different IngressClasses, then selecting one of the two IngressClasses with `ingressClassName`.

First, ensure the `--controller-class=` and `--ingress-class` are set to something different on each ingress controller. If your additional ingress controller is to be installed in a namespace where one or more ingress-nginx-neo controllers are already installed, then you need to specify a different unique `--election-id` for the new instance of the controller.

```yaml
# ingress-nginx-neo Deployment/Statefulset
spec:
  template:
     spec:
       containers:
         - name: controller
           args:
             - /nginx-ingress-controller
             - '--election-id=internal-ingress-controller-leader'
             - '--controller-class=k8s.io/internal-ingress-nginx'
             - '--ingress-class=internal-nginx'
            ...
```

Then use the same value in the IngressClass:

```yaml
# ingress-nginx-neo IngressClass
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: internal-nginx
spec:
  controller: k8s.io/internal-ingress-nginx
  ...
```

And refer to that IngressClass in your Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
spec:
  ingressClassName: internal-nginx
  ...
```

or if installing with Helm:

```yaml
controller:
  electionID: internal-ingress-controller-leader
  ingressClass: internal-nginx  # default: nginx
  ingressClassResource:
    name: internal-nginx  # default: nginx
    enabled: true
    default: false
    controllerValue: "k8s.io/internal-ingress-nginx"  # default: k8s.io/ingress-nginx
```

!!! important

    The controller selects an Ingress in this order:

    1. `spec.ingressClassName` references an IngressClass whose `spec.controller` equals the `--controller-class` value
       (with `--ingress-class-by-name=true`, chart value `controller.ingressClassByName`, an IngressClass whose name equals `--ingress-class` is accepted as well);
    2. otherwise, the `kubernetes.io/ingress.class` annotation equals the `--ingress-class` value;
    3. otherwise, the Ingress has no class and is processed only when `--watch-ingress-without-class=true`
       (chart value `controller.watchIngressWithoutClass`).

    Ingresses without a class are therefore ignored by default. Enable `--watch-ingress-without-class` on one controller only.

## Ingress class annotation

The controller also accepts the `kubernetes.io/ingress.class` annotation for Ingress controllers that do not support
IngressClasses. The annotation value must be equal to the `--ingress-class` flag (default `nginx`):

```yaml
metadata:
  name: foo
  annotations:
    kubernetes.io/ingress.class: "nginx"
```

An Ingress whose annotation has any other value (for example `gce`) is ignored by this controller.
`spec.ingressClassName` takes precedence over the annotation; prefer `spec.ingressClassName` for new Ingresses.
