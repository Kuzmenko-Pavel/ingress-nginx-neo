# Copyright 2018 The Kubernetes Authors. All rights reserved.
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

ARG BASE_IMAGE
ARG GOLANG_VERSION
ARG ETCD_IMAGE

FROM golang:${GOLANG_VERSION}-alpine3.23 AS go
FROM ${ETCD_IMAGE} AS etcd

FROM ${BASE_IMAGE}

ARG TARGETARCH
ARG GINKGO_VERSION
ARG HELM_VERSION
ARG K8S_RELEASE
ARG KUBECTL_SHA256_amd64
ARG KUBECTL_SHA256_arm64
ARG KUBE_APISERVER_SHA256_amd64
ARG KUBE_APISERVER_SHA256_arm64
ARG RESTY_CLI_VERSION
ARG RESTY_CLI_SHA
ARG LUAROCKS_VERSION
ARG LUAROCKS_SHA
ARG BUSTED_VERSION
ARG LUACHECK_VERSION
ARG LJ_RELENG_COMMIT
ARG LJ_RELENG_SHA

RUN set -eux; \
	if [ -e /etc/nsswitch.conf ]; then \
		grep '^hosts: files dns' /etc/nsswitch.conf; \
	else \
		echo 'hosts: files dns' > /etc/nsswitch.conf; \
	fi

COPY --from=go   /usr/local/go /usr/local/go
ENV GOPATH=/go
ENV PATH=$GOPATH/bin:/usr/local/go/bin:$PATH
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

# etcd and kube-apiserver back the envtest-based unit tests.
COPY --from=etcd /usr/local/bin/etcd /usr/local/bin/etcd

RUN apk update && apk upgrade && apk add --no-cache \
  bash \
  ca-certificates \
  wget \
  make \
  gcc \
  git \
  musl-dev \
  perl \
  unzip \
  openssl \
  tzdata \
  libc6-compat \
  sqlite-dev

RUN go install github.com/onsi/ginkgo/v2/ginkgo@${GINKGO_VERSION} \
  && go install helm.sh/helm/v4/cmd/helm@${HELM_VERSION} \
  && mv /go/bin/helm /usr/local/bin/helm \
  && rm -rf /root/.cache /go/pkg

RUN wget -qO /tmp/resty_cli.tgz \
  https://github.com/openresty/resty-cli/archive/v${RESTY_CLI_VERSION}.tar.gz \
  && echo "${RESTY_CLI_SHA} */tmp/resty_cli.tgz" | sha256sum -c - \
  && tar -C /tmp -xzf /tmp/resty_cli.tgz \
  && mv /tmp/resty-cli-${RESTY_CLI_VERSION}/bin/* /usr/local/bin/ \
  && resty -V \
  && rm -rf /tmp/*

RUN wget -qO /tmp/luarocks.tgz \
  https://github.com/luarocks/luarocks/archive/${LUAROCKS_VERSION}.tar.gz \
  && echo "${LUAROCKS_SHA} */tmp/luarocks.tgz" | sha256sum -c - \
  && tar -C /tmp -xzf /tmp/luarocks.tgz \
  && cd /tmp/luarocks* \
  && ./configure \
  && make install \
  && rm -rf /tmp/*

RUN luarocks install busted ${BUSTED_VERSION} \
  && luarocks install luacheck ${LUACHECK_VERSION}

RUN wget -qO /usr/local/bin/lj-releng \
  https://raw.githubusercontent.com/openresty/openresty-devel-utils/${LJ_RELENG_COMMIT}/lj-releng \
  && echo "${LJ_RELENG_SHA} */usr/local/bin/lj-releng" | sha256sum -c - \
  && chmod +x /usr/local/bin/lj-releng

RUN for bin in kubectl kube-apiserver; do \
    var="$(echo "${bin}" | tr 'a-z-' 'A-Z_')_SHA256_${TARGETARCH}"; \
    eval "sha=\${${var}}"; \
    wget -qO /usr/local/bin/${bin} https://dl.k8s.io/release/${K8S_RELEASE}/bin/linux/${TARGETARCH}/${bin} \
    && echo "${sha} */usr/local/bin/${bin}" | sha256sum -c - \
    && chmod +x /usr/local/bin/${bin} || exit 1; \
  done

LABEL org.opencontainers.image.source=https://github.com/Kuzmenko-Pavel/ingress-nginx-neo
LABEL org.opencontainers.image.description="ingress-nginx-neo e2e and Lua test runner"
LABEL org.opencontainers.image.licenses=Apache-2.0

WORKDIR $GOPATH
