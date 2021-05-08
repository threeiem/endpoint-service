go-demo-service
===============

_This repo can be used as a starting point for developing new Go service for the Pantheon platform. See the template documentation [here](docs/TEMPLATE.md)._

Overview
-----------

This service runs a simple hello world application.

Development
-----------

### Running the Demo Application locally

1. Copy `go-demo-service.template.yml` to `go-demo-service.yml`

```console
cp go-demo-service.template.yml go-demo-service.yml
```

2. Compile binary for the current architecture:

```console
make build
```

3. Run it:

```console
./go-demo-service
```

4. Use the provided client cert from the `test-fixtures/certs/` folder and call the app via curl:

```console
$ curl -skE test-fixtures/certs/client1.pem https://127.0.0.1:7443/v1/demo-get | jq .
{
  "Message": "Hello World!"
}
```

### Running the Demo Application in Kubernetes (Sandbox)

The app is currently running in the `shared` namespace of `sandbox-01`. For testing, you can use the command below:

```console
$ export PANTHEON_CERT=$HOME/pantheor.pem
$ curl -skE $PANTHEON_CERT https://35.222.2.185/v1/demo-get | jq .
{
  "Message": "Hello World!"
}
```