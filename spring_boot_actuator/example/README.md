# spring_boot_actuator: examples

This package holds Spring Boot Actuator's endpoints and their model, with
no HTTP of its own: the health report (`HealthIndicator`, `Health`,
`Status`, groups), the info (`InfoContributor`, `BuildProperties`,
`GitProperties`) and the mappings. Applications get the endpoints over
HTTP from
[`spring_boot_starter_actuator`](https://pub.dev/packages/spring_boot_starter_actuator),
which declares them as beans; this package is what a health indicator or
an info contributor of yours builds on.

[`example.dart`](example.dart) builds a health report of three
indicators (`ping`, `diskSpace` and a queue of its own) and the info of a
build by hand, and prints them as Spring Boot writes them.

## Run it

From the package directory:

```bash
dart run example/example.dart
```

It logs the HTTP status and the JSON of `/actuator/health`, of the
`core` group and of `/actuator/info` (the disk sizes depend on the
machine):

```text
[example] INFO: 503 {"status":"DOWN","components":{"diskSpace":{"status":"UP","details":{...}},"ping":{"status":"UP"},"queue":{"status":"DOWN","details":{"waiting":250}}},"groups":["core"]}
[example] INFO: 200 {"status":"UP"}
[example] INFO: {"build":{"name":"shop","version":"1.4.0","time":"2026-11-05T09:12:44Z"}}
```

## A health indicator of your own

In an application with the actuator starter, a bean is enough: it is in
the report under its bean name without `HealthIndicator`.

```dart
@Component()
class QueueHealthIndicator extends AbstractHealthIndicator {
  QueueHealthIndicator(this.queue);
  final MessageQueue queue;

  @override
  Future<void> doHealthCheck(HealthBuilder builder) async {
    final waiting = await queue.size();
    (waiting < 100 ? builder.up() : builder.down())
        .withDetail('waiting', waiting);
  }
}
```

The endpoints over HTTP, their properties and the differences from Spring
Boot are in the
[actuator starter's README](https://pub.dev/packages/spring_boot_starter_actuator).
