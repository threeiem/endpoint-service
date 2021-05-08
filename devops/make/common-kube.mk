# Common kube things. This is the simplest set of common kube tasks
#
# INPUT VARIABLES
#  - APP: should be defined in your topmost Makefile
#  - SECRET_FILES: list of files that should exist in secrets/* used by
#                  _validate_secrets task
#
# EXPORT VARIABLES
#   - KUBE_NAMESPACE: represents the kube namespace that has been detected based on
#              branch build and circle existence.
#   - KUBE_CONTEXT: set this variable to whatever kubectl reports as the default
#                   context
#   - KUBECTL_CMD: sets up cubectl with the namespace + context for easy usage
#                  in top level make files
#-------------------------------------------------------------------------------

_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

include $(_DIR)/_base.mk

## Append tasks to the global tasks
deps-circle:: deps-circle-kube
lint:: lint-kubeval
clean:: clean-kube

# this fetches the long name of the cluster
ifdef CLUSTER_DEFAULT
   KUBE_CONTEXT ?= $(shell kubectl config get-contexts | grep $(CLUSTER_DEFAULT) | tr -s ' ' | cut -d' ' -f2)
endif

# Use pants to divine the namespace on local development, if unspecified.
ifndef CIRCLECI
  KUBE_NAMESPACE ?= $(shell pants config get default-sandbox-name 2> /dev/null)
  KUBE_CONTEXT ?= $(shell pants sandbox | grep targetcluster | awk '{ print $$2 }')
endif

# use cases:
#  all default - NS/context aren't specified from caller
#    - master branch
#       ->  CONTEXT =  DEFAULT_CLUSTER ()
#       ->  NAMESPACE = PROD
#    - non master branch
#      -> CONTEXT = DEFAULT_SANDBOX_CTX
#      -> NAMESPACE = SANDBOX_NS
#
#  JUST NS specified
#    - master
#      -> CONTEXT = DEFAULT_CLUSTER
#      -> NAMESPACE = USER_SPECIFIED_NS
#    - non master
#      -> CONTEXT = DEFAULT_SANDBOX_CTX
#      -> NAMESPACE = USER_SPECIFIED_NS
#
#  JUST Context
#    - master
#      -> CONTEXT = USER_SPECIFIED_CTX
#      -> NAMESPACE = PROD
#    - non master
#      -> CONTEXT = USER_SPECIFIED_CTX
#      -> NAMESPACE = SANDBOX_NS
#
#  BOTH... Obvious take USER_SPECIFIED_*

# default kube context based on above rules
ifndef KUBE_CONTEXT
  KUBE_CONTEXT := gke_pantheon-sandbox_us-central1_sandbox-01

  ifeq ($(BRANCH), master) # prod
    KUBE_CONTEXT := gke_pantheon-internal_us-central1_general-01
  endif
endif

# If we are on master branch, use production kube env (unless KUBE_NAMESPACE is already set in the environment)based on above rules
# see cases above
ifndef KUBE_NAMESPACE
  # If on circle and not on master, build into a sandbox environment.
  # lower-cased for naming rules of sandboxes
  BRANCH_LOWER := $(shell echo $(BRANCH) | tr A-Z a-z)
  KUBE_NAMESPACE := sandbox-$(APP)-$(BRANCH_LOWER)

  ifeq ($(BRANCH), master) # prod
    KUBE_NAMESPACE := production
  endif
else
  KUBE_NAMESPACE := $(shell echo $(KUBE_NAMESPACE) | tr A-Z a-z)
endif

ifndef UPDATE_GCLOUD
  UPDATE_GCLOUD := true
endif

ifndef LABELS
  LABELS := app=$(APP)
endif

# template-sandbox lives in sandbox-02, force it to always use that cluster
ifeq ($(KUBE_NAMESPACE), template-sandbox)
  KUBE_CONTEXT := gke_pantheon-sandbox_us-east4_sandbox-02
endif

KUBECTL_CMD=kubectl --namespace=$(KUBE_NAMESPACE) --context=$(KUBE_CONTEXT)

# extend or define circle deps to install gcloud
ifeq ($(UPDATE_GCLOUD), true)
  deps-circle-kube:: install-update-kube setup-kube
