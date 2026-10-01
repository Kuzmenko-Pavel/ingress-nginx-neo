# Security policy

## Reporting a vulnerability

Report vulnerabilities privately with GitHub Security Advisories:
<https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/security/advisories/new>.

Do not open a public issue for an undisclosed vulnerability. Include where possible:

- the affected release version (image tag, chart version);
- a description of the issue and its impact;
- steps to reproduce or a proof of concept;
- scanner output and CVE identifiers.

## Supported versions

The latest minor release receives fixes; a fix is released as a patch release of that minor (see
the [release guide](https://kuzmenko-pavel.github.io/ingress-nginx-neo/latest/developer-guide/release/#hotfix)).
Older releases are not maintained.

The images of the latest release are scanned weekly with Trivy; findings are published to the code
scanning alerts of the repository.
