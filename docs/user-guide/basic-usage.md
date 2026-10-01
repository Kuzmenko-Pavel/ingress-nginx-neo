# Basic usage - host based routing

ingress-nginx-neo can be used for many use cases, inside various cloud providers and supports a lot of configurations. In this section you can find a common usage scenario where a single load balancer powered by ingress-nginx-neo will route traffic to 2 different HTTP backend services based on the host name.

First of all follow the [installation guide](../deploy/index.md) to install ingress-nginx-neo. Then imagine that you need to expose 2 HTTP services already installed, `myServiceA`, `myServiceB`, and configured as `type: ClusterIP`. 

Let's say that you want to expose the first at `myServiceA.foo.org` and the second at `myServiceB.foo.org`.

Create two **Ingress** resources like this:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-myservicea
spec:
  rules:
  - host: myservicea.foo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myservicea
            port:
              number: 80
  ingressClassName: nginx
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-myserviceb
spec:
  rules:
  - host: myserviceb.foo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myserviceb
            port:
              number: 80
  ingressClassName: nginx
```

When you apply this yaml, 2 ingress resources will be created managed by the **ingress-nginx-neo** instance. The controller handles all Ingress resources with `spec.ingressClassName: nginx` (the IngressClass created by the chart).
Please note that the ingress resource should be placed inside the same namespace of the backend resource.

On many cloud providers the Service of type `LoadBalancer` of ingress-nginx-neo will also create the corresponding Load Balancer resource. All you have to do is get the external IP and add a DNS `A record` inside your DNS provider that point myservicea.foo.org and myserviceb.foo.org to the nginx external IP. Get the external IP by running:

```console
kubectl get services -n ingress-nginx-neo ingress-nginx-neo-controller
```

To test inside minikube refer to this documentation: [Set up Ingress on Minikube with the NGINX Ingress Controller](https://kubernetes.io/docs/tasks/access-application-cluster/ingress-minikube/)
