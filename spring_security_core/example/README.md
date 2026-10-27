# spring_security_core: examples

[`example.dart`](example.dart) is a Spring Boot application without a
server: users with hashed passwords, a login through the
`AuthenticationManager`, and a service whose methods are guarded by
`@PreAuthorize`, `@PostAuthorize` and `@PostFilter`.

```yaml
dependencies:
  spring_security_core: ^0.4.1

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.1   # required: generates the proxies the checks run on
```

```bash
dart run build_runner build
dart run example/example.dart
```

```
cancelled 1
[Order(1 of ada)]
find 2: Access Denied
login: Bad credentials
[Order(1 of ada), Order(2 of bob)]
```

A server takes
[`spring_boot_starter_security`](https://pub.dev/packages/spring_boot_starter_security)
instead: it brings this package and puts each request's user in the
context. All options: the package
[README](https://pub.dev/packages/spring_security_core).
