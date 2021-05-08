# Common  Go Tasks
#
# INPUT VARIABLES
# - GOTEST_ARGS: Override the options passed by default ot go test (--race by default)
# - COVERALLS_TOKEN: Token to use when pushing coverage to coveralls.
#
# - FETCH_CA_CERT: The presence of this variable will cause the root CA certs
#                  to be downloaded to the file ca-certificates.crt before building.
#                  This can then be copied into the docker container.
#
#-------------------------------------------------------------------------------

## Append tasks to the global tasks
deps:: deps-go
deps-circle:: deps-circle-go deps
lint:: lint-go
test:: lint-go test-go
test-circle:: test test-coveralls
test-coverage:: test-coverage-go
build:: $(APP)
build-go:: $(APP)
clean:: clean-go

ifndef GOTEST_ARGS
  GOTEST_ARGS := -race -cover
endif

GOPATH ?= $(shell go env GOPATH)

## dependency manager detection
ifneq (,$(wildcard go.mod)) # if there IS go.mod
  USE_MODULE = 1
  GO111MODULE=on
  export GO11MODULE
  GOLANGCI_VERSION := v1.37.0
else ifneq (,$(wildcard Gopkg.toml)) # if ther IS Gopkg.toml
  USE_DEP = 1
else
  USE_GVT = 1
endif

DEBUG ?= false
CGO_ENABLED ?= 0
GO_FLAGS ?= -ldflags="-s -w"
ifneq (false,$(DEBUG))
  GO_FLAGS := -gcflags=all='-N -l'
endif

# allow specifying a package in cmd/
CMD ?= $(APP)
PACKAGE := .
OUTPUT := $(APP)
ifneq ($(CMD), $(APP))
  PACKAGE := ./cmd/$(CMD)
  OUTPUT := bin/$(CMD)
endif

## go tasks
$(OUTPUT): $(shell find . -type f -name '*.go')
	$(call INFO, "building project")
	@CGO_ENABLED=$(CGO_ENABLED) go build $(GO_FLAGS) -o $(OUTPUT) $(PACKAGE) > /dev/null

build-linux:: ## build project for linux
build-linux:: export GOOS=linux
build-linux:: _fetch-cert
build-linux:: $(OUTPUT)

build-circle:: build-linux ## build project for linux. If you need docker you will have to invoke that with an extension

