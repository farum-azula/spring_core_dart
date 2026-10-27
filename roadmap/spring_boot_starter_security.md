# spring_boot_starter_security

Spring Security for incoming requests, on the
[web starter](spring_boot_starter_web.md): a filter chain in front of the
controllers. The security context and `@PreAuthorize` come from
[spring_security_core](spring_security_core.md). Usage: the
[README](../spring_boot_starter_security/README.md); how it is shown to
be safe: [security_verification.md](security_verification.md) and
[docs/security.md](../docs/security.md).

## Done

- **Secure by default**, like Spring Boot: every request needs a login,
  form login for browsers and Basic for other clients, one user from
  `spring.security.user.*` (or a generated password), CSRF, security
  headers, logout. With a JWT decoder (`spring.security.oauth2.resourceserver.jwt.*`)
  a resource server instead.
- **`HttpSecurity`** with Spring's DSL: `authorizeHttpRequests` on the
  router's `PathPattern`s (deny when no rule matches), `httpBasic`,
  `formLogin`, `oauth2ResourceServer`, `csrf`, `cors`, `headers`,
  `sessionManagement`, `exceptionHandling`, `anonymous`, `logout`,
  `requestCache`, `securityContext`, `securityMatcher`; several chains by
  `@Order`.
- **`FilterChainProxy`** at Spring Boot's filter order, the context per
  request in its `Zone`, `StrictHttpFirewall`.
- **Sessions** on the web starter's `HttpSession`: the context stored in
  the session, a new session id at login, invalidation at logout.
- **JWT resource server**: RS/PS/ES/HS on Bouncy Castle's Dart port,
  `NimbusJwtDecoder` (JWK set URI, public key, secret key), issuer
  discovery, key rotation with a rate-limited refetch, RFC 6750 errors,
  scopes as authorities.
- **Errors** as `ProblemDetail`, with Spring's challenges and entry points
  per kind of client (browser, `XMLHttpRequest`, API).
- **Tests**: `user()`, `jwt()`, `csrf()`, `httpBasic()`, `anonymous()`
  for `MockMvc`, like `spring-security-test`.

## SSO: oauth2Login with OpenID Connect

The next step, before everything below. Today the starter is a resource
server: it accepts the tokens an identity provider issued to a client
(a single-page or Flutter app logs in, the server checks each request).
What Spring Security also does, and this starter does not yet, is the
login itself in the browser:

```dart
@Bean()
SecurityFilterChain web(HttpSecurity http) => http
    .authorizeHttpRequests((auth) => auth.anyRequest().authenticated())
    .oauth2Login()
    .logout((logout) => logout.oidcLogout())
    .build();
```

```properties
spring.security.oauth2.client.registration.keycloak.client-id=books
spring.security.oauth2.client.registration.keycloak.client-secret=${KEYCLOAK_SECRET}
spring.security.oauth2.client.registration.keycloak.scope=openid,profile,email
spring.security.oauth2.client.provider.keycloak.issuer-uri=https://sso.example.com/realms/books
```

- Client registrations and providers from `spring.security.oauth2.client.*`
  (Spring Boot's properties), the provider's endpoints from OpenID
  discovery (already there for the resource server).
- The authorization code flow: `/oauth2/authorization/{id}` redirects with
  `state`, `nonce` and PKCE; `/login/oauth2/code/{id}` checks them,
  exchanges the code, verifies the ID token (the JWT decoder of the
  resource server), loads user info; the user becomes an `OidcUser`
  (claims, `SCOPE_` and mapped authorities) in the session, with a new
  session id. A login page listing the providers.
- RP-initiated logout at the provider (`OidcClientInitiatedLogoutSuccessHandler`).
- Verified like the rest: the reference Spring application with
  `oauth2Login()` and a fake provider in the tests, attacks on `state`,
  `nonce`, `redirect_uri`, mixed-up providers and replayed codes, mutation
  testing.
- SAML 2.0 (`saml2Login()`) stays out for now: XML signatures need an XML
  parser the Dart team does not publish, another third-party package in
  the cryptography.

## Next

- **Remove `pointycastle`** (third-party, [docs/dependencies.md](../docs/dependencies.md#pointycastle-third-party-to-be-removed)):
  rewrite `lib/src/jwt/signature_primitives.dart` on a Dart team (or
  Google) package once one verifies RSA and ECDSA without third-party
  packages (Google's `webcrypto` does it on BoringSSL, but its current
  version pulls third-party build packages and needs CMake); the RFC 7515
  vectors and `test/jose_test.dart` show whether it verifies the same.
- **Remember-me** (`rememberMe()`, token-based and persistent).
- **Session registry**: the sessions of a user, a maximum per user,
  ending them all (ASVS 3.3.3 / 3.3.4).
- **Opaque tokens** (`opaqueToken()`, RFC 7662 introspection) and API keys.
- **Forwarded headers** (`X-Forwarded-Proto` / `Forwarded`) from the web
  starter, so HSTS and secure cookies work behind a proxy without
  `server.servlet.session.cookie.secure=true`.
- **A shared session store** (the web starter's), for more than one
  instance.
- **Rules per WebSocket message** (Spring's
  `AuthorizationManager<Message<?>>`); the handshake already passes the
  chain, and the connection keeps its user (`test/websocket_test.dart`).
