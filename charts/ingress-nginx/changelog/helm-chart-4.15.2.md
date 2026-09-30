# Changelog

This file documents all notable changes to [ingress-nginx](https://github.com/Kuzmenko-Pavel/ingress-nginx) Helm Chart. The release numbering uses [semantic versioning](http://semver.org).

### 4.15.2

* Update Ingress-Nginx version controller-v1.15.2
* Default images now come from this distribution: `global.image.registry: ghcr.io`, `controller.image.image: kuzmenko-pavel/ingress-nginx/controller`, `controller.admissionWebhooks.patch.image.image: kuzmenko-pavel/ingress-nginx/kube-webhook-certgen` (v1.6.10). The packaged chart pins their digests. `defaultBackend` keeps the upstream image (`registry.k8s.io`), so `global.image.registry` no longer applies to it
* Allow setting `ttlSecondsAfterFinished` for the admission webhook `createSecret` and `patch` Jobs (`controller.admissionWebhooks.createSecretJob.ttlSecondsAfterFinished`, `controller.admissionWebhooks.patchWebhookJob.ttlSecondsAfterFinished`; default `0`, unchanged)

**Full Changelog**: https://github.com/Kuzmenko-Pavel/ingress-nginx/compare/v1.15.1...v1.15.2
