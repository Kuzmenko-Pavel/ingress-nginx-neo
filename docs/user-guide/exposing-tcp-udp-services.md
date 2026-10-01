# Exposing TCP and UDP services

While the Kubernetes Ingress resource only officially supports routing external HTTP(s) traffic to services, ingress-nginx-neo can be configured to receive external TCP/UDP traffic from non-HTTP protocols and route them to internal services using TCP/UDP port mappings that are specified within a ConfigMap.

To support this, the `--tcp-services-configmap` and `--udp-services-configmap` flags can be used to point to an existing config map where the key is the external port to use and the value indicates the service to expose using the format:
`<external port>:<namespace/service name>:<service port/name>:[PROXY]:[PROXY]`

It is also possible to use a number or the name of the port. The two last fields are optional.
Adding `PROXY` in either or both of the two last fields we can use [Proxy Protocol](https://docs.nginx.com/nginx/admin-guide/load-balancer/using-proxy-protocol/) decoding (listen) and/or encoding (proxy_pass) in a TCP service. 
The first `PROXY` controls the decode of the proxy protocol and the second `PROXY` controls the encoding using proxy protocol. 
This allows an incoming connection to be decoded or an outgoing connection to be encoded. It is also possible to arbitrate between two different proxies by turning on the decode and encode on a TCP service. 

## With the Helm chart

The chart creates the ConfigMaps, passes the `--tcp-services-configmap` / `--udp-services-configmap` flags to the
controller and adds the ports to the controller Service. Set the chart values `tcp` and `udp`, where the key is the
external port and the value is `<namespace/service name>:<service port/name>:[PROXY]:[PROXY]`.

The next example exposes the service `example-go` running in the namespace `default` on port `8080` using the port `9000`,
and the service `kube-dns` running in the namespace `kube-system` on port `53` using the UDP port `53`:

```yaml
tcp:
  "9000": "default/example-go:8080"
udp:
  "53": "kube-system/kube-dns:53"
```

```console
helm upgrade ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
  --namespace ingress-nginx-neo \
  --reuse-values \
  --set tcp.9000="default/example-go:8080" \
  --set udp.53="kube-system/kube-dns:53"
```

With the release name `ingress-nginx-neo`, the chart creates the ConfigMaps `ingress-nginx-neo-tcp` and
`ingress-nginx-neo-udp` in the namespace `ingress-nginx-neo`, and the Service `ingress-nginx-neo-controller` gets the
ports `9000-tcp` and `53-udp`. Port numbers of the Service can be pinned with `controller.service.nodePorts.tcp` /
`controller.service.nodePorts.udp`.

## Without Helm

The next example shows how to expose the service `example-go` running in the namespace `default` in the port `8080` using the port `9000`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-neo-tcp
  namespace: ingress-nginx-neo
data:
  "9000": "default/example-go:8080"
```

NGINX provides [UDP Load Balancing](https://docs.nginx.com/nginx/admin-guide/load-balancer/tcp-udp-load-balancer/).
The next example shows how to expose the service `kube-dns` running in the namespace `kube-system` in the port `53` using the port `53`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-neo-udp
  namespace: ingress-nginx-neo
data:
  "53": "kube-system/kube-dns:53"
```

If TCP/UDP proxy support is used, then those ports need to be exposed in the Service defined for the Ingress controller.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-neo-controller
  namespace: ingress-nginx-neo
  labels:
    app.kubernetes.io/name: ingress-nginx-neo
    app.kubernetes.io/instance: ingress-nginx-neo
    app.kubernetes.io/component: controller
spec:
  type: LoadBalancer
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
    - name: https
      port: 443
      targetPort: https
      protocol: TCP
    - name: proxied-tcp-9000
      port: 9000
      targetPort: 9000
      protocol: TCP
    - name: proxied-udp-53
      port: 53
      targetPort: 53
      protocol: UDP
  selector:
    app.kubernetes.io/name: ingress-nginx-neo
    app.kubernetes.io/instance: ingress-nginx-neo
    app.kubernetes.io/component: controller
```

Then, the ConfigMaps should be added into the ingress controller's deployment args.

```yaml
args:
  - /nginx-ingress-controller
  - --tcp-services-configmap=$(POD_NAMESPACE)/ingress-nginx-neo-tcp
  - --udp-services-configmap=$(POD_NAMESPACE)/ingress-nginx-neo-udp
```
