#
FROM golang:1.14-buster AS immortal

WORKDIR /go/src/github.com/immortal/immortal
RUN git clone --single-branch --branch 0.24.3 --depth 1 https://github.com/immortal/immortal.git .
RUN make build-linux

#
FROM alpine:3.16 AS docker-host
LABEL org.opencontainers.image.source https://github.com/sergelogvinov/github-actions-runner

RUN apk --update add docker device-mapper && \
    mkdir /root/.docker && \
    ln -s /etc/docker-tlscerts/ca.crt   /root/.docker/ca.pem    && \
    ln -s /etc/docker-tlscerts/tls.crt  /root/.docker/cert.pem  && \
    ln -s /etc/docker-tlscerts/tls.key  /root/.docker/key.pem

ENV DOCKER_HOST=tcp://127.0.0.1:2376

VOLUME ["/var/lib/docker"]
ENTRYPOINT ["/usr/bin/dockerd","-H","tcp://0.0.0.0:2376"]

#
FROM debian:bullseye-slim AS containerd-host
LABEL org.opencontainers.image.source https://github.com/sergelogvinov/github-actions-runner

RUN apt-get update && apt-get install -y containerd iptables curl && \
    apt-get autoremove -y && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG BUILDKIT_VERSION=0.10.3
RUN fname="buildkit-v${BUILDKIT_VERSION}.${TARGETOS:-linux}-${TARGETARCH:-amd64}.tar.gz" && \
    curl -o "${fname}" -fSL "https://github.com/moby/buildkit/releases/download/v${BUILDKIT_VERSION}/${fname}" && \
    echo "fbc9c433cf77c5c00db6f797155edc60b44463524ae59a4961699dca15bcee00  ${fname}" | sha256sum -c && \
    tar xzf "${fname}" -C /usr && \
    rm -f "${fname}" /usr/bin/buildkit-qemu-* /usr/bin/buildkit-runc

ARG CNI_PLUGINS_VERSION=1.1.1
RUN fname="cni-plugins-${TARGETOS:-linux}-${TARGETARCH:-amd64}-v${CNI_PLUGINS_VERSION}.tgz" && \
  curl -o "${fname}" -fSL "https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/${fname}" && \
  echo "b275772da4026d2161bf8a8b41ed4786754c8a93ebfb6564006d5da7f23831e5  ${fname}" | sha256sum -c && \
  mkdir -p /opt/cni/bin && tar xzf "${fname}" -C /opt/cni/bin && \
  rm -f "${fname}"

RUN curl -o /tmp/nerdctl.tar.gz -fSL https://github.com/containerd/nerdctl/releases/download/v0.21.0/nerdctl-0.21.0-linux-amd64.tar.gz && \
    echo "686aee1161d9bf4865f391aaa4957d416df13f00493d67797e1ee8aad68cd057 /tmp/nerdctl.tar.gz" | sha256sum -c - && \
    cd /tmp && tar -xzf /tmp/nerdctl.tar.gz && mv nerdctl /usr/bin/nerdctl && rm -rf /tmp/*

COPY --from=immortal /go/src/github.com/immortal/immortal/build/amd64/ /usr/sbin/
COPY etc/immortal /etc/immortal

ENV IMMORTAL_EXIT=1

VOLUME ["/var/lib"]
ENTRYPOINT ["/usr/sbin/immortaldir","/etc/immortal"]

#
FROM debian:buster AS github-actions-runner
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

ENV REVIEWDOG_VERSION=0.13.1
RUN apt-get update && apt-get install -y docker.io && \
    wget https://github.com/reviewdog/reviewdog/releases/download/v${REVIEWDOG_VERSION}/reviewdog_${REVIEWDOG_VERSION}_Linux_x86_64.tar.gz \
        -O /tmp/reviewdog.tar.gz  && \
    echo "08a5a323939101195af1d420ab6be3a50ec12f58e3419e3fcd07b6871f0b9a7e  /tmp/reviewdog.tar.gz" | shasum -a 256 -c && \
    cd /tmp && tar --no-same-owner -xzf /tmp/reviewdog.tar.gz && \
    mv /tmp/reviewdog /usr/bin/reviewdog && \
    rm -rf /tmp/*

COPY --from=aquasec/trivy:0.29.2 /usr/local/bin/trivy /usr/local/bin/trivy

RUN wget https://dl.k8s.io/v1.23.3/kubernetes-client-linux-amd64.tar.gz -O /tmp/kubernetes-client-linux-amd64.tar.gz && \
    echo "7ee6292a77d7042ed3589f998231985e82abd90143496a65e29b8141dd39dced5f9cd87a7eeba1efa4dbf61e5ddec9e7929c14b7afcdf01d83af322ddf839efb  /tmp/kubernetes-client-linux-amd64.tar.gz" | shasum -a 512 -c && \
    cd /tmp && tar -xzf /tmp/kubernetes-client-linux-amd64.tar.gz && mv kubernetes/client/bin/kubectl /usr/bin/kubectl && \
    wget https://get.helm.sh/helm-v3.7.2-linux-amd64.tar.gz -O /tmp/helm.tar.gz && \
    echo "f439e0be3fa6dd1863883d9c390ae232  /tmp/helm.tar.gz" | md5sum -c - && \
    cd /tmp && tar -xzf /tmp/helm.tar.gz && mv linux-amd64/helm /usr/bin/helm && rm -rf /tmp/*

USER github
WORKDIR /app

ENV GITHUB_VERSION=2.294.0
RUN wget https://github.com/actions/runner/releases/download/v${GITHUB_VERSION}/actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz \
        -O actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz && \
    echo "a19a09f4eda5716e5d48ba86b6b78fc014880c5619b9dba4a059eaf65e131780  actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz" | shasum -a 256 -c && \
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