else
  deps-circle-kube:: setup-kube
endif

install-update-kube::
	$(call INFO, "updating or install gcloud cli")
	@if command -v gcloud >/dev/null; then \
		$(COMMON_MAKE_DIR)/sh/update-gcloud.sh > /dev/null ; \
	else  \
		$(COMMON_MAKE_DIR)/sh/install-gcloud.sh > /dev/null ; \
	fi

setup-kube::
	$(call INFO, "setting up gcloud cli")
	@$(COMMON_MAKE_DIR)/sh/setup-gcloud.sh

update-secrets:: ## update secret volumes in a kubernetes cluster
	$(call INFO, "updating secrets for $(KUBE_NAMESPACE) in $(KUBE_CONTEXT)")
	@APP=$(APP) KUBE_NAMESPACE=$(KUBE_NAMESPACE) KUBE_CONTEXT=$(KUBE_CONTEXT) LABELS=$(LABELS) \
		$(COMMON_MAKE_DIR)/sh/update-kube-object.sh $(ROOT_DIR)/devops/k8s/secrets > /dev/null

update-configmaps:: ## update configmaps in a kubernetes cluster
	$(call INFO, "updating configmaps for $(KUBE_NAMESPACE) in $(KUBE_CONTEXT)")
	@APP=$(APP) KUBE_NAMESPACE=$(KUBE_NAMESPACE) KUBE_CONTEXT=$(KUBE_CONTEXT) LABELS=$(LABELS) \
		$(COMMON_MAKE_DIR)/sh/update-kube-object.sh $(ROOT_DIR)/devops/k8s/configmaps > /dev/null

clean-secrets:: ## delete local secrets
	$(call INFO, "cleaning local Kube secrets")
	@git clean -dxf $(ROOT_DIR)/devops/k8s/secrets

clean-kube:: clean-secrets

verify-deployment-rollout:: ## validate that deployment to kube was successful and rollback if not
	@$(KUBECTL_CMD) rollout status deployment/$(APP) --timeout=10m \
		| grep 'successfully' && echo 'Deploy succeeded.' && exit 0 \
		|| echo 'Deploy unsuccessful. Rolling back. Investigate!' \
			&& $(KUBECTL_CMD) rollout undo deployment/$(APP) && exit 1

# set SECRET_FILES to a list, and this will ensure they are there
_validate-secrets::
		@for j in $(SECRET_FILES) ; do \
			if [ ! -e secrets/$$j ] ; then  \
			echo "Missing file: secrets/$$j" ;\
				exit 1 ;  \
			fi \
		done

# legacy compat
ifdef YAMLS
  KUBE_YAMLS ?= YAMLS
endif

KUBE_YAMLS_PATH ?= ./devops/k8s
KUBE_YAMLS_EXCLUDED_PATHS ?= configmaps

KUBEVAL_SKIP_CRDS ?=
ifneq (,$(KUBEVAL_SKIP_CRDS))
  KUBEVAL_SKIP_CRDS := --ignore-missing-schemas
endif

ifndef KUBE_YAMLS_CMD
  KUBE_YAMLS_CMD := find . -path '$(KUBE_YAMLS_PATH)/*' \
    $(foreach kube_excluded,$(KUBE_YAMLS_EXCLUDED_PATHS),\
      -not -path '$(KUBE_YAMLS_PATH)/$(kube_excluded)/*') \
    \( -name '*.yaml' -or -name '*.yml' \)
endif

ifdef KUBEVAL_SKIP_TEMPLATES
  KUBE_YAMLS_CMD := $(KUBE_YAMLS_CMD) | grep -vF 'template.'
endif

# use subshell to allow dependency tasks to update manifests
KUBEVAL_CMD := kubeval --strict $(KUBEVAL_SKIP_CRDS) $$($(KUBE_YAMLS_CMD))
ifdef KUBE_YAMLS
  KUBEVAL_CMD := kubeval --strict $(KUBEVAL_SKIP_CRDS) $(KUBE_YAMLS)
endif

lint-kubeval:: ## validate kube yamls
  ifneq (, $(shell command -v kubeval))
		$(KUBEVAL_CMD)
  endif

.PHONY::  deps-circle force-pod-restart
