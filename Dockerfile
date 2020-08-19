#
FROM golang:1.14 AS immortal

WORKDIR /go/src/github.com/immortal/immortal
RUN git clone --single-branch --branch 0.24.3 --depth 1 https://github.com/immortal/immortal.git .
RUN make build-linux

#
FROM debian:buster

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common procps vim-tiny \
        curl wget make zip rsync sudo \
        ansible ansible-lint jq && \
    apt-get install -y python3-boto python3-jmespath && \
    ln -s /usr/bin/python3 /usr/bin/python

RUN adduser --disabled-password --home /home/github --uid 1000 --gecos "GithubAgent" github && \
    echo "github ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    usermod -aG sudo github && \
    install -m 0775 -o github -g github -d /app && \
    install -m 0775 -o github -g github -d /home/github/.ansible -d /home/github/builds

ENV REVIEWDOG_VERSION=0.10.2
RUN apt-get update && apt-get install -y docker.io yamllint && \
    wget https://github.com/reviewdog/reviewdog/releases/download/v${REVIEWDOG_VERSION}/reviewdog_${REVIEWDOG_VERSION}_Linux_x86_64.tar.gz \
        -O /tmp/reviewdog.tar.gz && \
    cd /tmp && tar --no-same-owner -xzf /tmp/reviewdog.tar.gz && \
    mv /tmp/reviewdog /usr/bin/reviewdog && \
    rm -rf /tmp/*

RUN wget https://dl.k8s.io/v1.18.8/kubernetes-client-linux-amd64.tar.gz -O /tmp/kubernetes-client-linux-amd64.tar.gz && \
    cd /tmp && tar -xzf /tmp/kubernetes-client-linux-amd64.tar.gz && mv kubernetes/client/bin/kubectl /usr/bin/kubectl && \
    wget https://get.helm.sh/helm-v3.3.0-linux-amd64.tar.gz -O /tmp/helm.tar.gz && \
    cd /tmp && tar -xzf /tmp/helm.tar.gz && mv linux-amd64/helm /usr/bin/helm && rm -rf /tmp/*

USER github
WORKDIR /app

ENV GITHUB_VERSION=2.272.0
RUN curl -L -O https://github.com/actions/runner/releases/download/v${GITHUB_VERSION}/actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz && \
    tar xzf ./actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz && \
    rm actions-runner-linux-x64-${GITHUB_VERSION}.tar.gz && \
    sudo /app/bin/installdependencies.sh

RUN helm repo add stable https://kubernetes-charts.storage.googleapis.com && \
    helm repo add incubator https://kubernetes-charts-incubator.storage.googleapis.com

ENV RUNNER_WORK_FOLDER=/home/github/builds

COPY entrypoint.sh /entrypoint.sh
COPY ansible.cfg /etc/ansible/ansible.cfg
COPY --from=immortal /go/src/github.com/immortal/immortal/build/amd64/ /usr/sbin/

ENTRYPOINT [ "/entrypoint.sh" ]
