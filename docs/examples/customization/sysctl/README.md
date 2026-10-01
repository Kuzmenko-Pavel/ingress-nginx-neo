# Sysctl tuning

This example aims to demonstrate the use of an Init Container to adjust sysctl default values using `kubectl patch`.

```console
kubectl patch deployment -n ingress-nginx-neo ingress-nginx-neo-controller \
    --patch="$(curl -sL https://raw.githubusercontent.com/Kuzmenko-Pavel/ingress-nginx-neo/main/docs/examples/customization/sysctl/patch.json)"
```

**Changes:**

- Backlog Queue setting `net.core.somaxconn` from `128` to `32768`
- Ephemeral Ports setting `net.ipv4.ip_local_port_range` from `32768 60999` to `1024 65000`

In a [post from the NGINX blog](https://www.nginx.com/blog/tuning-nginx/), it is possible to see an explanation for the changes.

!!! note
    The init container runs `privileged`. With the Helm chart, add it through `controller.extraInitContainers`
    instead of patching the Deployment, so that `helm upgrade` keeps it. Both sysctls are network-namespaced;
    as an alternative without a privileged container, set them in the pod `securityContext.sysctls` (chart value
    `controller.sysctls`) if the kubelet allows them
    (see [Using sysctls in a Kubernetes Cluster](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/)).
