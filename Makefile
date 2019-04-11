GO_VERSION ?= 1.12.1
GOOS ?= linux
GOARCH ?= amd64
COMPOSE_PROJECT_NAME := ${TAG}-$(shell git rev-parse --abbrev-ref HEAD)
BRANCH := $(shell git rev-parse --abbrev-ref HEAD | sed "s!/!-!g")
ifeq (${BRANCH},master)
TAG    := $(shell git rev-parse --short HEAD)-go${GO_VERSION}
TRACKED_BRANCH := true
LATEST_TAG := latest
else
TAG    := $(shell git rev-parse --short HEAD)-${BRANCH}-go${GO_VERSION}
ifneq (,$(findstring release-,$(BRANCH)))
TRACKED_BRANCH := true
LATEST_TAG := ${BRANCH}-latest
endif
endif
CUSTOMTAG ?=

FILEEXT :=
ifeq (${GOOS},windows)
FILEEXT := .exe
endif

DOCKER_BUILD := docker build \
	--build-arg TAG=${TAG}

.DEFAULT_GOAL := help
.PHONY: help
help:
	@awk 'BEGIN { \
		FS = ":.*##"; \
		printf "\nUsage:\n  make \033[36m<target>\033[0m\n"\
	} \
	/^[a-zA-Z_-]+:.*?##/ { \
		printf "  \033[36m%-17s\033[0m %s\n", $$1, $$2 \
	} \
	/^##@/ { \
		printf "\n\033[1m%s\033[0m\n", substr($$0, 5) \
	} ' $(MAKEFILE_LIST)

##@ Dependencies

.PHONY: build-dev-deps
build-dev-deps: ## Install dependencies for builds
	go get github.com/mattn/goveralls
	go get golang.org/x/tools/cover
	go get github.com/modocache/gover
	curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | bash -s -- -b ${GOPATH}/bin v1.16.0

.PHONY: lint
lint: check-copyrights ## Analyze and find programs in source code
	@echo "Running ${@}"
	@golangci-lint run

.PHONY: check-copyrights
check-copyrights: ## Check source files for copyright headers
	@echo "Running ${@}"
	@go run ./scripts/check-copyright.go

.PHONY: goimports-fix
goimports-fix: ## Applies goimports to every go file (excluding vendored files)
	goimports -w -local storj.io $$(find . -type f -name '*.go' -not -path "*/vendor/*")

.PHONY: goimports-st
goimports-st: ## Applies goimports to every go file in `git status` (ignores untracked files)
	@git status --porcelain -uno|grep .go|grep -v "^D"|sed -E 's,\w+\s+(.+->\s+)?,,g'|xargs -I {} goimports -w -local storj.io {}

.PHONY: proto
proto: ## Rebuild protobuf files
	@echo "Running ${@}"
	go run scripts/protobuf.go install
	go run scripts/protobuf.go generate

##@ Simulator

.PHONY: install-sim
install-sim: ## install storj-sim
	@echo "Running ${@}"
	@go install -race -v storj.io/storj/cmd/storj-sim storj.io/storj/cmd/versioncontrol storj.io/storj/cmd/bootstrap storj.io/storj/cmd/satellite storj.io/storj/cmd/storagenode storj.io/storj/cmd/uplink storj.io/storj/cmd/gateway storj.io/storj/cmd/identity storj.io/storj/cmd/certificates

##@ Test

.PHONY: test
test: ## Run tests on source code (travis)
	go test -race -v -cover -coverprofile=.coverprofile ./...
	@echo done

.PHONY: test-sim
test-sim: ## Test source with storj-sim (travis)
	@echo "Running ${@}"
	@./scripts/test-sim.sh

.PHONY: test-certificate-signing
test-certificate-signing: ## Test certificate signing service and storagenode setup (travis)
	@echo "Running ${@}"
	@./scripts/test-certificate-signing.sh

