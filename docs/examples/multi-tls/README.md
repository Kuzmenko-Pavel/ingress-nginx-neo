# Multi TLS certificate termination

This example uses 2 different certificates to terminate SSL for 2 hostnames.

1. Create TLS secrets for `foo.bar.com` and `bar.baz.com` (see [TLS certificates](../PREREQUISITES.md#tls-certificates)):

    ```console
    $ openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout foobar.key -out foobar.crt \
        -subj "/CN=foo.bar.com/O=foo.bar.com" -addext "subjectAltName = DNS:foo.bar.com"
    $ kubectl create secret tls foobar --key foobar.key --cert foobar.crt
    $ openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout barbaz.key -out barbaz.crt \
        -subj "/CN=bar.baz.com/O=bar.baz.com" -addext "subjectAltName = DNS:bar.baz.com"
    $ kubectl create secret tls barbaz --key barbaz.key --cert barbaz.crt
    ```

2. Create the backends and the Ingress from [multi-tls.yaml](multi-tls.yaml). The `http-svc` backend uses the
   echo server image `ghcr.io/kuzmenko-pavel/ingress-nginx-neo/e2e-test-echo` of the release `<version>`:

    ```console
    $ curl -sL https://raw.githubusercontent.com/Kuzmenko-Pavel/ingress-nginx-neo/main/docs/examples/multi-tls/multi-tls.yaml \
        | sed "s/RELEASE_VERSION/<version>/" | kubectl apply -f -
    ```

The controller generates one `server` block per host in `nginx.conf`. Certificates are served dynamically (selected by
SNI in Lua), so `nginx.conf` does not contain per-host `ssl_certificate` paths:

```console
$ POD=$(kubectl -n ingress-nginx-neo get pods -l app.kubernetes.io/name=ingress-nginx-neo,app.kubernetes.io/component=controller -o name | head -1)
$ kubectl -n ingress-nginx-neo exec "$POD" -- cat /etc/nginx/nginx.conf | grep -E "## start server|server_name"
	## start server _
		server_name "_" ;
	## start server bar.baz.com
		server_name "bar.baz.com" ;
	## start server foo.bar.com
		server_name "foo.bar.com" ;
```

You should be able to reach the nginx service or the http-svc service using a hostname switch:

```console
$ kubectl get ing foo-tls
NAME      CLASS   HOSTS                     ADDRESS         PORTS     AGE
foo-tls   nginx   foo.bar.com,bar.baz.com   104.154.30.67   80, 443   13m

$ curl -k --resolve foo.bar.com:443:104.154.30.67 https://foo.bar.com/
Hostname: http-svc-66b7b8b4c6-zv8xl
...
Request Information:
	client_address=10.245.0.6
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
	x-forwarded-for=10.245.0.1
	x-forwarded-host=foo.bar.com
	x-forwarded-proto=https
...

$ curl -k --resolve bar.baz.com:443:104.154.30.67 https://bar.baz.com/
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

Each host gets its own certificate:

```console
$ openssl s_client -connect 104.154.30.67:443 -servername bar.baz.com </dev/null 2>/dev/null | openssl x509 -noout -subject
subject=CN = bar.baz.com, O = bar.baz.com
```

A request without a matching host is answered by the default backend:

```console
$ curl http://104.154.30.67/
<html>
<head><title>404 Not Found</title></head>
...
```
