#

THIS_FILE:=$(lastword $(MAKEFILE_LIST))
BUILD_VCS_BRANCH?=$(shell git branch 2>/dev/null | sed -n '/^\*/s/^\* //p' | sed 's/\//-/g' | sed 's/^(HEAD detached at \(.*\))$$/\1/g')
BUILD_VCS_NUMBER?=$(shell git rev-parse --short=7 HEAD)
CODE_TAG?=$(shell git describe --exact-match --tags 2>/dev/null || git branch 2>/dev/null | sed -n '/^\*/s/^\* //p' | sed 's/\//-/g' | sed 's/^(HEAD detached at \(.*\))$$/\1-$(BUILD_VCS_NUMBER)/g')

REGISTRY?=docker.pkg.github.com/sergelogvinov/github-actions-runner
RUNNER_REPOSITORY_URL?=https://github.com/sergelogvinov/github-actions-runner
RUNNER_TOKEN?=
DOCKER_HOST?=
HELM_PARAMS?=

#

help:
	@awk 'BEGIN {FS = ":.*?## "} /^[0-9a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)


build: ## Build project
	docker build $(BUILDARG) --rm -t local/github-actions-runner:$(CODE_TAG) \
		-f Dockerfile --target=github-actions-runner .
	docker build $(BUILDARG) --rm -t local/docker:$(CODE_TAG) \
		-f Dockerfile --target=docker-host .
	docker build $(BUILDARG) --rm -t local/containerd:$(CODE_TAG) \
		-f Dockerfile --target=containerd-host .


run: ## Run locally
	docker rm -f github-actions-runner 2>/dev/null ||:
	docker run --rm -ti --name github-actions-runner -h local \
		-e RUNNER_REPOSITORY_URL=$(RUNNER_REPOSITORY_URL) \
		-e RUNNER_TOKEN=$(RUNNER_TOKEN) \
		-e DOCKER_HOST=$(DOCKER_HOST) \
		local/github-actions-runner:$(CODE_TAG)


push: ## Push image to registry
	docker tag local/github-actions-runner:$(CODE_TAG) $(REGISTRY)/github-actions-runner:$(CODE_TAG)
	docker push $(REGISTRY)/github-actions-runner:$(CODE_TAG)

	docker tag local/docker:$(CODE_TAG) $(REGISTRY)/docker:$(CODE_TAG)
	docker push $(REGISTRY)/docker:$(CODE_TAG)

	docker tag local/containerd:$(CODE_TAG) $(REGISTRY)/containerd:$(CODE_TAG)
	docker push $(REGISTRY)/containerd:$(CODE_TAG)


deploy: ## Deploy to k8s
	touch .helm/build-machine/values-dev.yaml
	helm upgrade -i $(HELM_PARAMS) -f .helm/build-machine/values-dev.yaml \
		--history-max 3 \
		--set docker.image.tag=$(CODE_TAG) \
		build-machine .helm/build-machine/

	touch .helm/github-actions/values-dev.yaml
	helm upgrade -i $(HELM_PARAMS) -f .helm/github-actions/values-dev.yaml \
		--history-max 3 \
		--reuse-values \
		--set image.tag=$(CODE_TAG) \
		github-actions .helm/github-actions/


github-auth: ## Create k8s docker registry secret
	kubectl create secret docker-registry github-registry --docker-server=docker.pkg.github.com \
		--docker-username=$(GITHUB_ACTOR) --docker-password=$(GITHUB_TOKEN)