.PHONY: test-docker
test-docker: ## Run tests in Docker
	docker-compose up -d --remove-orphans test
	docker-compose run test make test

.PHONY: all-in-one
all-in-one: ## Deploy docker images with one storagenode locally
	export VERSION="${TAG}${CUSTOMTAG}" \
	&& $(MAKE) satellite-image storagenode-image gateway-image \
	&& docker-compose up --scale storagenode=1 satellite gateway

.PHONY: test-all-in-one
test-all-in-one: ## Test docker images locally
	export VERSION="${TAG}${CUSTOMTAG}" \
	&& $(MAKE) satellite-image storagenode-image gateway-image \
	&& ./scripts/test-aio.sh

##@ Build

.PHONY: images
images: satellite-image storagenode-image uplink-image gateway-image ## Build gateway, satellite, storagenode, and uplink Docker images
	echo Built version: ${TAG}

.PHONY: gateway-image
gateway-image: gateway_linux_arm gateway_linux_amd64 ## Build gateway Docker image
	${DOCKER_BUILD} --pull=true -t storjlabs/gateway:${TAG}${CUSTOMTAG}-amd64 \
		-f cmd/gateway/Dockerfile .
	${DOCKER_BUILD} --pull=true -t storjlabs/gateway:${TAG}${CUSTOMTAG}-arm32v6 \
		--build-arg=GOARCH=arm --build-arg=DOCKER_ARCH=arm32v6 \
		-f cmd/gateway/Dockerfile .
.PHONY: satellite-image
satellite-image: satellite_linux_arm satellite_linux_amd64 ## Build satellite Docker image
	${DOCKER_BUILD} --pull=true -t storjlabs/satellite:${TAG}${CUSTOMTAG}-amd64 \
		-f cmd/satellite/Dockerfile .
	${DOCKER_BUILD} --pull=true -t storjlabs/satellite:${TAG}${CUSTOMTAG}-arm32v6 \
		--build-arg=GOARCH=arm --build-arg=DOCKER_ARCH=arm32v6 \
		-f cmd/satellite/Dockerfile .
.PHONY: satellite-ui-image
satellite-ui-image: ## Build satellite-ui Docker image
	${DOCKER_BUILD} --pull=true -t storjlabs/satellite-ui:${TAG}${CUSTOMTAG} -f web/satellite/Dockerfile .
.PHONY: storagenode-image
storagenode-image: storagenode_linux_arm storagenode_linux_amd64 ## Build storagenode Docker image
	${DOCKER_BUILD} --pull=true -t storjlabs/storagenode:${TAG}${CUSTOMTAG}-amd64 \
		-f cmd/storagenode/Dockerfile .
	${DOCKER_BUILD} --pull=true -t storjlabs/storagenode:${TAG}${CUSTOMTAG}-arm32v6 \
		--build-arg=GOARCH=arm --build-arg=DOCKER_ARCH=arm32v6 \
		-f cmd/storagenode/Dockerfile .
.PHONY: uplink-image
uplink-image: uplink_linux_arm uplink_linux_amd64 ## Build uplink Docker image
	${DOCKER_BUILD} --pull=true -t storjlabs/uplink:${TAG}${CUSTOMTAG}-amd64 \
		-f cmd/uplink/Dockerfile .
	${DOCKER_BUILD} --pull=true -t storjlabs/uplink:${TAG}${CUSTOMTAG}-arm32v6 \
		--build-arg=GOARCH=arm --build-arg=DOCKER_ARCH=arm32v6 \
		-f cmd/uplink/Dockerfile .

