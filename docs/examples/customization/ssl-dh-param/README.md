# Custom DH parameters for perfect forward secrecy

This example aims to demonstrate the deployment of an ingress-nginx-neo controller and
use a ConfigMap to configure a custom Diffie-Hellman parameters file to help with
"Perfect Forward Secrecy".

## Custom configuration

```console
$ cat configmap.yaml
apiVersion: v1
data:
  ssl-dh-param: "ingress-nginx-neo/lb-dhparam"
kind: ConfigMap
metadata:
  name: ingress-nginx-neo-controller
  namespace: ingress-nginx-neo
  labels:
    app.kubernetes.io/name: ingress-nginx-neo
    app.kubernetes.io/component: controller
```

```console
$ kubectl apply -f configmap.yaml
```

## Custom DH parameters secret

```console
$ openssl dhparam 4096 2> /dev/null | base64 -w0
LS0tLS1CRUdJTiBESCBQQVJBTUVURVJ...
```

```console
$ cat ssl-dh-param.yaml
apiVersion: v1
data:
  dhparam.pem: "LS0tLS1CRUdJTiBESCBQQVJBTUVURVJ..."
kind: Secret
type: Opaque
metadata:
  name: lb-dhparam
  namespace: ingress-nginx-neo
```

```console
$ kubectl apply -f ssl-dh-param.yaml
```

## With the Helm chart

The chart value `dhParam` takes the base64-encoded DH parameters; the chart creates the Secret and sets `ssl-dh-param`
in the controller ConfigMap:

```console
$ helm upgrade ingress-nginx-neo oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
    --namespace ingress-nginx-neo \
    --reuse-values \
    --set dhParam="$(openssl dhparam 4096 2> /dev/null | base64 -w0)"
```

## Test

Check the contents of the configmap is present in the nginx.conf file using:

```console
$ kubectl -n ingress-nginx-neo exec deploy/ingress-nginx-neo-controller -- cat /etc/nginx/nginx.conf | grep ssl_dhparam
```
