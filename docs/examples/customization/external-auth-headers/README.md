# External authentication, authentication service response headers propagation

This example demonstrates propagation of selected authentication service response headers
to a backend service.

Sample configuration includes:

* Sample authentication service (plain NGINX configured through a ConfigMap) producing several response headers
  * Authentication logic is based on HTTP header: requests with header `User` containing string `internal` are considered authenticated
  * After successful authentication service generates response headers `UserID` and `UserRole`
* Sample echo service (`ghcr.io/kuzmenko-pavel/ingress-nginx-neo/e2e-test-echo`) displaying the request headers it receives
* Two ingress objects pointing to echo service
  * Public, which allows access from unauthenticated users (its auth URL has the query `code=200`)
  * Private, which allows access from authenticated users only

Deploy the example from this directory. [echo-service.yaml](echo-service.yaml) references the echo image as
`e2e-test-echo:RELEASE_VERSION`; the commands below set it to the release `<version>`:

```console
$ kubectl apply -f auth-service.yaml
configmap/demo-auth-service created
deployment.apps/demo-auth-service created
service/demo-auth-service created

$ sed "s/RELEASE_VERSION/<version>/" echo-service.yaml | kubectl apply -f -
deployment.apps/demo-echo-service created
service/demo-echo-service created
ingress.networking.k8s.io/public-demo-echo-service created
ingress.networking.k8s.io/secure-demo-echo-service created

$ kubectl get po
NAME                                 READY   STATUS    RESTARTS   AGE
demo-auth-service-6d5f7b9c8d-7g9mh   1/1     Running   0          30s
demo-echo-service-5c8f6d7b9f-3vw8c   1/1     Running   0          29s

$ kubectl get ing
NAME                       CLASS   HOSTS                                 ADDRESS          PORTS   AGE
public-demo-echo-service   nginx   public-demo-echo-service.kube.local   192.168.99.100   80      1m
secure-demo-echo-service   nginx   secure-demo-echo-service.kube.local   192.168.99.100   80      1m
```

The responses below are shortened to the relevant lines. The echo service prints the request headers it receives,
so the headers propagated from the authentication service appear as `userid` and `userrole`.

## Test 1: public service with no auth header

```console
$ curl -H 'Host: public-demo-echo-service.kube.local' -v 192.168.99.100
> GET / HTTP/1.1
> Host: public-demo-echo-service.kube.local
> User-Agent: curl/8.5.0
> Accept: */*
>
< HTTP/1.1 200 OK
< Content-Type: text/plain
<
...
Request Headers:
	accept=*/*
	host=public-demo-echo-service.kube.local
	user-agent=curl/8.5.0
	x-forwarded-for=192.168.99.1
	x-forwarded-host=public-demo-echo-service.kube.local
	...
```

The request is allowed, and no `userid` / `userrole` headers are passed to the backend.

## Test 2: secure service with no auth header

```console
$ curl -H 'Host: secure-demo-echo-service.kube.local' -v 192.168.99.100
> GET / HTTP/1.1
> Host: secure-demo-echo-service.kube.local
> User-Agent: curl/8.5.0
> Accept: */*
>
< HTTP/1.1 403 Forbidden
< Content-Type: text/html
<
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

## Test 3: public service with valid auth header

```console
$ curl -H 'Host: public-demo-echo-service.kube.local' -H 'User:internal' -v 192.168.99.100
> GET / HTTP/1.1
> Host: public-demo-echo-service.kube.local
> User-Agent: curl/8.5.0
> Accept: */*
> User:internal
>
< HTTP/1.1 200 OK
< Content-Type: text/plain
<
...
Request Headers:
	accept=*/*
	host=public-demo-echo-service.kube.local
	user=internal
	user-agent=curl/8.5.0
	userid=8fcb328c9c812b05a7e79feb1b8a80b0
	userrole=admin
	...
```

## Test 4: secure service with valid auth header

```console
$ curl -H 'Host: secure-demo-echo-service.kube.local' -H 'User:internal' -v 192.168.99.100
> GET / HTTP/1.1
> Host: secure-demo-echo-service.kube.local
> User-Agent: curl/8.5.0
> Accept: */*
> User:internal
>
< HTTP/1.1 200 OK
< Content-Type: text/plain
<
...
Request Headers:
	accept=*/*
	host=secure-demo-echo-service.kube.local
	user=internal
	user-agent=curl/8.5.0
	userid=1f1c2d4f7a9b4e0c8d6e5f4a3b2c1d0e
	userrole=admin
	...
```

The header `Other` returned by the authentication service is not listed in
`nginx.ingress.kubernetes.io/auth-response-headers`, so it is not passed to the backend.
