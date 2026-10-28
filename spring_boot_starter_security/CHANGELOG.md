## Unreleased

- `oauth2Login()`: single sign-on with OAuth 2.0 and OpenID Connect providers (Spring Security's `OAuth2LoginConfigurer`, `OAuth2AuthorizationRequestRedirectFilter`, `OAuth2LoginAuthenticationFilter`, `OidcAuthorizationCodeAuthenticationProvider`, `HttpSessionOAuth2AuthorizationRequestRepository`, the authorized client repositories, `OidcClientInitiatedLogoutSuccessHandler`); ID token signatures checked with the provider's JWK Set (`OidcIdTokenDecoderFactory`, also the `oidcIdTokenDecoder` bean); the default chain logs browsers in through the `spring.security.oauth2.client.*` registrations. The starter depends on and re-exports `spring_boot_starter_oauth2_client`, whose `OAuth2Error`, `OAuth2AuthenticationException`, `OAuth2TokenValidator`, `OAuth2TokenValidatorResult` and `DelegatingOAuth2TokenValidator` replace the starter's own (same signatures). `defaultSuccessUrl`, failure and logout URLs may be absolute (`http://localhost:5050/`). `transportJwkFetcher`.

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs
- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- Initial version: Spring Security for `spring_boot_starter_web`, secure by default like Spring Boot (every request needs a login; form login for browsers, HTTP Basic for other clients; one user from `spring.security.user.*` or a generated password; CSRF, security headers, logout). `SecurityFilterChain` beans built with `HttpSecurity` (`authorizeHttpRequests` on the router's path patterns, a request no rule matches is denied; `httpBasic`, `formLogin`, `oauth2ResourceServer`, `csrf`, `cors`, `headers`, `sessionManagement`, `exceptionHandling`, `logout`, `securityMatcher`), `FilterChainProxy` with a `StrictHttpFirewall`, sessions with a new id at login, JWT resource servers (RS, PS, ES and HS algorithms on Bouncy Castle's Dart port, JWK sets with key rotation, issuer discovery, `spring.security.oauth2.resourceserver.jwt.*`), errors as `ProblemDetail` with Spring's challenges, `@AuthenticationPrincipal` and `@CurrentSecurityContext` arguments. Tests: `user()`, `jwt()`, `csrf()`, `httpBasic()`, `anonymous()` for `MockMvc`. Compared with Spring Security 7.1 request by request; the differences are listed in the README.
