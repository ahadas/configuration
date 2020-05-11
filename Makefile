SHELL=/usr/bin/env bash -o pipefail

VERSION := $(strip $(shell [ -d .git ] && git describe --always --tags --dirty))
BUILD_DATE := $(shell date -u +"%Y-%m-%d")
BUILD_TIMESTAMP := $(shell date -u +"%Y-%m-%dT%H:%M:%S%Z")
VCS_BRANCH := $(strip $(shell git rev-parse --abbrev-ref HEAD))
VCS_REF := $(strip $(shell [ -d .git ] && git rev-parse --short HEAD))
DOCKER_REPO ?= quay.io/observatorium/observatorium-operator
CACHE_DIR="_cache"
FULL_OPERATOR_IMAGE="abc"
REGISTRY_NAMESPACE ?= "observatorium"
TOOLS_DIR="$(CACHE_DIR)/tools"
OPERATOR_SDK_VERSION="v0.17.0"
OPERATOR_SDK_PLATFORM ?= "x86_64-linux-gnu"
OPERATOR_SDK_BIN="operator-sdk-$(OPERATOR_SDK_VERSION)-$(OPERATOR_SDK_PLATFORM)"
OPERATOR_SDK="$(TOOLS_DIR)/$(OPERATOR_SDK_BIN)"

BIN_DIR ?= $(shell pwd)/tmp/bin

CONTROLLER_GEN ?= $(BIN_DIR)/controller-gen

vendor: go.mod go.sum
	go mod tidy
	go mod vendor

# Generate manifests e.g. CRD, RBAC etc.
manifests: $(CONTROLLER_GEN)
	$(CONTROLLER_GEN) crd paths="./..." output:crd:artifacts:config=deploy/crds

# Run go fmt against code
fmt:
	go fmt ./...

# Run go vet against code
vet:
	go vet ./...

# Generate code
generate: $(CONTROLLER_GEN)
	$(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths="./..."

# Build the docker image
container-build:
	docker build --build-arg BUILD_DATE="$(BUILD_TIMESTAMP)" \
		--build-arg VERSION="$(VERSION)" \
		--build-arg VCS_REF="$(VCS_REF)" \
		--build-arg VCS_BRANCH="$(VCS_BRANCH)" \
		--build-arg DOCKERFILE_PATH="/Dockerfile" \
		-t $(DOCKER_REPO):$(VCS_BRANCH)-$(BUILD_DATE)-$(VERSION) .

# Push the image
container-push: container-build
	docker tag $(DOCKER_REPO):$(VCS_BRANCH)-$(BUILD_DATE)-$(VERSION) $(DOCKER_REPO):latest
	docker push $(DOCKER_REPO):$(VCS_BRANCH)-$(BUILD_DATE)-$(VERSION)
	docker push $(DOCKER_REPO):latest

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

$(CONTROLLER_GEN): vendor $(BIN_DIR)
	go build -mod=vendor -o $@ sigs.k8s.io/controller-tools/cmd/controller-gen

operator-sdk:
	@if [ ! -x "$(OPERATOR_SDK)" ]; then\
		echo "Downloading operator-sdk $(OPERATOR_SDK_VERSION)";\
		mkdir -p $(TOOLS_DIR);\
		curl -JL https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/$(OPERATOR_SDK_BIN) -o $(OPERATOR_SDK);\
		chmod +x $(OPERATOR_SDK);\
	else\
		echo "Using operator-sdk cached at $(OPERATOR_SDK)";\
	fi

generate-csv: operator-sdk dist-csv-generator
	@if [ -z "$(REGISTRY_NAMESPACE)" ]; then\
		echo "REGISTRY_NAMESPACE env-var must be set to your $(IMAGE_REGISTRY) namespace";\
		exit 1;\
	fi
	OPERATOR_SDK=$(OPERATOR_SDK) FULL_OPERATOR_IMAGE=$(FULL_OPERATOR_IMAGE) hack/csv-generate.sh

dist-csv-generator:
	@if [ ! -x build/_output/bin/csv-generator ]; then\
		echo "Building csv-generator tool";\
		mkdir -p build/_output/bin;\
		go build -i -ldflags="-s -w" -mod=vendor -o build/_output/bin/csv-generator ./tools/csv-generator;\
	else \
		echo "Using pre-built csv-generator tool";\
	fi

