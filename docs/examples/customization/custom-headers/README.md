# Custom Headers

## Caveats

Changes to the custom header config maps do not force a reload of the ingress-nginx-neo controller.

### Workaround

To work around this limitation, perform a rolling restart of the deployment:

```console
kubectl -n ingress-nginx-neo rollout restart deployment ingress-nginx-neo-controller
```

## Example

This example demonstrates configuration of the ingress-nginx-neo controller via
a ConfigMap to pass a custom list of headers to the upstream
server.

[custom-headers.yaml](custom-headers.yaml) defines a ConfigMap in the `ingress-nginx-neo` namespace named `custom-headers`, holding several custom X-prefixed HTTP headers.

```console
kubectl apply -f https://raw.githubusercontent.com/Kuzmenko-Pavel/ingress-nginx-neo/main/docs/examples/customization/custom-headers/custom-headers.yaml
```

[configmap.yaml](configmap.yaml) defines a ConfigMap in the `ingress-nginx-neo` namespace named `ingress-nginx-neo-controller`. This controls the [global configuration](../../../user-guide/nginx-configuration/configmap.md) of the ingress controller, and already exists in a standard installation. The key `proxy-set-headers` is set to cite the `ingress-nginx-neo/custom-headers` ConfigMap created above.

```console
kubectl apply -f https://raw.githubusercontent.com/Kuzmenko-Pavel/ingress-nginx-neo/main/docs/examples/customization/custom-headers/configmap.yaml
```

The controller will read the `ingress-nginx-neo/ingress-nginx-neo-controller` ConfigMap, find the `proxy-set-headers` key, read HTTP headers from the `ingress-nginx-neo/custom-headers` ConfigMap, and include those HTTP headers in all requests flowing from nginx to the backends.

The above example was for passing a custom list of headers to the upstream server.
To pass the custom headers before sending response traffic to the client, use the add-headers key:

```console
kubectl apply -f https://raw.githubusercontent.com/Kuzmenko-Pavel/ingress-nginx-neo/main/docs/examples/customization/custom-headers/configmap-client-response.yaml
```

!!! note
    `kubectl apply` of `configmap.yaml` replaces the data of the controller ConfigMap managed by Helm, and a later
    `helm upgrade` overwrites it again. With the Helm chart, set the headers in the chart values instead: the chart
    creates the ConfigMaps `ingress-nginx-neo-custom-proxy-headers` / `ingress-nginx-neo-custom-add-headers` and sets
    `proxy-set-headers` / `add-headers` in the controller ConfigMap.

    ```yaml
    controller:
      proxySetHeaders:
        X-Different-Name: "true"
        X-Request-Start: t=${msec}
        X-Using-Nginx-Controller: "true"
      addHeaders:
        X-Using-Nginx-Controller: "true"
    ```

## Test

Check the contents of the ConfigMaps are present in the nginx.conf file using:

```console
kubectl -n ingress-nginx-neo exec deploy/ingress-nginx-neo-controller -- cat /etc/nginx/nginx.conf
```
