# spring_security_core: examples

[`example.dart`](example.dart) is a Spring Boot application without a
server. It shows:

- users with hashed passwords (`{argon2}...`) from a `UserDetailsService`
  bean, and the `AuthenticationManager` the auto-configuration builds from
  it;
- a login, kept as the program's current user, as a Flutter app does it;
- an `OrderService` whose methods are guarded by `@PreAuthorize`,
  `@PostAuthorize` and `@PostFilter`;
- a wrong password failing with `BadCredentialsException`;
- work done as another user with `SecurityContextHolder.runWithContext`.

```yaml
dependencies:
  spring_security_core: ^0.5.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.5.0   # required: generates the proxies the checks run on
```

## Run it

```bash
dart run build_runner build
dart run example/example.dart
```

After the banner and the startup log lines, it logs, through the
`example` logger (the two refusals as warnings):

```text
... INFO  ... example : cancelled 1
... INFO  ... example : [Order(1 of ada)]
... WARN  ... example : find 2: Access Denied
... WARN  ... example : login: Bad credentials
... INFO  ... example : [Order(1 of ada), Order(2 of bob)]
```

Line by line:

1. ada cancels her own order: `#order.owner == authentication.name` is
   true, so `@PreAuthorize` lets the call through.
2. `@PostFilter` removes bob's order from the list ada gets.
3. Order 2 belongs to bob: the method runs, then `@PostAuthorize` refuses
   to hand the result to ada (`AccessDeniedException`).
4. A wrong password fails with the same message as an unknown user would.
5. Run as root, an admin, `@PostFilter` keeps every order.

A server takes
[`spring_boot_starter_security`](https://pub.dev/packages/spring_boot_starter_security)
instead: it brings this package and puts the user of each request in the
security context. All the options are in the package
[README](https://pub.dev/packages/spring_security_core).
