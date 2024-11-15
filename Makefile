SHELL := /bin/bash

PACKAGE=seymour-deploy
VERSION:=0.1.0
PLATFORM=linux/amd64
# PLATFORM=linux/arm64
CONTAINER:=ghcr.io/freshrobotics/$(PACKAGE)-$(PLATFORM):$(VERSION)
TARFILE:=${PACKAGE}-${VERSION}.tar
# RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
RMW_IMPLEMENTATION=rmw_fastrtps_cpp
DDS_CONFIG_DIR=/opt/dds/config
CYCLONEDDS_URI=$(DDS_CONFIG_DIR)/cyclonedds-loopback.xml
FASTRTPS_DEFAULT_PROFILES_FILE=$(DDS_CONFIG_DIR)/fastrtps-loopback.xml

DOCKER_RUN_ARGS=--rm -it \
		--platform $(PLATFORM) \
		--privileged \
		--network host \
		--env RMW_IMPLEMENTATION=$(RMW_IMPLEMENTATION) \
		--env CYCLONEDDS_URI=$(CYCLONEDDS_URI) \
		--env FASTRTPS_DEFAULT_PROFILES_FILE=$(FASTRTPS_DEFAULT_PROFILES_FILE)

PHONY: help
help: ## show help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: version
version: ## print the package version
	@echo $(VERSION)

.PHONY: run
run: ## start container with shell
	docker run $(DOCKER_RUN_ARGS) \
		--name $(PACKAGE) \
		$(CONTAINER) \
		/bin/bash -i

.PHONY: stop
stop: ## stops running container
	docker stop $(PACKAGE)

.PHONY: shell
shell: ## get (another) shell to running container
	docker exec -it $(PACKAGE) /bin/bash

.PHONY: image
image: ## builds the deployable container image
	docker build \
		--platform $(PLATFORM) \
		--build-arg DDS_CONFIG_DIR=$(DDS_CONFIG_DIR) \
		--tag $(CONTAINER) \
		.

.PHONY: build-stage-image
build-stage-image: ## build container image to build stage
	docker build \
		--platform $(PLATFORM) \
		--build-arg DDS_CONFIG_DIR=$(DDS_CONFIG_DIR) \
		--tag $(CONTAINER) \
		--target build-stage \
		.

.PHONY: export-tarball
export-tarball: ## export image to tarball
	docker image save -o $(TARFILE) $(CONTAINER)

.PHONY: import-tarball
import-tarball: ## load image from tarball
	docker image load -i $(TARFILE)

.PHONY: talker-demo
talker-demo: ## run demo talker node
	docker run $(DOCKER_RUN_ARGS) \
		--name $(PACKAGE)-talker \
		$(CONTAINER) \
		/bin/bash -ic "ros2 run demo_nodes_cpp talker"

.PHONY: listener-demo
listener-demo: ## run demo talker node
	docker run $(DOCKER_RUN_ARGS) \
		--name $(PACKAGE)-listener \
		$(CONTAINER) \
		/bin/bash -ic "ros2 run demo_nodes_cpp listener"

.PHONY: install-multiarch
install-multiarch: ## setup multiarch support on ubuntu
	sudo apt-get install -y qemu-user-static
	docker run --privileged --rm tonistiigi/binfmt --install all