.PHONY: binary
binary: CUSTOMTAG = -${GOOS}-${GOARCH}
binary:
	@if [ -z "${COMPONENT}" ]; then echo "Try one of the following targets instead:" \
		&& for b in binaries ${BINARIES}; do echo "- $$b"; done && exit 1; fi
	mkdir -p release/${TAG}
	rm -f cmd/${COMPONENT}/resource.syso
	if [ "${GOARCH}" = "amd64" ]; then sixtyfour="-64"; fi; \
	[ "${GOARCH}" = "amd64" ] && goversioninfo $$sixtyfour -o cmd/${COMPONENT}/resource.syso \
	-original-name ${COMPONENT}_${GOOS}_${GOARCH}${FILEEXT} \
	-description "${COMPONENT} program for Storj" \
	-product-ver-build 9 -ver-build 9 \
	-product-version "alpha9" \
	resources/versioninfo.json || echo "goversioninfo is not installed, metadata will not be created"
	docker run --rm -i -v "${PWD}":/go/src/storj.io/storj -e GO111MODULE=on \
	-e GOOS=${GOOS} -e GOARCH=${GOARCH} -e GOARM=6 -e CGO_ENABLED=1 \
	-w /go/src/storj.io/storj -e GOPROXY -u $(shell id -u):$(shell id -g) storjlabs/golang:${GO_VERSION} \
	scripts/release.sh build -o release/${TAG}/$(COMPONENT)_${GOOS}_${GOARCH}${FILEEXT} \
	storj.io/storj/cmd/${COMPONENT}
	chmod 755 release/${TAG}/$(COMPONENT)_${GOOS}_${GOARCH}${FILEEXT}
	[ "${FILEEXT}" = ".exe" ] && storj-sign release/${TAG}/$(COMPONENT)_${GOOS}_${GOARCH}${FILEEXT} || echo "Skipping signing"
	rm -f release/${TAG}/${COMPONENT}_${GOOS}_${GOARCH}.zip

.PHONY: gateway_%
gateway_%:
	GOOS=$(word 2, $(subst _, ,$@)) GOARCH=$(word 3, $(subst _, ,$@)) COMPONENT=gateway $(MAKE) binary
	$(MAKE) binary-check COMPONENT=gateway GOARCH=$(word 3, $(subst _, ,$@)) GOOS=$(word 2, $(subst _, ,$@))
.PHONY: satellite_%
satellite_%:
	GOOS=$(word 2, $(subst _, ,$@)) GOARCH=$(word 3, $(subst _, ,$@)) COMPONENT=satellite $(MAKE) binary
	$(MAKE) binary-check COMPONENT=satellite GOARCH=$(word 3, $(subst _, ,$@)) GOOS=$(word 2, $(subst _, ,$@))
.PHONY: storagenode_%
storagenode_%:
	$(MAKE) binary-check COMPONENT=storagenode GOARCH=$(word 3, $(subst _, ,$@)) GOOS=$(word 2, $(subst _, ,$@))
.PHONY: binary-check
binary-check:
	@if [ -f release/${TAG}/${COMPONENT}_${GOOS}_${GOARCH} ]; then echo "release/${TAG}/${COMPONENT}_${GOOS}_${GOARCH} exists"; else $(MAKE) binary; fi
.PHONY: uplink_%
uplink_%:
	GOOS=$(word 2, $(subst _, ,$@)) GOARCH=$(word 3, $(subst _, ,$@)) COMPONENT=uplink $(MAKE) binary
	$(MAKE) binary-check COMPONENT=uplink GOARCH=$(word 3, $(subst _, ,$@)) GOOS=$(word 2, $(subst _, ,$@))
.PHONY: identity_%
identity_%:
	$(MAKE) binary-check COMPONENT=identity GOARCH=$(word 3, $(subst _, ,$@)) GOOS=$(word 2, $(subst _, ,$@))
.PHONY: certificates_%
certificates_%:
	GOOS=$(word 2, $(subst _, ,$@)) GOARCH=$(word 3, $(subst _, ,$@)) COMPONENT=certificates $(MAKE) binary
