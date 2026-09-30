#!/bin/bash

# Copyright 2026 The Kubernetes Authors.
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
# limitations under the License.

# Prints the NGINX base image reference used by the controller, chroot and test images.
#
# images/nginx/TAG is the single source of truth for the base image version: the image
# built from images/nginx is published as <repository>:<TAG>, and every consumer derives
# its reference from the same file. Published tags are never overwritten, so any change
# under images/nginx/rootfs requires a TAG bump.
#
# NGINX_BASE_REPOSITORY overrides the repository (e.g. a private mirror or an arm64 build).

set -o errexit
set -o nounset
set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "${NGINX_BASE_REPOSITORY:-ghcr.io/kuzmenko-pavel/ingress-nginx/nginx}:$(cat "${DIR}/../images/nginx/TAG")"
