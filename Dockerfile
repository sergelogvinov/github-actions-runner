#
FROM golang:1.14 AS immortal

WORKDIR /go/src/github.com/immortal/immortal
RUN git clone --single-branch --branch 0.24.3 --depth 1 https://github.com/immortal/immortal.git .
RUN make build-linux

#
FROM alpine:3.13 AS docker-host

RUN apk --update add docker device-mapper && \
    mkdir /root/.docker && \
    ln -s /etc/docker-tlscerts/ca.crt   /root/.docker/ca.pem    && \
    ln -s /etc/docker-tlscerts/tls.crt  /root/.docker/cert.pem  && \
    ln -s /etc/docker-tlscerts/tls.key  /root/.docker/key.pem

ENV DOCKER_HOST=tcp://127.0.0.1:2376

VOLUME ["/var/lib/docker"]
ENTRYPOINT ["/usr/bin/dockerd","-H","tcp://0.0.0.0:2376"]

#
FROM debian:buster AS github-actions-runner

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

RUN wget https://github.com/aquasecurity/trivy/releases/download/v0.18.2/trivy_0.18.2_Linux-64bit.deb \
        -O /tmp/trivy_0.18.1_Linux-64bit.deb  && \
    echo "9202d851deb56af8f61e6aa348c33f92  /tmp/trivy_0.18.1_Linux-64bit.deb" | md5sum -c - && \
    dpkg -i /tmp/trivy_0.18.1_Linux-64bit.deb && rm -f /tmp/trivy_0.18.1_Linux-64bit.deb

RUN wget https://dl.k8s.io/v1.21.1/kubernetes-client-linux-amd64.tar.gz -O /tmp/kubernetes-client-linux-amd64.tar.gz && \
    echo "6f642508984bd7dea0a6447663f0788a  /tmp/kubernetes-client-linux-amd64.tar.gz" | md5sum -c - && \
    cd /tmp && tar -xzf /tmp/kubernetes-client-linux-amd64.tar.gz && mv kubernetes/client/bin/kubectl /usr/bin/kubectl && \
    wget https://get.helm.sh/helm-v3.5.4-linux-amd64.tar.gz -O /tmp/helm.tar.gz && \
    echo "84485d3be5b14fa1caa5e36c551aef33  /tmp/helm.tar.gz" | md5sum -c - && \
    cd /tmp && tar -xzf /tmp/helm.tar.gz && mv linux-amd64/helm /usr/bin/helm && rm -rf /tmp/*

USER github
WORKDIR /app

ENV GITHUB_VERSION=2.278.0
RUN wget https://github.com/actions/runner/releases/download/v${GITHUB_VERSION}/actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz \
        -O actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz && \
    tar xzf ./actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz && \
    rm -f actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz

USER root
RUN /app/bin/installdependencies.sh
USER github

ENV RUNNER_WORK_FOLDER=/home/github/builds

COPY entrypoint.sh /entrypoint.sh
COPY ansible.cfg /etc/ansible/ansible.cfg
COPY --from=immortal /go/src/github.com/immortal/immortal/build/amd64/ /usr/sbin/

ENTRYPOINT [ "/entrypoint.sh" ]
