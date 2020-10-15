# github-actions-runner

Self-hosted runner fot github actions

Example to use .github/workflows/pr.yaml

__runs-on__ set to __self-hosted__

```
jobs:
  build-image:
    runs-on: self-hosted
    steps:
      - name: Build
        run: make build
```

## Get help

```
make help
```

## Build and push

```
make build
make push
```


## Run runner localy

```
make build

export RUNNER_REPOSITORY_URL=https://github.com/sergelogvinov/github-actions-runner
export RUNNER_TOKEN=_TIKEN_
export DOCKER_HOST=tcp://host:port
make run
```

## Run runner on k8s

```
cat <<EOF > .helm/build-machine/values-dev.yaml

replicaCount: 2

docker:
  enabled: true

registry:
  enabled: true
EOF

cat <<EOF > .helm/github-actions/values-dev.yaml

replicaCount: 2
envs:
  DOCKER_BUILDKIT: "1"
  DOCKER_HOST: tcp://build-machine:2376
  RUNNER_REPOSITORY_URL: https://github.com/sergelogvinov/github-actions-runner
  RUNNER_TOKEN: _TOKEN_
EOF

make deploy

kubectl get pods -owide

build-machine-0                    2/2     Running   0          1h     10.37.0.1    node-1    <none>           <none>
build-machine-1                    2/2     Running   0          1h     10.42.0.1    node-2    <none>           <none>
github-actions-0                   1/1     Running   0          1h     10.37.0.3    node-1    <none>           <none>
github-actions-1                   1/1     Running   0          1h     10.42.0.3    node-2    <none>           <none>
```

Gighub-actions worker receive tasks from server.
Worker runs commands on docker host.
Docker host has docker-registry on localhost.
You can use __--cache-from__ to receive build cache from local registry.

![Build-machine](docs/build–machine.svg)
