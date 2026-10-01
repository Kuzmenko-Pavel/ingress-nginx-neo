# TLS termination

This example demonstrates how to terminate TLS through the ingress-nginx-neo controller.

## Prerequisites

You need a [TLS cert](../PREREQUISITES.md#tls-certificates) and a [test HTTP service](../PREREQUISITES.md#test-http-service) for this example.

## Deployment

Create a `ingress.yaml` file.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-test
spec:
  tls:
    - hosts:
      - foo.bar.com
      # This assumes tls-secret exists and the SSL
      # certificate contains a CN for foo.bar.com
      secretName: tls-secret
  ingressClassName: nginx
  rules:
    - host: foo.bar.com
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            # This assumes http-svc exists and routes to healthy endpoints
            service:
              name: http-svc
              port:
                number: 80
```

The following command instructs the controller to terminate traffic using the provided
TLS cert, and forward un-encrypted HTTP traffic to the test HTTP service.

```console
kubectl apply -f ingress.yaml
```

## Validation

You can confirm that the Ingress works.

```console
$ kubectl describe ing nginx-test
Name:             nginx-test
Labels:           <none>
Namespace:        default
Address:          104.198.183.6
Ingress Class:    nginx
Default backend:  <default>
TLS:
  tls-secret terminates foo.bar.com
Rules:
  Host         Path  Backends
  ----         ----  --------
  foo.bar.com
               /   http-svc:80 (10.180.1.6:80)
Annotations:   <none>
Events:
  Type    Reason  Age   From                      Message
  ----    ------  ----  ----                      -------
  Normal  Sync    7s    nginx-ingress-controller  Scheduled for sync

$ curl --resolve foo.bar.com:443:104.198.183.6 https://foo.bar.com/
curl: (60) SSL certificate problem: self-signed certificate
More details here: https://curl.se/docs/sslcerts.html

$ curl -k --resolve foo.bar.com:443:104.198.183.6 https://foo.bar.com/
Hostname: http-svc-66b7b8b4c6-zv8xl

Pod Information:
	node name:	worker-1
	pod name:	http-svc-66b7b8b4c6-zv8xl
	pod namespace:	default
	pod IP:	10.180.1.6

Server values:
	server_version=nginx: 1.27.1 - lua: 10026

Request Information:
	client_address=10.240.0.4
	method=GET
	real path=/
	query=
	request_version=1.1
	request_scheme=http
	request_uri=http://foo.bar.com:80/

Request Headers:
	accept=*/*
	host=foo.bar.com
	user-agent=curl/8.5.0
	x-forwarded-for=104.132.0.80
	x-forwarded-host=foo.bar.com
	x-forwarded-port=443
	x-forwarded-proto=https
	x-forwarded-scheme=https
	x-real-ip=104.132.0.80
	x-request-id=f708ea7e369d4514fc90d51d7e27e91d
	x-scheme=https

Request Body:
	-no body in request-
```
