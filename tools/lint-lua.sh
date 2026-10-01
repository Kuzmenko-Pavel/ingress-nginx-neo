#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Lint the controller Lua code with luacheck (.luacheckrc) and lj-releng.
# Runs inside the e2e-test-runner image (see `make code-lint`).

set -euo pipefail

luacheck --codes -q rootfs/etc/nginx/lua/
find rootfs/etc/nginx/lua/ -name '*.lua' -not -path '*/test/*' -exec lj-releng -L -s {} +
