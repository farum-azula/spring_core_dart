# spring_boot_starter_flutter_security (next: started on 30 October 2026)

The security part of a Flutter app in a package of its own: the app
login, the platform code that keeps secrets and opens the login window,
a template for the app's own secrets, widgets that follow the logged-in
user, and the login screens. It took the platform code out of
`spring_boot_starter_flutter` and the app login out of the OAuth2 client
([spring_boot_starter_oauth2_client.md](spring_boot_starter_oauth2_client.md),
section 3).

## Why a package of its own

Since SSO, every app with `spring_boot_starter_flutter` gets the OAuth2
client, Feign, `spring_security_core` and the plugin's native code
(Swift, Kotlin, `androidx.browser`, two activities in the Android
manifest), even an app without any login. Tree shaking does not remove
it: the generated `main.spring.dart` lists the OAuth2 client's
auto-configuration, whose bean definitions reference that code, and their
conditions are decided at run time; native code is always built in. As
in Spring, an app adds security when it needs it:

- `spring_boot_starter_flutter`: back to widgets, beans, themes, profiles;
  no platform code, no OAuth2 client, Feign or security dependency.
- `spring_boot_starter_flutter_security`: depends on (and re-exports)
  `spring_boot_starter_flutter`, `spring_boot_starter_oauth2_client` and
  `spring_security_core`, so an app lists only this one package.
- ~~Measure first: the size of a minimal app (release APK and web) with
  the starter as it is now and without the OAuth2 part, so the docs can
  say what security costs.~~ Done (October 2026, Flutter 3.47): a
  minimal app with `spring_boot_starter_flutter` and the same app with
  this package: the release APK +0.54 MB (arm64-v8a 16.7 → 17.2 MB; 512
  KiB of Dart code, 17 KB of `classes.dex`), the web's `main.dart.js`
  +0.37 MB (2.34 → 2.71 MB; +0.12 MB gzipped). In the README, "What
  security costs".

## 1. Moved from spring_boot_starter_flutter

**Done (October 2026).** The package exists (a Flutter plugin outside the
pub workspace, like the Flutter starter); the Flutter starter has no
platform code, no plugin section and no dependency on the OAuth2 client
again. The names chosen: `SecretStore` / `InMemorySecretStore` /
`SecretStoreOAuth2AuthorizedClientService`, `PlatformSecretStore` /
`PlatformSecretStoreException`; `AuthorizationWindow` /
`LoopbackAuthorizationWindow`, `PlatformAuthorizationWindow` /
`AuthorizationWindowException` (all here since the move of section 1b);
the module `springBootStarterFlutterSecurityAutoConfiguration`; the
Kotlin package and the Swift class follow the package
(`dev.farumazula.spring_boot_starter_flutter_security`,
`SpringBootStarterFlutterSecurityPlugin`), and so do the channels and the
storage names (secrets stored under the old names are not migrated:
nothing was published). The integration tests stay in
`example/flutter_guide/integration_test` (they need an app). The app
sizes are measured (see "Why a package of its own").

What was planned:

- The plugin: `darwin/` (Swift: Keychain, `ASWebAuthenticationSession`),
  `android/` (Kotlin: Keystore, Custom Tabs, the redirect and
  management activities), the Windows (DPAPI) and Linux (libsecret)
  stores on `dart:ffi`, the web entry that registers nothing.
- `SecureTokenStore`, `PlatformAuthorizationBrowser`, their
  auto-configuration (before `springBootStarterOauth2ClientAutoConfiguration`;
  the client's module then names this package's module in its `after`),
  their tests and integration tests, the README section "Login and
  tokens".
- **Renames** (the names confused): `PlatformAuthorizationBrowser` opens
  the system's login window (Safari / Chrome sheet, the default browser)
  and waits for the redirect, it is no browser; candidates
  `AuthorizationWindow`, `SystemLoginWindow`. `AuthorizationBrowser` of
  the OAuth2 client and `LoopbackAuthorizationBrowser` follow.
  `TokenStore` keeps any secret, not only tokens: `SecretStore`.

## 1b. Moved from spring_boot_starter_oauth2_client

**Done (October 2026).** The OAuth2 client is exactly Spring's
`spring-security-oauth2-client` with Boot's
`spring-boot-starter-oauth2-client`; everything about logging an app in,
which Spring does not have, is here:

- `OAuth2LoginService` (`login`, `restore`, `logout`) and
  `OAuth2TokenRevocationClient`, which only its logout uses (Spring has
  no revocation client).
- `AuthorizationWindow`, `AuthorizationCancelledException`,
  `LoopbackAuthorizationWindow` (now the window of Windows and Linux;
  `PlatformAuthorizationWindow` stays the one of iOS, Android and macOS).
  The client has no `dart:io` left.
- `SecretStore`, `InMemorySecretStore`, `SecretTemplate`,
  `SecretStoreOAuth2AuthorizedClientService`.
