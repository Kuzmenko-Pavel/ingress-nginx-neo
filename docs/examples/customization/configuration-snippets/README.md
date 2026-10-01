# Configuration Snippets

## Ingress

The Ingress in [this example](ingress.yaml) adds a custom header to Nginx configuration that only applies to that specific Ingress. If you want to add headers that apply globally to all Ingresses, please have a look at [an example of specifying custom headers](../custom-headers/README.md).

!!! important
    Snippet annotations are disabled by default. The controller accepts the `configuration-snippet` annotation only when
    the controller ConfigMap sets [`allow-snippet-annotations: "true"`](../../../user-guide/nginx-configuration/configmap.md#allow-snippet-annotations)
    and [`annotations-risk-level: Critical`](../../../user-guide/nginx-configuration/configmap.md#annotations-risk-level)
    (with the chart: `controller.allowSnippetAnnotations=true` and `controller.config.annotations-risk-level=Critical`).
    Enable them only if you trust all users who can create Ingress objects.

```console
kubectl apply -f ingress.yaml
```

## Test

Check if the contents of the annotation are present in the nginx.conf file using:

```console
kubectl -n ingress-nginx-neo exec deploy/ingress-nginx-neo-controller -- cat /etc/nginx/nginx.conf
```
