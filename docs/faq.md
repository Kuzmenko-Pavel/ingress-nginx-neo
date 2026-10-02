
# FAQ

## Multi-tenant Kubernetes

Do not use in multi-tenant Kubernetes production installations. This project assumes that users that can create Ingress objects are administrators of the cluster.

For example, the controller has global and per Ingress configuration options that make it insecure, if enabled, in a multi-tenant environment. 

For example, enabling snippets, a global configuration, allows any Ingress object to run arbitrary Lua code that could affect the security of all Ingress objects that a controller is running. 

Snippet annotations are disabled by default: the ConfigMap key [`allow-snippet-annotations`](./user-guide/nginx-configuration/configmap.md#allow-snippet-annotations) is `false`.

## Multiple controller in one cluster

Question - How can I easily install multiple instances of the controller in the same cluster?

You can install them in different namespaces, each with its own IngressClass. With Helm (see
[Installation](./deploy/index.md)):

```
helm install ingress-nginx-neo-2 oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
  --version <version> \
  --namespace ingress-nginx-neo-2 --create-namespace \
  --set controller.ingressClassResource.name=nginx-two \
  --set controller.ingressClass=nginx-two \
  --set controller.ingressClassResource.controllerValue="example.com/ingress-nginx-neo-2" \
  --set controller.ingressClassResource.enabled=true \
  --set controller.ingressClassByName=true
```

If you need to install yet another instance, repeat the command with a new release name, namespace and
IngressClass (for example from "-2" to "-3").

Note that `controller.ingressClassResource.name` and `controller.ingressClass` have to be set correctly.
The first creates the IngressClass object and the other configures the controller pods.

See [Multiple Ingress controllers](./user-guide/multiple-ingress.md) for details.

### I can't use multiple namespaces, what should I do?

If you need to install all instances in the same namespace, then you need to specify a different **election id**, like this:

```
helm install ingress-nginx-neo-2 oci://ghcr.io/kuzmenko-pavel/ingress-nginx-neo/charts/ingress-nginx-neo \
  --version <version> \
  --namespace ingress-nginx-neo \
  --set controller.electionID=nginx-two-leader \
  --set controller.ingressClassResource.name=nginx-two \
  --set controller.ingressClass=nginx-two \
  --set controller.ingressClassResource.controllerValue="example.com/ingress-nginx-neo-2" \
  --set controller.ingressClassResource.enabled=true \
  --set controller.ingressClassByName=true
```

## Retaining Client IPAddress

Question - How to obtain the real-client-ipaddress ?

The goto solution for retaining the real-client IPaddress is to enable PROXY protocol.

Enabling PROXY protocol has to be done on both, the controller, as well as the L4 load balancer, in front of the controller.

The real-client IP address is lost by default, when traffic is forwarded over the network. But enabling PROXY protocol ensures that the connection details are retained and hence the real-client IP address doesn't get lost.

Enabling proxy-protocol on the controller is documented [here](./user-guide/nginx-configuration/configmap.md#use-proxy-protocol) .

For enabling proxy-protocol on the LoadBalancer, please refer to the documentation of your infrastructure provider because that is where the LB is provisioned.

Some more info available [here](./user-guide/miscellaneous.md#source-ip-address)

Some more info on proxy-protocol is [here](./user-guide/miscellaneous.md#proxy-protocol)

### client-ipaddress on single-node cluster

Single node clusters are created for dev & test uses with tools like "kind" or "minikube". A trick to simulate a real use network with these clusters (kind or minikube) is to install Metallb and configure the ipaddress of the kind container or the minikube vm/container, as the starting and ending of the pool for Metallb in L2 mode. Then the host ip becomes a real client ipaddress, for curl requests sent from the host.

After installing the controller on a kind or a minikube cluster with Helm, you can configure it for real-client-ip with a simple change to the service that the chart creates (`ingress-nginx-neo-controller` for the default release name). The service object of --type LoadBalancer has a field service.spec.externalTrafficPolicy. If you set the value of this field to "Local" then the real-ipaddress of a client is visible to the controller.

```
% kubectl explain service.spec.externalTrafficPolicy
KIND:       Service
VERSION:    v1

FIELD: externalTrafficPolicy <string>

DESCRIPTION:
    externalTrafficPolicy describes how nodes distribute service traffic they
    receive on one of the Service's "externally-facing" addresses (NodePorts,
    ExternalIPs, and LoadBalancer IPs). If set to "Local", the proxy will
    configure the service in a way that assumes that external load balancers
    will take care of balancing the service traffic between nodes, and so each
    node will deliver traffic only to the node-local endpoints of the service,
    without masquerading the client source IP. (Traffic mistakenly sent to a
    node with no endpoints will be dropped.) The default value, "Cluster", uses
    the standard behavior of routing to all endpoints evenly (possibly modified
    by topology and other features). Note that traffic sent to an External IP or
    LoadBalancer IP from within the cluster will always get "Cluster" semantics,
    but clients sending to a NodePort from within the cluster may need to take
    traffic policy into account when picking a node.
    
    Possible enum values:
     - `"Cluster"` routes traffic to all endpoints.
     - `"Local"` preserves the source IP of the traffic by routing only to
    endpoints on the same node as the traffic was received on (dropping the
    traffic if there are no local endpoints).
```

### client-ipaddress L7

The solution is to get the real client IPaddress from the ["X-Forward-For" HTTP header](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For)

Example : If your application pod behind the controller uses the NGINX webserver and the reverseproxy inside it, then you can do the following to preserve the remote client IP.

- First you need to make sure that the X-Forwarded-For header reaches the backend pod. This is done by using a controller ConfigMap key. It is documented [here](./user-guide/nginx-configuration/configmap.md#use-forwarded-headers)

- Next, edit `nginx.conf` file inside your app pod, to contain the directives shown below:

```
set_real_ip_from 0.0.0.0/0; # Trust all IPs (use your VPC CIDR block in production)
real_ip_header X-Forwarded-For;
real_ip_recursive on;

log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" '
                'host=$host x-forwarded-for=$http_x_forwarded_for';

access_log /var/log/nginx/access.log main;

```

## Validation Of **`path`**

- For improving security and also following desired standards on Kubernetes API spec, the controller validates the
value of the key `ingress.spec.rules.http.paths.path`. This validation is enabled by default and controlled by the
ConfigMap key [`strict-validate-path-type`](./user-guide/nginx-configuration/configmap.md#strict-validate-path-type).

- When "`ingress.spec.rules.http.pathType=Exact`" or "`pathType=Prefix`", this
validation limits the characters accepted in the field "`ingress.spec.rules.http.paths.path`"
to alphanumeric characters and "`/`", "`_`", "`-`", "`.`". Also, in this case,
the path must start with "`/`".

- When the ingress resource path contains other characters (like on rewrite
configurations), the pathType value should be "`ImplementationSpecific`".

- API Spec on pathType is documented [here](https://kubernetes.io/docs/concepts/services-networking/ingress/#path-types)

- The validation happens in the admission webhook. So if an ingress object contains other characters in the `path`
field, but is not using `pathType` value `ImplementationSpecific`, then the ingress object is denied admission.

- The cluster admin should establish validation rules using mechanisms like
"`Open Policy Agent`", to validate that only authorized users can use
ImplementationSpecific pathType and that only the authorized characters can be
used.

- A complete example of an Openpolicyagent gatekeeper rule is available [here](./examples/openpolicyagent/README.md)

- If you have any issues or concerns, please open an issue in the
[GitHub repository](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/issues).

## Why does chunked transfer encoding from my application fail?

- If your code is setting the HTTP header `"Transfer-Encoding: chunked"` and
the controller log messages show an error about duplicate header, it is
because of this change in NGINX <http://hg.nginx.org/nginx/rev/2bf7792c262e>

- More details are available in this issue <https://github.com/kubernetes/ingress-nginx/issues/11162>
