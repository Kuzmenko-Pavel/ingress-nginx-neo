# Release

## Versions

The git tag is the only version source. A release is one signed annotated tag `vX.Y.Z`; every
artifact of the release takes its version from it: images `vX.Y.Z`, chart `X.Y.Z` with
`appVersion` `vX.Y.Z`, kubectl plugin, static manifests and the documentation version `X.Y`.
No file in the repository holds a version.

The Makefile derives everything from `VERSION` and `CHANNEL` once per run:

| | `CHANNEL=dev` (local) | `CHANNEL=latest` (CI on `main`) | `CHANNEL=release` (CI on a tag) |
|---|---|---|---|
| `VERSION` | `git describe` of the nearest release tag, else `v0.0.0-dev` | same | the tag of the run (`RELEASE_TAG`, `GITHUB_REF_NAME`) |
| image tag | `dev` | `latest` | `vX.Y.Z` |
| chart version | `0.0.0-dev` | `0.0.0-latest` | `X.Y.Z` |
| chart `appVersion` | `dev` | `latest` | `vX.Y.Z` |
| docs version | — | `latest` | `X.Y` |
| `<version>` in the docs pages | highest published release | highest published release | `vX.Y.Z` |
| image digests pinned in the chart | no | no | yes |
| cosign signature, SBOM, provenance | no | yes | yes |

```console
make version
make version CHANNEL=release VERSION=vX.Y.Z
```

Documentation pages write the release as the placeholder `<version>`, always inside code. The MkDocs hook
`tools/docs/release_version.py` replaces it with `DOCS_RELEASE_TAG`, which the Makefile sets from the row
above; before the first release the placeholder stays. `make docs-build` runs the unit tests of the hook.
Example manifests under `docs/examples` use the placeholder `RELEASE_VERSION`, replaced by the `sed`
commands of their pages.

`charts/ingress-nginx-neo/Chart.yaml` carries `version: 0.0.0-latest` and `appVersion: latest`, and
`values.yaml` leaves image tags and digests empty: image tags default to the chart `appVersion`.
Every use of the chart by the Makefile goes through a copy in `dist/chart/` that gets the version of
the channel and, for a release, the digests of the published images; the packaged chart is
`dist/ingress-nginx-neo-<chart version>.tgz`.

Releases follow 0.x semantics: a minor release may contain breaking changes, always listed under
**Breaking changes** in the release notes; a patch release contains fixes only. The latest minor is
supported. Published versions are immutable.

## Creating a release

Releases are cut from `main` (or from a `release-X.Y` branch for a hotfix), in a clone whose
`origin` is `Kuzmenko-Pavel/ingress-nginx-neo`, with an OpenPGP signing key listed in
`trusted_release_managers.yml`.

```console
git switch main && git pull
make release-tag                         # proposes the next version
make release-tag RELEASE_VERSION=vX.Y.Z  # explicit version
git push origin vX.Y.Z
```

`make release-tag` (`tools/release/changelog.sh`):

1. checks that the tree is clean, the branch is `main` or `release-X.Y`, `HEAD` is the tip of its
   `origin` branch, OpenPGP signing is configured and `origin` is the project repository;
2. takes the commits since the nearest release tag (the first release needs `NOTES_FROM=<rev>`,
   the changelog then starts after that revision);
3. proposes the version from them: a breaking change gives the next minor (next major from 1.0),
   a `feat` the next minor, anything else the next patch; `RELEASE_VERSION` must be greater than
   every release of its line and must not exist;
4. writes the changelog into the tag message and opens it in the editor:

   ```text
   ingress-nginx-neo vX.Y.Z

   ### Breaking changes
   - chart: rename values key foo to bar (a1b2c3d)

   ### Features
   - controller: support ordered real_ip_header sources (d4e5f6a)

   ### Fixes
   - plugin: find DaemonSet controller pods by default (0a1b2c3)

   ### Other
   - ci(release): verify tag signer by fingerprint (b2c3d4e)
   ```

5. creates the signed annotated tag `git tag -s -a` and prints the push command. It never pushes.

## Release workflow

Pushing the tag starts `release.yaml`:

1. **verify** — `make release-verify RELEASE_TAG=<tag>`: the tag is `vX.Y.Z`, annotated and signed
   with OpenPGP by a key of `trusted_release_managers.yml` read from `origin/main` (compared by
   fingerprint in an empty temporary keyring); the tagged commit is on `origin/main` or
   `origin/release-X.Y`; its **CI result** check passed; its GitHub Release is not published.
2. **deps** — publishes missing dependency images (normally none: `main` published them).
3. **publish** (environment `release`, approved by a reviewer) — `publish-guard`; rebuilds the
   delivered images from the tagged source, pushes them with SBOM and provenance, tags the
   dependency images with the version (`docker-promote`), signs every digest; builds and signs the
   kubectl plugin; packages the chart with pinned digests and pushes and signs it; renders the
   static manifests; renders the release notes (`dist/release-notes.md`: the tag message, the
   artifacts with digests, install and verification commands); creates or updates the **draft**
   GitHub Release with all assets and checks they are attached.
4. **docs** — publishes the documentation version `X.Y`; when the tag is the highest release, the
   alias `stable` and the site root move to it.
5. **finalize** — publishes the draft release; it is marked latest only when the tag is the highest
   release.

A failed run is re-run as it is. The state of a release is its GitHub Release: as long as it is a
draft (or missing), the workflow may run again; delivered images already published from the
tagged commit are kept, the chart and the assets are replaced, the draft is updated. Once
published, `release-verify` rejects the tag.

The tested commit is the tagged commit: the e2e suite does not run again on the tag.

## Trusted release managers

`trusted_release_managers.yml` maps the email of a release manager to their ASCII-armored public
OpenPGP key:

```yaml
owner@example.com: |-
  -----BEGIN PGP PUBLIC KEY BLOCK-----
  ...
  -----END PGP PUBLIC KEY BLOCK-----
```

Keys are added or removed by pull request; the version on `main` is authoritative. Without keys
every release is rejected ("no trusted release signers configured"). SSH and X.509 tag signatures
are not accepted.

## Hotfix

Fixes land on `main` first. When `main` cannot be released, the fix is shipped from a branch of the
released line:

```console
# fix merged into main as <sha>
git push origin v0.Y.Z^{commit}:refs/heads/release-0.Y        # once per line, on the release commit
git switch -c fix/<name> origin/release-0.Y
git cherry-pick -x <sha>
# pull request fix/<name> -> release-0.Y, CI result passes, merge
git switch release-0.Y && git pull
make release-tag                                             # proposes v0.Y.(Z+1)
git push origin v0.Y.(Z+1)
```

The release publishes `v0.Y.(Z+1)` and the documentation version `0.Y`; `stable` moves only when it
is the highest release. A release never changes the `latest` channel.

## The latest channel

Every push to `main` that passes CI publishes the images `:latest`, the chart `0.0.0-latest`, the
documentation version `latest` and the kubectl plugin as a workflow artifact. Until the first
release the documentation root points to `latest`.
