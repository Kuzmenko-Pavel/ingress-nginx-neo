# Default backend

The default backend is a service which handles all URL paths and hosts the ingress-nginx-neo controller doesn't understand
(i.e., all the requests that are not mapped with an Ingress).

Basically a default backend exposes two URLs:

- `/healthz` that returns 200
- `/` that returns 404

When no default backend service is configured, the controller answers these requests itself with `404`.

The chart deploys a default backend with `defaultBackend.enabled=true`. Its default image is
[custom-error-pages](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/tree/main/images/custom-error-pages)
(`ghcr.io/kuzmenko-pavel/ingress-nginx-neo/custom-error-pages`, tag = chart `appVersion`), which serves `/healthz`,
`/metrics` and error pages for the status codes passed by the controller. The chart sets the controller flag
`--default-backend-service` to this backend automatically.

```console
helm upgrade ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
  --namespace ingress-nginx-neo \
  --reuse-values \
  --set defaultBackend.enabled=true
```

!!! example
    The image also customizes the error pages served via the default backend, see [Custom errors](custom-errors.md)
    and the [Custom errors example](../examples/customization/custom-errors/README.md).
