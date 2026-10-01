# gRPC

This example demonstrates how to route traffic to a gRPC service through the ingress-nginx-neo controller.

## Prerequisites

1. You have a kubernetes cluster running.
2. You have a domain name such as `example.com` that is configured to route traffic to the ingress-nginx-neo controller.
3. You have the ingress-nginx-neo controller installed as per the [installation guide](../../deploy/index.md).
4. You have a backend application running a gRPC server listening for TCP traffic.  Step 1 deploys a public test server if you don't have one.
5. You're also responsible for provisioning an SSL certificate for the ingress. So you need to have a valid SSL certificate, deployed as a Kubernetes secret of type `tls`, in the same namespace as the gRPC application.

### Step 1: Create a Kubernetes `Deployment` for the gRPC app

- If you already have a gRPC application deployed in your cluster, skip this step and continue from Step 2.

- This example uses [grpcbin](https://github.com/moul/grpcbin), a public gRPC test server with server reflection.
  It serves plaintext gRPC on port `9000`:

  ```
  cat <<EOF | kubectl apply -f -
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    labels:
      app: grpcbin
    name: grpcbin
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: grpcbin
    template:
      metadata:
        labels:
          app: grpcbin
      spec:
        containers:
        - image: moul/grpcbin:latest@sha256:bd8f2ffdd02d0849fad2d1c754eff4402c867e7a3e0552b8992f4590f5687d20
          name: grpcbin
          ports:
          - containerPort: 9000
          resources:
            limits:
              cpu: 100m
              memory: 100Mi
            requests:
              cpu: 50m
              memory: 50Mi
  EOF
  ```

### Step 2: Create the Kubernetes `Service` for the gRPC app

- Create a service of type ClusterIP. Edit the name/namespace/label/port to match your deployment/pod.
  ```
  cat <<EOF | kubectl apply -f -
  apiVersion: v1
  kind: Service
  metadata:
    labels:
      app: grpcbin
    name: grpcbin
  spec:
    ports:
    - port: 80
      protocol: TCP
      targetPort: 9000
    selector:
      app: grpcbin
    type: ClusterIP
  EOF
  ```

### Step 3: Create the Kubernetes `Ingress` resource for the gRPC app

- Use the following example manifest of a ingress resource to create a ingress for your grpc app. If required, edit it to match your app's details like name, namespace, service, secret etc. Make sure you have the required SSL-Certificate, existing in your Kubernetes cluster in the same namespace where the gRPC app is. The certificate must be available as a kubernetes secret resource, of type "kubernetes.io/tls" https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets. This is because we are terminating TLS on the ingress.

  ```
  cat <<EOF | kubectl apply -f -
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    annotations:
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    name: fortune-ingress
    namespace: default
  spec:
    ingressClassName: nginx
    rules:
    - host: grpctest.dev.mydomain.com
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: grpcbin
              port:
                number: 80
    tls:
    # This secret must exist beforehand
    # The cert must also contain the subj-name grpctest.dev.mydomain.com
    # See ../PREREQUISITES.md#tls-certificates
    - secretName: wildcard.dev.mydomain.com
      hosts:
        - grpctest.dev.mydomain.com
  EOF
  ```

- The takeaway is that we are not doing any TLS configuration on the server (as we are terminating TLS at the ingress level, gRPC traffic will travel unencrypted inside the cluster and arrive "insecure").

- For your own application you may or may not want to do this.  If you prefer to forward encrypted traffic to your POD and terminate TLS at the gRPC server itself, add the ingress annotation `nginx.ingress.kubernetes.io/backend-protocol: "GRPCS"`.

- A few more things to note:

  - We've tagged the ingress with the annotation `nginx.ingress.kubernetes.io/backend-protocol: "GRPC"`.  This is the magic ingredient that sets up the appropriate nginx configuration to route http/2 traffic to our service.

  - We're terminating TLS at the ingress and have configured an SSL certificate `wildcard.dev.mydomain.com`.  The ingress matches traffic arriving as `https://grpctest.dev.mydomain.com:443` and routes unencrypted messages to the backend Kubernetes service.

### Step 4: test the connection

- Once we've applied our configuration to Kubernetes, it's time to test that we can actually talk to the backend.  To do this, we'll use the [grpcurl](https://github.com/fullstorydev/grpcurl) utility:

  ```
  $ grpcurl -d '{"greeting": "neo"}' grpctest.dev.mydomain.com:443 hello.HelloService/SayHello
  {
    "reply": "hello neo"
  }
  ```

### Debugging Hints

1. Obviously, watch the logs on your app.
2. Watch the logs of the controller (increasing verbosity with `--v=` as
   needed): `kubectl -n ingress-nginx-neo logs deploy/ingress-nginx-neo-controller`.
3. Double-check your address and ports.
4. Set the `GODEBUG=http2debug=2` environment variable to get detailed http/2
   logging on the client and/or server.
5. Study RFC 9113 (http/2) <https://www.rfc-editor.org/rfc/rfc9113>.

> See also the specific gRPC settings of NGINX: https://nginx.org/en/docs/http/ngx_http_grpc_module.html

### Notes on using response/request streams

> `grpc_read_timeout` and `grpc_send_timeout` will be set as `proxy_read_timeout` and `proxy_send_timeout` when you set backend protocol to `GRPC` or `GRPCS`.

1. If your server only does response streaming and you expect a stream to be open longer than 60 seconds, you will have to change the `grpc_read_timeout` to accommodate this.
2. If your service only does request streaming and you expect a stream to be open longer than 60 seconds, you have to change the
`grpc_send_timeout` and the `client_body_timeout`.
3. If you do both response and request streaming with an open stream longer than 60 seconds, you have to change all three timeouts: `grpc_read_timeout`, `grpc_send_timeout` and `client_body_timeout`.
