# spring_boot_starter_websocket: examples

[`example.dart`](example.dart) declares a `@WebSocketClient` interface and
a service using it, and talks to a local echo server through the
transport the starter uses.

```yaml
dependencies:
  spring_boot_dart: ^0.2.0
  spring_boot_starter_websocket: ^0.2.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.2.0
```

```bash
dart run build_runner build   # writes the ChatSocket implementation
dart run example/example.dart
```

More in the package
[README](https://pub.dev/packages/spring_boot_starter_websocket).
