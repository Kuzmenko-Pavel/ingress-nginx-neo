# External Basic Authentication

### Example 1

Use an external service (Basic Auth) located in `https://httpbin.org`

```
$ kubectl apply -f ingress.yaml
ingress.networking.k8s.io/external-auth created

$ kubectl get ing external-auth
NAME            CLASS   HOSTS                         ADDRESS       PORTS   AGE
external-auth   nginx   external-auth-01.sample.com   172.17.4.99   80      13s

$ kubectl get ing external-auth -o yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://httpbin.org/basic-auth/user/passwd
  creationTimestamp: 2016-10-03T13:50:35Z
  generation: 1
  name: external-auth
  namespace: default
  resourceVersion: "2068378"
  uid: 5c388f1d-8970-11e6-9004-080027d2dc94
spec:
  ingressClassName: nginx
  rules:
  - host: external-auth-01.sample.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service: 
            name: http-svc
            port: 
              number: 80
status:
  loadBalancer:
    ingress:
    - ip: 172.17.4.99
$
```

## Test 1: no username/password (expect code 401)

```console
$ curl -k http://172.17.4.99 -v -H 'Host: external-auth-01.sample.com'
* Rebuilt URL to: http://172.17.4.99/
*   Trying 172.17.4.99...
* Connected to 172.17.4.99 (172.17.4.99) port 80 (#0)
> GET / HTTP/1.1
> Host: external-auth-01.sample.com
> User-Agent: curl/7.50.1
> Accept: */*
>
< HTTP/1.1 401 Unauthorized
< Server: nginx
< Date: Mon, 03 Oct 2016 14:52:08 GMT
< Content-Type: text/html
< Content-Length: 195
< Connection: keep-alive
< WWW-Authenticate: Basic realm="Fake Realm"
<
<html>
<head><title>401 Authorization Required</title></head>
<body bgcolor="white">
<center><h1>401 Authorization Required</h1></center>
<hr><center>nginx</center>
</body>
</html>
* Connection #0 to host 172.17.4.99 left intact
```

## Test 2: valid username/password (expect code 200)

```
$ curl -k http://172.17.4.99 -v -H 'Host: external-auth-01.sample.com' -u 'user:passwd'
* Rebuilt URL to: http://172.17.4.99/
*   Trying 172.17.4.99...
* Connected to 172.17.4.99 (172.17.4.99) port 80 (#0)
* Server auth using Basic with user 'user'
> GET / HTTP/1.1
> Host: external-auth-01.sample.com
> Authorization: Basic dXNlcjpwYXNzd2Q=
> User-Agent: curl/7.50.1
> Accept: */*
>
< HTTP/1.1 200 OK
< Server: nginx
< Date: Mon, 03 Oct 2016 14:52:50 GMT
< Content-Type: text/plain
< Transfer-Encoding: chunked
< Connection: keep-alive
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
	client_address=10.2.60.2
	method=GET
	real path=/
	query=
	request_version=1.1
	request_scheme=http
	request_uri=http://external-auth-01.sample.com:80/

Request Headers:
	accept=*/*
	authorization=Basic dXNlcjpwYXNzd2Q=
	connection=close
	host=external-auth-01.sample.com
	user-agent=curl/7.50.1
	x-forwarded-for=10.2.60.1
	x-forwarded-host=external-auth-01.sample.com
	x-forwarded-port=80
	x-forwarded-proto=http
	x-real-ip=10.2.60.1

Request Body:
	-no body in request-
* Connection #0 to host 172.17.4.99 left intact
```

## Test 3: invalid username/password (expect code 401)

```
curl -k http://172.17.4.99 -v -H 'Host: external-auth-01.sample.com' -u 'user:user'
* Rebuilt URL to: http://172.17.4.99/
*   Trying 172.17.4.99...
* Connected to 172.17.4.99 (172.17.4.99) port 80 (#0)
* Server auth using Basic with user 'user'
> GET / HTTP/1.1
> Host: external-auth-01.sample.com
> Authorization: Basic dXNlcjp1c2Vy
> User-Agent: curl/7.50.1
> Accept: */*
>
< HTTP/1.1 401 Unauthorized
< Server: nginx
< Date: Mon, 03 Oct 2016 14:53:04 GMT
< Content-Type: text/html
< Content-Length: 195
< Connection: keep-alive
* Authentication problem. Ignoring this.
< WWW-Authenticate: Basic realm="Fake Realm"
<
<html>
<head><title>401 Authorization Required</title></head>
<body bgcolor="white">
<center><h1>401 Authorization Required</h1></center>
<hr><center>nginx</center>
</body>
</html>
* Connection #0 to host 172.17.4.99 left intact
```