.PHONY: inspector_%
inspector_%:
	GOOS=$(word 2, $(subst _, ,$@)) GOARCH=$(word 3, $(subst _, ,$@)) COMPONENT=inspector $(MAKE) binary

COMPONENTLIST := gateway satellite storagenode uplink identity certificates inspector
OSARCHLIST    := darwin_amd64 linux_amd64 linux_arm windows_amd64
BINARIES      := $(foreach C,$(COMPONENTLIST),$(foreach O,$(OSARCHLIST),$C_$O))
.PHONY: binaries
binaries: ${BINARIES} ## Build gateway, satellite, storagenode, uplink, identity, and certificates binaries (jenkins)

##@ Deploy

.PHONY: deploy
deploy: ## Update Kubernetes deployments in staging (jenkins)
	for deployment in $$(kubectl --context nonprod -n v3 get deployment -l app=storagenode --output=jsonpath='{.items..metadata.name}'); do \
		kubectl --context nonprod --namespace v3 patch deployment $$deployment -p"{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"storagenode\",\"image\":\"storjlabs/storagenode:${TAG}\"}]}}}}" ; \
	done
	kubectl --context nonprod --namespace v3 patch deployment satellite -p"{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"satellite\",\"image\":\"storjlabs/satellite:${TAG}\"}]}}}}"

.PHONY: push-images
push-images: ## Push Docker images to Docker Hub (jenkins)
	# images have to be pushed before a manifest can be created
	# satellite
	docker push storjlabs/satellite:${TAG}${CUSTOMTAG}-amd64
	docker push storjlabs/satellite:${TAG}${CUSTOMTAG}-arm32v6
	docker manifest create storjlabs/satellite:${TAG}${CUSTOMTAG} storjlabs/satellite:${TAG}${CUSTOMTAG}-amd64 storjlabs/satellite:${TAG}${CUSTOMTAG}-arm32v6
	docker manifest annotate storjlabs/satellite:${TAG}${CUSTOMTAG} storjlabs/satellite:${TAG}${CUSTOMTAG}-amd64 --os linux --arch amd64
	docker manifest annotate storjlabs/satellite:${TAG}${CUSTOMTAG} storjlabs/satellite:${TAG}${CUSTOMTAG}-arm32v6 --os linux --arch arm --variant arm32v6
	docker manifest push storjlabs/satellite:${TAG}${CUSTOMTAG}
	# storagenode
	docker push storjlabs/storagenode:${TAG}${CUSTOMTAG}-amd64
	docker push storjlabs/storagenode:${TAG}${CUSTOMTAG}-arm32v6
	docker manifest create storjlabs/storagenode:${TAG}${CUSTOMTAG} storjlabs/storagenode:${TAG}${CUSTOMTAG}-amd64 storjlabs/storagenode:${TAG}${CUSTOMTAG}-arm32v6
	docker manifest annotate storjlabs/storagenode:${TAG}${CUSTOMTAG} storjlabs/storagenode:${TAG}${CUSTOMTAG}-amd64 --os linux --arch amd64
	docker manifest annotate storjlabs/storagenode:${TAG}${CUSTOMTAG} storjlabs/storagenode:${TAG}${CUSTOMTAG}-arm32v6 --os linux --arch arm --variant arm32v6
	docker manifest push storjlabs/storagenode:${TAG}${CUSTOMTAG}
	# uplink
	docker push storjlabs/uplink:${TAG}${CUSTOMTAG}-amd64
	docker push storjlabs/uplink:${TAG}${CUSTOMTAG}-arm32v6
	docker manifest create storjlabs/uplink:${TAG}${CUSTOMTAG} storjlabs/uplink:${TAG}${CUSTOMTAG}-amd64 storjlabs/uplink:${TAG}${CUSTOMTAG}-arm32v6
	docker manifest annotate storjlabs/uplink:${TAG}${CUSTOMTAG} storjlabs/uplink:${TAG}${CUSTOMTAG}-amd64 --os linux --arch amd64
	docker manifest annotate storjlabs/uplink:${TAG}${CUSTOMTAG} storjlabs/uplink:${TAG}${CUSTOMTAG}-arm32v6 --os linux --arch arm --variant arm32v6
	docker manifest push storjlabs/uplink:${TAG}${CUSTOMTAG}
	# gateway
	docker push storjlabs/gateway:${TAG}${CUSTOMTAG}-amd64
	docker push storjlabs/gateway:${TAG}${CUSTOMTAG}-arm32v6
	docker manifest create storjlabs/gateway:${TAG}${CUSTOMTAG} storjlabs/gateway:${TAG}${CUSTOMTAG}-amd64 storjlabs/gateway:${TAG}${CUSTOMTAG}-arm32v6
	docker manifest annotate storjlabs/gateway:${TAG}${CUSTOMTAG} storjlabs/gateway:${TAG}${CUSTOMTAG}-amd64 --os linux --arch amd64
	docker manifest annotate storjlabs/gateway:${TAG}${CUSTOMTAG} storjlabs/gateway:${TAG}${CUSTOMTAG}-arm32v6 --os linux --arch arm --variant arm32v6
	docker manifest push storjlabs/gateway:${TAG}${CUSTOMTAG}
