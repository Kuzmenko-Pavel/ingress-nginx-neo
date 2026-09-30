# Changelog

This file documents all notable changes to [ingress-nginx](https://github.com/Kuzmenko-Pavel/ingress-nginx) Helm Chart. The release numbering uses [semantic versioning](http://semver.org).

### 4.15.2

* Update Ingress-Nginx version controller-v1.15.2
* Images are published to `ghcr.io/kuzmenko-pavel/ingress-nginx` and pinned by digest in the packaged chart
* Allow setting `ttlSecondsAfterFinished` for the admission webhook `createSecret` and `patch` Jobs (`controller.admissionWebhooks.createSecretJob.ttlSecondsAfterFinished`, `controller.admissionWebhooks.patchWebhookJob.ttlSecondsAfterFinished`; default `0`, unchanged)

**Full Changelog**: https://github.com/Kuzmenko-Pavel/ingress-nginx/compare/v1.15.1...v1.15.2
