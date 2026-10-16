#!/bin/bash

# Copyright 2018 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and

# Go unit tests. Runs inside the e2e-test-runner image (see `make test-unit`):
# some tests need a writable /etc/ingress-controller and the envtest binaries
# (etcd, kube-apiserver) in /usr/local/bin. Writes JUnit and coverage of every
# Go module to TEST_REPORTS.

set -o errexit
set -o nounset
set -o pipefail

mkdir -p /tmp/nginx "${TEST_REPORTS:?}"
reports="$(cd "${TEST_REPORTS}" && pwd)"

# gotestsum of tools/go.mod, built for the container platform.
go -C tools build -o /tmp/gotestsum gotest.tools/gotestsum

# go_test <name> <packages...>: JUnit in unit-<name>.xml, coverage in
# coverage-<name>.out. TEST_ARGS holds extra arguments of go test.
go_test() {
  local name="$1"
  shift
  # TEST_ARGS is unquoted on purpose: it holds several arguments.
  /tmp/gotestsum --format pkgname --junitfile "${reports}/unit-${name}.xml" -- \
    -covermode=atomic -coverprofile="${reports}/coverage-${name}.out" ${TEST_ARGS:-} "$@"
  echo "coverage of ${name}: $(go tool cover -func="${reports}/coverage-${name}.out" | awk 'END { print $NF }')" \
    "(${TEST_REPORTS}/coverage-${name}.out)"
}

go_test go $(go list ./... | grep -vE '/test/e2e|/images/|/docs/examples')

for module in images/kube-webhook-certgen/rootfs images/custom-error-pages/rootfs images/fastcgi-helloserver/rootfs; do
  name="$(basename "$(dirname "${module}")")"
  (cd "${module}" && go_test "go-${name}" ./...)
done

test/channel_test.sh
tools/release/changelog_test.sh
tools/release/verify-tag_test.sh
