# spring_boot_starter_oauth2_client and SSO (in progress, October 2026)

Single sign-on with OAuth 2.0 and OpenID Connect, for servers and apps,
with Spring Boot's properties. Three parts:

1. **`spring_boot_starter_oauth2_client`** (new, pure Dart: the VM,
   Flutter, the web): registrations and providers, discovery, PKCE, the
   token endpoint, refresh, the authorized clients, the users
   (`OAuth2User`, `OidcUser`), the login of an app, tokens on Feign
   calls. Spring's `spring-security-oauth2-client` and
   `spring-boot-starter-oauth2-client`.
2. **`oauth2Login()` in `spring_boot_starter_security`**: the server logs
   the browser in (authorization code flow, the session keeps the user).
   Pages rendered by the server and Flutter web use it.
3. **Flutter, in `spring_boot_starter_flutter`** (which becomes a
   plugin): the `TokenStore` on the platform's secure storage and the
   login window of the system browser, both on our own platform code.

## Which flow where (the security decision)

| Client | Flow | Tokens live |
|---|---|---|
| Server pages | `oauth2Login()`: the server is a confidential client | on the server, in the session |
| Flutter web | the same, the server is the app's backend (BFF) | on the server; the browser has only the `HttpOnly` session cookie |
| Flutter iOS, Android, macOS | authorization code + PKCE, a public client (RFC 8252), the system browser | Keychain / Keystore (`TokenStore`) |
| Flutter Windows, Linux | the same, the redirect to a loopback server on `127.0.0.1` | DPAPI / libsecret (`TokenStore`) |
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
with its third-party dependency): an app trusts the ID token it got
directly from the token endpoint over TLS, as OpenID Connect Core 3.1.3.7
allows; the server checks the signature too (part 2).

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
(load, save, remove); `InMemoryOAuth2AuthorizedClientService` and
`TokenStoreOAuth2AuthorizedClientService` (JSON in a `TokenStore`);
`OAuth2AuthorizedClientManager` that refreshes a token expiring within
the clock skew (60 s) and runs one refresh at a time per client, and gets
client-credentials tokens.

**`TokenStore`** (not a Spring type): a small secret store,
`read` / `write` / `delete` of strings by key. `InMemoryTokenStore` by
default; the Flutter starter replaces it with the platform's secure
storage.

**Users:** `OAuth2User`, `DefaultOAuth2User`, `OidcUser`,
`DefaultOidcUser`, `OAuth2AuthenticationToken` (an `Authentication`);
`DefaultOAuth2UserService` (the user-info endpoint), `OidcUserService`
(user info when the endpoint exists, `sub` must match);
`GrantedAuthoritiesMapper`. Authorities as Spring: `OIDC_USER` or
`OAUTH2_USER` and `SCOPE_<scope>`. `OidcIdTokenValidator`: `iss`, `aud`
contains the client id, `azp`, `exp` and `iat` with the clock skew,
`nonce`.

**The login of an app** (no Spring counterpart, Spring has no apps):

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
  `OAuth2AuthorizedClientService` (so in the `TokenStore`), the
  `OAuth2AuthenticationToken` put in the `SecurityContextHolder`,
  `AuthenticationSuccessEvent` published. `restore()` at startup brings
  back the user of the stored tokens (refreshing them if needed);
  `logout()` revokes the tokens (RFC 7009, when the provider has the
  endpoint), removes them, clears the context, publishes
  `LogoutSuccessEvent`; ending the provider's session in the browser is
  optional.
- `AuthorizationBrowser`: opens the provider's page and completes with
  the URI the provider redirected to. `authorize(redirectUri:,
  authorizationUri:)` takes a function that builds the authorization URI
  from the redirect URI actually used (a loopback browser picks its port).
  `LoopbackAuthorizationBrowser` (pure `dart:io`: a one-shot server on
  `127.0.0.1`, any free port, the system's browser) serves the VM and
  desktops; the Flutter starter gives the native one. In a browser it
  throws: use `oauth2Login()` on the server.

**Feign:** `OAuth2AccessTokenInterceptor` adds `Authorization: Bearer`
with a fresh token of the current user (or of the client, for client
credentials), with Spring Cloud OpenFeign's properties
`spring.cloud.openfeign.oauth2.enabled` and
`spring.cloud.openfeign.oauth2.client-registration-id`. On a 401 the
token is refreshed once and the call repeated.

**Auto-configuration:** the repository when a registration is set, the
authorized client service on the `TokenStore`, the manager, the token
clients, the user services, `OAuth2LoginService` and the loopback
browser where `dart:io` exists, the Feign interceptor when enabled.

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
  fixation). Later: the differential test against Spring's `oauth2Login()`
  and mutation testing.

## 3. Flutter (spring_boot_starter_flutter; moving to spring_boot_starter_flutter_security)

The starter becomes a Flutter plugin (iOS, Android, macOS, Windows,
Linux) with its own platform code, no community plugins:

| Platform | `TokenStore` | `AuthorizationBrowser` |
|---|---|---|
| iOS, macOS | Keychain, generic passwords, this device only, not synced | `ASWebAuthenticationSession` |
| Android | values sealed with an AES-256-GCM key of the Android Keystore, in the app's private preferences | Custom Tabs, the redirect caught by the plugin's `RedirectReceiverActivity`, declared with its scheme in the app's manifest |
| Windows | DPAPI (`CryptProtectData`, current user) through FFI, in the app's support directory | loopback |
| Linux | the Secret Service through libsecret (FFI) | loopback |
| Web | none (the login runs on the server) | none |

Both replace the pure-Dart defaults by auto-configuration; the app sets
only its redirect scheme (Android: the starter's `RedirectReceiverActivity`
with an intent filter in the app's `AndroidManifest.xml`, so apps that
never log in configure nothing; the iOS / macOS callback scheme comes
from the redirect URI). Done for the Flutter part (October 2026): see
[spring_boot_starter_flutter.md](spring_boot_starter_flutter.md#tokens-and-secrets-of-the-user).

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
  the app's login on the VM with the loopback browser.

## Later

- Tokens on WebSocket handshakes (a header on the VM and mobile, a query
  parameter or protocol in browsers).
- The differential test of `oauth2Login()` against Spring Security,
  mutation testing of the new code, and the rest of the hardening: see
  [spring_boot_starter_flutter_security.md](spring_boot_starter_flutter_security.md),
  sections 5 (providers: Google, Apple), 6 (DPoP) and 7.
- Back-channel logout, `saml2Login()` (needs an XML signature stack),
  Pushed Authorization Requests. DPoP comes with the Flutter security
  package (section 6 of its plan).
