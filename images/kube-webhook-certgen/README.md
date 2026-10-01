# kube-webhook-certgen

Generates a CA and a leaf certificate with a long (100y) expiration and stores them in a Secret,
then patches the `caBundle` of ValidatingWebhookConfiguration, MutatingWebhookConfiguration and
APIService objects with that CA. It can also patch the webhooks' `failurePolicy`.

The ingress-nginx-neo Helm chart runs it as pre-install and post-install hook Jobs to provision the
admission webhook certificate. It is based on [jet/kube-webhook-certgen](https://github.com/jet/kube-webhook-certgen)
(MIT, see `rootfs/LICENSE`).

The tool is meant for self-signed webhook certificates. For a complete certificate management
solution use [cert-manager](https://github.com/cert-manager/cert-manager); the chart supports it with
`controller.admissionWebhooks.certManager.enabled`.

## Image

`ghcr.io/kuzmenko-pavel/ingress-nginx-neo/kube-webhook-certgen:<version>`, published with every
ingress-nginx-neo release for `linux/amd64` and `linux/arm64`.

## Commands

```
Usage:
  kube-webhook-certgen [flags]
  kube-webhook-certgen [command]

Available Commands:
  completion  Generate the autocompletion script for the specified shell
  create      Generate a ca and server cert+key and store the results in a secret 'secret-name' in 'namespace'
  help        Help about any command
  patch       Patch a ValidatingWebhookConfiguration, MutatingWebhookConfiguration or APIService 'object-name' by using the ca from 'secret-name' in 'namespace'
  version     Prints the CLI version information

Flags:
  -h, --help                help for kube-webhook-certgen
      --kubeconfig string   Path to kubeconfig file: e.g. ~/.kube/kind-config-kind
      --log-format string   Log format: text|json (default "json")
      --log-level string    Log level: panic|fatal|error|warn|info|debug|trace (default "info")
```

### create

```
Flags:
      --cert-name string     Name of cert file in the secret (default "cert")
  -h, --help                 help for create
      --host string          Comma-separated hostnames and IPs to generate a certificate for
      --key-name string      Name of key file in the secret (default "key")
      --namespace string     Namespace of the secret where certificate information will be written
      --secret-name string   Name of the secret where certificate information will be written
```

### patch

```
Flags:
      --apiservice-name string        Name of APIService that will be patched
  -h, --help                          help for patch
      --namespace string              Namespace of the secret where certificate information will be read from
      --patch-failure-policy string   If set, patch the webhooks with this failure policy. Valid options are Ignore or Fail
      --patch-mutating                If true, patch MutatingWebhookConfiguration (default true)
      --patch-validating              If true, patch ValidatingWebhookConfiguration (default true)
      --secret-name string            Name of the secret where certificate information will be read from
      --webhook-name string           Name of ValidatingWebhookConfiguration and MutatingWebhookConfiguration that will be updated
```

`patch` fails when `--patch-validating=false`, `--patch-mutating=false` and no `--apiservice-name` are given.

## Development

```console
make test-unit          # includes the unit tests of this module
make test-e2e-certgen   # creates a kind cluster and runs hack/e2e.sh against it
```
