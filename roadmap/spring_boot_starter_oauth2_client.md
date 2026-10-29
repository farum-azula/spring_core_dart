# spring_boot_starter_oauth2_client and SSO (in progress, October 2026)

Single sign-on with OAuth 2.0 and OpenID Connect, for servers and apps,
with Spring Boot's properties. Three parts:

1. **`spring_boot_starter_oauth2_client`** (new, pure Dart: the VM,
   Flutter, the web): registrations and providers, discovery, PKCE, the
   token endpoint, refresh, the authorized clients, the users
   (`OAuth2User`, `OidcUser`), tokens on Feign calls. Exactly Spring's
   `spring-security-oauth2-client` and `spring-boot-starter-oauth2-client`,
   nothing of the apps.
2. **`oauth2Login()` in `spring_boot_starter_security`**: the server logs
   the browser in (authorization code flow, the session keeps the user).
   Pages rendered by the server and Flutter web use it.
3. **The app login, in `spring_boot_starter_flutter_security`** (a
   plugin): `OAuth2LoginService`, the `AuthorizationWindow` (the system's
   login window, a loopback redirect on Windows and Linux), the
   `SecretStore` on the platform's secure storage and the authorized
   client service on it, `SecretTemplate`, on our own platform code.
   Spring has no apps, so none of it is in the client: the platform code
   moved out of `spring_boot_starter_flutter`, and the login, the windows
   and the stores out of the client (October 2026).

## Which flow where (the security decision)

| Client | Flow | Tokens live |
|---|---|---|
| Server pages | `oauth2Login()`: the server is a confidential client | on the server, in the session |
| Flutter web | the same, the server is the app's backend (BFF) | on the server; the browser has only the `HttpOnly` session cookie |
| Flutter iOS, Android, macOS | authorization code + PKCE, a public client (RFC 8252), the system browser | Keychain / Keystore (`SecretStore`) |
| Flutter Windows, Linux | the same, the redirect to a loopback server on `127.0.0.1` | DPAPI / libsecret (`SecretStore`) |
| Server to server | client credentials | in memory |

Why, as the OAuth 2.0 Security BCP (RFC 9700), OAuth 2.0 for Native Apps
(RFC 8252) and OAuth 2.0 for Browser-Based Applications (IETF draft) say:

- **Native apps** are public clients: no client secret in an app, ever
  (anyone extracts it). PKCE with `S256` binds the code to the app that
  started the login, so a code stolen on the redirect (another app
  registered the same scheme) is useless. `state` against CSRF on the
  redirect, `nonce` against replayed ID tokens. The login page opens in
  the **system browser** (`ASWebAuthenticationSession`, Custom Tabs, the
  default browser), never in a WebView: the app cannot read the password,
  and the user's SSO session of the browser is reused.
- **Tokens at rest** only in the platform's secure storage: the Keychain
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synced), an
  AES-GCM key of the Android Keystore that never leaves it, DPAPI on
  Windows, the Secret Service (libsecret) on Linux. No fallback to a
  plain file: without secure storage the tokens stay in memory and the
  starter says so in the log.
- **The web** has no secure storage and any script injected into the page
  (XSS) reads what the app holds. So Flutter web never holds tokens: the
  server logs in and keeps them, the browser sends the session cookie
  (`HttpOnly`, `SameSite=Lax`), CSRF tokens protect the unsafe methods.
  It needs the app and the API on the same site (`localhost` with two
  ports, `app.example.com` and `api.example.com`): browsers drop
  third-party cookies. `FetchHttpTransport` sends cookies when told to
  (`credentials: 'include'`). The app login of part 3 refuses to run in
  a browser.

## 1. spring_boot_starter_oauth2_client

Depends on `spring_boot_dart`, `spring_web_dart` (the HTTP transport),
`spring_security_core` (`Authentication`, the security context, events),
`spring_boot_starter_feign` (the token interceptor) and the logging
starter. No JWT signature code here (that is in the security starter,
with its third-party dependency): the default `OidcIdTokenDecoder`
(`TokenEndpointOidcIdTokenDecoder`) trusts the ID token it got directly
from the token endpoint over TLS, as OpenID Connect Core 3.1.3.7 allows;
the server checks the signature too (part 2). It stays the client's
default because the refresh of authorized clients uses it, not only the
app login.

