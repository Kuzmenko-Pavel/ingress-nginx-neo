# Custom Configuration

Using a [ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) is possible to customize the NGINX configuration

For example, if we want to change the timeouts we need to create a ConfigMap:

```console
$ cat configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-neo-controller
  namespace: ingress-nginx-neo
  labels:
    app.kubernetes.io/name: ingress-nginx-neo
    app.kubernetes.io/component: controller
data:
  proxy-connect-timeout: "10"
  proxy-read-timeout: "120"
  proxy-send-timeout: "120"
```

```console
curl https://raw.githubusercontent.com/Kuzmenko-Pavel/ingress-nginx-neo/main/docs/examples/customization/custom-configuration/configmap.yaml \
    | kubectl apply -f -
```

If the Configmap is updated, NGINX will be reloaded with the new configuration.

With the Helm chart, set the same keys in `controller.config`, so that `helm upgrade` keeps them:

```yaml
controller:
  config:
    proxy-connect-timeout: "10"
    proxy-read-timeout: "120"
    proxy-send-timeout: "120"
```

See [ConfigMap](../../../user-guide/nginx-configuration/configmap.md) for all available keys.
