# spring_boot_starter_security: examples

[`example.dart`](example.dart) is a Spring Boot application with a secured
book API on port 8080: two `SecurityFilterChain`s (the API with HTTP Basic
and no session, the pages with form login), users with hashed passwords,
and `@PreAuthorize` on a service method.

```yaml
dependencies:
  spring_boot_starter_security: ^0.3.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.3.2
```

```bash
dart run build_runner build
dart run example/example.dart

curl -i localhost:8080/api/books                                   # 200, public
curl -i localhost:8080/api/me                                      # 401, WWW-Authenticate: Basic
curl -i -u ada:ada-secret localhost:8080/api/me                    # 200 ada
curl -i -u ada:ada-secret -X DELETE localhost:8080/api/books/1     # 403, not an admin
curl -i -u root:root-secret -X DELETE localhost:8080/api/books/1   # 204
```

In a browser, <http://localhost:8080/account> shows the login page first.

Without any configuration the starter is secure by default (every request
needs a login, one user with a generated password). All options: the
package [README](https://pub.dev/packages/spring_boot_starter_security).
