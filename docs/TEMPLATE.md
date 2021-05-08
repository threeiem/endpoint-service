Go Demo Service
===============

This service runs a simple hello world application which can act as a base for new services.

## Forking the demo app and initializing your new app

1. Press the "Use this template" button to fork this repository.
1. Clone your fork to your local machine.
1. Add `common_makefiles` to your repo by following the installation steps from [https://github.com/pantheon-systems/common_makefiles#usage](https://github.com/pantheon-systems/common_makefiles#usage)
1. Edit `Makefile` and set the `APP` to the name of your application (ex. "foo-service").
1. Run `make init` to replace all instances of `go-demo-service` with the value of `APP`.
1. Delete the `init:` target from `Makefile`.

### Initialization troubleshooting

If you're on a Mac and `make init` fails, try `brew install gnu-sed`. The `make init` command uses `sed` to replace `go-demo-app` with your app. The BSD sed found on macs has a different invocation from GNU sed, which this Makefile is written for. 

## Certificates

If you want to deploy the application to sandbox or production, you need to use a new pair of certificates. These can be obtained from Vault either manually (for local testing) or using the Vault-agent sidecar injector (see https://github.com/pantheon-systems/gke-terraform/tree/master/modules/vault-injector/examples)

## Graphql

Please see the [experimental Graphql branch](https://github.com/pantheon-systems/go-demo-service/tree/graphql-experimental) for a POC Graphql implementation for the Go Demo Service.
