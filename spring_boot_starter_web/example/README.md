# spring_boot_starter_web: examples

[`example.dart`](example.dart) is a Spring Boot application with a small
book API on port 8080: a `@RestController` with a GET returning JSON, a
POST with a `@Valid` body answering `201 Created`, an `@ExceptionHandler`
answering a `ProblemDetail`, and server-sent events.

```yaml
dependencies:
  spring_boot_starter_web: ^0.4.1

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.1
```

```bash
dart run build_runner build   # writes the controller's request handlers
dart run example/example.dart
curl localhost:8080/api/books/978-0
```

More in the package
[README](https://pub.dev/packages/spring_boot_starter_web).
