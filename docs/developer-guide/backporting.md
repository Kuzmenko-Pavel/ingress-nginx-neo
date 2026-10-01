# Backporting

ingress-nginx-neo is based on the kubernetes/ingress-nginx codebase and shares its Go module path
(`k8s.io/ingress-nginx`) and directory layout, so changes of that project and of its other
derivatives can be applied with `git cherry-pick`.

## From kubernetes/ingress-nginx

```console
git remote add upstream https://github.com/kubernetes/ingress-nginx.git
git fetch upstream --no-tags
git switch -c fix/<name> origin/main
git cherry-pick -x <sha>
```

`--no-tags` keeps the tags of the other project out of the clone: release tags of
ingress-nginx-neo are the only tags it needs, and `make release-tag` reads the nearest one.
`-x` records the source commit in the message; rewrite the subject in
[Conventional Commits](ci.md#conventional-commits) form, for example
`fix(controller): <description>`.

Typical adjustments after the pick:

- paths: the chart is `charts/ingress-nginx-neo`, build and release logic is in the `Makefile` and
  `tools/`, the static manifests are generated at release time;
- image references and versions in charts, tests and docs follow this repository
  (`ghcr.io/kuzmenko-pavel/ingress-nginx-neo/...`, versions from the release tag);
- regenerate generated files (`make docs-generate helm-docs-generate`).

## From other derivatives

The same procedure applies to any repository that shares the codebase: add it as a remote with a
descriptive name, fetch without tags and cherry-pick with `-x`.

## NGINX fixes

Fixes of NGINX itself are backported as patches of the base image; see
[Images](images.md#nginx-base) and
[images/nginx/README.md](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/blob/main/images/nginx/README.md).