deps-go:: _go-install-dep-tools deps-lint ## install dependencies for project assumes you have go binary installed
ifneq (,$(wildcard vendor))
	@find  ./vendor/* -maxdepth 0 -type d -exec rm -rf "{}" \; || true
endif

ifdef USE_MODULE
	$(call INFO, "restoring dependencies using modules via \'go get\'")
	@GO111MODULE=on go get
endif

ifdef USE_GVT
	$(call INFO, "restoring dependencies with \'gvt\'")
	@gvt rebuild > /dev/null
endif

ifdef USE_DEP
	$(call INFO, "ensuring dependencies with \'dep\'")
  ifdef CIRCLECI
	  @cd $$(readlink -f "$$(pwd)") && dep ensure > /dev/null
  else
		@dep ensure > /dev/null
  endif
endif

lint-go:: deps-lint
  ifdef USE_MODULE
		$(call INFO, "scanning source with golangci-lint")
		golangci-lint	run -E goimports -v
  else
		$(call INFO, "scanning source with gometalinter")
# for now we disable gotype because its vendor suport is mostly broken
#  https://github.com/alecthomas/gometalinter/issues/91
		gometalinter.v2 --vendor --enable-gc -Dstaticcheck -Dgotype -Ddupl -Dgocyclo -Dinterfacer -Daligncheck -Dunconvert -Dvarcheck  -Dstructcheck -E vet -E golint -E gofmt -E unused --deadline=80s
		gometalinter.v2 --vendor --enable-gc --disable-all -E staticcheck --deadline=60s
		gometalinter.v2 --vendor --enable-gc --disable-all -E interfacer  --deadline=30s
		gometalinter.v2 --vendor --enable-gc --disable-all -E unconvert -E varcheck   --deadline=30s
		gometalinter.v2 --vendor --enable-gc --disable-all -E structcheck  --deadline=30s
  endif

GO_TEST_CMD := go test $(GOTEST_ARGS)  $$(go list ./... | grep -Ev '/vendor/|/devops/')
ifneq (,$(findstring -race, $(GOTEST_ARGS)))
  GO_TEST_CMD := CGO_ENABLED=1 $(GO_TEST_CMD)
endif
test-go:: ## run go tests (fmt vet)
	$(call INFO, "running tests with $(GOTEST_ARGS)")
	@$(GO_TEST_CMD)

test-no-race:: lint ## run tests without race detector
	$(call WARN, "DEPRECATED: set GOTEST_ARGS and run make test-go to change how go-test runs from common-go. Running tests without race detection.")
	go test $$(go list ./... | grep -Ev '/vendor/|/devops/')

deps-circle-go::
	$(call WARN, "DEPRECATED: stop calling deps-circle-go in your Makefiles. Your build may break in the future when this warning is removed")

deps-lint::
ifdef USE_MODULE
  ifeq (, $(shell command -v golangci-lint))
	  curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s -- -b $(GOPATH)/bin $(GOLANGCI_VERSION)
  else
		$(call INFO, "golangci already installed")
  endif
else
  ifeq (, $(shell command -v gometalinter.v2))
	$(call INFO, "installing gometalinter")
	@GO111MODULE=off go get -u gopkg.in/alecthomas/gometalinter.v2 > /dev/null
	@gometalinter.v2 --install > /dev/null
  else
		$(call INFO, "gometalinter already installed")
  endif
endif

deps-coveralls-go:: ## install goveralls for sending go test coverage reports to Coveralls.io
ifeq (, $(shell command -v goveralls))
	$(call INFO, "installing goveralls")
	@GO111MODULE=off go get github.com/mattn/goveralls > /dev/null
endif

deps-status:: ## check status of deps with gostatus
ifeq (, $(shell command -v gostatus))
	$(call INFO, "installing gostatus")
	@GO111MODULE=off go get -u github.com/shurcooL/gostatus > /dev/null
endif
	@go list -f '{{join .Deps "\n"}}' . | gostatus -stdin -v

test-coverage-go:: ## run coverage report
	$(call INFO, "running go test")
	@go test -v -coverprofile=coverage.out $$(go list ./... | grep -Ev '/vendor/|/devops/') > /dev/null

test-coveralls:: deps-coveralls-go test-coverage-go ## run coverage and report to coveralls
ifdef COVERALLS_TOKEN
	$(call INFO, "reporting coverage to coveralls")
	@goveralls -repotoken $$COVERALLS_TOKEN -service=circleci -coverprofile=coverage.out > /dev/null
else
	$(call WARN, "You asked to use Coveralls but neglected to set the COVERALLS_TOKEN environment variable")
endif

test-coverage-html:: test-coverage ## output html coverage file
	$(call INFO, "generating html coverage report")
	@go tool cover -html=coverage.out > /dev/null

clean-go::
	$(call INFO, "cleaning build and test artifacts")
	@rm -f '$(APP)' coverage.out

# this will detect if the project is dep or not and use it if it is. If not install gvt
# if no manifest then its probably dep
ifdef USE_GVT
  _go-install-dep-tools: _go-install-gvt
endif
ifdef USE_DEP
  _go-install-dep-tools: _go-install-dep
endif

_go-install-gvt::
ifeq (, $(shell command -v gvt))
	$(call INFO, "installing 'gvt' go dependency tool")
	@go get -u github.com/FiloSottile/gvt > /dev/null
endif

_go-install-dep::
ifeq (, $(shell command -v dep))
	$(call INFO, "installing 'dep' go dependency tool")
	@go get -u github.com/golang/dep/... > /dev/null
endif


_fetch-cert::
ifdef FETCH_CA_CERT
	$(call INFO, "fetching CA certs from haxx.se")
	@curl -s -L https://curl.haxx.se/ca/cacert.pem -o ca-certificates.crt > /dev/null
endif

.PHONY:: _fetch-cert _gvt-install test-coverage-html test-coveralls deps-status deps-coveralls-go deps-circle deps-go test-circle test-go build-circle build-linux build-go _go-install-dep-tools
