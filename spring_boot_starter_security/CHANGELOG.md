## 0.5.0

### Breaking

- Access tokens must have the `typ` `JWT` (in any case) or none, as Spring Security 7's `JwtTypeValidator.jwt()`, in every default decoder and validator (`JwtValidators.createDefault`, `createDefaultWithIssuer`, the `spring.security.oauth2.resourceserver.jwt.*` decoder): `at+jwt`, `logout+jwt`, `secevent+jwt` and `dpop+jwt` tokens signed with the same keys are refused. For a provider that types its access tokens as RFC 9068 says, start the validator with `JwtTypeValidator(['at+jwt', 'JWT'], allowEmpty: true)`. The `oauth2Login()` ID token decoder checks the same.
- A token bound to a client certificate (`cnf.x5t#S256`, RFC 8705) is refused with either scheme: the web starter does not hand client certificates to the security filters, so the binding cannot be checked (Spring refuses it without the certificate too).
- `DefaultBearerTokenResolver` with `allowUriQueryParameter` reads `access_token` in `GET` requests only, as in Spring.
- The CORS filter uses only the bean named `corsConfigurationSource`, as Spring Security does (another name is ignored; a bean of another type under that name stops the start), and `CorsFilter.configurationFor` returns a `FutureOr`. It applies that bean's rules alone where the bean has some: `@CrossOrigin` and the `WebMvcConfigurer` mappings no longer widen them. Elsewhere it applies the rules of the handler the router would call, chosen with its `consumes`, `produces` and `headers` too, as Spring's `HandlerMappingIntrospector` chooses it; a WebSocket handshake gets the bean's rules or none, no longer the `WebMvcConfigurer` mappings.
- The CORS filter answers a pre-flight that has no configuration with a 200 without CORS headers (was a 403), as Spring's `CorsFilter`, and checks an actual request's own method: a `HEAD` or `DELETE` the rules do not list is a 403 before the security checks.
- Only a login makes a session. Before it, the CSRF token is the `XSRF-TOKEN` cookie (`CookieCsrfTokenRepository`, `HttpOnly`, `SameSite=Lax`), the page to come back to is the signed `REDIRECT_URI` cookie (`CookieRequestCache`, Spring's) and the OAuth 2.0 authorization request of `oauth2Login()` the signed `OAUTH2_AUTHORIZATION_REQUEST` cookie (`CookieOAuth2AuthorizationRequestRepository`), so clients that are not logged in cannot fill the session store. Spring Security keeps the three in the session; `HttpSessionCsrfTokenRepository`, `HttpSessionRequestCache` and `HttpSessionOAuth2AuthorizationRequestRepository` can still be set. The cookies are signed by `CookieSigner` with `spring.security.cookie.secret` (32 characters or more, the same on every instance), else with a random key of the process. A `response_mode=form_post` login needs HTTPS (its cookie is `SameSite=None; Secure`). The CSRF token's header is now `X-XSRF-TOKEN` (the cookie repository's, as in Spring; it was `X-CSRF-TOKEN`); pages that take the name from the token (`CsrfToken.headerName`) need no change.
- `RequestCache.removeRequest` takes the response too, as in Spring.
- A login refused because too many password checks run and wait (`PasswordChecksBusyException`, `spring.security.password-checks.*`) is answered `503` with `Retry-After: 1`, never as a failed login (no event, no challenge); a warning is logged at most once a minute. The chain's own provider uses the `PasswordCheckLimiter` bean.
- Each user holds at most 10 sessions by default: a new login ends the user's least recently used one, so one account cannot fill the session store by logging in again and again. `sessionManagement((s) => s.maximumSessions(n))` or `spring.security.session.maximum-sessions` changes it (`-1`: no limit, Spring's default), `.maxSessionsPreventsLogin(true)` or `spring.security.session.max-sessions-prevents-login=true` refuses the new login instead (`SessionAuthenticationException`); the properties are not in Spring Boot, apply only to chains with sessions (form login, `oauth2Login()`), and a chain's own setting wins. Spring's `SessionRegistry`, `SessionRegistryImpl` (over the session repository: it holds ids only and asks the repository which live), `SessionInformation`, `ConcurrentSessionControlAuthenticationStrategy` and `RegisterSessionAuthenticationStrategy`. Users are told apart by name and by where the login came from.
- DPoP: a proof's `jti` is kept until `iat` + clock skew + 5 seconds, so a `DPoPProofJtiCache` gets an `expiresAt` 5 seconds later, and must refuse a recorded id until it drops it, whatever its expiry says.

### Changes

- With `oauth2ResourceServer()`, a request that carries a token in a header (`Authorization: Bearer`, or `DPoP` with a proof) is exempt from CSRF, as Spring's `registerDefaultCsrfOverride` (which exempts `Bearer` only): POST, PUT and DELETE API calls got a 403. A token in the `access_token` query never exempts a request, and the chain's logout and login URLs keep their CSRF check (Spring exempts them).
- DPoP: the proof's key is compared with the token's `cnf.jkt` before its `jti` is recorded, so proofs of made-up keys cannot fill the replay cache; a token without `cnf.jkt` is refused before the proof is read.
- DPoP: a proof can no longer be replayed at exactly `iat` + clock skew.
- A DPoP-bound token sent as `Bearer` publishes one failure event, never a success first (`UnboundBearerTokenAuthenticationProvider`).
- A failed fetch of the JWK Set or of the issuer's metadata is made again 30 seconds later at the earliest, never once per token.
- The key cache's lifetime, the refetch pause and the DPoP replay cache's purges are measured on a monotonic clock, so a wall clock set back stretches none of them.
- `JwtTypeValidator`, Spring's validator of the `typ` header.
- `StrictHttpFirewall` refuses `.` and `..` segments with path parameters (`..;x`) also with `allowSemicolon`.
- `oauth2Login()`: a callback with another method than `GET` or a form `POST` (`HEAD`, `PUT`, ...) fails with `invalid_request` and leaves the login in progress alone.

## 0.4.3

- `JwtDecoders.fromIssuerLocation` finds the issuer's metadata with the OAuth2 client's discovery (`ClientRegistrations.configurationForIssuerLocation`): the same locations and issuer check. A location the fetcher cannot read (a 404 of `transportJwkFetcher` included) now moves to the next, so the RFC 8414 metadata is found behind a missing OpenID Connect document. `oauth2Login()` is in the differential test against Spring Security 7.1.
- `oauth2Login()`: single sign-on with OAuth 2.0 and OpenID Connect providers (Spring Security's `OAuth2LoginConfigurer`, `OAuth2AuthorizationRequestRedirectFilter`, `OAuth2LoginAuthenticationFilter`, `OidcAuthorizationCodeAuthenticationProvider`, `HttpSessionOAuth2AuthorizationRequestRepository`, the authorized client repositories, `OidcClientInitiatedLogoutSuccessHandler`); ID token signatures checked with the provider's JWK Set (`OidcIdTokenDecoderFactory`, also the `oidcIdTokenDecoder` bean); the default chain logs browsers in through the `spring.security.oauth2.client.*` registrations. The starter depends on and re-exports `spring_boot_starter_oauth2_client`, whose `OAuth2Error`, `OAuth2AuthenticationException`, `OAuth2TokenValidator`, `OAuth2TokenValidatorResult` and `DelegatingOAuth2TokenValidator` replace the starter's own (same signatures). `defaultSuccessUrl`, failure and logout URLs may be absolute (`http://localhost:5050/`). `transportJwkFetcher`.

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs
- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- Initial version: Spring Security for `spring_boot_starter_web`, secure by default like Spring Boot (every request needs a login; form login for browsers, HTTP Basic for other clients; one user from `spring.security.user.*` or a generated password; CSRF, security headers, logout). `SecurityFilterChain` beans built with `HttpSecurity` (`authorizeHttpRequests` on the router's path patterns, a request no rule matches is denied; `httpBasic`, `formLogin`, `oauth2ResourceServer`, `csrf`, `cors`, `headers`, `sessionManagement`, `exceptionHandling`, `logout`, `securityMatcher`), `FilterChainProxy` with a `StrictHttpFirewall`, sessions with a new id at login, JWT resource servers (RS, PS, ES and HS algorithms on Bouncy Castle's Dart port, JWK sets with key rotation, issuer discovery, `spring.security.oauth2.resourceserver.jwt.*`), errors as `ProblemDetail` with Spring's challenges, `@AuthenticationPrincipal` and `@CurrentSecurityContext` arguments. Tests: `user()`, `jwt()`, `csrf()`, `httpBasic()`, `anonymous()` for `MockMvc`. Compared with Spring Security 7.1 request by request; the differences are listed in the README.
