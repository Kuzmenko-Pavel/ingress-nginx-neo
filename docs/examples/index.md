# Ingress examples

This directory contains a catalog of examples on how to run, configure and scale Ingress.
Please review the [prerequisites](PREREQUISITES.md) before trying them.

The examples on these pages use the `spec.ingressClassName` field to select the IngressClass.

Category | Name | Description | Complexity Level
---------| ---- | ----------- | ----------------
Apps | [Docker Registry](docker-registry/README.md) | expose a container registry with large uploads and TLS | Intermediate
Apps | [gRPC](grpc/README.md) | route gRPC traffic to a backend with TLS termination | Intermediate
Auth | [Basic authentication](auth/basic/README.md) | password protect your website | Intermediate
Auth | [Client certificate authentication](auth/client-certs/README.md) | secure your website with client certificate authentication | Intermediate
Auth | [External authentication plugin](auth/external-auth/README.md) | defer to an external authentication service | Intermediate
Auth | [OAuth external auth](auth/oauth-external-auth/README.md) | protect a service with OAuth2 Proxy or Vouch Proxy and GitHub | Advanced
Customization | [Configuration snippets](customization/configuration-snippets/README.md) | customize nginx location configuration using annotations | Advanced
Customization | [Custom configuration](customization/custom-configuration/README.md) | change global NGINX settings with the controller ConfigMap | Beginner
Customization | [Custom DH parameters for perfect forward secrecy](customization/ssl-dh-param/README.md) | use custom Diffie-Hellman parameters for DHE ciphers | Intermediate
Customization | [Custom errors](customization/custom-errors/README.md) | serve custom error pages from the default backend | Intermediate
Customization | [Custom headers](customization/custom-headers/README.md) | set custom headers before sending traffic to backends | Advanced
Customization | [External authentication with response header propagation](customization/external-auth-headers/README.md) | pass headers from the authentication service to the backend | Intermediate
Customization | [Sysctl tuning](customization/sysctl/README.md) | tune kernel parameters of the controller pods with an init container | Advanced
Features | [Rewrite](rewrite/README.md) | rewrite request paths and redirect to an application root | Intermediate
Features | [Session stickiness](affinity/cookie/README.md) | route requests consistently to the same endpoint | Advanced
Features | [Canary Deployments](canary/README.md) | weighted canary routing to a separate deployment | Intermediate
Policy | [Open Policy Agent rules](openpolicyagent/README.md) | restrict `pathType: ImplementationSpecific` with Gatekeeper | Advanced
Scaling | [Static IP](static-ip/README.md) | a single ingress gets a single static IP |  Intermediate
TLS | [Multi TLS certificate termination](multi-tls/README.md) | terminate TLS for several hosts with one certificate per host | Intermediate
TLS | [TLS termination](tls-termination/README.md) | terminate TLS at the controller and proxy plain HTTP to the backend | Beginner