**Registrations** (Spring's names and properties):

```properties
spring.security.oauth2.client.registration.keycloak.client-id=neon-app
spring.security.oauth2.client.registration.keycloak.scope=openid,profile,email
spring.security.oauth2.client.registration.keycloak.redirect-uri=neonbooks:/oauth2/callback
spring.security.oauth2.client.provider.keycloak.issuer-uri=http://localhost:8180/realms/neon

# The common providers need only the client: google, github, facebook, okta
spring.security.oauth2.client.registration.google.client-id=...
spring.security.oauth2.client.registration.google.client-secret=...
```

- `ClientRegistration` (id, client id and secret, authentication method
  `client_secret_basic` / `client_secret_post` / `none`, grant type,
  redirect URI with `{baseUrl}`, `{registrationId}` templates, scopes,
  client name, `ProviderDetails`: authorization, token, user-info and JWK
  Set URIs, issuer, user name attribute, the metadata such as
  `end_session_endpoint` and `revocation_endpoint`).
- `ClientRegistrationRepository`, `InMemoryClientRegistrationRepository`,
  `CommonOAuth2Provider` (google, github, facebook, okta),
  `ClientRegistrations.fromIssuerLocation` (OpenID discovery; the
  `issuer` of the metadata must equal the configured one).
- From properties like Boot's `OAuth2ClientPropertiesMapper`. Discovery
  happens on first use and is cached, not at startup as in Spring Boot:
  an app must start offline (documented difference).

**Tokens and the token endpoint:** `OAuth2AccessToken`,
`OAuth2RefreshToken`, `OidcIdToken`, `OAuth2AccessTokenResponse`; token
response clients for `authorization_code` (with the PKCE verifier),
`refresh_token` and `client_credentials` on the `HttpTransport`; errors
as `OAuth2AuthorizationException` with the `OAuth2Error`.
`OAuth2AuthorizationRequest` with `state`, `nonce` and `code_challenge`
(`S256`, always, also for confidential clients), random values from
`Random.secure()`.

**Authorized clients:** `OAuth2AuthorizedClient` (registration, principal
name, access, refresh and ID token); `OAuth2AuthorizedClientService`
(load, save, remove); `InMemoryOAuth2AuthorizedClientService`;
`OAuth2AuthorizedClientManager` that refreshes a token expiring within
the clock skew (60 s) and runs one refresh at a time per client, and gets
client-credentials tokens.

**Users:** `OAuth2User`, `DefaultOAuth2User`, `OidcUser`,
`DefaultOidcUser`, `OAuth2AuthenticationToken` (an `Authentication`);
`DefaultOAuth2UserService` (the user-info endpoint), `OidcUserService`
(user info when the endpoint exists, `sub` must match);
`GrantedAuthoritiesMapper`. Authorities as Spring: `OIDC_USER` or
`OAUTH2_USER` and `SCOPE_<scope>`. `OidcIdTokenValidator`: `iss`, `aud`
contains the client id, `azp`, `exp` and `iat` with the clock skew,
`nonce`.

**Feign:** `OAuth2AccessTokenInterceptor` adds `Authorization: Bearer`
with a fresh token of the current user (or of the client, for client
credentials), with Spring Cloud OpenFeign's properties
`spring.cloud.openfeign.oauth2.enabled` and
`spring.cloud.openfeign.oauth2.client-registration-id`. On a 401
`OAuth2AccessTokenErrorDecoder` marks the token expired, so the next call
refreshes it (the failed call is not repeated: Feign's interceptors do
not see responses).

**Auto-configuration**, as Spring Boot's `OAuth2ClientAutoConfiguration`
and Spring Security's `OAuth2AuthorizedClientManagerRegistrar`: the
repository when a registration is set, the in-memory authorized client
service, the token clients, the `OidcIdTokenDecoder`, the user services
and the manager with a repository, the Feign interceptor and error
decoder when enabled. Another auto-configuration that replaces a
default comes `before` this one (the security starter's decoder, the
Flutter security package's authorized client service); the client names
no other module.

## 2. oauth2Login() in spring_boot_starter_security

Done (October 2026): what was built and what is left, in
[spring_boot_starter_security.md](spring_boot_starter_security.md#sso-oauth2login-with-openid-connect);
usage in the starter's
[README](../spring_boot_starter_security/README.md#single-sign-on-oauth2login).
The ID tokens are checked by the starter's `OidcIdTokenDecoderFactory`
(signature with the provider's JWK Set, then `OidcIdTokenValidator`),
registered as the `oidcIdTokenDecoder` bean before this starter's
auto-configuration, so the refresh of authorized clients uses it too.
The plan as it was:

```dart
@Bean()
SecurityFilterChain web(HttpSecurity http) => http
    .authorizeHttpRequests((auth) => auth.anyRequest().authenticated())
    .oauth2Login(Customizer.withDefaults())
    .logout((logout) => logout.logoutSuccessHandler(
          OidcClientInitiatedLogoutSuccessHandler(registrations)))
    .build();
```

- `OAuth2AuthorizationRequestRedirectFilter`
  (`/oauth2/authorization/{registrationId}`): the request with `state`,
  `nonce` and PKCE, saved in the session
  (`HttpSessionOAuth2AuthorizationRequestRepository`), a redirect to the
  provider.
- `OAuth2LoginAuthenticationFilter` (`/login/oauth2/code/{registrationId}`):
  the saved request taken once, `state` and the registration must match,
  an `error` parameter is a failure, the code exchanged with the
  verifier, the ID token's signature checked with the provider's JWK Set
  (the resource server's `JwtDecoder`) and the validators, the user
  loaded and mapped, a new session id, the context in the session, the
  authorized client saved, the success handler (the saved request, or
  `defaultSuccessUrl`).
- The default login page lists the registrations; with one registration
  the entry point goes straight to it (as Spring).
  `OidcClientInitiatedLogoutSuccessHandler` ends the provider's session.
- The default chain of the auto-configuration adds `oauth2Login()` when
  registrations exist and no `SecurityFilterChain` bean does (Boot's
  `OAuth2WebSecurityConfiguration`).
- A chain can accept both the session and bearer tokens: Flutter web
  through the session, the native apps with their access tokens
  (`oauth2ResourceServer().jwt()` with the same issuer).
- Verified as the rest ([security_verification.md](security_verification.md)):
  a fake provider in the tests, attacks as tests (missing, wrong and
  replayed `state`, replayed codes, a wrong `nonce`, ID tokens of another
  issuer or audience, expired, `alg: none`, signed by another key, mixed-up
  registrations, provider errors, no open redirect after login, session
  fixation). The differential test against Spring's `oauth2Login()` and
  mutation testing: done (October 2026, see
  [spring_boot_starter_flutter_security.md](spring_boot_starter_flutter_security.md),
  section 7).

## 3. The app login: spring_boot_starter_flutter_security

Done (October 2026). First in the OAuth2 client (the login, the windows,
the stores) and in `spring_boot_starter_flutter` (the platform code);
now all in `spring_boot_starter_flutter_security`, a Flutter plugin
(iOS, Android, macOS, Windows, Linux) with its own platform code, no
community plugins. The client keeps only what Spring has.

**The app login** (no Spring counterpart, Spring has no apps):

```dart
@Service()
class Account {
  Account(this._login);
  final OAuth2LoginService _login;

  Future<void> signIn() => _login.login('keycloak'); // the system browser
  Future<void> signOut() => _login.logout();
}
```

- `OAuth2LoginService.login(registrationId)`: PKCE, `state`, `nonce`, the
  browser, the code exchanged, the ID token checked, user info loaded,
  the authorities mapped, the authorized client saved in the
  `OAuth2AuthorizedClientService` (so in the `SecretStore`), the
  `OAuth2AuthenticationToken` put in the `SecurityContextHolder`,
  `AuthenticationSuccessEvent` published. `restore()` at startup brings
  back the user of the stored tokens (refreshing them if needed);
  `logout()` revokes the tokens (RFC 7009, when the provider has the
  endpoint), removes them, clears the context, publishes
  `LogoutSuccessEvent`; ending the provider's session in the browser is
  optional.
- `AuthorizationWindow`: opens the provider's page and completes with
  the URI the provider redirected to. `authorize(redirectUri:,
  authorizationUri:)` takes a function that builds the authorization URI
  from the redirect URI actually used (a loopback browser picks its port).
  `LoopbackAuthorizationWindow` (`dart:io`: a one-shot server on
  `127.0.0.1`, any free port, the system's browser) serves Windows and
  Linux; `PlatformAuthorizationWindow` Android, iOS and macOS. In a
  browser there is none and `login` throws: use `oauth2Login()` on the
  server.
- `OAuth2TokenRevocationClient` (RFC 7009), only for that logout: Spring
  has no revocation client either.
- `SecretStore` (not a Spring type): a small secret store,
  `read` / `write` / `delete` of strings by key; `PlatformSecretStore` on
  the platform's secure storage, `InMemorySecretStore` where there is none
  (the web). `SecretStoreOAuth2AuthorizedClientService` keeps the
  authorized clients there as JSON; `SecretTemplate` the app's own
  objects.

**Auto-configuration** of the Flutter security package, registered
`before` the client's: the `SecretStore` (the platform's, else in
memory), `SecretTemplate`, the `AuthorizationWindow` of the platform, the
`PrincipalNotifier`, and with a registration the
`SecretStoreOAuth2AuthorizedClientService` (in place of the client's
in-memory one) and `OAuth2LoginService`.

| Platform | `SecretStore` | `AuthorizationWindow` |
|---|---|---|
| iOS, macOS | Keychain, generic passwords, this device only, not synced | `PlatformAuthorizationWindow`: `ASWebAuthenticationSession` |
| Android | values sealed with an AES-256-GCM key of the Android Keystore, in the app's private preferences | `PlatformAuthorizationWindow`: Custom Tabs, the redirect caught by the plugin's `RedirectReceiverActivity`, declared with its scheme in the app's manifest |
| Windows | DPAPI (`CryptProtectData`, current user) through FFI, in the app's support directory | `LoopbackAuthorizationWindow` |
| Linux | the Secret Service through libsecret (FFI) | `LoopbackAuthorizationWindow` |
| Web | none (the login runs on the server) | none |

The app sets only its redirect scheme (Android: the package's
`RedirectReceiverActivity` with an intent filter in the app's
`AndroidManifest.xml`, so apps that never log in configure nothing; the
iOS / macOS callback scheme comes from the redirect URI). See
[spring_boot_starter_flutter_security.md](spring_boot_starter_flutter_security.md)
and the package's
[README](../spring_boot_starter_flutter_security/README.md#the-app-login).

## Example

Done (October 2026). `example/server_guide` and `example/flutter_guide`
log in with Keycloak ([example/keycloak](../example/keycloak/README.md):
`docker compose up`, a realm `neon` with the same users and roles, a
confidential client for the server, a public one for the app), both with
a profile `sso`; without it the form login runs as before, no Keycloak
needed.

- The server ([chapter 4](../example/server_guide/README.md#single-sign-on-with-keycloak)):
  a second API chain with `oauth2Login()` for Flutter web (back to the
  web app's configured URL), `oauth2ResourceServer().jwt()` for the
  native apps (audience `neon-api`), Keycloak's realm roles (a `roles`
  claim) as `ROLE_*` through a `GrantedAuthoritiesMapper` and the
  resource server's properties, `preferred_username` as the name. The
  logout answers the `end_session_endpoint` URL as JSON (the app logs out
  with `fetch`, which cannot follow the redirect of
  `OidcClientInitiatedLogoutSuccessHandler`).
- The app ([chapter 7](../example/flutter_guide/README.md#single-sign-on-with-keycloak)):
  `OAuth2LoginService` on iOS, Android, macOS (`books.neon.app:` scheme)
  and Windows, Linux (loopback), `restore()` at startup, logout with
  revocation and the end of Keycloak's session; the web navigates to the
  server's login and keeps only the session cookie
  (`FetchCredentials.include`, the CSRF cookie read from the page). The
  tokens go on Feign calls through an interceptor of the app, not
  `spring.cloud.openfeign.oauth2.enabled`: that one fails calls made
  without a user, and the catalog is public.
- Checked end to end against Keycloak 26.8: the browser's login,
  session, CSRF and logout; bearer tokens of root (ADMIN) and ada (403);
  the app's login with the loopback window (on the VM, before the login
  moved to the Flutter security package).

## Later

- ~~Tokens on WebSocket handshakes~~ (done, October 2026:
  `OAuth2AccessTokenHeaders` writes `Bearer`, or `DPoP` and a proof whose
  `htu` is the `http(s)` form of the `ws(s)` URL, for a handshake
  interceptor; browsers send the session cookie of the server mode).
  Not done: a ready-made handshake interceptor (the client does not
  depend on the WebSocket starter).
- ~~The differential test of `oauth2Login()` against Spring Security,
  mutation testing of the new code~~ (done, October 2026), the plain
  `http://` warning and the one discovery (done), and the rest of the
  hardening: see
  [spring_boot_starter_flutter_security.md](spring_boot_starter_flutter_security.md),
  sections 5 (providers: Google, Apple), 6 (DPoP) and 7.
- Back-channel logout, `saml2Login()` (needs an XML signature stack),
  Pushed Authorization Requests. DPoP: the client's side in Dart is done
  (proofs, nonces, `DPoPKey`, `LoadableDPoPKey`, `SoftwareDPoPKey`, the
  `dpop` property, `auto` by default); the native keys of the apps are
  in the Flutter security package (section 6 of its plan), the
  WebCrypto key of the web next.
- From the comparison with Spring Security 7
  ([docs/security-spring-comparison.md](../docs/security-spring-comparison.md)):
  the token exchange grant (RFC 8693) and the JWT bearer grant
  (RFC 7523); client authentication with `private_key_jwt`,
  `client_secret_jwt` and `tls_client_auth`; the registration chosen per
  HTTP client (Spring 7's `@ClientRegistrationId`), not only per Feign
  client name; an authorized client service in a database, with a data
  starter. The password grant stays out: Spring Security 7 removed it.
