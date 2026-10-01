# Basic Authentication

This example shows how to add authentication in a Ingress rule using a secret that contains a file generated with `htpasswd`.
It's important the file generated is named `auth` (actually - that the secret has a key `data.auth`), otherwise the ingress-controller returns a 503.

## Create htpasswd file

```console
$ htpasswd -c auth foo
New password: <bar>
New password:
Re-type new password:
Adding password for user foo
```

## Convert htpasswd into a secret

```console
$ kubectl create secret generic basic-auth --from-file=auth
secret "basic-auth" created
```

## Examine secret

```console
$ kubectl get secret basic-auth -o yaml
apiVersion: v1
data:
  auth: Zm9vOiRhcHIxJE9GRzNYeWJwJGNrTDBGSERBa29YWUlsSDkuY3lzVDAK
kind: Secret
metadata:
  name: basic-auth
  namespace: default
type: Opaque
```

## Using kubectl, create an ingress tied to the basic-auth secret

```console
$ echo "
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-with-auth
  annotations:
    # type of authentication
    nginx.ingress.kubernetes.io/auth-type: basic
    # name of the secret that contains the user/password definitions
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    # message to display with an appropriate context why the authentication is required
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required - foo'
spec:
  ingressClassName: nginx
  rules:
  - host: foo.bar.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service: 
            name: http-svc
            port: 
              number: 80
" | kubectl apply -f -
```

## Use curl to confirm authorization is required by the ingress

```
$ curl -v http://10.2.29.4/ -H 'Host: foo.bar.com'
*   Trying 10.2.29.4...
* Connected to 10.2.29.4 (10.2.29.4) port 80 (#0)
> GET / HTTP/1.1
> Host: foo.bar.com
> User-Agent: curl/7.43.0
> Accept: */*
>
< HTTP/1.1 401 Unauthorized
< Server: nginx
< Date: Wed, 11 May 2016 05:27:23 GMT
< Content-Type: text/html
< Content-Length: 195
< Connection: keep-alive
< WWW-Authenticate: Basic realm="Authentication Required - foo"
<
<html>
<head><title>401 Authorization Required</title></head>
<body bgcolor="white">
<center><h1>401 Authorization Required</h1></center>
<hr><center>nginx</center>
</body>
</html>
* Connection #0 to host 10.2.29.4 left intact
```

## Use curl with the correct credentials to connect to the ingress

```
$ curl -v http://10.2.29.4/ -H 'Host: foo.bar.com' -u 'foo:bar'
*   Trying 10.2.29.4...
* Connected to 10.2.29.4 (10.2.29.4) port 80 (#0)
* Server auth using Basic with user 'foo'
> GET / HTTP/1.1
> Host: foo.bar.com
> Authorization: Basic Zm9vOmJhcg==
> User-Agent: curl/7.43.0
> Accept: */*
>
< HTTP/1.1 200 OK
< Server: nginx
< Date: Wed, 11 May 2016 06:05:26 GMT
< Content-Type: text/plain
< Transfer-Encoding: chunked
< Connection: keep-alive
< Vary: Accept-Encoding
<
Hostname: http-svc-66b7b8b4c6-zv8xl

Pod Information:
	node name:	worker-1
	pod name:	http-svc-66b7b8b4c6-zv8xl
	pod namespace:	default
	pod IP:	10.180.1.6

Server values:
	server_version=nginx: 1.27.1 - lua: 10026

Request Information:
	client_address=10.2.29.4
	method=GET
	real path=/
	query=
	request_version=1.1
	request_scheme=http
	request_uri=http://foo.bar.com:80/

Request Headers:
	accept=*/*
	connection=close
	host=foo.bar.com
	user-agent=curl/7.43.0
	x-forwarded-for=10.2.29.1
	x-forwarded-host=foo.bar.com
	x-forwarded-port=80
	x-forwarded-proto=http
	x-real-ip=10.2.29.1
	x-request-id=e426c7829ef9f3b18d40730857c3eddb
	x-scheme=http

Request Body:
	-no body in request-
* Connection #0 to host 10.2.29.4 left intact
```
