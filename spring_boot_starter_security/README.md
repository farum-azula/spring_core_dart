# spring_boot_starter_security

Spring Security for [`spring_boot_starter_web`](../spring_boot_starter_web/README.md),
like Spring Boot's security starter: a filter chain in front of the
controllers, configured with `HttpSecurity`, with HTTP Basic, form login,
JWT resource servers, CSRF, CORS and security headers.

```yaml
dependencies:
  spring_boot_starter_security: ^0.4.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.0
  spring_boot_starter_test: ^0.4.0     # MockMvc, springBootTest
```

It brings the web starter and [`spring_security_core`](../spring_security_core/README.md)
(users, passwords, `@PreAuthorize`): one dependency.

## Secure by default

With the starter listed and nothing configured, like Spring Boot:

- every request needs a login;
- browsers get a login page (`/login`), programs and `curl` a
  `401` with `WWW-Authenticate: Basic`;
- one user: `user`, with `spring.security.user.password` or a password
  generated at startup (logged);
- CSRF protection, security headers, logout at `POST /logout`.

```properties
spring.security.user.name=admin
spring.security.user.password=change-me
spring.security.user.roles=ADMIN
```

## Your rules

```dart
@Configuration()
class SecurityConfig {
  @Bean()
  SecurityFilterChain filterChain(HttpSecurity http) => http
      .authorizeHttpRequests((auth) => auth
          .requestMatchers('/public/**').permitAll()
          .requestMatchers('/api/admin/**').hasRole('ADMIN')
          .requestMatchersFor(HttpMethod.get, ['/api/books/**']).permitAll()
          .anyRequest().authenticated())
      .formLogin()
      .httpBasic()
      .build();

  @Bean()
  UserDetailsService users() => InMemoryUserDetailsManager([
        User.withUsername('ada').password('{argon2}...').roles(['USER']).build(),
      ]);
}
```

- **Rules** use the router's path patterns (`/api/**`, `/users/{id}`) on
  the path the router sees, so a rule covers exactly what the controllers
  under it serve. The first matching rule decides; a request no rule
  matches is **denied**. `access(...)` takes any `AuthorizationManager`
  (it gets the path variables).
- **Logins:** `httpBasic()`, `formLogin()` (the generated page, or
  `loginPage('/my-login')`), `oauth2ResourceServer((s) => s.jwt())`.
- **Sessions:** a login gives the session a new id (session fixation);
  `sessionManagement((s) => s.sessionCreationPolicy(SessionCreationPolicy.stateless))`
  for APIs.
- **CSRF:** on for every method but GET, HEAD, TRACE and OPTIONS; the token
  is in pages (`csrfTokenOf(request)`) or, for single-page apps,
  `csrf((c) => c.csrfTokenRepository(const CookieCsrfTokenRepository.withHttpOnlyFalse()))`.
  APIs authenticated by headers only: `csrf((c) => c.disable())`.
- **Several chains:** `securityMatcher('/api/**')` limits a chain; order
  the beans with `@Order`, the one matching every request last.

## JWT resource servers

```properties
spring.security.oauth2.resourceserver.jwt.issuer-uri=https://login.example.com
# or: spring.security.oauth2.resourceserver.jwt.jwk-set-uri=https://login.example.com/jwks
spring.security.oauth2.resourceserver.jwt.audiences=my-api
```

With these properties every request needs a valid bearer token (or
declare a chain with `oauth2ResourceServer((s) => s.jwt())`). Scopes
become `SCOPE_x` authorities; `@AuthenticationPrincipal() Jwt jwt` gives
the token. Verification: RS256-512, PS256-512, ES256-512 (Bouncy Castle's
Dart port `pointycastle`, a third-party package [to be
replaced](../docs/dependencies.md#pointycastle-third-party-to-be-removed)),
HS256-512 with `NimbusJwtDecoder.withSecretKey`; `alg: none`,
algorithm confusion, keys embedded in tokens, `crit`, nested and
oversized tokens are refused; `exp` / `nbf` with 60 s of skew; keys are
cached and fetched again for an unknown `kid` (at most every 30 s).

**Not yet: logging in through the provider in the browser**
(`oauth2Login()`, SSO with OpenID Connect), for pages rendered by the
server; maybe later
([roadmap](../roadmap/spring_boot_starter_security.md#sso-oauth2login-with-openid-connect)).
Today an application that logs its users in through Keycloak, Auth0, ...
gets the token on the client side (a single-page or Flutter app) and the
starter checks it on every request.

## In controllers

```dart
@GetMapping('/me')
String me(Authentication authentication) => authentication.name;

@GetMapping('/profile')
String profile(@AuthenticationPrincipal() UserDetails user) => user.username;
```

`Principal` and `@CurrentSecurityContext() SecurityContext` work too, and
`@PreAuthorize` on controllers and services (see `spring_security_core`).

## Tests

```dart
import 'package:spring_boot_starter_security/testing.dart';

await app.mockMvc
    .perform(MockRequestBuilder(HttpMethod.get, '/api/admin')
      ..with_(user('ada').roles(['ADMIN'])))
    .andExpect(status: 200);
await app.mockMvc
    .perform(MockRequestBuilder(HttpMethod.post, '/api/books')
      ..with_(user('ada'))
      ..with_(csrf()))
    .andExpect(status: 201);
```

`jwt()`, `httpBasic(user, password)`, `anonymous()`, `authentication(...)`
too, like `spring-security-test`.

## The firewall

Before any rule, requests whose path could be read two ways are refused
with `400`: `;`, encoded `/` `\` `%` `.`, `//`, `.` and `..` segments,
control characters, `TRACE`, and request targets Dart would read as a host
(`//host/path`). Like Spring's `StrictHttpFirewall`.

## Differences from Spring Security

Checked by sending the same requests to this starter and to Spring
Security 7.1 ([tool/security_reference](../tool/security_reference/README.md),
`test/differential_test.dart`); what differs on purpose:

- **Errors are not re-dispatched to `/error`.** Spring Boot sends a 400
  or 403 through the security chain again for `/error`, where the request
  is anonymous: a client gets `401` instead, and after a form login
  without a CSRF token the user lands on `/error`. Here the 400 or 403 is
  the answer.
- **dart:io normalizes paths** (`..`, `%2e%2e`, `\`) before the
  application (RFC 3986). The rules see the normalized path, as the router
  does; Spring's firewall refuses the raw path instead.
- **CORS is on by default**, with the router's configuration (the
  `CorsConfigurationSource` bean and `@CrossOrigin`, also for pre-flights);
  Spring needs `.cors()` and, with a `CorsConfigurationSource` bean,
  ignores `@CrossOrigin` in pre-flights.
- **The session cookie** is `SameSite=Lax` by default
  (`server.servlet.session.cookie.same-site`), and sessions are limited
  (`server.servlet.session.max-sessions`, 10 000).
- **Errors are `ProblemDetail`** (`application/problem+json`), never the
  exception's message.
- **Two `Authorization` headers** are refused (Spring reads the first).
- **A failed Basic login creates no session** (Spring's creates one
  through `/error`).

How the packages are shown to be safe: [docs/security.md](../docs/security.md).
