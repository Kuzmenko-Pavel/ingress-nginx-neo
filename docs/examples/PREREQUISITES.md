# Prerequisites

Many of the examples in this directory have common prerequisites.

## TLS certificates

Unless otherwise mentioned, the TLS secret used in examples is a 2048 bit RSA
key/cert pair with an arbitrarily chosen hostname, created as follows

```console
$ openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=nginxsvc/O=nginxsvc"
Generating a 2048 bit RSA private key
................+++
................+++
writing new private key to 'tls.key'
-----

$ kubectl create secret tls tls-secret --key tls.key --cert tls.crt
secret "tls-secret" created
```

Note: If using CA Authentication, described below, you will need to sign the server certificate with the CA.

## Client Certificate Authentication

CA Authentication also known as Mutual Authentication allows both the server and client to verify each others
identity via a common CA.

We have a CA Certificate which we usually obtain from a Certificate Authority and use that to sign
both our server certificate and client certificate. Then every time we want to access our backend, we must
pass the client certificate.

These instructions are based on the following [blog](https://medium.com/@awkwardferny/configuring-certificate-based-mutual-authentication-with-kubernetes-ingress-nginx-20e7e38fdfca)

**Generate the CA Key and Certificate:**

```console
openssl req -x509 -sha256 -newkey rsa:4096 -keyout ca.key -out ca.crt -days 356 -nodes -subj '/CN=My Cert Authority'
```

**Generate the Server Key, and Certificate and Sign with the CA Certificate:**

```console
openssl req -new -newkey rsa:4096 -keyout server.key -out server.csr -nodes -subj '/CN=mydomain.com'
openssl x509 -req -sha256 -days 365 -in server.csr -CA ca.crt -CAkey ca.key -set_serial 01 -out server.crt
```

**Generate the Client Key, and Certificate and Sign with the CA Certificate:**

```console
openssl req -new -newkey rsa:4096 -keyout client.key -out client.csr -nodes -subj '/CN=My Client'
openssl x509 -req -sha256 -days 365 -in client.csr -CA ca.crt -CAkey ca.key -set_serial 02 -out client.crt
```

Once this is complete you can continue to follow the instructions [here](./auth/client-certs/README.md#creating-certificate-secrets)



## Test HTTP Service

All examples that require a test HTTP Service use the standard http-svc Deployment and Service from
[http-svc.yaml](http-svc.yaml). It runs the echo server image `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/e2e-test-echo`,
which listens on port `80` and replies with the details of the request it received (pod information, method, path,
query, headers and body).

Deploy it with the image of the release `<version>`:

```console
$ curl -sL https://raw.githubusercontent.com/Kuzmenko-Pavel/ingress-nginx-neo/main/docs/examples/http-svc.yaml \
    | sed "s/RELEASE_VERSION/<version>/" | kubectl apply -f -
deployment.apps/http-svc created
service/http-svc created

$ kubectl get po
NAME                        READY   STATUS    RESTARTS   AGE
http-svc-66b7b8b4c6-zv8xl   1/1     Running   0          1m

$ kubectl get svc http-svc
NAME       TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
http-svc   ClusterIP   10.0.122.116   <none>        80/TCP    1m
```

You can test that the HTTP Service works with a port-forward:

```console
$ kubectl port-forward svc/http-svc 8080:80
Forwarding from 127.0.0.1:8080 -> 80

$ curl http://127.0.0.1:8080/
Hostname: http-svc-66b7b8b4c6-zv8xl

Pod Information:
	node name:	worker-1
	pod name:	http-svc-66b7b8b4c6-zv8xl
	pod namespace:	default
	pod IP:	10.180.1.6

Server values:
	server_version=nginx: 1.27.1 - lua: 10026

Request Information:
	client_address=127.0.0.1
	method=GET
	real path=/
	query=
	request_version=1.1
	request_scheme=http
	request_uri=http://127.0.0.1:80/

Request Headers:
	accept=*/*
	host=127.0.0.1:8080
	user-agent=curl/8.5.0

Request Body:
	-no body in request-
```
