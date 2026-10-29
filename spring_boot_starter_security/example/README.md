# spring_boot_starter_security: examples

[`example.dart`](example.dart) is a Spring Boot application with a secured
book API on port 8080. It shows:

- two `SecurityFilterChain`s: the API (`/api/**`) with HTTP Basic, no
  session and so no CSRF token, and every other page with a login form, a
  session and CSRF protection;
- users with hashed passwords (`{argon2}...`) from a `UserDetailsService`
  bean;
- `@PreAuthorize` on a service method: only admins delete books, whatever
  calls the method;
- the logged-in user in controllers (`Authentication`,
  `@AuthenticationPrincipal()`).

```yaml
dependencies:
  spring_boot_starter_security: ^0.4.3

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3
```

## Run it

The generator writes the controllers' handlers and the proxies that the
`@PreAuthorize` check runs in (`example.spring.dart`):

```bash
dart run build_runner build
dart run example/example.dart
```

Then call it:

```bash
curl -i localhost:8080/api/books                                   # 200, public
curl -i localhost:8080/api/me                                      # 401, WWW-Authenticate: Basic
curl -i -u ada:ada-secret localhost:8080/api/me                    # 200 ada
curl -i -u ada:ada-secret -X DELETE localhost:8080/api/books/1     # 403, not an admin
curl -i -u root:root-secret -X DELETE localhost:8080/api/books/1   # 204
```

- `GET /api/books` is open to everyone: the API chain's first rule
  permits it.
- `/api/me` needs a login; without one, `curl` gets the Basic challenge.
- ada may log in but is not an admin: the rule lets her through to the
  controller, and the service's `@PreAuthorize("hasRole('ADMIN')")` refuses
  the call with `403`.
- root is an admin, so the book is deleted.

In a browser, <http://localhost:8080/account> sends you to the generated
login page first (the second chain), then greets the user.

Without any configuration the starter is secure by default: every request
needs a login, and there is one user, `user`, with a password generated
and logged at startup. All the options are in the package
[README](https://pub.dev/packages/spring_boot_starter_security).
