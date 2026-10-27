# spring_security_core

Spring Security's core for Dart: who is logged in, users and passwords,
and method security — `@PreAuthorize`, `@PostAuthorize`, `@Secured`,
`@PreFilter` and `@PostFilter` on bean methods. It works on a server (with
[`spring_boot_starter_security`](../spring_boot_starter_security/README.md),
which brings it) and in a Flutter app.

```yaml
dependencies:
  spring_security_core: ^0.3.2
```

It brings and re-exports `spring_boot_dart` and the logging starter: an
application lists it (or the security starter) alone.

## Method security

```dart
@Service()
class OrderService {
  @PreAuthorize("hasRole('ADMIN') or #order.owner == principal.username")
  Future<void> cancel(Order order) async { ... }

  @PostAuthorize('returnObject.owner == authentication.name')
  Future<Order> find(String id) => orders.load(id);

  @Secured(['ROLE_SUPPORT'])
  Future<void> refund(String id) async { ... }

  @PostFilter('filterObject.owner == authentication.name')
  Future<List<Order>> all() => orders.all();
}
```

A denied call throws `AccessDeniedException`, a call without any
authentication `AuthenticationCredentialsNotFoundException`. An `async`
method fails through its `Future`, before its body runs. The package knows
nothing of HTTP (it depends only on `spring_boot_dart` and the logging
starter): in a web application `spring_boot_starter_security` answers
these exceptions `403` and `401`.

| In the expression | Is |
|---|---|
| `hasRole('ADMIN')`, `hasAnyRole('A', 'B')` | the user has `ROLE_ADMIN` / one of the roles (the `RoleHierarchy` bean applies) |
| `hasAuthority('SCOPE_read')`, `hasAnyAuthority(...)` | the user has the authority |
| `isAuthenticated()`, `isFullyAuthenticated()`, `isAnonymous()` | how the user logged in |
| `permitAll`, `denyAll` | always / never |
| `principal`, `authentication` | the user (`principal.username`), the `Authentication` (`authentication.name`) |
| `#order`, `#p0`, `#a0` | the arguments |
| `returnObject`, `filterObject` | the result (`@PostAuthorize`), the element (`@PreFilter`, `@PostFilter`) |
| `hasPermission(#order, 'cancel')` | the `PermissionEvaluator` bean (denies without one) |
| `@shop.isOpen()` | a bean (its class `@Introspected`) |

Classes of the bean's own package used by the method (`Order`) are
readable in expressions without `@Introspected`.

Like Spring, the checks run through the bean's proxy: a call from inside
the bean (`this.cancel(...)`) is not checked. Unlike Spring, nothing has to
enable method security (`@EnableMethodSecurity`): the dependency is enough,
so an annotation is never silently ignored — and a bean with such
annotations that cannot be proxied fails the startup instead of running
unchecked. Every expression is parsed at startup. Method security runs
before every other advice: a `@Cacheable` result is never returned to a
caller who may not call the method.

## Who is logged in

```dart
final authentication = SecurityContextHolder.getContext().authentication;
```

The context is kept per `Zone` (Dart's `ThreadLocal`): on a server the
security filter chain gives each request its own, so a request sees only
its user, also after `await`. Outside every scope there is one context for
the whole program — in a Flutter app, the logged-in user:

```dart
final result = await authenticationManager.authenticate(
  UsernamePasswordAuthenticationToken.unauthenticated(name, password),
);
SecurityContextHolder.setContext(SecurityContextImpl(result));
```

`SecurityContextHolder.runWithContext(body, context)` runs work as a given
user (a job, a test).

## Users and passwords

| Type | Like Spring's |
|---|---|
| `UserDetails`, `User.withUsername(...).password(...).roles([...]).build()` | `User` |
| `UserDetailsService`, `InMemoryUserDetailsManager` | the same |
| `AuthenticationManager`, `ProviderManager`, `DaoAuthenticationProvider` | the same |
| `PasswordEncoderFactories.createDelegatingPasswordEncoder()` | the same, Argon2 by default |
| `Argon2PasswordEncoder`, `Pbkdf2PasswordEncoder`, `SCryptPasswordEncoder` | the same, Spring's formats and defaults |

With a `UserDetailsService` bean (and a `PasswordEncoder` bean, or the
delegating encoder) the auto-configuration builds the
`AuthenticationManager`.

`DaoAuthenticationProvider`, like Spring's:

- an unknown user and a wrong password fail the same way
  (`BadCredentialsException`), and an unknown user still checks the
  password against a dummy hash, so the time does not tell which;
- locked and disabled accounts fail before the password check, an expired
  password after it;
- an old hash (another `{id}`, weaker parameters) is re-hashed at the next
  login through a `UserDetailsPasswordService`.

Password hashing takes hundreds of milliseconds of CPU: here it runs on
another isolate, so a login does not stop the server's other requests.

Events: `AuthenticationSuccessEvent` and the failure events
(`AuthenticationFailureBadCredentialsEvent`, ...) — listen to them to lock
accounts or slow clients down; the packages do not count attempts.

## Tests

```dart
import 'package:spring_security_core/testing.dart';

test('admins cancel any order', () async {
  await withMockUser(() => orders.cancel(order), roles: ['ADMIN']);
});
```

`withAuthentication(body, authentication)` and `withAnonymousUser(body)`
too.

## Differences from Spring Security

- **BCrypt** (Spring's default `{bcrypt}`) is not available: there is no
  vetted Dart implementation, and cryptography is not written here by hand
  ([docs/security.md](../docs/security.md)). New hashes are `{argon2}` (which Spring
  checks too); a `{bcrypt}` hash fails with an error saying so. Argon2,
  PBKDF2 and scrypt use Bouncy Castle's Dart port (`pointycastle`, a
  third-party package [to be
  replaced](../docs/dependencies.md#pointycastle-third-party-to-be-removed)),
  like Spring's Java encoders, and their hashes move between Java and Dart
  both ways (checked against Spring Security 7.1 by
  `tool/security_reference`).
- **Method security is always on** (no `@EnableMethodSecurity`), and
  unproxied annotated beans fail the startup.
- **Beans called from expressions** (`@shop.isOpen()`) need
  `@Introspected` (no reflection).
- **Multi-factor authorities**: Spring Security 7 adds `FACTOR_PASSWORD` to
  users who logged in with a password; not here yet.

How the packages are shown to be safe: [docs/security.md](../docs/security.md) and
[roadmap/security_verification.md](../roadmap/security_verification.md).
