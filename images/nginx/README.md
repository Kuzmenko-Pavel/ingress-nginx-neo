# NGINX base image

`ghcr.io/kuzmenko-pavel/ingress-nginx-neo/nginx` is the base of the controller images and of the
`e2e-test-runner` and `e2e-test-echo` test images. It is built from `rootfs/`:

- `rootfs/Dockerfile` — Alpine build stage and runtime stage;
- `rootfs/build.sh` — downloads, patches and compiles NGINX, its modules, LuaJIT and the Lua
  libraries; every component version is an `export *_VERSION=` line at the top of the script;
- `rootfs/patches/` — patches applied to the NGINX sources, in file name order.

## Contents

- NGINX 1.27.1 (see `NGINX_VERSION` in `rootfs/build.sh`) with the patches of `rootfs/patches/`, built with
  `--with-http_v2_module`, `--with-http_v3_module`, `--with-stream` and the SSL, realip, sub,
  gzip_static, gunzip, secure_link, auth_request and stub_status modules.
- Static modules: ngx_devel_kit, set-misc, headers-more, lua-nginx, stream-lua-nginx and
  lua-upstream.
- Dynamic modules: http-auth-digest, ModSecurity-nginx (libmodsecurity v3 with the OWASP Core Rule
  Set), geoip2, brotli and njs.
- OpenTelemetry NGINX module (`/etc/nginx/modules/otel_ngx_module.so`) built against opentelemetry-cpp.

## Image tag

The image is content addressed: its tag is `src-<hash>` of every file under `images/nginx/rootfs`
(`tools/content-tag.sh`). Changing any of these files produces a new tag; CI builds and
publishes it for `linux/amd64` and `linux/arm64` on the native runners of each architecture, and the
controller images of the same commit are built `FROM` it. Releases additionally tag it with the
release version. There is no manual version to bump.

```console
make print-NGINX_IMAGE                     # reference used by this tree
make docker-build-deps DEPS=nginx          # pull it, or build it for the host platform
```

## Adding a patch

1. Add `NN_nginx-<nginx version>-<topic>.patch` to `rootfs/patches/`, where `NN` orders it after the
   existing patches. Patches apply with `patch -p1` from the NGINX source root.
2. Start the patch with a plain-text header that says what it changes and why.
3. Build the image locally (`make docker-build-deps DEPS=nginx`) and run the controller e2e suite
   (`make test-e2e`).

## Backporting an NGINX security fix

Security fixes of newer NGINX releases are backported as patches:

1. Find the fixing commit in the [nginx repository](https://github.com/nginx/nginx).
2. Add `NN_nginx-<nginx version>-CVE-YYYY-NNNNN.patch`; its header names the CVE and the upstream
   commit (`Backport of upstream nginx commit <sha> ("<subject>") for CVE-YYYY-NNNNN.`), followed by
   the adapted diff.
3. Ship the patch in a release: the content tag, and with it the controller images, change
   automatically.
