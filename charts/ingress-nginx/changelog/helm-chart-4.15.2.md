# Changelog

This file documents all notable changes to [ingress-nginx](https://github.com/Kuzmenko-Pavel/ingress-nginx) Helm Chart. The release numbering uses [semantic versioning](http://semver.org).

### 4.15.2

* Update Ingress-Nginx version controller-v1.15.2
* All default images now come from this distribution (`global.image.registry: ghcr.io`), for `linux/amd64` and `linux/arm64`: `kuzmenko-pavel/ingress-nginx/controller`, `kuzmenko-pavel/ingress-nginx/kube-webhook-certgen` (v1.6.10) and, as default backend, `kuzmenko-pavel/ingress-nginx/custom-error-pages` (v1.3.0, replaces the amd64-only `registry.k8s.io/defaultbackend-amd64:1.5`; same port 8080 and `/healthz`, returns 404 for unknown hosts/paths). The packaged chart pins all digests
* Install instructions use the OCI chart; migration notes from the kubernetes/ingress-nginx chart
* Allow setting `ttlSecondsAfterFinished` for the admission webhook `createSecret` and `patch` Jobs (`controller.admissionWebhooks.createSecretJob.ttlSecondsAfterFinished`, `controller.admissionWebhooks.patchWebhookJob.ttlSecondsAfterFinished`; default `0`, unchanged)

**Full Changelog**: https://github.com/Kuzmenko-Pavel/ingress-nginx/compare/v1.15.1...v1.15.2