ifeq (${TRACKED_BRANCH},true)
	docker tag storjlabs/satellite:${TAG}${CUSTOMTAG} storjlabs/satellite:${LATEST_TAG}
	docker push storjlabs/satellite:${LATEST_TAG}
	docker tag storjlabs/storagenode:${TAG}${CUSTOMTAG} storjlabs/storagenode:${LATEST_TAG}
	docker push storjlabs/storagenode:${LATEST_TAG}
	docker tag storjlabs/uplink:${TAG}${CUSTOMTAG} storjlabs/uplink:${LATEST_TAG}
	docker push storjlabs/uplink:${LATEST_TAG}
	docker tag storjlabs/gateway:${TAG}${CUSTOMTAG} storjlabs/gateway:${LATEST_TAG}
	docker push storjlabs/gateway:${LATEST_TAG}
endif

.PHONY: binaries-upload
binaries-upload: ## Upload binaries to Google Storage (jenkins)
	cd "release/${TAG}"; for f in "*"; do zip "$f".zip "$f"; done
	cd "release/${TAG}"; gsutil -m cp -r *.zip "gs://storj-v3-alpha-builds/${TAG}/"

##@ Clean

.PHONY: clean
clean: test-docker-clean binaries-clean clean-images ## Clean docker test environment, local release binaries, and local Docker images

.PHONY: binaries-clean
binaries-clean: ## Remove all local release binaries (jenkins)
	rm -rf release

.PHONY: clean-images
ifeq (${TRACKED_BRANCH},true)
clean-images: ## Remove Docker images from local engine
	-docker rmi storjlabs/gateway:${TAG}${CUSTOMTAG} storjlabs/gateway:${LATEST_TAG}
	-docker rmi storjlabs/satellite:${TAG}${CUSTOMTAG} storjlabs/satellite:${LATEST_TAG}
	-docker rmi storjlabs/storagenode:${TAG}${CUSTOMTAG} storjlabs/storagenode:${LATEST_TAG}
	-docker rmi storjlabs/uplink:${TAG}${CUSTOMTAG} storjlabs/uplink:${LATEST_TAG}
else
clean-images:
	-docker rmi storjlabs/gateway:${TAG}${CUSTOMTAG}
	-docker rmi storjlabs/satellite:${TAG}${CUSTOMTAG}
	-docker rmi storjlabs/storagenode:${TAG}${CUSTOMTAG}
	-docker rmi storjlabs/uplink:${TAG}${CUSTOMTAG}
endif

.PHONY: test-docker-clean
test-docker-clean: ## Clean up Docker environment used in test-docker target
	-docker-compose down --rmi all

