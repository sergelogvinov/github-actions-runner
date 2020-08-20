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

export RUNNER_REPOSITORY_URL==https://github.com/$user/$project
export RUNNER_TOKEN=_TIKEN_
export DOCKER_HOST=tcp://host:port
make run
```
