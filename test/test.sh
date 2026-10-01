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
# (etcd, kube-apiserver) in /usr/local/bin.

set -o errexit
set -o nounset
set -o pipefail

mkdir -p /tmp/nginx

go test $(go list ./... | grep -vE '/test/e2e|/images/|/docs/examples')

for module in images/kube-webhook-certgen/rootfs images/custom-error-pages/rootfs images/fastcgi-helloserver/rootfs; do
  (cd "${module}" && go test ./...)
done
