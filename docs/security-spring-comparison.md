# Spring Security features, compared

This page lists every feature of Spring Security's servlet reference and of
Spring Boot's security auto-configuration, and says for each whether the
Dart packages have it. Read it when you come from Spring and want to know
whether something you use there works here, or when you plan what to build
next.

Compared with **Spring Security 7.1** (including what 6.3 to 7.1 added and
7 kept) and **Spring Boot 4.1**, in **October 2026**, against the code of
`spring_security_core` (core), `spring_boot_starter_security` (starter)
and `spring_boot_starter_oauth2_client` (client). Each status was checked
in the code (`lib/`), not only in the READMEs.

| Status | Meaning |
|---|---|
| **done** | works as in Spring; small differences are in the package's README ("Differences") |
| **partial** | the main part works; what is missing is said in the note |
| **missing** | not there yet; planned in a roadmap file |
| **in progress** | being built now |
| **out of scope** | left out on purpose; the note says why |

The links go to the Spring reference (`docs.spring.io/spring-security/reference/servlet/...`).
Where each missing feature is planned:
[core](../roadmap/spring_security_core.md),
[starter](../roadmap/spring_boot_starter_security.md),
[client](../roadmap/spring_boot_starter_oauth2_client.md).

## Authentication

| Feature | Status | Notes |
|---|---|---|
| [Architecture](https://docs.spring.io/spring-security/reference/servlet/authentication/architecture.html): `SecurityContextHolder`, `Authentication`, `AuthenticationManager`, `ProviderManager`, `AuthenticationProvider`, entry points | done | core; the context is kept per `Zone`, not per thread |
| `Authentication.Builder` (7.0: copy an `Authentication` and add to it) | missing | needed by multi-factor authentication |
| [Form login](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/form.html) | done | starter; generated login and logout pages |
| [HTTP Basic](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/basic.html) | done | starter |
| [Digest](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/digest.html) | out of scope | Spring itself advises against it: the server must keep passwords in plain text or as MD5 |
| [In-memory users](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/in-memory.html), [`UserDetails`](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/user-details.html), [`UserDetailsService`](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/user-details-service.html), [`DaoAuthenticationProvider`](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/dao-authentication-provider.html) | done | core; no user enumeration by message or timing; old hashes upgraded at login |
| [JDBC users](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/jdbc.html) (`JdbcUserDetailsManager`) | missing | waits for a data starter; a `UserDetailsService` bean on your own store works today |
| [`CredentialsContainer`, password erasure](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/credentials-container.html) | done | core |
| [Password encoders](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/password-encoder.html): Argon2, PBKDF2, scrypt, delegating | done | core; hashes verify both ways against Spring |
| BCrypt (`{bcrypt}`, Spring's default) | missing | only once a vetted Dart implementation exists; never written here by hand |
| Legacy encoders (MD5, SHA, `LdapShaPasswordEncoder`, `StandardPasswordEncoder`), Password4j encoders incl. Balloon hashing (7.0) | out of scope | the legacy ones exist in Spring only to read old hashes; Password4j is a Java library |
| [Compromised password checking](https://docs.spring.io/spring-security/reference/features/authentication/password-storage.html#authentication-compromised-password-check) (6.3, `HaveIBeenPwnedRestApiPasswordChecker`) | missing | |
| [Password change endpoint](https://docs.spring.io/spring-security/reference/features/authentication/password-storage.html#authentication-change-password-configuration) (`passwordManagement()`, `/.well-known/change-password`) | missing | |
| [LDAP](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/ldap.html) (bind, password compare, Active Directory) | missing | there is no LDAP client from the Dart team; until then, a custom `AuthenticationProvider` |
| [Multi-factor authentication](https://docs.spring.io/spring-security/reference/servlet/authentication/mfa.html) (7.0: `FACTOR_*` authorities, `@EnableMultiFactorAuthentication`, `AuthorizationManagerFactories.multiFactor()`) | missing | |
| [Persistence](https://docs.spring.io/spring-security/reference/servlet/authentication/persistence.html) (`SecurityContextRepository`, session and request attribute) | done | starter |
| [Passkeys / WebAuthn](https://docs.spring.io/spring-security/reference/servlet/authentication/passkeys.html) (6.4, `webAuthn()`) | missing | needs COSE keys and CBOR attestation parsing |
| [One-time token login](https://docs.spring.io/spring-security/reference/servlet/authentication/onetimetoken.html) (6.4, `oneTimeTokenLogin()`, magic links) | missing | |
| [Remember-me](https://docs.spring.io/spring-security/reference/servlet/authentication/rememberme.html) (token-based and persistent) | missing | |
| [Anonymous](https://docs.spring.io/spring-security/reference/servlet/authentication/anonymous.html) | done | starter |
| [Pre-authentication](https://docs.spring.io/spring-security/reference/servlet/authentication/preauth.html) (`RequestHeaderAuthenticationFilter`, a proxy that already logged the user in) | missing | |
| [JAAS](https://docs.spring.io/spring-security/reference/servlet/authentication/jaas.html) | out of scope | a Java platform API |
| [CAS](https://docs.spring.io/spring-security/reference/servlet/authentication/cas.html) | out of scope | rare today; OpenID Connect covers single sign-on (CAS servers speak it too) |
| [X.509 client certificates](https://docs.spring.io/spring-security/reference/servlet/authentication/x509.html) (`x509()`) | missing | the web starter already asks for client certificates (`server.ssl.client-auth`); no filter turns them into a user |
| [Kerberos / SPNEGO](https://docs.spring.io/spring-security/reference/servlet/authentication/kerberos/index.html) (in Spring Security since 7.0) | out of scope | needs GSS-API, a Java platform API |
| [Run-As](https://docs.spring.io/spring-security/reference/servlet/authentication/runas.html) | out of scope | belongs to the old access API that Spring moved out (`spring-security-access`) |
| Switch user (`SwitchUserFilter`, impersonation) | missing | |
| [Logout](https://docs.spring.io/spring-security/reference/servlet/authentication/logout.html) | done | starter; `Clear-Site-Data` on logout missing (see headers) |
| [Authentication events](https://docs.spring.io/spring-security/reference/servlet/authentication/events.html) | done | core; `DefaultAuthenticationEventPublisher` as in Boot |

## Session management

| Feature | Status | Notes |
|---|---|---|
| [Session fixation protection](https://docs.spring.io/spring-security/reference/servlet/authentication/session-management.html) | done | a new session id at login (`changeSessionId`; `migrateSession` and `newSession` are not offered) |
| `SessionCreationPolicy` | partial | `ifRequired` and `stateless`; not `always` and `never` |
| Concurrency control (`maximumSessions`, `maxSessionsPreventsLogin`, `expiredUrl`) | missing | |
| `SessionRegistry` (a user's sessions, ending them all) | missing | |
| Invalid session detection (`invalidSessionUrl`) | missing | |
| A limit on all sessions | done | not in Spring: `server.servlet.session.max-sessions` (10 000); sessions without a login go first; when only logins are left, a login of the user holding the most sessions makes room (one account cannot lock the others out), and with one login per user a new session is refused with 503, as Tomcat's `maxActiveSessions` |
| Shared session store (Spring Session) | missing | the sessions live in one process |

## Authorization

| Feature | Status | Notes |
|---|---|---|
| [Architecture](https://docs.spring.io/spring-security/reference/servlet/authorization/architecture.html): `AuthorizationManager`, `AuthorizationManagers.anyOf/allOf`, `RoleHierarchy` | done | core |
| `AllAuthoritiesAuthorizationManager`, `hasAllAuthorities` (7.0) | missing | `access(...)` with `AuthorizationManagers.allOf` does the same |
| `AuthorizationManagerFactory` (7.0) | missing | comes with multi-factor authentication |
| Access API (`AccessDecisionManager`, voters), `authorizeRequests` | out of scope | Spring 7 removed or moved them out |
| [`authorizeHttpRequests`](https://docs.spring.io/spring-security/reference/servlet/authorization/authorize-http-requests.html) with path patterns and methods; deny when no rule matches | done | starter; the router's `PathPattern` |
| Request matchers: header, media type, `and`/`or`/negated, custom | done | starter |
| IP address matcher (`hasIpAddress`, `InetAddressMatcher` 7.1) | missing | a custom `RequestMatcher` today |
| Regex matcher, dispatcher type matchers | out of scope | no regex matcher on purpose (one path model); Dart has no servlet dispatches |
| SpEL in request rules (`WebExpressionAuthorizationManager`) | missing | `access(AuthorizationManager)` takes a function |
| [Method security](https://docs.spring.io/spring-security/reference/servlet/authorization/method-security.html): `@PreAuthorize`, `@PostAuthorize`, `@Secured`, `@PreFilter`, `@PostFilter`, `hasPermission` | done | core; always on (no `@EnableMethodSecurity`) |
| JSR-250 (`@RolesAllowed`, `@PermitAll`, `@DenyAll`) | missing | |
| Meta-annotations and templates (`@HasRole("ADMIN")` with `{value}`, `AnnotationTemplateExpressionDefaults`, 6.3) | partial | a `const` class that extends `PreAuthorize` works as a fixed composed annotation; templates with parameters do not |
| `@AuthorizeReturnObject` (6.3, secured proxies of returned objects) | missing | |
| `@HandleAuthorizationDenied` (6.3, a fallback value instead of a 403) | missing | |
| Custom expression handler, `PermissionEvaluator` beans | done | core |
| [Domain object ACLs](https://docs.spring.io/spring-security/reference/servlet/authorization/acls.html) | missing | `hasPermission` with your own `PermissionEvaluator` works; no ACL tables or `AclService` |
| [Authorization events](https://docs.spring.io/spring-security/reference/servlet/authorization/events.html) (`AuthorizationDeniedEvent`, `AuthorizationEventPublisher`) | missing | |

## OAuth 2.0

| Feature | Status | Notes |
|---|---|---|
| [OAuth2 login](https://docs.spring.io/spring-security/reference/servlet/oauth2/login/core.html) (`oauth2Login()`, OpenID Connect, PKCE, user services, authorities mapper) | done | starter on the client |
| [Advanced login configuration](https://docs.spring.io/spring-security/reference/servlet/oauth2/login/advanced.html) (endpoints, request resolver, `idTokenDecoder`) | done | |
| `response_mode=form_post` | done (addition) | Spring sends no `response_mode` (an authorization request customizer adds it); here the registration's `response-mode`, the callback's `POST` with the method checked and its CSRF exemption |
| [OIDC RP-initiated logout](https://docs.spring.io/spring-security/reference/servlet/oauth2/login/logout.html) | done | `OidcClientInitiatedLogoutSuccessHandler` |
| [OIDC back-channel logout](https://docs.spring.io/spring-security/reference/servlet/oauth2/login/logout.html#configure-provider-initiated-oidc-logout) (`oidcLogout()`) | missing | |
| [Client registrations and providers](https://docs.spring.io/spring-security/reference/servlet/oauth2/client/core.html), issuer discovery, common providers | done | client; discovery at first use, not at startup |
| `oauth2Client()` (authorization code grant without login) | missing | |
| `@RegisteredOAuth2AuthorizedClient` controller parameter | missing | the `OAuth2AuthorizedClientManager` bean gives the same |
| [Grants](https://docs.spring.io/spring-security/reference/servlet/oauth2/client/authorization-grants.html): authorization code, refresh token, client credentials | done | client |
| Token exchange (RFC 8693, 6.3) | missing | |
| JWT bearer grant (RFC 7523) | missing | |
| Password grant | out of scope | removed in Spring Security 7 |
| [Client authentication](https://docs.spring.io/spring-security/reference/servlet/oauth2/client/client-authentication.html): `client_secret_basic`, `client_secret_post`, `none` | done | |
| `private_key_jwt`, `client_secret_jwt`, `tls_client_auth` | missing | the values exist; the token clients refuse them. Apple's JWT as `client_secret` (what Spring applications write a parameters converter for): `JwtClientSecret`, `client-secret-jwt.*` (addition) |
| [Authorized clients](https://docs.spring.io/spring-security/reference/servlet/oauth2/client/authorized-clients.html): service, repository, manager | done | client: in memory, as in Spring Boot; in the app's secure storage with `spring_boot_starter_flutter_security`; no JDBC service |
| Tokens on HTTP clients (`OAuth2ClientHttpRequestInterceptor` 6.4, HTTP service clients and `@ClientRegistrationId` 7.0) | partial | Feign: `OAuth2AccessTokenInterceptor` with Spring Cloud OpenFeign's properties; no per-client annotation |
| Pushed Authorization Requests (RFC 9126) | missing | not in Spring's client either |
| [Resource server, JWT](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html) | done | starter; custom `JwkSource` too; `JwtTypeValidator.jwt()` among the default validators, as in 7.0 |
| Certificate-bound access tokens (RFC 8705, `X509CertificateThumbprintValidator` among the default validators) | missing | such tokens are refused with either scheme (fail closed): the web starter does not hand the client certificate to the security filters |
| `NimbusJwtEncoder` (minting JWTs) | missing | |
| [Opaque token introspection](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/opaque-token.html) (`opaqueToken()`, RFC 7662) | missing | |
| [Multi-tenancy](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/multitenancy.html) (`JwtIssuerAuthenticationManagerResolver`, several issuers) | missing | one issuer per chain; several chains by path work |
| [Bearer tokens](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/bearer-tokens.html): header, custom header, query parameter | done | the query parameter off by default and read in `GET` requests only, as in Spring; only a token in the header exempts a request from CSRF (README "Differences") |
| Bearer token in a form body (`allowFormEncodedBodyParameter`) | missing | |
| [DPoP-bound access tokens](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/dpop-tokens.html) (RFC 9449, 6.5) | done | starter, on by itself with `jwt()`; `htu` normalized, bound tokens refused as `Bearer`, DPoP requests exempt from CSRF as `Bearer` ones, the key's `cnf.jkt` checked before the `jti` is recorded, and the `jti` kept 5 s past the proof's window (README "Differences"); the client's side (proofs on token requests, Feign calls and user info, `dpop` per registration, `auto` by default) in the OAuth2 client, an addition: Spring Security 7 has none; the apps' keys in the Secure Enclave / Keychain, the Android Keystore or the `SecretStore` (Flutter security package); the web's WebCrypto key next |
| [Protected resource metadata](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/protected-resource-metadata.html) (RFC 9728) | missing | |
| [Authorization server](https://docs.spring.io/spring-security/reference/servlet/oauth2/authorization-server/index.html) (in Spring Security since 7.0), dynamic client registration | out of scope | use an identity provider (Keycloak, Auth0, ...) |

Not in the table, because Spring has no counterpart (Spring Security logs
in browsers on a server, and Java has no apps): the login of an app, in
`spring_boot_starter_flutter_security` (`OAuth2LoginService` with token
revocation, `AuthorizationWindow`, `SecretStore`,
`SecretStoreOAuth2AuthorizedClientService`, `SecretTemplate`). It builds
on the client's registrations, token clients and authorized clients; see
[its README](../spring_boot_starter_flutter_security/README.md#the-app-login).

## SAML 2.0

| Feature | Status | Notes |
|---|---|---|
| [SAML 2.0 login](https://docs.spring.io/spring-security/reference/servlet/saml2/login/index.html), [logout](https://docs.spring.io/spring-security/reference/servlet/saml2/logout.html), [metadata](https://docs.spring.io/spring-security/reference/servlet/saml2/metadata.html) | out of scope | XML signatures need an XML parser and canonicalization the Dart team does not publish: another third-party package in the cryptography. Most SAML identity providers speak OpenID Connect too |

## Protection against exploits

| Feature | Status | Notes |
|---|---|---|
| [CSRF](https://docs.spring.io/spring-security/reference/servlet/exploits/csrf.html): session and cookie repositories, XOR handler, ignoring matchers | done | starter; token requests exempt by their header only, and not at the logout and login URLs (README "Differences") |
| `csrf.spa()` (7.0) | missing | `CookieCsrfTokenRepository` with the plain handler does it by hand |
| [Headers](https://docs.spring.io/spring-security/reference/servlet/exploits/headers.html): cache control, `nosniff`, HSTS, frame options, X-XSS-Protection, CSP, Referrer-Policy | done | starter |
| CSP report-only, Permissions-Policy, Cross-Origin-Opener/Embedder/Resource-Policy, `Clear-Site-Data` | partial | through `addHeaderWriter`; no DSL methods |
| [HTTP](https://docs.spring.io/spring-security/reference/servlet/exploits/http.html): redirect to HTTPS (`redirectToHttps`, `requiresChannel`) | missing | |
| [Proxy server configuration](https://docs.spring.io/spring-security/reference/servlet/appendix/proxy-server.html) (`X-Forwarded-*`, `Forwarded`) | missing | planned in the web starter |
| [HttpFirewall](https://docs.spring.io/spring-security/reference/servlet/exploits/firewall.html) (`StrictHttpFirewall`) | done | starter |
| [CORS](https://docs.spring.io/spring-security/reference/servlet/integrations/cors.html) | done | on by default here |

## Integrations and configuration

| Feature | Status | Notes |
|---|---|---|
| [Concurrency](https://docs.spring.io/spring-security/reference/servlet/integrations/concurrency.html) (`DelegatingSecurityContextExecutor`) | done | not needed: the context follows the `Zone` across `await` and timers |
| [Localization](https://docs.spring.io/spring-security/reference/servlet/integrations/localization.html) of messages | missing | English only |
| [Servlet APIs](https://docs.spring.io/spring-security/reference/servlet/integrations/servlet-api.html) (`getUserPrincipal`) | done | `request.principal`; `isUserInRole` and `login()` have no Dart counterpart |
| [Spring Data](https://docs.spring.io/spring-security/reference/servlet/integrations/data.html) (`?#{principal}` in queries) | missing | waits for a data starter |
| [Spring MVC](https://docs.spring.io/spring-security/reference/servlet/integrations/mvc.html): `@AuthenticationPrincipal`, `@CurrentSecurityContext`, `CsrfToken` parameters | done | starter |
| [WebSocket](https://docs.spring.io/spring-security/reference/servlet/integrations/websocket.html): handshake | done | the connection keeps its user |
| WebSocket message authorization (`AuthorizationManager<Message<?>>`) | missing | |
| [JSP taglib](https://docs.spring.io/spring-security/reference/servlet/integrations/jsp-taglibs.html) | out of scope | no JSP |
| [Observability](https://docs.spring.io/spring-security/reference/servlet/integrations/observability.html) (Micrometer observations of filters and authorization) | missing | waits for an observation API in the family |
| [Java configuration](https://docs.spring.io/spring-security/reference/servlet/configuration/java.html): `HttpSecurity`, several chains, `securityMatcher`, `addFilterBefore/After/At` | done | starter |
| `WebSecurityCustomizer` (`web.ignoring()`), `Customizer<HttpSecurity>` beans (7.0 modular configuration) | missing | a chain with `permitAll()` and its own `securityMatcher` instead |
| [Kotlin DSL](https://docs.spring.io/spring-security/reference/servlet/configuration/kotlin.html), [XML namespace](https://docs.spring.io/spring-security/reference/servlet/configuration/xml-namespace.html) | out of scope | Java/Kotlin only |

## Testing

| Feature | Status | Notes |
|---|---|---|
| [Method security tests](https://docs.spring.io/spring-security/reference/servlet/test/method.html): `@WithMockUser`, `@WithAnonymousUser`, `@WithSecurityContext` | done | functions: `withMockUser`, `withAnonymousUser`, `withAuthentication` |
| `@WithUserDetails` (a user from the `UserDetailsService`) | missing | `withAuthentication` with a loaded user |
| [Request post-processors](https://docs.spring.io/spring-security/reference/servlet/test/mockmvc/request-post-processors.html): `user`, `userDetails`, `authentication`, `anonymous`, `httpBasic`, `csrf`, `jwt` | done | starter's `testing.dart` |
| `opaqueToken()`, `oauth2Login()`, `oidcLogin()`, `oauth2Client()` post-processors | missing | `authentication(...)` with an `OAuth2AuthenticationToken` |
| [Request builders](https://docs.spring.io/spring-security/reference/servlet/test/mockmvc/request-builders.html) (`formLogin()`, `logout()`) | missing | |
| [Result matchers](https://docs.spring.io/spring-security/reference/servlet/test/mockmvc/result-matchers.html) (`authenticated()`, `unauthenticated()`, `withAuthorities`) | missing | |

## Spring Boot auto-configuration

| Feature | Status | Notes |
|---|---|---|
| [Secure by default](https://docs.spring.io/spring-boot/reference/web/spring-security.html), form login or Basic by content negotiation, `spring.security.user.*`, generated password | done | |
| The default user backs off with OAuth2 client, resource server or own `UserDetailsService` | done | |
| `DefaultAuthenticationEventPublisher`, `spring.security.filter.order` | done | |
| `PathRequest.toStaticResources().atCommonLocations()` | missing | |
| `EndpointRequest` (actuator endpoints) | missing | waits for an actuator |
| `spring.security.oauth2.resourceserver.jwt.*` | partial | all but `public-key-location` |
| `spring.security.oauth2.resourceserver.opaquetoken.*` | missing | with opaque tokens |
| `spring.security.oauth2.client.*` (registrations, providers) | done | client |
| `spring.security.saml2.*`, `spring.security.oauth2.authorizationserver.*` | out of scope | see SAML 2.0 and authorization server |

## Counts

Of the 116 rows above: 43 done (one of them an addition), 5 partial,
54 missing, 14 out of scope. Many missing rows are small (a DSL method, a test
helper); the done rows carry the most used parts of Spring Security.

The ones a Spring user meets most often, in order: remember-me;
`oauth2Client()` and `@RegisteredOAuth2AuthorizedClient`; opaque token
introspection; session concurrency control and the session registry;
multi-factor authentication; BCrypt; JDBC users; multi-tenant resource
servers; OIDC back-channel logout; one-time token login and passkeys.
