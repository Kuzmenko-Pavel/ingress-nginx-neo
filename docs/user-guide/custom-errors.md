# Custom errors

When the [`custom-http-errors`][cm-custom-http-errors] option is enabled, the Ingress controller configures NGINX so
that it passes several HTTP headers down to its `default-backend` in case of error:

| Header           | Value                                                               |
| ---------------- | ------------------------------------------------------------------- |
| `X-Code`         | HTTP status code returned by the request                            |
| `X-Format`       | Value of the `Accept` header sent by the client                     |
| `X-Original-URI` | URI that caused the error                                           |
| `X-Namespace`    | Namespace where the backend Service is located                      |
| `X-Ingress-Name` | Name of the Ingress where the backend is defined                    |
| `X-Service-Name` | Name of the Service backing the backend                             |
| `X-Service-Port` | Port number of the Service backing the backend                      |
| `X-Request-ID`   | Unique ID that identifies the request - same as for backend service |

A custom error backend can use this information to return the best possible representation of an error page. For
example, if the value of the `Accept` header send by the client was `application/json`, a carefully crafted backend
could decide to return the error payload as a JSON document instead of HTML.

!!! Important
    The custom backend is expected to return the correct HTTP status code instead of `200`.
    NGINX does not change the response from the custom default backend.

The [custom-error-pages][img-custom-error-pages] image (`ghcr.io/kuzmenko-pavel/ingress-nginx-neo/custom-error-pages`)
is such a custom backend. It is the default image of the chart's default backend (`defaultBackend.image`), listens on
port `8080` and serves the file `<code>.<ext>` (or `<first digit>xx.<ext>`) from the directory `ERROR_FILES_PATH`
(default `/www`), where the extension is derived from `X-Format` (default `DEFAULT_RESPONSE_FORMAT`, `text/html`).

See also the [Custom errors][example-custom-errors] example.

[cm-custom-http-errors]: ./nginx-configuration/configmap.md#custom-http-errors
[img-custom-error-pages]: https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/tree/main/images/custom-error-pages
[example-custom-errors]: ../examples/customization/custom-errors/README.md
