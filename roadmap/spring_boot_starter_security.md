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
  a resource server instead; with OAuth2 client registrations,
  `oauth2Login()`.
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

Done (October 2026), on [spring_boot_starter_oauth2_client](spring_boot_starter_oauth2_client.md)
(part 2 there; usage in the
[README](../spring_boot_starter_security/README.md#single-sign-on-oauth2login)):

- `HttpSecurity.oauth2Login()` with Spring's configurer: `loginPage`,
  `defaultSuccessUrl` (a path or an absolute URL, such as a Flutter web
  app's origin), `successHandler`, `failureHandler`, `failureUrl`,
  `authorizationEndpoint`, `redirectionEndpoint`, `tokenEndpoint`,
  `userInfoEndpoint` (user services, authorities mapper), the
  registration and authorized client repositories, and `idTokenDecoder`.
- `OAuth2AuthorizationRequestRedirectFilter` and
  `DefaultOAuth2AuthorizationRequestResolver` (`state`, `nonce`, PKCE
  `S256` always, `{baseUrl}` from the request and the context path),
  `HttpSessionOAuth2AuthorizationRequestRepository` (one request per
  session, by its `state`, removed when used).
- `OAuth2LoginAuthenticationFilter` with
  `OAuth2LoginAuthenticationProvider` and
  `OidcAuthorizationCodeAuthenticationProvider`: the callback must come to
  its login's redirect URI, the RFC 9207 `iss`, the code exchanged with
  the verifier, the ID token's signature checked with the provider's JWK
  Set (`OidcIdTokenDecoderFactory` on the resource server's
  `NimbusJwtDecoder`), the claims and the `nonce`, the user info's `sub`,
  the authorities mapped, a new session id, the authorized client saved
  (`AuthenticatedPrincipalOAuth2AuthorizedClientRepository`,
  `HttpSessionOAuth2AuthorizedClientRepository`).
- The generated login page lists the registrations (escaped); with one
  registration and no form login the entry point goes straight to it.
- `OidcClientInitiatedLogoutSuccessHandler` (`end_session_endpoint`,
  `id_token_hint`, `post_logout_redirect_uri` templates).
- Auto-configuration: with registrations and no `SecurityFilterChain`
  bean, the default chain has `oauth2Login()` (and bearer tokens with a
  `JwtDecoder`), no default user, an `OAuth2AuthorizedClientRepository`
  bean; the `oidcIdTokenDecoder` bean (signatures checked) is registered
  before the OAuth2 client starter's, so refreshed ID tokens are checked
  the same way.
- The security starter depends on the OAuth2 client and re-exports it;
  `OAuth2Error`, `OAuth2AuthenticationException` and the token validators
  are the client's (one type for the resource server and the login).
- Attacks as tests: [docs/security.md](../docs/security.md#how-it-is-shown).

Left:

- ~~The differential test of `oauth2Login()` against Spring Security
  (`tool/security_reference`) and mutation testing of the new code
  ([security_verification.md](security_verification.md)).~~ Done
  (October 2026); not measured yet: the `oauth2Login()` parts of
  `http_security.dart`.
- The example: `example/server_guide` logging in with Keycloak (part
  "Example" of the OAuth2 client's roadmap).
- `oauth2Client()` (the authorization code grant without a login,
  `OAuth2AuthorizationCodeGrantFilter`), `response_mode=form_post`, OIDC
  back-channel logout, `logout((l) => l.oidcLogout())`.
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
- **DPoP-bound access tokens** (RFC 9449): the resource server's part is
  done (October 2026, `lib/src/jwt/dpop.dart`, `test/dpop_test.dart`);
  left: a shared `DPoPProofJtiCache` for several instances, `htu` behind
  a TLS proxy (needs the forwarded headers above). The differential test
  (against Spring Security 7.1 with `dPoP()`) and the mutation score
  (97.1 %) of the DPoP code are done. The apps' part:
  [spring_boot_starter_flutter_security.md](spring_boot_starter_flutter_security.md).
- **From the comparison with Spring Security 7**
  ([docs/security-spring-comparison.md](../docs/security-spring-comparison.md)),
  not planned elsewhere yet:
  - logins: `oneTimeTokenLogin()`, passkeys (`webAuthn()`), `x509()` (the
    web starter already asks for client certificates), pre-authentication
    (`RequestHeaderAuthenticationFilter`), switch user,
    `passwordManagement()` (`/.well-known/change-password`); the web part
    of multi-factor authentication (the login page asking for the missing
    factor);
  - sessions: concurrency control (`maximumSessions`, with the session
    registry above), `invalidSessionUrl`, the `always` and `never`
    creation policies;
  - resource server: several issuers
    (`JwtIssuerAuthenticationManagerResolver`), bearer tokens in a form
    body, protected resource metadata (RFC 9728), `NimbusJwtEncoder`,
    `spring.security.oauth2.resourceserver.jwt.public-key-location`;
  - `@RegisteredOAuth2AuthorizedClient` controller parameters;
  - exploits: `csrf.spa()`, DSL methods for Permissions-Policy,
    Cross-Origin-*-Policy, CSP report-only and `Clear-Site-Data` on
    logout, `redirectToHttps()`;
  - rules: an IP address matcher (`hasIpAddress`), SpEL in request rules
    (`WebExpressionAuthorizationManager`), `WebSecurityCustomizer` and
    `Customizer<HttpSecurity>` beans, Boot's `PathRequest` (and
    `EndpointRequest` once there is an actuator);
  - observability of the filters and of authorization;
  - tests: `oauth2Login()`, `oidcLogin()`, `oauth2Client()` and
    `opaqueToken()` post-processors, `formLogin()` and `logout()` request
    builders, `authenticated()` / `unauthenticated()` result matchers.
