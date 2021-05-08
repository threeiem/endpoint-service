# Docker common things

#
# INPUT VARIABLES
# 	- QUAY_USER: The quay.io user to use (usually set in CI)
# 	- QUAY_PASSWD: The quay passwd to use  (usually set in CI)
# 	- IMAGE: the docker image to use. will be computed if it doesn't exist.
# 	- REGISTRY: The docker registry to use. defaults to quay.
#
# EXPORT VARIABLES
# 	- BUILD_NUM: The build number for this build. Will use pants default sandbox
# 	             if not on circleCI, if that isn't available will defauilt to 'dev'.
# 	             If it is in circle will use CIRCLE_BUILD_NUM otherwise.
# 	- IMAGE: The image to use for the build.
# 	- REGISTRY: The registry to use for the build.
# 	- IMAGE_BASENAME: The image without the tag field on it.. i.e. foo:1.0.0 would have image basename of 'foo'
#
#-------------------------------------------------------------------------------

_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

include $(_DIR)/_base.mk

## Append tasks to the global tasks
lint:: lint-hadolint

# use pants if it exists outside of circle to get the default namespace and use it for the build
ifndef CIRCLECI
  BUILD_NUM := $(shell pants config get default-sandbox-name 2> /dev/null || echo dev)-$(COMMIT)
endif
ifndef BUILD_NUM
  BUILD_NUM := dev
endif

# TODO: the docker login -e email flag logic can be removed when all projects stop using circleci 1.0 or
#       if circleci 1.0 build container upgrades its docker > 1.14
ifdef CIRCLE_BUILD_NUM
  BUILD_NUM := $(CIRCLE_BUILD_NUM)
  ifeq (email-required, $(shell docker login --help | grep -q Email && echo email-required))
    QUAY := docker login -p "$$QUAY_PASSWD" -u "$$QUAY_USER" -e "unused@unused" quay.io
  else
    QUAY := docker login -p "$$QUAY_PASSWD" -u "$$QUAY_USER" quay.io
  endif
endif

# These can be overridden
REGISTRY ?= quay.io/getpantheon
IMAGE		 ?= $(REGISTRY)/$(APP):$(BUILD_NUM)
# Should we try to pull instead of building?
DOCKER_TRY_PULL ?= false
# Should we rebuild the tag regardless of whether it exists locally or elsewhere?
DOCKER_FORCE_BUILD ?= true
# Should we include build arguments?
DOCKER_BUILD_ARGS ?= ""

# because users can supply image, we substring extract the image base name
IMAGE_BASENAME := $(firstword $(subst :, ,$(IMAGE)))

# if there is a docker file then set the docker variable so things can trigger off it
ifneq ("$(wildcard Dockerfile))","")
# file is there
  DOCKER:=true
endif

DOCKER_BUILD_CONTEXT ?= .

build-docker:: setup-quay build-linux ## build the docker container
	@FORCE_BUILD=$(DOCKER_FORCE_BUILD) TRY_PULL=$(DOCKER_TRY_PULL) \
		$(COMMON_MAKE_DIR)/sh/build-docker.sh \
		$(IMAGE) $(DOCKER_BUILD_CONTEXT) $(DOCKER_BUILD_ARGS)

# stub build-linux std target
build-linux::

push:: setup-quay ## push the container to the registry
	$(call INFO,"pushing image $(IMAGE)")
	@docker push $(IMAGE)

setup-quay:: ## setup docker login for quay.io
  ifdef CIRCLE_BUILD_NUM
    ifndef QUAY_PASSWD
			$(call ERROR, "Need to set QUAY_PASSWD environment variable.")
    endif
  ifndef QUAY_USER
		$(call ERROR, "Need to set QUAY_USER environment variable.")
  endif
	$(call INFO, "Setting up quay login credentials.")
	@$(QUAY) > /dev/null
else
	$(call INFO, "No docker login unless we are in CI.")
	$(call INFO, "We will fail if the docker config.json does not have the quay credentials.")
endif

push-circle:: ## Deprecated: Command is misleading. It builds before pushes the container from circle
	$(call WARN, "DEPRECATED: Build docker separately if it has not already been built and then use 'make push'.")
	$(call WARN, "Building container before pushing...")
	@make build-docker
push-circle::
	@make push

DOCKERFILES := $(shell find . -name 'Dockerfile*' -not -path "./devops/make*")
lint-hadolint:: ## lint Dockerfiles
ifneq (, $(shell command -v hadolint))
  ifdef DOCKERFILES
		$(call INFO, "running hadolint for $(DOCKERFILES)")
		hadolint $(DOCKERFILES)
  endif
endif

.PHONY:: setup-quay build-docker push
