# spring_security_core

The part of security that does not depend on HTTP: who is logged in,
users and their password hashes, and access rules on bean methods
(`@PreAuthorize`, `@PostAuthorize`, `@Secured`, `@PreFilter` and
`@PostFilter`).

Use it when an application must know its user and check what that user
may do, wherever the call comes from: a web request, a scheduled job, a
button in a Flutter app. The rules sit on the methods they protect, in one
line each, instead of `if` checks spread over the code. Passwords are
stored as slow, salted hashes in the same formats as Spring Security, so a
Dart and a Java service can share a user table.

On a server, list
[`spring_boot_starter_security`](../spring_boot_starter_security/README.md)
instead: it brings this package and adds the filter chain that logs in
the user of each request. In a Flutter app, or a program without HTTP,
this package alone is enough.

```yaml
dependencies:
  spring_security_core: ^0.4.2
```

It brings and re-exports `spring_boot_dart` and the logging starter, so an
application lists it (or the security starter) alone. Method security
needs the proxies that `spring_core_dart_generator` writes, so the
application also has the generator and `build_runner` as dev
dependencies.

*In the guides:* [server, 4. Security](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#4-security), [app, 7. Login & roles](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#7-login--roles).

## Method security

An annotation on a bean method says who may call it. The check runs
before (or after) every call, whatever the caller is:

```dart
@Service()
class OrderService {
  // Admins cancel any order, other users only their own.
  @PreAuthorize("hasRole('ADMIN') or #order.owner == principal.username")
  Future<void> cancel(Order order) async { ... }

  // Whether the caller may see the order depends on what was loaded.
  @PostAuthorize('returnObject.owner == authentication.name')
  Future<Order> find(String id) => orders.load(id);

  // A plain list of roles is the whole rule.
  @Secured(['ROLE_SUPPORT'])
  Future<void> refund(String id) async { ... }

  // Each user gets only their own orders out of the list.
  @PostFilter('filterObject.owner == authentication.name')
  Future<List<Order>> all() => orders.all();
}
```

Spring (Java):

```java
@PreAuthorize("hasRole('ADMIN') or #order.owner == principal.username")
public void cancel(Order order) { ... }
```

| Annotation | What it does |
|---|---|
| `@PreAuthorize(expression)` | runs the method only when the expression is `true` |
| `@PostAuthorize(expression)` | hands the result (`returnObject`) to the caller only when the expression is `true`; the method has already run, so use it for reads, not changes |
| `@Secured([...])` | runs the method only when the user has one of the listed authorities, written in full (`ROLE_ADMIN`) |
| `@PreFilter(expression)` | removes from a collection argument the elements (`filterObject`) for which the expression is `false`; with several collection parameters, `filterTarget` names one |
| `@PostFilter(expression)` | removes from the returned `List`, `Set` or `Map` the elements for which the expression is `false`; any other result type fails the call |

What happens on a call:

- no authentication in the security context at all: the call fails with
  `AuthenticationCredentialsNotFoundException`, before any expression
  runs;
- an expression that says no: `AccessDeniedException`;
- an expression that fails or does not give a `bool`: `ArgumentError`, and
  the method does not run.

A synchronous method throws; an `async` method returns a failed `Future`,
and with `@PreAuthorize` its body never runs. This package knows nothing
of HTTP: in a web application, `spring_boot_starter_security` turns these
exceptions into `401` and `403` answers.

What an expression can use:

| In the expression | Is |
|---|---|
| `hasRole('ADMIN')`, `hasAnyRole('A', 'B')` | the user has `ROLE_ADMIN` / one of the roles; a `RoleHierarchy` bean applies |
| `hasAuthority('SCOPE_read')`, `hasAnyAuthority(...)` | the user has the authority |
| `isAuthenticated()`, `isFullyAuthenticated()`, `isAnonymous()` | how the user logged in |
| `permitAll`, `denyAll` | always / never |
| `principal`, `authentication` | the user (`principal.username`), the `Authentication` (`authentication.name`) |
| `#order`, `#p0`, `#a0` | the arguments, by name and by position |
| `returnObject`, `filterObject` | the result (`@PostAuthorize`), the element (`@PreFilter`, `@PostFilter`) |
| `hasPermission(#order, 'cancel')` | asks the `PermissionEvaluator` bean; denies when there is none |
| `@shop.isOpen()` | a bean, whose class must be `@Introspected` |

Classes of the bean's own package used by the method (`Order` above) are
readable in expressions without `@Introspected`. The password of a `User`
and the credentials of an `Authentication` are never readable.

How the checks run:

- **Through the bean's proxy**, as in Spring: a call from inside the bean
  (`this.cancel(...)`) is not checked.
- **Always on.** Spring needs `@EnableMethodSecurity`; here the dependency
  is enough, so an annotation is never silently ignored. A bean with such
  annotations that cannot be proxied (a `final` class, for example) fails
  the startup instead of running unchecked.
- **Parsed at startup.** A typo in an expression stops the application
  instead of opening the method.
- **Before every other advice.** `@Cacheable`, `@Validated` and the
  application's aspects run only for an authorized call, so a cached result
  is never returned to a caller who may not call the method.
- **On the class**, an annotation applies to every method without one of
  its own (not to getters and setters).

`hasRole` adds the prefix `ROLE_`. For authorities named without it (plain
`ADMIN` from a directory), declare a `GrantedAuthorityDefaults('')` bean.

## Who is logged in

Every check reads the user from the current security context, so code
never passes the user around:

```dart
final authentication = SecurityContextHolder.getContext().authentication;
```

The context is kept per `Zone`, Dart's counterpart of Java's thread-local
storage. On a server the security starter gives each request its own
scope, so a request sees only its user, also after an `await`. Outside
every scope there is one context for the whole program: in a Flutter app,
that is the logged-in user.

```dart
// A Flutter app logs the user in and keeps the result.
final result = await authenticationManager.authenticate(
  UsernamePasswordAuthenticationToken.unauthenticated(name, password),
);
SecurityContextHolder.setContext(SecurityContextImpl(result));
```

`SecurityContextHolder.runWithContext(body, context)` runs work as a given
user, in a scope of its own: a nightly job that calls secured services as
a system user, or a test. The context stays current in `body` and in
everything it starts, and is gone afterwards.

The strategy behind the holder can be replaced
(`setContextHolderStrategy`), but rarely needs to be. Note that with
`GlobalSecurityContextHolderStrategy`, `runWithContext` puts the previous
context back as soon as `body` returns, so for an `async` body at its
first `await`.

## Users and passwords

| Type | What it is | Spring |
|---|---|---|
| `UserDetails`, `User.withUsername(...).password(...).roles([...]).build()` | a user: name, password hash, authorities, account flags | `User` |
| `UserDetailsService`, `InMemoryUserDetailsManager` | loads a user by name; you write one over your user table | the same |
| `AuthenticationManager`, `ProviderManager`, `DaoAuthenticationProvider` | checks a login and returns the authenticated user | the same |
| `PasswordEncoderFactories.createDelegatingPasswordEncoder()` | the recommended encoder: writes `{argon2}` hashes, reads every supported one | the same, with BCrypt as default there |
| `Argon2PasswordEncoder`, `Pbkdf2PasswordEncoder`, `SCryptPasswordEncoder` | one algorithm each, Spring's formats and defaults | the same |

With a `UserDetailsService` bean, the auto-configuration builds the
`AuthenticationManager`: a `DaoAuthenticationProvider` over it, with the
`PasswordEncoder` bean or, without one, the delegating encoder. With
`AuthenticationProvider` beans, it is a `ProviderManager` over all of
them. An application that declares its own `AuthenticationManager` keeps
it.

```dart
// Registration: store the hash, never the password.
final encoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
final stored = encoder.encode(form.password); // {argon2}$argon2id$v=19$...
```

What `DaoAuthenticationProvider` guarantees, as Spring's does:

- an unknown user and a wrong password fail the same way
  (`BadCredentialsException`), and an unknown user still checks the
  password against a dummy hash, so neither the answer nor its time tells
  whether the user exists;
- locked, disabled and expired accounts fail before the password check,
  an expired password after it;
- a stored hash that no encoder understands (such as `{bcrypt}`) fails as
  a wrong password, with a warning in the log; it never logs in;
- a hash made with older settings (another `{id}`, weaker parameters) is
  re-hashed after a successful login and stored through a
  `UserDetailsPasswordService` bean, or the user service itself when it is
  one.

Hashing a password takes hundreds of milliseconds of CPU. On the Dart VM
the login's password check runs on another isolate, so a login does not
stop the server's other requests; on the web it runs in place. The
re-hash of an upgraded password runs on the main isolate.

**Events:** every login publishes `AuthenticationSuccessEvent` or a
failure event (`AuthenticationFailureBadCredentialsEvent`,
`AuthenticationFailureLockedEvent`, ...) as an application event. Listen
to them to lock accounts or slow clients down: the packages do not count
attempts themselves.

## Tests

`package:spring_security_core/testing.dart` runs code as a given user, in
a scope of its own, so tests running at the same time do not see each
other's user:

```dart
import 'package:spring_security_core/testing.dart';

test('admins cancel any order', () async {
  await withMockUser(() => orders.cancel(order), roles: ['ADMIN']);
});

test('users cannot cancel orders of others', () async {
  await expectLater(
    withMockUser(() => orders.cancel(othersOrder)), // user, ROLE_USER
    throwsA(isA<AccessDeniedException>()),
  );
});
```

`withMockUser` takes `username`, `roles` or `authorities`;
`withAuthentication(body, authentication)` takes any `Authentication`
(your own `UserDetails`, a JWT); `withAnonymousUser(body)` runs as the
anonymous user a web request without a login has. Spring's counterparts
are the `@WithMockUser`, `@WithSecurityContext` and `@WithAnonymousUser`
annotations.

## Differences from Spring Security

- **BCrypt** (Spring's default `{bcrypt}`) is not available: there is no
  vetted Dart implementation, and cryptography is not written here by
  hand ([docs/security.md](../docs/security.md)). New hashes are
  `{argon2}`, which Spring checks too; a `{bcrypt}` hash fails with an
  error saying so.
- **Hashes move between Java and Dart.** Argon2, PBKDF2 and scrypt use
  Bouncy Castle's Dart port (`pointycastle`, a third-party package
  [to be replaced](../docs/dependencies.md#pointycastle-third-party-to-be-removed)),
  like Spring's Java encoders, and their hashes verify both ways (checked
  against Spring Security 7.1 by `tool/security_reference`). One
  exception: in the delegating encoder, `{pbkdf2}` means the
  `@SpringSecurity_v5_8` settings here, while Spring 6 and later read it
  with the older v5_5 settings. Java hashes stored as `{pbkdf2}` may
  therefore not verify here; `{pbkdf2@SpringSecurity_v5_8}` hashes do.
- **Method security is always on** (no `@EnableMethodSecurity`), and
  unproxied annotated beans fail the startup.
- **Beans called from expressions** (`@shop.isOpen()`) need
  `@Introspected`, since there is no reflection.
- **The context is kept per `Zone`**, not per thread.
- **Multi-factor authorities**: Spring Security 7 adds `FACTOR_PASSWORD`
  to users who logged in with a password; not here yet.

How the packages are shown to be safe: [docs/security.md](../docs/security.md) and
[roadmap/security_verification.md](../roadmap/security_verification.md).
