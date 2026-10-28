# spring_boot_starter_flutter_security (planned, next)

The security part of a Flutter app in a package of its own: the platform
code that keeps secrets and opens the login window, a template for the
app's own secrets, widgets that follow the logged-in user, and the login
screens. Today the first part is inside `spring_boot_starter_flutter`
([spring_boot_starter_oauth2_client.md](spring_boot_starter_oauth2_client.md),
section 3); this package takes it out.

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
- Measure first: the size of a minimal app (release APK and web) with
  the starter as it is now and without the OAuth2 part, so the docs can
  say what security costs.

## 1. Moved from spring_boot_starter_flutter

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

## 2. Secrets of the app: SecretStore and SecretTemplate

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

- A user name and password form on the `AuthenticationManager`: errors,
  progress, customised through the theme and builders.
- A button for any registration of the properties
  (`OAuth2LoginButton('keycloak')`).
- Ready buttons for Google, Apple, Microsoft, GitHub, customisable within
  what their brand rules allow (light / dark, shape, the allowed texts):
  Google's and Apple's guidelines fix colours, spacing, logo and text,
  and the stores reject buttons that break them.

## 5. Providers: what each needs

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

## 6. DPoP: tokens bound to the app's key (server and app)

A `Bearer` access token works for whoever holds it until it expires. With
DPoP (RFC 9449) it is bound to a key that only the app has, so a stolen
token is useless. Spring Security accepts DPoP-bound tokens since 6.5;
this starter does not yet (a `DPoP` request gets a `401`, listed in the
security starter's README). Both sides come together:

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
behaviour: DPoP-bound tokens accepted by `oauth2ResourceServer().jwt()`
next to `Bearer` ones, the `jti` cache, nonces; attacks as tests (a
replayed proof, another key, a wrong `htu` / `htm`, a stale `iat`, a
missing or wrong `ath`, `Bearer` instead of `DPoP`, `alg: none`, a
private key in the proof).

App (`spring_boot_starter_oauth2_client` and this package): the key and
the signing in the plugin's platform code, proofs on token requests and
on every Feign / `RestClient` / `HttpTransport` call, `DPoP-Nonce`
answered once; on automatically when the provider's discovery has
`dpop_signing_alg_values_supported`, `Bearer` otherwise.

Providers: Keycloak, Okta, Auth0, Ping, Curity and Spring Authorization
Server support it; Google, Apple, GitHub and Microsoft Entra ID (which has
its own proof-of-possession) do not, as far as known (check before).

## 7. Hardening of the SSO (from the review of October 2026)

The protocol attacks are covered by tests (see docs/security.md); open:

- The differential test of `oauth2Login()` against Spring Security, and
  mutation testing of the OAuth2 client and the login.
- The Windows (DPAPI) and Linux (libsecret) stores run on devices: CI
  jobs on GitHub's Windows and Linux runners.
- Untested: cancelling the login on iOS, https redirects (Universal Links
  / App Links), the macOS fallback to the login keychain (-34018).
- A warning in the log when an issuer or redirect URI uses `http://`
  other than on localhost: an app trusts the ID token because of TLS.
- One OpenID discovery: the resource server (`JwtDecoders.fromIssuerLocation`)
  and the client (`ClientRegistrations.fromIssuerLocation`) each have
  one; the security starter now depends on the client and can use its.
- A comparison of Spring Security 7's features with the security
  starter and the OAuth2 client, everything missing written into
  "Differences" and here (DPoP was missed so; to check: `oauth2Client()`,
  opaque tokens, one-time token login, passkeys, multi-tenant resource
  servers).
- Docs, "Differences from Spring" of the client: in Spring
  `spring-boot-starter-oauth2-client` brings web security and
  `oauth2Login()`; here a server lists `spring_boot_starter_security`
  (which brings the client), because the client must also run in Flutter
  and browsers, without the `dart:io` server.

## Order

1. The package split, `SecretStore` and `SecretTemplate`, the display
   widgets (1-3).
2. Google on Android (App Links if needed).
3. The login form, the provider button, the Google, Microsoft and GitHub
   buttons.
4. Sign in with Apple: the native sheet, `form_post` and the JWT secret
   on the server.
5. DPoP (6), the server and the app together.
6. The hardening (7), parts of it alongside.
