<!--
-----------------NOTICE------------------------
This page is referenced in code (krew manifest, nginx.tmpl) as
https://kuzmenko-pavel.github.io/ingress-nginx-neo/kubectl-plugin/
Do not move it without providing redirects.
-----------------------------------------------
-->

# The ingress-nginx-neo kubectl plugin

The kubectl plugin inspects a running controller: the generated `nginx.conf`, the dynamic backends and
certificates, the logs, and the Ingress resources it serves. It is invoked as `kubectl ingress-nginx-neo`; the
binary is named `kubectl-ingress_nginx_neo`.

## Installation

The plugin is attached to every [release](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases) as an
archive per platform: `kubectl-ingress_nginx_neo_<os>_<arch>.tar.gz` (`.zip` for Windows) for `linux`, `darwin` and
`windows` on `amd64` and `arm64`. The commands below install the release `<version>`.

### With krew

Install [krew](https://krew.sigs.k8s.io/), then install the plugin from the krew manifest of the release:

```console
kubectl krew install --manifest-url=https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/ingress-nginx-neo.yaml
```

The krew manifest pins the SHA-256 checksum of every archive. To install another version, uninstall the plugin with
`kubectl krew uninstall ingress-nginx-neo` and install it again with the manifest URL of that release.

### From the release archive

Download the archive for your platform, verify it (see
[Artifacts and verification](./deploy/artifacts.md#kubectl-plugin)) and put the binary into a directory on your
`PATH`. For example, on Linux `amd64`:

```console
curl -fsSLO https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/kubectl-ingress_nginx_neo_linux_amd64.tar.gz
curl -fsSLO https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/releases/download/<version>/checksums.sha256
sha256sum --check --ignore-missing checksums.sha256
tar -xzf kubectl-ingress_nginx_neo_linux_amd64.tar.gz kubectl-ingress_nginx_neo
sudo install kubectl-ingress_nginx_neo /usr/local/bin/
```

### Check the installation

```console
kubectl ingress-nginx-neo --version
```

prints `ingress-nginx-neo version <version> (commit <commit>, https://github.com/Kuzmenko-Pavel/ingress-nginx-neo)`.

`kubectl ingress-nginx-neo --help` lists the commands:

```console
$ kubectl ingress-nginx-neo --help
A kubectl plugin for inspecting ingress-nginx-neo controllers

Usage:
  ingress-nginx-neo [command]

Available Commands:
  backends    Inspect the dynamic backend information of an ingress-nginx instance
  certs       Output the certificate data stored in an ingress-nginx pod
  completion  Generate the autocompletion script for the specified shell
  conf        Inspect the generated nginx.conf
  exec        Execute a command inside an ingress-nginx pod
  general     Inspect the other dynamic ingress-nginx information
  help        Help about any command
  info        Show information about the controller service
  ingresses   Provide a short summary of all of the ingress definitions
  lint        Inspect kubernetes resources for possible issues
  logs        Get the kubernetes logs for an ingress-nginx pod
  ssh         ssh into a running ingress-nginx pod

Flags:
      --as string                      Username to impersonate for the operation. User could be a regular user or a service account in a namespace.
      --as-group stringArray           Group to impersonate for the operation, this flag can be repeated to specify multiple groups.
      --as-uid string                  UID to impersonate for the operation.
      --as-user-extra stringArray      User extras to impersonate for the operation, this flag can be repeated to specify multiple values for the same key.
      --cache-dir string               Default cache directory (default "/home/me/.kube/cache")
      --certificate-authority string   Path to a cert file for the certificate authority
      --client-certificate string      Path to a client certificate file for TLS
      --client-key string              Path to a client key file for TLS
      --cluster string                 The name of the kubeconfig cluster to use
      --context string                 The name of the kubeconfig context to use
      --disable-compression            If true, opt-out of response compression for all requests to the server
  -h, --help                           help for ingress-nginx-neo
      --insecure-skip-tls-verify       If true, the server's certificate will not be checked for validity. This will make your HTTPS connections insecure
      --kubeconfig string              Path to the kubeconfig file to use for CLI requests.
  -n, --namespace string               If present, the namespace scope for this CLI request
      --request-timeout string         The length of time to wait before giving up on a single server request. Non-zero values should contain a corresponding time unit (e.g. 1s, 2m, 3h). A value of zero means don't timeout requests. (default "0")
  -s, --server string                  The address and port of the Kubernetes API server
      --tls-server-name string         Server name to use for server certificate validation. If it is not provided, the hostname used to contact the server is used
      --token string                   Bearer token for authentication to the API server
      --user string                    The name of the kubeconfig user to use
  -v, --version                        version for ingress-nginx-neo

Use "ingress-nginx-neo [command] --help" for more information about a command.
```

## Common flags

- Every command supports the basic `kubectl` configuration flags such as `--namespace`, `--context` and
  `--kubeconfig`. Without `--namespace`, the namespace of the current kubeconfig context is used, or `default`.
  The examples below use `-n ingress-nginx-neo`, the namespace of a default installation.
- `ingresses` and `lint` inspect resources and support `--all-namespaces`.

### Selecting the controller pod

The commands that act on a controller pod (`backends`, `certs`, `conf`, `exec`, `general`, `logs`, `ssh`) support
these flags:

| Flag | Description |
|------|-------------|
| `--pod <name>` | use the pod with this name |
| `-l`, `--selector <label query>` | use a pod matching this label selector |
| `--deployment <name>` | use a pod of this Deployment |
| `--container <name>` | the controller container in the pod (default `controller`) |

`--pod` takes precedence over `--selector`, which takes precedence over `--deployment`. Without any of them, the
plugin looks for pods in the namespace that match the selector

```
app.kubernetes.io/component=controller,app.kubernetes.io/name in (ingress-nginx-neo,ingress-nginx)
```

and uses the first pod that is Ready (or the first pod found, if none is Ready). This works for controllers deployed
as a Deployment or a DaemonSet, and for releases that keep the name `ingress-nginx`
(see [Migrate from kubernetes/ingress-nginx](./deploy/migrate.md)). If several controllers run in the same
namespace, select one with `--selector`, for example
`-l app.kubernetes.io/instance=<release>,app.kubernetes.io/component=controller`.

## Commands

### backends

`kubectl ingress-nginx-neo backends` prints the backends that the controller currently knows about, as a JSON array.
Each backend object contains the fields `name`, `service`, `port`, `sslPassthrough`, `endpoints`,
`sessionAffinityConfig`, `upstreamHashByConfig`, `noServer` and `trafficShapingPolicy` (empty fields are omitted).

```console
$ kubectl ingress-nginx-neo backends -n ingress-nginx-neo
[
  {
    "name": "default-apple-service-5678",
    ...
```

Add `--list` to print only the backend names, one per line. Backend names have the form
`<namespace>-<service>-<port>`:

```console
$ kubectl ingress-nginx-neo backends -n ingress-nginx-neo --list
default-apple-service-5678
default-echo-service-8080
upstream-default-backend
```

Add `--backend <name>` to print only the backend with this name. `--list` and `--backend` cannot be combined.

### certs

`kubectl ingress-nginx-neo certs --host <hostname>` prints the certificate and private key that the controller uses
for the host, in PEM format. `--host` is required. If the controller has no certificate for the host, the command
prints `No cert found for host <hostname>`.

!!! warning
    This command prints the private key. Do not share its output and do not log it.

```console
$ kubectl ingress-nginx-neo certs -n ingress-nginx-neo --host testaddr.local
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
-----BEGIN RSA PRIVATE KEY-----
<REDACTED! DO NOT SHARE THIS!>
-----END RSA PRIVATE KEY-----
```

### conf

`kubectl ingress-nginx-neo conf` prints the generated `nginx.conf`. Add `--host <hostname>` to print only the
`server` block for this host:

```console
$ kubectl ingress-nginx-neo conf -n ingress-nginx-neo --host testaddr.local
server {
        server_name "testaddr.local" ;
...
```

If the host has no server block, the command prints `host <hostname> was not found in the controller's nginx.conf`.

### exec

`kubectl ingress-nginx-neo exec` runs a command in the controller container, like `kubectl exec`. Pass the command
after `--`. It supports `-i`, `--stdin` (pass stdin to the container) and `-t`, `--tty` (stdin is a TTY):

```console
$ kubectl ingress-nginx-neo exec -n ingress-nginx-neo -- /nginx-ingress-controller --version
```

### general

`kubectl ingress-nginx-neo general` prints the general dynamic configuration of the controller as JSON. It
prints an empty object:

```console
$ kubectl ingress-nginx-neo general -n ingress-nginx-neo
{}
```

### info

`kubectl ingress-nginx-neo info` shows the name and addresses of the controller Service:

```console
$ kubectl ingress-nginx-neo info -n ingress-nginx-neo
Service: ingress-nginx-neo-controller
Service cluster IP address: 10.96.172.20
LoadBalancer IP|CNAME: 
```

The `LoadBalancer IP|CNAME` line shows the `spec.loadBalancerIP` field of the Service, which is empty unless an IP
address was requested for the load balancer. Use `kubectl get service` to see the address assigned by the cloud
provider.

Without `--service`, the command looks for Services in the namespace that match the controller selector shown in
[Selecting the controller pod](#selecting-the-controller-pod) and whose name ends with `-controller`. If none or
several are found, pass the name with `--service <service>`.

### ingresses

`kubectl ingress-nginx-neo ingresses` (aliases `ingress` and `ing`) shows one row per host and path of the Ingress
definitions in a namespace, with the backend Service and its number of endpoints. Add `--all-namespaces` to show all
namespaces (this adds the `NAMESPACE` column) and `--host <hostname>` to show only one host.

Compare:

```console
$ kubectl get ingresses --all-namespaces
NAMESPACE   NAME               CLASS   HOSTS                            ADDRESS        PORTS   AGE
default     example-ingress1   nginx   testaddr.local,testaddr2.local   203.0.113.10   80      5d
default     test-ingress-2     nginx   *                                203.0.113.10   80      5d
```

with:

```console
$ kubectl ingress-nginx-neo ingresses --all-namespaces
NAMESPACE   INGRESS NAME       HOST+PATH                   ADDRESSES      TLS   SERVICE         SERVICE PORT   ENDPOINTS
default     example-ingress1   testaddr.local/etameta      203.0.113.10   NO    pear-service    5678           5
default     example-ingress1   testaddr2.local/otherpath   203.0.113.10   NO    apple-service   5678           1
default     test-ingress-2     *                           203.0.113.10   NO    echo-service    8080           2
```

### lint

`kubectl ingress-nginx-neo lint` checks the Ingress resources and Deployments of a namespace for known
configuration issues, such as annotations or controller flags that the controller does not support. Use
`lint ingresses` or `lint deployments` to run only one of the two checks.

| Flag | Description |
|------|-------------|
| `--all-namespaces` | check resources in all namespaces |
| `--show-all` | also list resources without problems (marked `✓`) |
| `-v`, `--verbose` | show a link to an issue explaining each problem, where one exists |

```console
$ kubectl ingress-nginx-neo lint --all-namespaces --verbose
Checking ingresses...
✗ anamespace/this-nginx
  - Contains the session-cookie-hash annotation, which the controller does not support.
      https://github.com/kubernetes/ingress-nginx/issues/3743

✗ othernamespace/ingress-definition-blah
  - The rewrite-target annotation value does not reference a capture group
      https://github.com/kubernetes/ingress-nginx/issues/3174

Checking deployments...
✗ namespace2/ingress-nginx-neo-controller
  - Uses the --sort-backends flag, which the controller does not accept
      https://github.com/kubernetes/ingress-nginx/issues/3655

```

### logs

`kubectl ingress-nginx-neo logs` prints the logs of the controller container, like `kubectl logs` with a subset of
its flags: `-f`, `--follow`, `-p`, `--previous`, `--since`, `--since-time`, `--tail`, `--timestamps` and
`--limit-bytes`.

```console
$ kubectl ingress-nginx-neo logs -n ingress-nginx-neo --tail 20
-------------------------------------------------------------------------------
NGINX Ingress controller
  Release:       <version>
  Build:         <commit>
  Repository:    https://github.com/Kuzmenko-Pavel/ingress-nginx-neo
  nginx version: nginx/<nginx version>

-------------------------------------------------------------------------------
...
```

### ssh

`kubectl ingress-nginx-neo ssh` opens an interactive shell in the controller container. It is the same as
`kubectl ingress-nginx-neo exec -it -- /bin/bash`.

```console
$ kubectl ingress-nginx-neo ssh -n ingress-nginx-neo
```

### completion

`kubectl ingress-nginx-neo completion <shell>` generates a shell completion script for `bash`, `zsh`, `fish` or
`powershell`.
