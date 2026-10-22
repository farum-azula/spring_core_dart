# spring_security_core (planned)

Spring Security, split like Spring itself into halves that work alone:

| Package | What | Needs |
|---|---|---|
| `spring_security_core` (this file) | who is logged in, `@PreAuthorize` on beans | `spring_core_dart` only |
| [`spring_boot_starter_security`](spring_boot_starter_security.md) | incoming requests: filter chain, Basic, sessions, JWT resource server | the [web starter](spring_boot_starter_web.md) |
| [`spring_boot_starter_oauth2_client`](spring_boot_starter_oauth2_client.md) | outgoing requests: tokens for Feign, WebSocket and HTTP clients, login with PKCE in Flutter | the Feign / WebSocket starters |

A server takes the core and the security starter; a Flutter app takes the
core and the OAuth2 client; `@PreAuthorize` and the `SecurityContext` are
the same in both.

## Security context

- `Authentication` (principal, authorities, details) and
  `SecurityContextHolder`, kept in a `Zone` value — Dart's counterpart of
  Spring's `ThreadLocal`, so it survives `await`. On a server it is the
  request's user, in a Flutter app the logged-in user.
- Events: `AuthenticationSuccessEvent`, `AuthenticationFailureEvent`,
  `LogoutSuccessEvent` — e.g. a basket bean clears itself on logout with an
  `@EventListener`.
- `PasswordEncoder` (BCrypt, Argon2) in pure Dart, for the servers'
  `UserDetailsService`.

## Method security

`@PreAuthorize`, `@PostAuthorize` and `@Secured` on bean methods, on the
existing AOP proxies, with the existing SpEL: `hasRole`, `hasAuthority`,
`isAuthenticated()`, `principal`, method parameters (`#isbn`) and
`returnObject`.

```dart
@Service()
class OrderService {
  @PreAuthorize("hasRole('ADMIN') or #order.owner == principal.name")
  Future<void> cancel(Order order) async { ... }

  @PostAuthorize('returnObject.owner == principal.name')
  Future<Order> find(String id) async { ... }
}
```

A denied call throws `AccessDeniedException`; the editor checks the SpEL
like every other expression.

In a client app this is a convenience for the UI (hide a button, keep a
service from being called), not protection: the app can be taken apart
and patched. The real check is always the server's — like secrets, which
never belong in an app (see [flutter_spring](flutter_spring.md),
`--dart-define`).
