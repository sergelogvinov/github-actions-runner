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

FROM debian:11-slim AS github-actions-runner
LABEL org.opencontainers.image.source https://github.com/sergelogvinov/github-actions-runner

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y && apt-get dist-upgrade -y && \
    apt-get install -y --no-install-recommends software-properties-common procps vim-tiny \
        curl wget make zip rsync \
        ansible ansible-lint yamllint jq && \
    apt-get install -y python3-boto python3-jmespath && \
    ln -s /usr/bin/python3 /usr/bin/python

RUN adduser --disabled-password --home /home/github --uid 1000 --gecos "GitHubAgent" github && \
    install -m 0775 -o github -g github -d /app && \
    install -m 0775 -o github -g github -d /home/github/.ansible -d /home/github/builds

ENV REVIEWDOG_VERSION=0.14.1
RUN apt-get update && apt-get install -y docker.io && \
    wget https://github.com/reviewdog/reviewdog/releases/download/v${REVIEWDOG_VERSION}/reviewdog_${REVIEWDOG_VERSION}_Linux_x86_64.tar.gz \
        -O /tmp/reviewdog.tar.gz  && \
    echo "bf0ada422e13a94aafb26bcd8ade3ae6d98e6a3db4a9c1cb17686ee64e021314  /tmp/reviewdog.tar.gz" | shasum -a 256 -c && \
    cd /tmp && tar --no-same-owner -xzf /tmp/reviewdog.tar.gz && \
    mv /tmp/reviewdog /usr/bin/reviewdog && \
    rm -rf /tmp/*

COPY --from=docker:20.10-cli /usr/libexec/docker/cli-plugins/docker-compose /usr/libexec/docker/cli-plugins/docker-compose
COPY --from=docker/buildx-bin:0.10.4 /buildx /usr/libexec/docker/cli-plugins/docker-buildx
COPY --from=aquasec/trivy:0.38.3 /usr/local/bin/trivy /usr/local/bin/trivy

ARG HELM_VERSION=3.11.0 NERDCTL_VERSION=1.2.0
RUN wget https://dl.k8s.io/v1.23.3/kubernetes-client-linux-amd64.tar.gz -O /tmp/kubernetes-client-linux-amd64.tar.gz && \
    cd /tmp && tar -xzf /tmp/kubernetes-client-linux-amd64.tar.gz && mv kubernetes/client/bin/kubectl /usr/bin/kubectl && \
    wget https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz -O /tmp/helm.tar.gz && \
    echo "6c3440d829a56071a4386dd3ce6254eab113bc9b1fe924a6ee99f7ff869b9e0b /tmp/helm.tar.gz" | sha256sum -c - && \
    cd /tmp && tar -xzf /tmp/helm.tar.gz && mv linux-amd64/helm /usr/bin/helm && rm -rf /tmp/* && \
    wget https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-amd64.tar.gz -O /tmp/nerdctl.tar.gz && \
    echo "9d6f3427a1c0af0c38a0a707751b424d04cca13b82c62ad03ec3f4799c2de48c /tmp/nerdctl.tar.gz" | sha256sum -c - && \
    cd /tmp && tar -xzf /tmp/nerdctl.tar.gz && mv nerdctl /usr/bin/nerdctl && rm -rf /tmp/* && \
    wget https://github.com/mozilla/sops/releases/download/v3.7.3/sops-v3.7.3.linux -O /tmp/sops && \
    echo "913515e57d0112840540dc3c56370ff9 /tmp/sops" | md5sum -c - && \
    install -o root -g root /tmp/sops /usr/bin/sops && rm -rf /tmp/*

# helm hooks error log https://github.com/helm/helm/pull/11228
COPY --from=helm --chown=root:root /go/src/bin/helm /usr/bin/helm

COPY --from=amazon/aws-cli:2.9.18 /usr/local/aws-cli /usr/local/aws-cli
RUN ln -s /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws

ENV HELM_DATA_HOME=/usr/local/share/helm
RUN helm plugin install https://github.com/jkroepke/helm-secrets --version v3.15.0 && \
    helm repo add bitnami  https://charts.bitnami.com/bitnami && \
    helm repo add sinextra https://helm-charts.sinextra.dev && \
    helm repo update

USER github
WORKDIR /app

ENV GITHUB_VERSION=2.303.0
RUN wget https://github.com/actions/runner/releases/download/v${GITHUB_VERSION}/actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz \
        -O actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz && \
    echo "e4a9fb7269c1a156eb5d5369232d0cd62e06bec2fd2b321600e85ac914a9cc73  actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz" | shasum -a 256 -c && \
    tar xzf ./actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz && \
    rm -f actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz

USER root
RUN /app/bin/installdependencies.sh
USER github

ENV RUNNER_WORK_FOLDER=/home/github/builds

COPY entrypoint.sh /entrypoint.sh
COPY etc/ansible.cfg /etc/ansible/ansible.cfg
COPY --from=immortal /go/src/github.com/immortal/immortal/build/amd64/ /usr/sbin/

ENTRYPOINT [ "/entrypoint.sh" ]
