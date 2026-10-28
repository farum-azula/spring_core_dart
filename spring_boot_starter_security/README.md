# spring_boot_starter_security

Security for web applications built with
[`spring_boot_starter_web`](../spring_boot_starter_web/README.md): a filter
chain in front of the controllers decides who may call which endpoint,
logs users in, and protects browser sessions.

A server with any endpoint that is not public needs this: it must know who
is calling (a login form, HTTP Basic, a token from an identity provider),
refuse what that user may not do, keep a page on another site from using
the user's session (CSRF), and send the headers that keep browsers safe.
Writing those checks by hand in every controller is easy to get wrong.
With this starter they live in one place, run before any controller, and
are on as soon as the dependency is listed.

```yaml
dependencies:
  spring_boot_starter_security: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2
  spring_boot_starter_test: ^0.4.2     # MockMvc, springBootTest
```

It brings the web starter and
[`spring_security_core`](../spring_security_core/README.md) (users,
password hashes, `@PreAuthorize` on bean methods), so this one dependency
is enough.

*In the guides:* [server, 4. Security](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#4-security).

## Secure by default

With the starter listed and nothing configured, as in Spring Boot:

- every request needs a login;
- a browser asking for a page is redirected to a generated login page,
  `/login`; programs and `curl` get a `401` with `WWW-Authenticate:
  Basic`; scripts (`X-Requested-With: XMLHttpRequest`) get a plain `401`,
  so no browser password dialog appears;
- there is one user, `user`, whose password is
  `spring.security.user.password` or, when that is not set, a random one
  logged at startup (for development only);
- CSRF protection, security headers and logout at `POST /logout` are on.

```properties
# A development user instead of the generated password.
spring.security.user.name=admin
spring.security.user.password=change-me
spring.security.user.roles=ADMIN
```

The default user disappears as soon as the application has its own users:
a `UserDetailsService`, an `AuthenticationProvider`, an
`AuthenticationManager` or a `JwtDecoder` bean, or the JWT properties
below. Its password is stored as `{noop}` unless it already starts with an
`{id}`. With a `PasswordEncoder` bean it is stored as given, so it must
already be encoded, and a generated password cannot log in.

| Property | Default |
|---|---|
| `spring.security.user.name` | `user` |
| `spring.security.user.password` | a random one, logged at startup |
| `spring.security.user.roles` | none |
| `spring.security.filter.order` | `-100`: the place of the security filter among the web filters |
| `spring.security.oauth2.resourceserver.jwt.*` | see [JWT resource servers](#jwt-resource-servers) |

## Your rules

Declare a `SecurityFilterChain` bean to replace the default chain. Each
bean method that takes an `HttpSecurity` gets a fresh builder:

```dart
@Configuration()
class SecurityConfig {
  @Bean()
  SecurityFilterChain filterChain(HttpSecurity http) => http
      .authorizeHttpRequests((auth) => auth
          .requestMatchers('/public/**').permitAll()
          .requestMatchers('/api/admin/**').hasRole('ADMIN')
          // Anyone may read the catalogue; changing it needs a login.
          .requestMatchersFor(HttpMethod.get, ['/api/books/**']).permitAll()
          .anyRequest().authenticated())
      .formLogin()
      .httpBasic()
      .build();

  // The users and their hashed passwords.
  @Bean()
  UserDetailsService users() => InMemoryUserDetailsManager([
        User.withUsername('ada').password('{argon2}...').roles(['USER']).build(),
      ]);
}
```

Spring (Java):

```java
@Bean
SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
  return http
      .authorizeHttpRequests(auth -> auth
          .requestMatchers("/public/**").permitAll()
          .requestMatchers("/api/admin/**").hasRole("ADMIN")
          .requestMatchers(HttpMethod.GET, "/api/books/**").permitAll()
          .anyRequest().authenticated())
      .formLogin(Customizer.withDefaults())
      .httpBasic(Customizer.withDefaults())
      .build();
}
```

- **Rules** use the router's path patterns (`/api/**`, `/users/{id}`) on
  the path the router sees, so a rule covers exactly what the controllers
  under it serve. Paths are case-sensitive and a trailing slash counts:
  protect `/admin` and `/admin/**` when both exist. The first matching
  rule decides, and a request that no rule matches is **denied**. Besides
  `permitAll`, `denyAll`, `authenticated`, `fullyAuthenticated`,
  `anonymous`, `hasRole`, `hasAnyRole`, `hasAuthority` and
  `hasAnyAuthority`, `access(...)` takes any `AuthorizationManager`; it
  receives the path variables of the rule's pattern
  (`context.variables['id']`), for rules such as "users may only read
  their own profile".
- **A chain without `authorizeHttpRequests`** lets every request through,
  with a warning in the log.
- **Logins:** `httpBasic()`; `formLogin()`, with the generated page or
  your own (`formLogin((f) => f.loginPage('/sign-in'))`, a page every user
  must be allowed to reach); `oauth2ResourceServer((s) => s.jwt())` for
  bearer tokens. A form or Basic login without any user in the
  application fails the startup.
- **Sessions:** a login gives the session a new id, so an id planted
  before the login is worthless (session fixation). APIs whose clients
  send credentials or a token with every request use no session at all:
  `sessionManagement((s) =>
  s.sessionCreationPolicy(SessionCreationPolicy.stateless))`.
- **Several chains:** `securityMatcher('/api/**')` limits a chain to some
  paths; order the beans with `@Order`. The first chain whose matcher fits
  handles the request. A chain that matches every request must come last,
  or the startup fails. A request that no chain matches goes on without
  any security filter, as in Spring, so keep a last chain without
  `securityMatcher`.
- **Headers:** `nosniff`, no caching, `X-Frame-Options: DENY` and, over
  HTTPS, HSTS are sent by default. `headers((h) => ...)` changes them:
  `contentSecurityPolicy(...)`, `referrerPolicy(...)`,
  `frameOptions(XFrameOptionsMode.sameOrigin)`, `addHeaderWriter(...)`.
- **CORS** is on, with the router's configuration (the
  `CorsConfigurationSource` bean and `@CrossOrigin`), pre-flight requests
  included; `cors((c) => c.configurationSource(...))` takes other rules.
- **Your own filters:** `addFilterBefore`, `addFilterAfter` and
  `addFilterAt` place a `WebFilter` relative to a built-in filter class
  (`addFilterAfter(MyFilter(), CsrfFilter)`).

## CSRF protection

Cross-site request forgery is a page on another site making the user's
browser send a request to your application, with the user's cookies. CSRF
protection makes every state-changing request carry a token that such a
page cannot know.

What is checked: every method except GET, HEAD, TRACE and OPTIONS needs
the token, in the header `X-CSRF-TOKEN` or the form field `_csrf` (by
default the token is kept in the session). What happens on failure:

- no token stored for the client yet (a first request, an expired
  session): `403`, and a new token is created for the next try;
- a token missing from the request, or not equal to the stored one
  (compared in constant time): `403`.

The `403` comes also for anonymous users; they are not asked to log in. A
login form posted without the token is refused too.

**Pages rendered by the server** put the token in their forms as a hidden
field. `csrfTokenOf(request)` gives it (and creates it when the client has
none):

```dart
@GetMapping('/form')
String form(ServerHttpRequest request) {
  final csrf = csrfTokenOf(request)!;
  return '<input type="hidden" name="${csrf.parameterName}" value="${csrf.token}">';
}
```

By default each page gets the token masked with fresh random bytes
(`XorCsrfTokenRequestAttributeHandler`), so the bytes are never the same
twice and cannot be guessed from the size of compressed responses
(BREACH).

**Single-page and Flutter web apps** render no forms: they read the token
from a cookie, `XSRF-TOKEN`, and send it back in the `X-XSRF-TOKEN`
header. That needs two settings together: a cookie that scripts can read,
and a handler that accepts the raw cookie value. With the cookie alone,
the default handler expects a masked token, and the raw value the script
sends is refused with `403`.

```dart
.csrf((c) => c
    .csrfTokenRepository(const CookieCsrfTokenRepository.withHttpOnlyFalse())
    // The script sends the cookie value as it is, not a masked token.
    .csrfTokenRequestHandler(const CsrfTokenRequestAttributeHandler()))
```

The token is created only when something reads it or a check needs it.
For the client to have the cookie before its first `POST`, add a filter
that reads the token on every request, as the server guide does:

```dart
// Reading the token writes the XSRF-TOKEN cookie when it is new.
final class CsrfCookieFilter extends OncePerRequestFilter {
  @override
  Future<void> doFilterInternal(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    csrfTokenOf(request);
    return chain.doFilter(request, response);
  }
}

// In the chain:
.addFilterAfter(CsrfCookieFilter(), CsrfFilter)
```

Spring (Java):

```java
http.csrf(c -> c
    .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
    .csrfTokenRequestHandler(new CsrfTokenRequestAttributeHandler()));
```

**APIs authenticated only by headers** (Basic, bearer tokens), never by
cookies, can turn it off: `csrf((c) => c.disable())`. A browser does not
send those headers by itself, so another site cannot forge such a
request. `csrf((c) => c.ignoringRequestMatchers('/webhooks/**'))` exempts
single paths, such as a webhook a third party posts to.

## JWT resource servers

An API whose users log in at an identity provider (Keycloak, Auth0, ...)
receives a JSON Web Token with every request and must check it. Set the
provider and the API's audience:

```properties
spring.security.oauth2.resourceserver.jwt.issuer-uri=https://login.example.com
# or: spring.security.oauth2.resourceserver.jwt.jwk-set-uri=https://login.example.com/jwks
spring.security.oauth2.resourceserver.jwt.audiences=my-api
```

With `issuer-uri` or `jwk-set-uri` set, the default chain needs a valid
bearer token on every request, and there is no default user. Or declare a
chain with `oauth2ResourceServer((s) => s.jwt())`, usually with a
`stateless` session policy.

| Property | Default |
|---|---|
| `spring.security.oauth2.resourceserver.jwt.issuer-uri` | none; the keys come from the issuer's metadata |
| `spring.security.oauth2.resourceserver.jwt.jwk-set-uri` | none; the URL of the provider's public keys |
| `spring.security.oauth2.resourceserver.jwt.jws-algorithms` | `RS256`; used with `jwk-set-uri` only |
| `spring.security.oauth2.resourceserver.jwt.audiences` | none: no audience check |
| `spring.security.oauth2.resourceserver.jwt.authority-prefix` | `SCOPE_` |
| `spring.security.oauth2.resourceserver.jwt.authorities-claim-name` | `scope`, else `scp` |
| `spring.security.oauth2.resourceserver.jwt.authorities-claim-delimiter` | a space |
| `spring.security.oauth2.resourceserver.jwt.principal-claim-name` | `sub` |

With `jwk-set-uri`, the issuer (when `issuer-uri` is set too) and the
audiences are checked. With `issuer-uri` alone, `jws-algorithms` is not
used: the algorithms are those the provider's keys allow.

What is checked, in order; any failure is a `401` with `WWW-Authenticate:
Bearer error="invalid_token"`:

1. The token is parsed strictly: never `alg: none`, no `crit` header, no
   nested or encrypted tokens, at most 64 KiB.
2. Its `alg` must be an accepted one and fit the key, so an RSA public key
   is never used as an HMAC secret (algorithm confusion). Supported:
   RS256 to RS512, PS256 to PS512, ES256 to ES512, and HS256 to HS512 with
   `NimbusJwtDecoder.withSecretKey`.
3. The signature is checked with the key of the token's `kid`. Keys named
   in the token itself (`jku`, `jwk`, `x5u`) are ignored: a token cannot
   bring its own key.
4. `exp` and `nbf` are checked with 60 seconds of clock skew, then the
   issuer and the audiences as configured.

The provider's keys are cached for 5 minutes. A token with an unknown
`kid` fetches them again, at most once every 30 seconds, so made-up ids
cannot flood the provider. A valid token without the rights a rule needs
gets `403` with `error="insufficient_scope"`. Bearer tokens in the query
string (`access_token=`) are ignored unless the
`DefaultBearerTokenResolver` allows them.

Scopes become `SCOPE_x` authorities, so a rule reads
`hasAuthority('SCOPE_orders.read')`. `@AuthenticationPrincipal() Jwt jwt`
gives the token to a controller, and method security expressions can read
`principal.claims['tenant']`.

The signatures are verified with Bouncy Castle's Dart port
(`pointycastle`), a third-party package
[to be replaced](../docs/dependencies.md#pointycastle-third-party-to-be-removed).

**Not yet: logging in through the provider in the browser**
(`oauth2Login()`, SSO with OpenID Connect), for pages rendered by the
server; maybe later
([roadmap](../roadmap/spring_boot_starter_security.md#sso-oauth2login-with-openid-connect)).
Today an application that logs its users in through Keycloak, Auth0, ...
gets the token on the client side (a single-page or Flutter app), and the
starter checks it on every request.

## In controllers

A controller method can ask for the current user:

```dart
@GetMapping('/me')
String me(Authentication authentication) => authentication.name;

@GetMapping('/profile')
String profile(@AuthenticationPrincipal() UserDetails user) => user.username;
```

A `Principal` parameter and `@CurrentSecurityContext() SecurityContext`
work too. `@PreAuthorize` and the other method security annotations of
[`spring_security_core`](../spring_security_core/README.md) work on
controllers and services. A denied call becomes a `403`; a caller who is
not logged in is asked to log in instead (a `401`, or the login page for a
browser).

## Tests

`package:spring_boot_starter_security/testing.dart` makes `MockMvc`
requests as a given user, without a real login:

```dart
import 'package:spring_boot_starter_security/testing.dart';

// An admin may open the admin API.
await app.mockMvc
    .perform(MockRequestBuilder(HttpMethod.get, '/api/admin')
      ..with_(user('ada').roles(['ADMIN'])))
    .andExpect(status: 200);

// A POST needs a CSRF token as well as a user.
await app.mockMvc
    .perform(MockRequestBuilder(HttpMethod.post, '/api/books')
      ..with_(user('ada'))
      ..with_(csrf()))
    .andExpect(status: 201);
```

`jwt()`, `httpBasic(user, password)`, `anonymous()`, `userDetails(...)`
and `authentication(...)` exist too, as in `spring-security-test`. The
library also re-exports `withMockUser` and its siblings from
`spring_security_core`.

## The firewall

Before any rule is looked at, requests whose path could be read two ways
are refused with `400`. Otherwise an attacker who makes a rule read
`/admin` differently from the router could reach a protected controller
through an unprotected rule. Refused:

- in the path: `;` and `%3B`, an encoded `/` (`%2F`), `\` and `%5C`, an
  encoded `%` (`%25`) or `.` (`%2E`), `//`, `.` and `..` segments, spaces,
  control and non-ASCII characters, `%00`, line separators;
- a request target that Dart would read as a host (`//host/path`);
- methods other than DELETE, GET, HEAD, OPTIONS, PATCH, POST and PUT
  (TRACE echoes the request, cookies included);
- header names that are not printable ASCII, and header values with
  control characters (a tab is allowed).

A `StrictHttpFirewall` bean with one `allow...` option turned on relaxes a
single rule, for an application that really needs such paths
(`StrictHttpFirewall(allowUrlEncodedSlash: true)`).

## Size limits

So that one request cannot make the server do unbounded work:

- an `Authorization: Basic` header longer than 8 192 characters, or sent
  twice, fails as bad credentials;
- a bearer token over 64 KiB is refused;
- the login filter reads a form body of at most 64 KB. When the CSRF
  token comes as a form field, though, the CSRF filter has already read
  the form with the web starter's 1 MiB limit, and the login filter uses
  those fields;
- sessions are limited by `server.servlet.session.max-sessions` (10 000
  by default; the least recently used are dropped);
- password hashing runs only for requests that carry credentials.

## Behaviour to know

As the code behaves today:

- `headers((h) => h.defaultsDisabled())` makes later `frameOptions`,
  `httpStrictTransportSecurity`, `contentTypeOptions`, `xssProtection`
  and `cacheControl` calls do nothing; only `contentSecurityPolicy`,
  `referrerPolicy` and `addHeaderWriter` still add headers (Spring adds
  the headers configured after it).
- Users given to a chain with `HttpSecurity.userDetailsService(...)` never
  get their old password hashes upgraded at login; users of a
  `UserDetailsService` bean do.
- With only `issuer-uri`, `jws-algorithms` is ignored (see above).

## Differences from Spring Security

Checked by sending the same requests to this starter and to Spring
Security 7.1 ([tool/security_reference](../tool/security_reference/README.md),
`test/differential_test.dart`). What differs on purpose:

- **Errors are not re-dispatched to `/error`.** Spring Boot sends a 400 or
  403 through the security chain again for `/error`, where the request is
  anonymous: a client gets `401` instead, and after a form login without
  a CSRF token the user lands on `/error`. Here the 400 or 403 is the
  answer.
- **dart:io normalizes paths** (`..`, `%2e%2e`, `\`) before the
  application (RFC 3986). The rules see the normalized path, as the router
  does; Spring's firewall refuses the raw path instead.
- **CORS is on by default**, with the router's configuration (the
  `CorsConfigurationSource` bean and `@CrossOrigin`, also for
  pre-flights). Spring needs `.cors()` and, with a
  `CorsConfigurationSource` bean, ignores `@CrossOrigin` in pre-flights.
- **The session cookie** is `SameSite=Lax` by default
  (`server.servlet.session.cookie.same-site`), and sessions are limited
  (`server.servlet.session.max-sessions`, 10 000).
- **Errors are `ProblemDetail`** (`application/problem+json`), never the
  exception's message.
- **Two `Authorization` headers** are refused (Spring reads the first).
- **A failed Basic login creates no session** (Spring's creates one
  through `/error`).
- **`SessionCreationPolicy`** has `ifRequired` (the default) and
  `stateless` only, not `always` and `never`.

How the packages are shown to be safe: [docs/security.md](../docs/security.md).
