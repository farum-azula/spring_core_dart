# spring_boot_starter_websocket: examples

[`example.dart`](example.dart) is a Spring Boot application with a
`@WebSocketClient` interface and a service using it, talking to a local
echo server.

```yaml
dependencies:
  spring_boot_starter_websocket: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2
```

```bash
dart run build_runner build   # writes the ChatSocket implementation
dart run example/example.dart
```

More in the package
[README](https://pub.dev/packages/spring_boot_starter_websocket).
