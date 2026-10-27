# spring_security_core

Spring Security, split like Spring itself into halves that work alone:

| Package | What | Status |
|---|---|---|
| `spring_security_core` (this file) | who is logged in, users and passwords, `@PreAuthorize` on beans | done ([README](../spring_security_core/README.md)) |
| [`spring_boot_starter_security`](spring_boot_starter_security.md) | incoming requests: filter chain, Basic, form login, sessions, JWT resource server | done |
| [`spring_boot_starter_oauth2_client`](spring_boot_starter_oauth2_client.md) | outgoing requests: tokens for Feign, WebSocket and HTTP clients, login with PKCE in Flutter | planned |

A server takes the security starter (it brings the core); a Flutter app
takes the core and, later, the OAuth2 client; `@PreAuthorize` and the
`SecurityContext` are the same in both. How it is shown to be safe:
[security_verification.md](security_verification.md), [docs/security.md](../docs/security.md).

## Done

- `Authentication`, `SecurityContextHolder` kept per `Zone` (Dart's
  `ThreadLocal`, survives `await`) with one global context outside every
  scope (the logged-in user of a Flutter app).
- Users: `UserDetails`, `User.withUsername`, `UserDetailsService`,
  `InMemoryUserDetailsManager`, account status checks.
- `AuthenticationManager`, `ProviderManager`, `DaoAuthenticationProvider`
  (no user enumeration by message or timing, re-hashing of old hashes,
  hashing on another isolate), events (success, failures, logout).
- Password encoders on Bouncy Castle's Dart port (`pointycastle`): Argon2
  (default), PBKDF2, scrypt, delegating; Spring's formats, hashes checked
  both ways against Spring Security 7.1.
- Method security: `@PreAuthorize`, `@PostAuthorize`, `@Secured`,
  `@PreFilter`, `@PostFilter` on the AOP proxies with SpEL (`hasRole`,
  `principal`, `#arg`, `returnObject`, `hasPermission`, `@bean`), always
  on, expressions parsed at startup, unproxied annotated beans fail the
  startup, run before `@Cacheable`. `RoleHierarchy`,
  `GrantedAuthorityDefaults`.
- Tests: `withMockUser`, `withAuthentication`, `withAnonymousUser`.

In a client app method security is a convenience for the UI (hide a
button, keep a service from being called), not protection: the app can be
taken apart and patched. The real check is always the server's — like
secrets, which never belong in an app (see
[spring_boot_starter_flutter](spring_boot_starter_flutter.md),
`--dart-define`).

## Next

- **Remove `pointycastle`** (third-party, [docs/dependencies.md](../docs/dependencies.md#pointycastle-third-party-to-be-removed)):
  rewrite `lib/src/crypto/kdf_primitives.dart` on a Dart team (or Google)
  package once one has Argon2, PBKDF2 and scrypt; the hashes of
  `test/vectors/` (written by Spring) show whether it computes the same.
- **BCrypt** (`{bcrypt}`, Spring's default): only when a vetted Dart
  implementation exists; never written here by hand.
- **Multi-factor authentication** (Spring Security 7's `FACTOR_*`
  authorities, `@EnableMultiFactorAuthentication`).
- **The editor:** the language server checks `@PreAuthorize` expressions
  like other SpEL (names of arguments, beans).
- **Flutter:** the logged-in user as a listenable for widgets, logout
  clearing beans (`LogoutSuccessEvent`), with the OAuth2 client.
