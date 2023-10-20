#
FROM golang:1.19-buster AS immortal

WORKDIR /go/src/github.com/immortal/immortal
RUN git clone --single-branch --branch 0.24.3 --depth 1 https://github.com/immortal/immortal.git .
RUN make build-linux

###

FROM alpine:3.17 AS docker-host
LABEL org.opencontainers.image.source https://github.com/sergelogvinov/github-actions-runner

RUN apk --update add docker device-mapper && \
    mkdir /root/.docker && \
    ln -s /etc/docker-tlscerts/ca.crt   /root/.docker/ca.pem    && \
    ln -s /etc/docker-tlscerts/tls.crt  /root/.docker/cert.pem  && \
    ln -s /etc/docker-tlscerts/tls.key  /root/.docker/key.pem

ENV DOCKER_HOST=tcp://127.0.0.1:2376

VOLUME ["/var/lib/docker"]
ENTRYPOINT ["/usr/bin/dockerd","-H","tcp://0.0.0.0:2376"]

###

FROM golang:1.18-bullseye AS helm

WORKDIR /go/src/
RUN git clone --single-branch --depth 2 --branch hooks-logs https://github.com/sergelogvinov/helm.git .
RUN make

###

FROM debian:bullseye-slim AS containerd-host
LABEL org.opencontainers.image.source https://github.com/sergelogvinov/github-actions-runner

RUN apt-get update && apt-get install -y containerd iptables curl && \
    apt-get autoremove -y && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG BUILDKIT_VERSION=0.10.6
RUN fname="buildkit-v${BUILDKIT_VERSION}.${TARGETOS:-linux}-${TARGETARCH:-amd64}.tar.gz" && \
    curl -o "${fname}" -fSL "https://github.com/moby/buildkit/releases/download/v${BUILDKIT_VERSION}/${fname}" && \
    echo "9a21a41298c4a2a7a2b57cb90d37463d3a9057aedfe97a04b0e4fd6f622549d8  ${fname}" | sha256sum -c && \
    tar xzf "${fname}" -C /usr && \
    rm -f "${fname}" /usr/bin/buildkit-qemu-* /usr/bin/buildkit-runc

ARG CNI_PLUGINS_VERSION=1.1.1
RUN fname="cni-plugins-${TARGETOS:-linux}-${TARGETARCH:-amd64}-v${CNI_PLUGINS_VERSION}.tgz" && \
  curl -o "${fname}" -fSL "https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/${fname}" && \
  echo "b275772da4026d2161bf8a8b41ed4786754c8a93ebfb6564006d5da7f23831e5  ${fname}" | sha256sum -c && \
  mkdir -p /opt/cni/bin && tar xzf "${fname}" -C /opt/cni/bin && \
  rm -f "${fname}"

COPY --from=immortal /go/src/github.com/immortal/immortal/build/amd64/ /usr/sbin/
COPY etc/immortal /etc/immortal

ENV IMMORTAL_EXIT=1

VOLUME ["/var/lib"]
ENTRYPOINT ["/usr/sbin/immortaldir","/etc/immortal"]

###

FROM ghcr.io/sergelogvinov/github-actions-runner:2.310.2-gcp AS github-actions-runner

COPY scripts/ /
COPY etc/ansible.cfg /etc/ansible/ansible.cfg

ENTRYPOINT [ "/entrypoint.sh" ]
