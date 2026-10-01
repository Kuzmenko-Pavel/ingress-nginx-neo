#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Lint the controller Lua code with luacheck (.luacheckrc) and lj-releng.
# Runs inside the e2e-test-runner image (see `make code-lint`).

set -euo pipefail

luacheck --codes -q rootfs/etc/nginx/lua/
# ngx_conf_init*.lua of init_by_lua_file define the globals of .luacheckrc on
# purpose; lj-releng has no list of allowed globals, luacheck checks them.
find rootfs/etc/nginx/lua/ -name '*.lua' -not -path '*/test/*' \
  -not -name ngx_conf_init.lua -not -name ngx_conf_init_stream.lua \
  -exec lj-releng -L -s {} +
