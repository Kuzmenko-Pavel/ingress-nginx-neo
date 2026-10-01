# Copyright 2019 The Kubernetes Authors. All rights reserved.
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

ARG GOLANG_VERSION

FROM golang:${GOLANG_VERSION}-alpine3.23 AS builder

ARG CFSSL_VERSION

# cfssl needs cgo for its sqlite certificate database.
RUN apk add --no-cache gcc musl-dev \
  && CGO_ENABLED=1 go install \
    github.com/cloudflare/cfssl/cmd/cfssl@${CFSSL_VERSION} \
    github.com/cloudflare/cfssl/cmd/cfssljson@${CFSSL_VERSION}

FROM alpine:3.23.3@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659

RUN apk add --no-cache bash sqlite-libs

COPY --from=builder /go/bin/cfssl /go/bin/cfssljson /usr/local/bin/

EXPOSE 8888

CMD ["cfssl"]
