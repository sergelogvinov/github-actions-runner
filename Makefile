#

THIS_FILE:=$(lastword $(MAKEFILE_LIST))
BUILD_VCS_BRANCH?=$(shell git branch 2>/dev/null | sed -n '/^\*/s/^\* //p' | sed 's/\//-/g' | sed 's/^(HEAD detached at \(.*\))$$/\1/g')
BUILD_VCS_NUMBER?=$(shell git rev-parse --short=7 HEAD)
CODE_TAG?=$(shell git describe --exact-match --tags 2>/dev/null || git branch 2>/dev/null | sed -n '/^\*/s/^\* //p' | sed 's/\//-/g' | sed 's/^(HEAD detached at \(.*\))$$/\1-$(BUILD_VCS_NUMBER)/g')

REGISTRY?=docker.pkg.github.com/sergelogvinov/github-actions-runner
RUNNER_REPOSITORY_URL?=https://github.com/sergelogvinov/github-actions-runner
RUNNER_TOKEN?=

#

help:
	@awk 'BEGIN {FS = ":.*?## "} /^[0-9a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)


build: ## Build project
	docker build $(BUILDARG) --rm -t local/github-actions-runner:$(CODE_TAG) -f Dockerfile .


run: ## Run locally
	docker rm -f github-actions-runner 2>/dev/null ||:
	docker run --rm -ti --name github-actions-runner -h local \
		-e RUNNER_REPOSITORY_URL=$(RUNNER_REPOSITORY_URL) \
		-e RUNNER_TOKEN=$(RUNNER_TOKEN) \
		local/github-actions-runner:$(CODE_TAG)


push:
	docker tag local/github-actions-runner:$(CODE_TAG) $(REGISTRY)/github-actions-runner:$(CODE_TAG)
	docker push $(REGISTRY)/github-actions-runner:$(CODE_TAG)