- Their beans (`platformSecretStore` or `inMemorySecretStore`,
  `secretTemplate`, `platformAuthorizationWindow` or
  `loopbackAuthorizationWindow`, `authorizedClientService`,
  `oauth2LoginService`), in this package's module, which comes `before`
  the client's so its `OAuth2AuthorizedClientService` replaces the
  client's `InMemoryOAuth2AuthorizedClientService`. The client's module
  names no other module. The login beans are conditional on a
  registration property or an application's `ClientRegistrationRepository`
  (as the security starter's decoder): a `@ConditionalOnBean` here would
  not see the client's repository yet.
- Kept in the client: `TokenEndpointOidcIdTokenDecoder` as its default
  `OidcIdTokenDecoder`, because the refresh of authorized clients uses it
  too; the security starter replaces it on servers.

## 2. Secrets of the app: SecretStore and SecretTemplate

**Done (October 2026).** `keys()` and `deleteAll()` on every store (in
memory, Keychain, Keystore, DPAPI, libsecret). `SecretTemplate`, next to
`SecretStore` (first in the OAuth2 client, here since section 1b): a bean
(`secretTemplate`), namespace `app` by default, `oauth2` refused,
`UnsupportedError` on the web. Not run on a device yet: the
libsecret `keys()` (`secret_password_searchv_sync`) and DPAPI listing.

What was planned:

The store is a plain secret store (key -> string): an app may keep its
own secrets there (a PIN, an API key, the key of an encrypted local
database), not only the login's tokens.

- `SecretStore` (today's `TokenStore`): `read`, `write`, `delete`, plus
  `keys()` and `deleteAll()`.
- `SecretTemplate`, like Spring Vault's `VaultTemplate` (secrets by path)
  and `RedisTemplate` (objects through a serializer): objects as JSON
  through the `ObjectMapper`.

  ```dart
  await secrets.write('pin', PinSettings(hash: h, attempts: 0));
  final pin = await secrets.read<PinSettings>('pin');
  await secrets.delete('pin');
  ```

- Namespaces: the app's keys never collide with the OAuth2 client's
  (`oauth2.*`).
- The limits, said in the docs: for small secrets, not data (the Keychain
  is no database); to protect much data, keep only its encryption key
  here.
- The web has no secure storage: the template fails there with a clear
  error, never falls back to memory or `localStorage` silently.

## 3. Widgets that follow the user (display only)

**Done (October 2026).** `PrincipalNotifier` (a bean) listens through
`ListeningSecurityContextHolderStrategy` (added to `spring_security_core`
with `SecurityContextChangedListener` and `SecurityContextChangedEvent`,
Spring Security's names) and to the authentication events;
`context.principal`, `PrincipalBuilder`, `PrincipalView` (`hasRole`,
`hasAuthority`, `authenticated`, `expression` through the
`MethodSecurityExpressionHandler` bean). The Flutter guide's `Session`
keeps its own notification: it also runs the logins, and its widgets
read it in many places.

What was planned:

Not security: the app is in the user's hands (it can be patched, the API
called directly), so hiding a button protects nothing; the server's
checks (a 403) do. The same holds for `@PreAuthorize` on the app's own
beans. These widgets only spare the user buttons that would fail, like
Thymeleaf's `sec:authorize`, which only decides what a page renders.

Named after the principal (Spring's word for who is logged in:
`@AuthenticationPrincipal`, Thymeleaf's `sec:authentication="principal"`),
not after security, so they promise no protection; the first line of
their docs: "for display only, the server checks access".

- `PrincipalNotifier`: the current `Authentication` as a `Listenable`,
  changed on login and logout (what `Session` of `flutter_guide` does by
  hand today); `context.principal` reads it in `build` and rebuilds the
  widget when it changes.
- `PrincipalBuilder`: builds with the current authentication (`null`
  when nobody is logged in).

  ```dart
  PrincipalBuilder(
    builder: (context, authentication) => authentication == null
        ? const LoginButton()
        : Text('Hello, ${authentication.name}'),
  )
  ```

- `PrincipalView`: a child for a principal that matches, another one
  otherwise; `hasRole`, `hasAuthority`, `authenticated`, or a SpEL
  expression as in `@PreAuthorize`.

  ```dart
  PrincipalView(
    hasRole: 'ADMIN',
    child: const AdminMenu(),
    otherwise: const SizedBox.shrink(),
  )
  ```
- Later, with the starter's navigation: routes that send a logged-out
  user to the login screen.

## 4. Login screens

**Done (October 2026).** `LoginForm` (the `AuthenticationManager` bean,
the checks, progress, one text for a wrong name, password, unknown user
or refused account and another for service failures, the security
context set and an `InteractiveAuthenticationSuccessEvent` as Spring's
form login, autofill hints, the obscured password with a toggle,
`fieldBuilder` / `submitButtonBuilder` / `errorBuilder`, texts from the
app's messages); `OAuth2LoginButton(registrationId)` (the label from
`client-name`, a cancelled window silent, `onError`); `GoogleLoginButton`,
`AppleLoginButton`, `MicrosoftLoginButton`, `GitHubLoginButton`, only
what each brand's rules let an app choose as parameters. Decided: the
form and the provider button adapt to the app type (`LoginDesign`:
Material, Cupertino, plain widgets coloured from the `SpringTheme`)
instead of requiring Material; the brand buttons draw themselves the same
everywhere. The Google, Microsoft and GitHub logos are vector paths
from the owners' published artwork (sources and terms in the README and
`NOTICE`); Apple's artwork license forbids redistribution, so
`AppleLoginButton` takes the app's own copy. Tests:
`test/login_screens_test.dart` (designs, semantics, RTL, text scaling);
the brand buttons are a golden of the Flutter guide
(`goldens/login_buttons.png`), whose login page uses the form and the
provider button. Not done: Google Sans and Segoe UI are not shipped
(their owners'), so the goldens use Roboto in their place.

What was planned:

- A user name and password form on the `AuthenticationManager`: errors,
  progress, customised through the theme and builders.
- A button for any registration of the properties
  (`OAuth2LoginButton('keycloak')`).
- Ready buttons for Google, Apple, Microsoft, GitHub, customisable within
  what their brand rules allow (light / dark, shape, the allowed texts):
  Google's and Apple's guidelines fix colours, spacing, logo and text,
  and the stores reject buttons that break them.

## 5. Providers: what each needs

**Done (October 2026)** for Google and Apple, provider-agnostic where
possible (the provider names are in the presets and the docs only); the
docs are the sections "Login with Google" and "Sign in with Apple" of
the security starter's and this package's READMEs. As built:

- **https redirects.** Android App Links: the app declares the package's
  `RedirectReceiverActivity` with an `autoVerify` intent filter for the
  redirect's host and path (README: the manifest, `assetlinks.json`, the
  SHA-256 fingerprints of debug, upload and Play signing keys, `adb`
  checks); the plugin remembers the redirect URI of the login that runs
  and hands over only a link with the same scheme, host, port and exact
  path (`RedirectMatcher`, JVM unit tests), refuses `http://` redirects
  and, on Android 12+, an `https` host the system has not verified for
  the app (`redirect_not_verified`, before the page opens). iOS 17.4 /
  macOS 14.4: `ASWebAuthenticationSession`'s `.https(host:path:)` was
  already there (checked); documented with the `webcredentials:`
  associated domain the session needs and the
  `apple-app-site-association` file.
- **Google** (researched, not run with an account): the client types per
  platform and the redirect to use with the plugin (iOS client and the
  reversed client id; Android client with "Custom URI scheme" enabled in
  its advanced settings, since new Android clients refuse custom schemes
  by default from October 2023, and no `https` redirects for Android or
  iOS clients, so App Links do not help with Google; Desktop client with
  its non-secret secret; Web client on the server); roles through a
  `GrantedAuthoritiesMapper`, users by `sub`, refresh tokens not rotated.
- **Sign in with Apple, the app:** the plugin's `native_sign_in` channel
  (`ASAuthorizationAppleIDProvider`, scopes `name` / `email`, the
  nonce's SHA-256 hash, the state), `AppleIdSignIn` /
  `PlatformAppleIdSignIn` (bean `appleIdSignIn` on iOS and macOS),
  `NativeSignIn` and the registration property `native-sign-in`
  (`apple` by default for the `apple` provider, `none`). The identity
  token comes from the OS, so the app verifies its signature: the OAuth2
  client got `JwkSetOidcIdTokenDecoder` (RS256 / ES256 against the
  registration's JWK Set; the RSA and ECDSA verification and the PKCS #8
  reading added to its one pointycastle file), then the claims, the
  nonce, the state and `sub` = the sheet's user. The code is exchanged
  at the registration's `token-uri`, which must be the app's server
  (Apple's documented flow for apps with a server: the server verifies,
  exchanges the code with the client secret JWT, manages the session);
  no `redirect_uri` and no PKCE are sent (the sheet sent none; the token
  client now leaves `redirect_uri` out when the request had none). The
  first authorization's name goes into the user info, kept in the login
  record and carried to later sign-ins of the same user. On Android and
  desktops the registration uses the browser.
- **Sign in with Apple, the server:** `response_mode=form_post` in
  `oauth2Login()` (`ResponseMode` and the `response-mode` property in
  the client, `form_post` by default for the `apple` provider): the
  callback reads the posted form, requires the method the login asked
  for, exempts only the callback's `POST` from CSRF, warns when a post
  comes without a session (the cookie must be `SameSite=None; Secure`),
  and passes Apple's unsigned `user` to the user service only. The
  client secret: `JwtClientSecret` / `JwtClientSecretResolver` /
  `OAuth2ClientSecretResolver` in the OAuth2 client (`client-secret-jwt.*`:
  `issuer`, `key-id`, `private-key-location` or `private-key`,
  `audience`, `lifetime`), ES256 with the client's existing RFC 6979
  signer rather than a second one in the security starter, the bean
  `clientSecretResolver` used by the token response clients. Spring
  Security's `NimbusJwtClientAuthenticationParametersConverter` covers
  `private_key_jwt` / `client_secret_jwt` (`client_assertion`), not
  Apple's JWT as `client_secret`, so the helper is an addition, as is
  `CommonOAuth2Provider.apple`.
- Verified: unit tests in the three Dart packages and the Kotlin tests;
  the form post end to end against the local Keycloak 26
  (`oauth2_form_post_keycloak_e2e_test.dart`, tag `e2e`); the example
  built for Android, the iOS simulator and macOS. Not verified (no
  accounts): Google's consoles and token endpoint, Apple's sheet on a
  device (it needs the capability and a provisioning profile), Apple's
  token endpoint with a real `.p8` key, an App Link on a device with a
  verified domain, Universal Links / `webcredentials` with a real
  domain.

What was planned:

- **Google**
  - Android: Google no longer accepts custom URI schemes
    (`books.neon.app:`) for new Android clients, as far as known: check
    first; then App Links (https redirects, verified with
    `assetlinks.json`) in the plugin, or the native Credential Manager.
  - iOS: the reversed client id scheme
    (`com.googleusercontent.apps...:/oauth2redirect`) works.
  - Desktop: Google's "Desktop app" clients have a `client_secret` that
    Google itself calls not secret and requires in the token request;
    explain that it is no real secret (PKCE protects the code).
  - Google has no roles: the app maps users to authorities itself (its
    own `GrantedAuthoritiesMapper`, from its database or a list); keep
    users by `sub`, never by email, or only with `email_verified`
    (account takeover otherwise).
  - Refresh tokens are not rotated: one long-lived token, so its storage
    and revocation on logout matter.
  - A "Login with Google" section in the docs (server and app).
- **Apple** (needed in practice: the App Store asks for an equivalent
  privacy-focused login when an app offers Google's)
  - iOS / macOS: the native sheet (`ASAuthorizationAppleIDProvider`),
    not the browser.
  - The server: the `client_secret` is a JWT signed with the app's key
    (ES256); name and email come only on the first login and with
    `response_mode=form_post`, which `oauth2Login()` does not support yet
    (query only).
- **Microsoft, GitHub**: GitHub is OAuth 2.0 without OpenID Connect (user
  info only); Microsoft's issuer depends on the tenant.

## 5b. The web: two modes, the same API

A browser has no secure storage, but web apps log in all the same, so the
web gets the app login too, provider-agnostic, chosen by one property;
the code is the same as on phones (`login(registrationId)`, `restore()`,
`logout()`, `PrincipalBuilder`, Feign clients), no `kIsWeb` in the app.

```yaml
spring:
  flutter:
    security:
      web:
        mode: server        # server (default) | spa
        # server-url: https://api.example.com   # server mode, when not same origin
```

- **`server` (backend-for-frontend, the default, the strongest):**
  **done (October 2026).** The
  app's server logs in (`oauth2Login()`), tokens never reach the browser,
  which holds an `HttpOnly` session cookie. `login` navigates to the
  server's `/oauth2/authorization/{registrationId}`; `restore` asks the
  server who is logged in; `logout` posts the logout with the CSRF token,
  then ends the provider's session when it has `end_session_endpoint`;
  cookies (`FetchCredentials.include`) and the CSRF header (from the
  `XSRF-TOKEN` cookie) are added by the starter. Replaces the hand-written
  code of `flutter_guide`.

  As built: `OAuth2LoginService` became an interface, with
  `NativeOAuth2LoginService` (phones, desktops) and
  `ServerOAuth2LoginService` (the browser, bean `serverOAuth2LoginService`
  on the `web` platform profile; `login` returns `null` there, the page
  leaves). The properties `spring.flutter.security.web.mode`,
  `server-url`, `user-endpoint` (default `/user`, as Spring's guide
  "Spring Boot and OAuth2"), `logout-url` (`/logout`),
  `authorization-base-uri` (`/oauth2/authorization`). The user endpoint's contract:
  `{"name", "authorities", "registrationId", "attributes"}`, only `name`
  required (an `OAuth2AuthenticationToken` with `registrationId`, a
  `PreAuthenticatedAuthenticationToken`, new in `spring_security_core`,
  without); no controller in the security starter, a documented one
  instead (which user data a page sees is the server's decision). The
  logout answer: `{"logoutUrl"}` (the server guide's) or a `Location` on a
  `2xx` (`202 Accepted`), `http(s)` only; a script cannot follow Spring's
  redirect to the provider. `CsrfCookieHttpTransport` and the
  `httpTransport` bean (before Feign's; backs off for an application's
  own), `BrowserPage` behind an interface so all of it is tested on the
  VM. `flutter_guide` lost its `BrowserPage`, `BrowserSessionTransport`
  and its web restore; `/api/me` of the server guide answers
  `authorities` and `registrationId` too. Not done: a test in a real
  browser (`flutter test --platform chrome`).
- **`spa` (no server of one's own):** **done (October 2026).** PKCE in
  the browser as a public client, tokens in the tab's memory only,
  restored after a reload through the provider's session (`prompt=none`);
  DPoP with a non-extractable WebCrypto key (kept in IndexedDB as a
  `CryptoKey`, usable but not readable) when the registration uses it;
  refresh token rotation required (warned about); a Content Security
  Policy from `spring.flutter.web.*`. Needs a provider that accepts public
  browser clients and allows CORS on its token endpoint; otherwise a
  clear error points to `server`.

  As built: `SpaOAuth2LoginService` (bean `spaOAuth2LoginService` with
  `mode=spa`; the start fails without a registration). `login` builds the
  client's `OAuth2AuthorizationRequest.forRegistration` (plus `dpop_jkt`
  with DPoP), keeps it in `sessionStorage` for the round trip only (the
  verifier is useless without the code) and navigates the page; `restore`
  finishes the login when the page is back on the redirect URI (default
  in the docs: `{baseUrl}/`, the page) with the native login's checks,
  cleans the address bar (`history.replaceState`, the app's parameters
  and the route kept) and `sessionStorage`; an answer the tab did not ask
  for, or older than 10 minutes, logs nobody in; a refused login throws.
  The restore decision: a hidden iframe breaks with third-party cookie
  blocking and a refresh token in memory dies with the reload, so the
  silent login is a top-level `prompt=none` redirect, made only when a
  hint in `localStorage` (the registration id, no secret) says this
  browser logged in before, never twice in a row; `login_required` (and
  the other `prompt=none` errors) is nobody;
  `spring.flutter.security.web.silent-restore=false` turns it off.
  `logout` forgets, revokes (best effort), and always ends the provider's
  session (`end_session_endpoint`, back to the app). The tokens:
  `TabOAuth2AuthorizedClientService` (memory; a refresh that keeps the
  refresh token is a warning, once). The key: `WebCryptoDPoPKey`
  (`webCryptoDPoPKey`, a `LoadableDPoPKey` made at the first proof;
  `BrowserKeyVault` / `BrowserKeyPair` around WebCrypto and IndexedDB,
  in memory where IndexedDB is refused). The page: `SpaBrowserPage`
  (base URI, `replaceLocation`, the two storages as `BrowserStorage`),
  all on `dart:js_interop`, no package. The CSP: the generator's
  `spring.flutter.web.content-security-policy` (and `-report-only`) in
  `web_dev_config.yaml`, a ready policy in spa mode with the providers'
  origins; the production host's headers documented. Tests on the VM
  (`test/spa_login_test.dart`: the round trip and its attacks, the
  exchange, the cleanup, the silent login, logout, DPoP with a fake
  vault, rotation) and against the local Keycloak
  (`test/spa_keycloak_e2e_test.dart`, tag `e2e`: a scripted browser with
  cookies through the login form; DPoP tokens bound to the key, the
  silent login, the logout, `login_required`, CORS of `neon-web`).
  `flutter_guide` has an optional `spa` profile, Keycloak the public
  client `neon-web`. Not done: a run in a real browser (the WebCrypto,
  IndexedDB and history code is only compiled), the example's API calls
  with the token in spa mode (its token interceptor is native-only and
  the server guide's CORS does not allow `Authorization` / `DPoP`).
- **Flutter web and XSS:** Flutter draws on a canvas and never turns data
  into HTML, so the classic DOM XSS is mostly gone; what remains is
  foreign scripts in `index.html` (analytics, tag managers), the supply
  chain, `HtmlElementView` with user HTML, `javascript:` URLs, other
  content served from the same origin, browser extensions. The docs say
  so.
- **`SecretStore` on the web:** the tab's memory (gone with the tab), no
  disk; named and documented as such. No WebAssembly "vault": Wasm memory
  is readable by any script of the page. What isolates in a browser: a
  non-extractable WebCrypto key, a separate origin in an iframe, (weakly)
  a worker.

## 6. DPoP: tokens bound to the app's key (server and app)

A `Bearer` access token works for whoever holds it until it expires. With
DPoP (RFC 9449) it is bound to a key that only the app has, so a stolen
token is useless. Spring Security accepts DPoP-bound tokens since 6.5;
so does the security starter now (the server part below is done); the
apps' part in Dart is done in the OAuth2 client, the native keys of the
apps here, and the WebCrypto key of the web (`spa` mode, section 5b).

How it works:

1. The app creates an ES256 key pair once; the private key stays in the
   Keystore / Secure Enclave (signing happens there, the key is never
   exported), DPAPI / libsecret on desktops.
2. The token request (code, refresh) carries a `DPoP` header: a JWT
   proof (`typ: dpop+jwt`, the public `jwk` in its header; `htm`, `htu`,
   `iat`, a one-time `jti`) signed with the private key. The provider
   returns a token of type `DPoP` whose `cnf.jkt` is the thumbprint
   (RFC 7638) of that key.
3. Each API call sends `Authorization: DPoP <token>` and a new proof for
   that request, with `ath`, the hash of the token.
4. The server checks: the token as today; the proof's type, an
   asymmetric algorithm (no `none`, no HS*), its signature by its `jwk`
   (no private key in it); `htm` and `htu` equal to the request (the
   external URL behind proxies); a fresh `iat`; `jti` not seen before
   (kept for the freshness window; shared between instances like the
   sessions); `ath`; the key's thumbprint equal to `cnf.jkt`. A token
   with `cnf.jkt` sent as `Bearer` without a proof is refused. Errors:
   `WWW-Authenticate: DPoP error="invalid_dpop_proof"`; optional
   `DPoP-Nonce` challenges.

Server (`spring_boot_starter_security`), with Spring Security's names and
behaviour: **done (October 2026)**. DPoP-bound tokens are accepted by
`oauth2ResourceServer().jwt()` next to `Bearer` ones; `DPoPProofContext`,
`DPoPProofJwtDecoderFactory`, `DPoPAuthenticationToken`,
`DPoPAuthenticationProvider`, `DPoPAuthenticationFilter`,
`DPoPAuthenticationEntryPoint`, the `jti` cache (`DPoPProofJtiCache`,
in memory by default: 100 000 ids, 1 000 per key, fail closed, as Spring
7's), `Jwt.jwkThumbprint`; the shared `JwkThumbprint`,
`DPoPProofClaims` and `TokenType.dpop` in the OAuth2 client. The attacks
are tests (`test/dpop_test.dart`, rows in docs/security.md); the
differences from Spring are in the starter's README. Not done: nonces
(`DPoP-Nonce`; Spring's resource server has none either), a shared `jti`
store, `htu` behind a TLS-terminating proxy (needs the web starter's
forwarded headers). The differential test and the mutation score of the
DPoP code are done (section 7).

App, the Dart part (`spring_boot_starter_oauth2_client`): **done
(October 2026)**. `DPoPKey`, `SoftwareDPoPKey` (ES256 in Dart with
pointycastle, RFC 6979 nonces; `toJwk` / `fromJwk` for whoever stores
it), `DPoPProofBuilder`, `ECDSA.transcodeSignatureToConcat` (DER to raw
`R || S`, for the native keys); proofs on the token requests (code,
refresh, client credentials) with `use_dpop_nonce` answered once,
`token_type: DPoP` read (`Bearer` kept when the provider issues it); the
Feign interceptor's `DPoP <token>` and proof per call, nonces remembered
per server from error answers; the user services' DPoP calls; the
registration's `dpop` property (`auto`, the default since the native
keys, the stored DPoP tokens and the handshake proofs below: on when the
discovery lists ES256 in `dpop_signing_alg_values_supported`; `true`;
`false`); the
`dPoPKey` bean, a `SoftwareDPoPKey` per run (`ConditionalOnMissingBean`).
Tests in `test/dpop_client_test.dart` of both starters (the second sends
the client's proofs through the resource server chain).

App, the native part (this package): **done (October 2026)**.
`PlatformDPoPKey`, the `DPoPKey` bean `platformDPoPKey`, registered
before the OAuth2 client's module (whose per-run key backs off), not on
the web: an EC P-256 key made in the Secure Enclave on iOS and macOS
(permanent, tagged `<bundle id>.spring_dpop_key`, after first unlock,
this device only), a software key of the Keychain where the Secure
Enclave is missing or unusable (Macs without one, macOS builds without
the data protection keychain's entitlements), signed with
`SecKeyCreateSignature` (DER, turned into `R || S` in Dart); an EC P-256
key of the Android Keystore (`PURPOSE_SIGN`, SHA-256, StrongBox with a
fallback), `SHA256withECDSA`, the public JWK from the X.509 key;
`SecretStoreDPoPKey` on Windows and Linux (a `SoftwareDPoPKey` kept as a
JWK under `oauth2.dpop-key`). The channel `dpop_key` (`dpopPublicJwk`,
`dpopSign`, `dpopDelete`); the key is made at the first proof
(`LoadableDPoPKey` in the client: `DPoPProofBuilder` awaits `load()`); a
key gone is `no_key` and replaced at the next proof.
`SecretStoreOAuth2AuthorizedClientService` keeps the token type and,
for DPoP tokens, the key's thumbprint: tokens bound to another key are
dropped at load (the user logs in again); records without a type read
as `Bearer`. Logout deletes the key (a key per login); `restore()`
treats `invalid_dpop_proof` as a refused login. Proofs on WebSocket
handshakes and calls of the app's own: `OAuth2AccessTokenHeaders` in the
client (`ws(s)` URLs become `http(s)` in `htu`), used by the Feign
interceptor and the example's `SupportHandshake` (browsers send the
session cookie instead). Tests: `test/dpop_key_test.dart` (mocked
channel), `example/flutter_guide/integration_test/dpop_key_test.dart`
run on macOS (the Keychain key of a debug build), the iOS 27 simulator
(its emulated Secure Enclave) and an Android 17 emulator (the Keystore
without secure hardware), each proof checked with pointycastle.

Not done: a run on a StrongBox phone, on Windows and Linux, and end to
end against Keycloak with DPoP on a phone (the web's spa login is tested
against Keycloak with DPoP); proofs on `RestClient` calls (when it exists); the retry of a
Feign call answered `use_dpop_nonce` and nonces from successful answers
(Feign shows neither to the interceptor).

Providers: Keycloak, Okta, Auth0, Ping, Curity and Spring Authorization
Server support it; Google, Apple, GitHub and Microsoft Entra ID (which has
its own proof-of-possession) do not, as far as known (check before).

### Design: types and names

No DTOs mapped by the `ObjectMapper`: as the JWT code here and Spring
Security's `Jwt`, tokens and proofs are header and claim maps with typed
getters, read strictly (exact types, no coercion, nothing unexpected
accepted) and written by hand. The signature covers the base64url
strings, not an object, and the key thumbprint (RFC 7638) is a SHA-256 of
an exact JSON text (required members only, sorted, no spaces), which no
serializer guarantees.

Already there (security starter, `lib/src/jwt/`): `Jwt`, `ParsedJws`,
ES256 / RS256 / PS256 verification (`EcVerificationKey`,
`RsaVerificationKey` from a JWK), `OAuth2TokenValidator<Jwt>`. Missing:
signing, thumbprints, everything of DPoP.

Shared (`spring_boot_starter_oauth2_client`, used by the server and the
app):

```dart
/// RFC 7638: SHA-256 of {"crv","kty","x","y"} (EC) or {"e","kty","n"}
/// (RSA), members sorted, no spaces; base64url.
abstract final class JwkThumbprint {
  static String of(Map<String, Object?> jwk);
}

/// The claims of a DPoP proof.
final class DPoPProofClaims {
  final String jti;     // one-time id
  final String htm;     // HTTP method
  final Uri htu;        // URL without query and fragment
  final DateTime iat;
  final String? ath;    // base64url(SHA-256(access token)), on API calls
  final String? nonce;  // when the server asked for one

  Map<String, Object?> toJson();                // the app writes it
  factory DPoPProofClaims.fromJson(Map claims); // the server reads it, strictly
                                                // (Jwt is the security starter's)
}
```

Plus the `cnf` claim (`jkt`) on `Jwt` and `DPoP` as a token type of
`OAuth2AccessToken` next to `Bearer`.

Server (`spring_boot_starter_security`, Spring Security 6.5's names; done,
as sketched, with `ath` checked by the factory and `cnf.jkt` by the
provider):

```dart
final class DPoPProofContext {        // what the proof is checked against
  final String dPoPProof;             // the DPoP header
  final String method;                // the request's method
  final Uri targetUri;                // the external URL (behind proxies)
  final String? accessToken;
}

final class DPoPProofJwtDecoderFactory {
  JwtDecoder createDecoder(DPoPProofContext context);
  // the key from the proof's own `jwk` header (EC / RSA, public only),
  // asymmetric algorithms only (no none, no HS*), validators: typ, htm,
  // htu, iat window, jti replay, ath
}

final class DPoPAuthenticationToken extends AbstractAuthenticationToken {}

final class DPoPAuthenticationProvider implements AuthenticationProvider {
  // 1. the access token through the usual JwtDecoder (iss, aud, exp)
  // 2. the proof through DPoPProofJwtDecoderFactory
  // 3. JwkThumbprint.of(proof jwk) == the token's cnf.jkt
  // -> a JwtAuthenticationToken, as for Bearer
}
```

- `Authorization: DPoP <token>` resolved next to `Bearer`; a token with
  `cnf.jkt` sent as `Bearer` without a proof is a 401.
- The `jti` cache with the freshness window as TTL (in memory; shared
  later, for replicas and several isolates).
- `WWW-Authenticate: DPoP algs="ES256 RS256 ...", error="invalid_dpop_proof"`;
  `DPoP-Nonce` optional.
- On by itself: `oauth2ResourceServer().jwt()` accepts both kinds, as in
  Spring.

App (`spring_boot_starter_oauth2_client` and this package):

```dart
/// The key that signs proofs; its private part never leaves it.
abstract interface class DPoPKey {
  JwsAlgorithm get algorithm;               // ES256
  Map<String, Object?> get publicJwk;       // {"kty":"EC","crv":"P-256","x","y"}
  Future<Uint8List> sign(Uint8List input);  // raw R||S (64 bytes), not DER
}

final class DPoPProofBuilder {
  DPoPProofBuilder(this.key);
  Future<String> build({
    required String method,
    required Uri url,
    String? accessToken,   // -> ath
    String? nonce,
  });
  // {"typ":"dpop+jwt","alg":"ES256","jwk":{...}} + the claims,
  // base64url(header).base64url(claims), signed, base64url(signature)
}
```

- `DPoPKey` per platform: the Secure Enclave on iOS / macOS
  (`SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave`), the
  Android Keystore (an EC key with `PURPOSE_SIGN`); both sign in DER,
  converted to raw R||S (32 + 32 bytes) as JOSE wants. Windows, Linux
  and the VM: a key made in Dart (pointycastle), kept in the
  `SecretStore`, signed in Dart.
- The token response clients add `DPoP` to code and refresh requests and
  answer a `use_dpop_nonce` error once with the nonce (done).
- The Feign / `RestClient` interceptors send `DPoP <token>` and a fresh
  proof with `ath` for DPoP tokens; nonces remembered per server (Feign
  done; `RestClient` when it exists).
- On by itself when the discovery has `dpop_signing_alg_values_supported`,
  or with `spring.security.oauth2.client.registration.<id>.dpop=true|false`
  (done).
- As built, `DPoPKey.algorithm` is the `alg` name (`String`), not the
  security starter's `JwsAlgorithm` (the client cannot depend on it).

Tests: the RFC 9449 and RFC 7638 examples as vectors; the attacks (a
replayed `jti`, another key, a wrong `htm` / `htu` with query and case,
a stale `iat`, a wrong or missing `ath`, `Bearer` for a bound token,
`alg: none` and HS256 in a proof, a private `d` in the proof's `jwk`, a
DER signature instead of R||S); end to end with Keycloak, which issues
DPoP tokens.

## 7. Hardening of the SSO (from the review of October 2026)

The protocol attacks are covered by tests (see docs/security.md). Done
in October 2026, except where said:

- ~~The differential test of `oauth2Login()` against Spring Security, and
  mutation testing of the OAuth2 client and the login.~~ Done:
  `tool/security_reference` has the profiles `oauth2`
  (`OAuth2LoginReference`) and `dpop` (`DPoPResourceServerReference`);
  `test/differential_test.dart` starts a fake OpenID Connect provider on
  a socket (`test/differential_provider.dart`) that the Spring reference
  and a Dart application both log in at: 18 scenarios (the redirect, the
  login and the saved page, wrong, missing and replayed `state`, the
  callback in another browser, provider errors, used and injected codes,
  mix-ups, ID tokens of another audience or nonce, the OpenID Connect
  logout), 14 the same, 4 different on purpose (another `iss` and another
  registration's callback refused here, logged in by Spring; an unknown
  registration a 400, Spring's a 500; no session for a failed login).
  The DPoP resource server too: 24 requests, the same except `htm` in
  lower case and `htu` with the host in capitals or a query (RFC 9449
  §4.3 here); Spring Security 7.1 needs `dPoP()` (on by default here) and
  refuses a bound token sent as `Bearer` as this starter does. Run
  locally (JDK 21, Maven) and in the CI job "Security compared with
  Spring Security". Mutation scores (`tool/mutation_test.dart`, with the
  new `--test` option): DPoP 97.1 %, `lib/src/oauth2/` 80.3 % (90.7 %
  without its `form_post` code, written while measured), the client's ID
  token validator, DPoP proof builder and authorization response 100 %;
  docs/security-mutation.md. Not measured: the `oauth2Login()` parts of
  `http_security.dart` (hours for the whole file) and the app login's
  checks in `NativeOAuth2LoginService` (`flutter test`, which the tool
  does not run).
- The Windows (DPAPI) and Linux (libsecret) stores run on devices: CI
  jobs on GitHub's Windows and Linux runners. Written: the job "Secret
  stores on Windows and Linux" (`desktop-secret-stores`) runs
  `test/desktop_secret_store_test.dart` (dart:ffi against DPAPI, and
  against GNOME Keyring unlocked in its own D-Bus session: read, write,
  `keys()`, `deleteAll()`, apps kept apart, no plain text in the DPAPI
  file, the DPoP key across restarts). **Open:** its first run on GitHub
  (it cannot run here; the YAML is checked).
- Untested: cancelling the login on iOS, https redirects (Universal Links
  / App Links), the macOS fallback to the login keychain (-34018).
- ~~A warning in the log when an issuer or redirect URI uses `http://`
  other than on localhost: an app trusts the ID token because of TLS.~~
  Done: the registration mapper of the OAuth2 client warns once per
  registration about an issuer, authorization, token, JWK Set, user-info
  or redirect URI with `http://` on a host other than `localhost`,
  `127.0.0.1` and `[::1]` (discovered endpoints included), and never
  fails.
- ~~One OpenID discovery: the resource server (`JwtDecoders.fromIssuerLocation`)
  and the client (`ClientRegistrations.fromIssuerLocation`) each have
  one; the security starter now depends on the client and can use its.~~
  Done: `ClientRegistrations.configurationForIssuerLocation` (the three
  locations, the issuer check) is used by both; the resource server's
  fetcher stays injectable. Found on the way: with the default fetcher a
  404 stopped the resource server's search, so the RFC 8414 fallback
  only worked with fetchers of the tests; now it moves on.
- ~~A comparison of Spring Security 7's features with the security
  starter and the OAuth2 client.~~ Done (October 2026):
  [docs/security-spring-comparison.md](../docs/security-spring-comparison.md);
  the missing items are in the security roadmaps and the READMEs'
  "Differences".
- ~~Docs, "Differences from Spring" of the client: in Spring
  `spring-boot-starter-oauth2-client` brings web security and
  `oauth2Login()`; here a server lists `spring_boot_starter_security`
  (which brings the client), because the client must also run in Flutter
  and browsers, without the `dart:io` server.~~ Done (the client's
  README).

## Order

The whole plan (1-7) is the security work, started on 30 October 2026 with DPoP's design above.


1. ~~The package split, the app login moved out of the OAuth2 client,
   `SecretStore` and `SecretTemplate`, the display widgets (1-3).~~ Done
   (October 2026), the size measurement too.
2. ~~Google on Android (App Links if needed).~~ Done (October 2026),
   section 5.
3. ~~The login form, the provider button, the Google, Microsoft and
   GitHub buttons.~~ Done (October 2026), with the Apple button (section
   4).
4. ~~Sign in with Apple: the native sheet, `form_post` and the JWT secret
   on the server.~~ Done (October 2026), section 5.
5. DPoP (6), the server and the app together.
6. The hardening (7), parts of it alongside.
