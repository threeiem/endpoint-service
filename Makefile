# Change these to match your app
APP := go-demo-service

include devops/make/common.mk
include devops/make/common-docker.mk
include devops/make/common-kube.mk
include devops/make/common-go.mk

ifeq ($(CIRCLECI),true)
	# When running in Circle, run the Docker images used for testing in the background.
 	DOCKER_BACKGROUND := -d
else
	# When running locally, run in foreground and cleanup afterwards (which doesn't work in Circle)
	DOCKER_BACKGROUND := -it --rm
endif

ifeq ($(KUBE_NAMESPACE), production)
	REPLICAS := 2
else
	REPLICAS := 1
endif

# On macs, use gsed instead of sed (avoid bsd sed)
SED := $(shell which gsed || which sed)

init:
	# Search and replace references to the demo service
	find ./pkg/ -type f -name "*.go" -exec $(SED) --in-place="" --expression="s/go-demo-service/$(APP)/g" {} \;
	mv devops/k8s/configmaps/non-prod/config/go-demo-service.yml devops/k8s/configmaps/non-prod/config/$(APP).yml
	mv devops/k8s/configmaps/production/config/go-demo-service.yml devops/k8s/configmaps/production/config/$(APP).yml
	find ./devops/k8s/ -type f -name "*.yml" -exec $(SED) --in-place="" --expression="s/go-demo-service/$(APP)/g" {} \;
	mv go-demo-service.template.yml $(APP).yml

	for file in "main.go .gitignore Dockerfile Makefile go.mod"; do \
		$(SED) --in-place="" --expression="s/go-demo-service/$(APP)/g" $$file;\
	done

deploy: update-psp update-sa update-configmaps update-services update-deployment

check-deployment-status:
	@timeout 900 $(KUBECTL_CMD) rollout status deployment/$(APP) \
		| grep 'successfully' && echo 'Deploy succeeded.' && exit 0 \
		|| echo 'Deploy unsuccessful. Investigate.' && exit 1

update-deployment:
	test "$(IMAGE)" \
		-a "$(REPLICAS)" \
		-a "$(BUILD_NUM)" \
		-a "$(KUBE_NAMESPACE)"
	sed -e "s#__IMAGE__#$(IMAGE)#" \
		-e "s#__REPLICAS__#$(REPLICAS)#" \
		-e "s/__BUILD__/$(BUILD_NUM)/" \
		devops/k8s/deployment.yml \
		| $(KUBECTL_CMD) apply -f -

update-services:
	test "$(KUBE_NAMESPACE)"
	$(KUBECTL_CMD) apply -f devops/k8s/service.yml

update-sa: ## push service account (KSA) to kube
	$(KUBECTL_CMD) apply --record -f devops/k8s/sa.yml
	$(KUBECTL_CMD) apply --record -f devops/k8s/rbac.yml

update-psp: ## push pod security policy to kube
	$(KUBECTL_CMD) apply --record -f devops/k8s/psp.yml
