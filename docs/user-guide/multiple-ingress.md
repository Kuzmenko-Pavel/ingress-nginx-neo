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

## Admission webhooks with several controllers

Every release of the chart creates a ValidatingWebhookConfiguration with `failurePolicy: Fail`. By
default Kubernetes calls the webhook of every release for every Ingress in the cluster, and the
controller skips an Ingress of another class. When any of the controllers is unavailable (restart,
upgrade, crash), its webhook does not answer, and Kubernetes rejects the creation and update of all
Ingresses in the cluster, including those of other classes.

With `controller.admissionWebhooks.matchIngressClass: true` the webhook is called only for
Ingresses of the classes of its release. The class is decided as by the controller above:
`controller.ingressClassResource.name` and `aliases`, the name `controller.ingressClass` with
`controller.ingressClassByName`, the `kubernetes.io/ingress.class` annotation, an Ingress without a
class with `controller.watchIngressWithoutClass`. A controller that is down then blocks only the
Ingresses of its own class. Enable this value in every release when a cluster runs several
controllers.

The condition knows only the classes the chart creates. Ingresses of a class created outside the
chart with the same `controllerValue` (for example with `controller.ingressClassResource.enabled:
false`) are served by the controller but not validated by the webhook. In this case keep
`matchIngressClass` disabled.

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
