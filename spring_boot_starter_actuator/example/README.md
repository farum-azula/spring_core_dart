# spring_boot_starter_actuator: examples

This starter answers Spring Boot Actuator's endpoints under `/actuator`
in a [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
server: whether the application works (`health`), what it is (`info`),
which addresses it answers (`mappings`), and endpoints of your own.

[`example.dart`](example.dart) is a small order service with a
`HealthIndicator` of its own (`orders`), an `@Endpoint` of its own
(`/actuator/orders`), an `InfoContributor`, and a security chain from
`EndpointRequest`: `health`, `info` and the discovery page for everybody,
the other endpoints for the role `ADMIN`.
[`lib/resources/application.properties`](lib/resources/application.properties)
exposes the endpoints, shows the health's details and switches the
Kubernetes probes on.

## Run it

```yaml
dependencies:
  spring_boot_starter_actuator: ^0.8.0
  spring_boot_starter_security: ^0.8.0   # only to secure the endpoints

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.8.0   # required: finds the starters and your beans
```

From the package directory:

```bash
dart run build_runner build
dart run example/example.dart
```

Then, in another terminal:

```console
$ curl localhost:8086/actuator/health
{"status":"UP","components":{"diskSpace":{...},"livenessState":{"status":"UP"},"orders":{"status":"UP","details":{"pending":2}},"ping":{"status":"UP"},"readinessState":{"status":"UP"}},"groups":["liveness","readiness"]}
$ curl localhost:8086/actuator/health/readiness
{"status":"UP"}
$ curl localhost:8086/actuator/info
{"example":{"name":"orders","version":"1.0.0"}}
$ curl -i localhost:8086/actuator/orders
HTTP/1.1 401 Unauthorized
$ curl -u admin:<the password in the log> localhost:8086/actuator/orders/A-1
{"id":"A-1","state":"pending"}
```

The endpoints, their properties and the differences from Spring Boot are
in the package [README](https://pub.dev/packages/spring_boot_starter_actuator).
