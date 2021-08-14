#
FROM golang:1.14-buster AS immortal

WORKDIR /go/src/github.com/immortal/immortal
RUN git clone --single-branch --branch 0.24.3 --depth 1 https://github.com/immortal/immortal.git .
RUN make build-linux

#
FROM alpine:3.14 AS docker-host
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

ARG BUILDKIT_VERSION=0.9.0
RUN fname="buildkit-v${BUILDKIT_VERSION}.${TARGETOS:-linux}-${TARGETARCH:-amd64}.tar.gz" && \
    curl -o "${fname}" -fSL "https://github.com/moby/buildkit/releases/download/v${BUILDKIT_VERSION}/${fname}" && \
    echo "1b307268735c8f8e68b55781a6f4c03af38acc1bc29ba39ebaec6d422bccfb25  buildkit-v0.9.0.linux-amd64.tar.gz" | sha256sum -c && \
    tar xzf "${fname}" -C /usr && \
    rm -f "${fname}" /usr/bin/buildkit-qemu-* /usr/bin/buildkit-runc

ARG CNI_PLUGINS_VERSION=1.0.0
RUN fname="cni-plugins-${TARGETOS:-linux}-${TARGETARCH:-amd64}-v${CNI_PLUGINS_VERSION}.tgz" && \
  curl -o "${fname}" -fSL "https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/${fname}" && \
  echo "5894883eebe3e38f4474810d334b00dc5ec59bd01332d1f92ca4eb142a67d2e8  ${fname}" | sha256sum -c && \
  mkdir -p /opt/cni/bin && tar xzf "${fname}" -C /opt/cni/bin && \
  rm -f "${fname}"

RUN curl -o /tmp/nerdctl.tar.gz -fSL https://github.com/containerd/nerdctl/releases/download/v0.11.0/nerdctl-0.11.0-linux-amd64.tar.gz && \
    echo "8c8a740295267bf50a322820ccf33fc1669337b03a544ae1e75bccb30f7705e1 /tmp/nerdctl.tar.gz" | sha256sum -c - && \
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

ENV REVIEWDOG_VERSION=0.11.0
RUN apt-get update && apt-get install -y docker.io && \
    wget https://github.com/reviewdog/reviewdog/releases/download/v${REVIEWDOG_VERSION}/reviewdog_${REVIEWDOG_VERSION}_Linux_x86_64.tar.gz \
        -O /tmp/reviewdog.tar.gz  && \
    echo "69fb0c04166fd1d311d8f37c45516617  /tmp/reviewdog.tar.gz" | md5sum -c - && \
    cd /tmp && tar --no-same-owner -xzf /tmp/reviewdog.tar.gz && \
    mv /tmp/reviewdog /usr/bin/reviewdog && \
    rm -rf /tmp/*

RUN wget https://github.com/aquasecurity/trivy/releases/download/v0.19.2/trivy_0.19.2_Linux-64bit.deb \
        -O /tmp/trivy_Linux-64bit.deb  && \
    echo "4e8bfe28713e471e4e4078e2cfd933b9  /tmp/trivy_Linux-64bit.deb" | md5sum -c - && \
    dpkg -i /tmp/trivy_Linux-64bit.deb && rm -f /tmp/trivy_Linux-64bit.deb

RUN wget https://dl.k8s.io/v1.22.0/kubernetes-client-linux-amd64.tar.gz -O /tmp/kubernetes-client-linux-amd64.tar.gz && \
    echo "e601ab125bde75fb0ae083c997e333a7  /tmp/kubernetes-client-linux-amd64.tar.gz" | md5sum -c - && \
    cd /tmp && tar -xzf /tmp/kubernetes-client-linux-amd64.tar.gz && mv kubernetes/client/bin/kubectl /usr/bin/kubectl && \
    wget https://get.helm.sh/helm-v3.6.3-linux-amd64.tar.gz -O /tmp/helm.tar.gz && \
    echo "24b16800f8c7f44b5dd128e3355ecf1b  /tmp/helm.tar.gz" | md5sum -c - && \
    cd /tmp && tar -xzf /tmp/helm.tar.gz && mv linux-amd64/helm /usr/bin/helm && rm -rf /tmp/*

USER github
WORKDIR /app

ENV GITHUB_VERSION=2.280.2
RUN wget https://github.com/actions/runner/releases/download/v${GITHUB_VERSION}/actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz \
        -O actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz && \
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
