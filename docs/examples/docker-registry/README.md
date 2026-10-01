# Docker registry

This example demonstrates how to deploy a [container registry](https://github.com/distribution/distribution) (the `registry` image) in the cluster and configure Ingress to enable access from the Internet.

## Deployment

First we deploy the docker registry in the cluster:

```console
kubectl apply -f https://raw.githubusercontent.com/Kuzmenko-Pavel/ingress-nginx-neo/main/docs/examples/docker-registry/deployment.yaml
```

!!! Important
    **DO NOT RUN THIS IN PRODUCTION**

    This deployment uses `emptyDir` in the `volumeMount` which means the contents of the registry will be deleted when the pod dies.

The next required step is creation of the ingress rules. To do this we have two options: with and without TLS

### Without TLS

Download and edit the yaml deployment replacing `registry.<your domain>` with a valid DNS name pointing to the ingress controller:

```console
wget https://raw.githubusercontent.com/Kuzmenko-Pavel/ingress-nginx-neo/main/docs/examples/docker-registry/ingress-without-tls.yaml
kubectl apply -f ingress-without-tls.yaml
```

!!! Important
    Running a docker registry without TLS requires we configure our local docker daemon with the insecure registry flag.

Please check [deploy a plain HTTP registry](https://distribution.github.io/distribution/about/insecure/#deploy-a-plain-http-registry)

### With TLS

Download and edit the yaml deployment replacing `registry.<your domain>` with a valid DNS name pointing to the ingress controller:

```console
wget https://raw.githubusercontent.com/Kuzmenko-Pavel/ingress-nginx-neo/main/docs/examples/docker-registry/ingress-with-tls.yaml
kubectl apply -f ingress-with-tls.yaml
```

The Ingress requests a [Let's Encrypt](https://letsencrypt.org/) certificate through [cert-manager](https://cert-manager.io/) (annotation `cert-manager.io/cluster-issuer`, see [TLS/HTTPS](../../user-guide/tls.md#automated-certificate-management-with-cert-manager)).
Install cert-manager and create a ClusterIssuer, or remove the annotation and create the secret `registry-tls` with an existing SSL certificate.

### Testing

To test the registry is working correctly we download a known image from [Docker Hub](https://hub.docker.com), create a tag pointing to the new registry and upload the image:

```console
docker pull ubuntu:24.04
docker tag ubuntu:24.04 registry.<your domain>/ubuntu:24.04
docker push registry.<your domain>/ubuntu:24.04
```

Please replace `registry.<your domain>` with your domain.
