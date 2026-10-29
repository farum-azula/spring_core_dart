# spring_boot_starter_flutter_security

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Security for Flutter apps built on
[`spring_boot_starter_flutter`](https://pub.dev/packages/spring_boot_starter_flutter):
the login of the app with OAuth 2.0 / OpenID Connect, the platform code
that keeps secrets and opens the login window, a template for the app's
own secrets, and widgets that follow the logged-in user.

An app that logs its user in (Keycloak, Google, Okta, ... with OAuth 2.0
/ OpenID Connect) or keeps secrets (a PIN, an API key, the key of an
encrypted database) needs a safe place on the device and the system's
login window. They are platform code (Swift, Kotlin, two Android
activities), so they live here, not in the Flutter starter: an app
without a login carries none of it. As in Spring Boot, an app adds
security when it needs it.

- **The app login**: `OAuth2LoginService` logs the user in with the
  authorization code flow and PKCE, brings them back at startup and logs
  them out, on the registrations of `spring_boot_starter_oauth2_client`.
  In a browser the same calls let the app's server log the user in
  (backend-for-frontend): no token reaches the page; an app without a
  server of its own logs in from the browser (spa mode: tokens in the
  tab's memory, DPoP with a key the page cannot export).
- **Secrets in the platform's secure storage**: the Keychain (iOS,
  macOS), the Android Keystore, DPAPI (Windows), the Secret Service
  (Linux). The login keeps its tokens there; `SecretTemplate` keeps the
  app's own objects.
- **The system's login window**: the provider's page in a Safari sheet
  (iOS, macOS) or a Chrome tab (Android), the redirect back caught by the
  package; Windows and Linux open the default browser and catch the
  redirect on `127.0.0.1`.
- **Widgets that follow the user**: `context.principal`,
  `PrincipalBuilder` and `PrincipalView`, for display only (the server
  checks access).
- **Login screens**: `LoginForm` (a user name and password on the
  `AuthenticationManager`), `OAuth2LoginButton` for any registration,
  and the Google, Apple, Microsoft and GitHub buttons as their branding
  rules draw them.

```dart
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

@Service()
class Account {
  Account(this._login);
  final OAuth2LoginService _login;

  Future<void> start() => _login.restore(); // logged in from last time?
  Future<void> signIn() => _login.login('keycloak'); // the login window
  Future<void> signOut() => _login.logout(); // revoke, forget
}

class Header extends StatelessWidget {
  const Header({super.key});

  // Builds again on every login and logout.
  @override
  Widget build(BuildContext context) =>
      Text('Hello, ${context.principal?.name ?? 'guest'}');
}
```

```properties
# lib/resources/application.properties
spring.security.oauth2.client.registration.keycloak.client-id=neon-app
spring.security.oauth2.client.registration.keycloak.scope=openid,profile,email
spring.security.oauth2.client.registration.keycloak.redirect-uri=dev.neon.books:/oauth2/callback
spring.security.oauth2.client.provider.keycloak.issuer-uri=https://id.neon.books/realms/neon
```

A complete app: the [Flutter guide](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide),
chapter 7 (single sign-on with Keycloak).

## Contents

- [Setup](#setup)
- [The app login](#the-app-login)
- [The web: the server logs in](#the-web-the-server-logs-in)
- [The web without a server: the browser logs in (spa mode)](#the-web-without-a-server-the-browser-logs-in-spa-mode)
- [Tokens and the login window](#tokens-and-the-login-window)
- [Providers: Google and Apple](#providers-google-and-apple)
- [DPoP: tokens bound to the app's key](#dpop-tokens-bound-to-the-apps-key)
- [Secrets of the app: `SecretTemplate`](#secrets-of-the-app-secrettemplate)
- [Widgets that follow the user](#widgets-that-follow-the-user)
- [Login screens](#login-screens)
- [Platforms](#platforms)
- [What security costs](#what-security-costs)

## Setup

```yaml
dependencies:
  flutter:
    sdk: flutter
  spring_boot_starter_flutter_security: ^0.4.3

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3
```

**One package, one import.** It depends on and re-exports
`spring_boot_starter_flutter` (with `spring_boot_dart` and logging),
`spring_boot_starter_oauth2_client` (the registrations, the authorized
clients, Feign) and `spring_security_core`
(`SecurityContextHolder`, `@PreAuthorize`): list this package instead of
the Flutter starter, and
`import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';`
gives all of them. Everything else (the generator, `SpringApplicationWidget`,
themes) is as in the Flutter starter's README.

## The app login

Spring Security logs in browsers: its `oauth2Login()` runs on the server,
which is a confidential client and keeps the tokens in its session. An
app on a phone or a desktop logs in by itself (`NativeOAuth2LoginService`,
the `OAuth2LoginService` bean there; a browser gets the server's login,
[next section](#the-web-the-server-logs-in)), as a public client (it cannot keep a secret:
anyone can extract it), with the authorization code flow and PKCE of
OAuth 2.0 for Native Apps (RFC 8252). `OAuth2LoginService` is that login,
built on the OAuth2 client: its registrations
(`spring.security.oauth2.client.*`), its `authorization_code` token
client, its user services, its ID token decoder and its authorized
client manager.

| Platform | Login window | Redirect URI | Tokens |
|---|---|---|---|
| iOS, macOS | `PlatformAuthorizationWindow`: `ASWebAuthenticationSession` (a Safari sheet); Sign in with Apple's own sheet for `native-sign-in=apple` ([below](#sign-in-with-apple)) | the app's scheme (`neonbooks:/oauth2/callback`), or `https` with an associated domain (iOS 17.4, macOS 14.4) | Keychain |
| Android | `PlatformAuthorizationWindow`: a Custom Tab, the redirect caught by the package's activity | the app's scheme, or an `https` App Link ([below](#android-app-links-https-redirects)) | Android Keystore |
| Windows, Linux | `LoopbackAuthorizationWindow`: the default browser, the redirect on a one-shot server on `127.0.0.1` (RFC 8252 §7.3) | `http://127.0.0.1/callback` (any free port) | DPAPI, the Secret Service |
| Web | none: the page goes to the server's login ([below](#the-web-the-server-logs-in)) | the server's | none: the server logs in (`oauth2Login()` of `spring_boot_starter_security`) and keeps them |

Leave `client-secret` out: the registration is then a public client
(`client-authentication-method=none`), and PKCE protects its codes. On
Windows and Linux the provider must accept a loopback redirect with any
port (Keycloak: `http://127.0.0.1/*`; Google: a desktop client); a
redirect URI with a port (`http://127.0.0.1:8400/callback`) keeps it.

`login('keycloak')`:

1. builds the authorization request: a random `state` (32 bytes of
   `Random.secure()`), a PKCE verifier (64 bytes) and its `S256`
   challenge, and for `openid` a random `nonce` (its SHA-256 hash is
   sent);
2. opens the provider's login page in the `AuthorizationWindow` and
   waits for the redirect back;
3. checks the redirect: back to the redirect URI, the `state` it sent
   (else `invalid_state_parameter`), the `iss` parameter when present or
   announced (RFC 9207, else `invalid_issuer`), then an `error`
   (`access_denied`, ...) or a `code`;
4. exchanges the code with the verifier and the redirect URI actually
   used;
5. for OpenID Connect checks the ID token (issuer, audience, `azp`,
   expiry and issue time with 60 seconds of skew, the nonce) and loads
   the user info, whose `sub` must be the ID token's;
6. maps the authorities (`OIDC_USER` or `OAUTH2_USER`, `SCOPE_<scope>`,
   then the `GrantedAuthoritiesMapper` bean), puts the
   `OAuth2AuthenticationToken` in the `SecurityContextHolder`, saves the
   tokens in the `OAuth2AuthorizedClientService` and publishes an
   `AuthenticationSuccessEvent`.

Any failure is an `OAuth2AuthenticationException` whose `error.errorCode`
says why; a closed page is an `AuthorizationCancelledException`.

`restore()` at startup brings the user back from the stored tokens and
refreshes them when they expire within a minute; a refresh token the
provider refuses (`invalid_grant`) logs the user out, an unreachable
provider does not (an app starts offline). `logout()` revokes the
refresh and access tokens (`OAuth2TokenRevocationClient`, RFC 7009, when
the provider has a `revocation_endpoint`), forgets them, clears the
context and publishes a `LogoutSuccessEvent`, all without a window. The
user stays logged in at the provider in the system's browser, so the
next login may need no password; that is the usual logout of a mobile
app. `logout(endSession: true)` also ends the provider's session in the
login window (OpenID Connect RP-initiated logout, with the ID token as
`id_token_hint`): for "switch account"; iOS and macOS announce that
window with their own "... wants to use ... to Sign In" prompt, whose
text no app can change.

The ID token's signature is not checked: it comes straight from the
token endpoint over TLS, which OpenID Connect Core §3.1.3.7 allows (the
OAuth2 client's `TokenEndpointOidcIdTokenDecoder`). Tokens with
`alg: none` are refused all the same. Declare an `OidcIdTokenDecoder`
bean to check signatures too.

**The beans.** Outside a browser, with a
`spring.security.oauth2.client.registration.*` property, the package
declares `oauth2LoginService` (a `NativeOAuth2LoginService`) and
`authorizedClientService`, a `SecretStoreOAuth2AuthorizedClientService`
that writes each authorized client as JSON to the `SecretStore` (under
`oauth2.authorized-client.<registration>.<principal>`; the login keeps
what `restore` needs under `oauth2.login`). Its module comes before the
OAuth2 client's, so this service replaces the client's in-memory one.
On iOS and macOS it also declares `appleIdSignIn`, Sign in with Apple's
sheet ([below](#sign-in-with-apple)). Every bean of the package backs off
when the application declares one of its type: `SecretStore`,
`SecretTemplate`, `AuthorizationWindow`, `AppleIdSignIn`,
`OAuth2AuthorizedClientService`, `OAuth2LoginService`,
`PrincipalNotifier`, and on the web `BrowserPage` and `HttpTransport`. Nothing in the package logs a token, a code, a
verifier or a secret.

Spring has no counterpart: its `oauth2Login()` logs browsers in on a
server. The checks are those of its `OAuth2LoginAuthenticationFilter`,
`OidcAuthorizationCodeAuthenticationProvider` and `OidcUserService`.

## The web: the server logs in

A browser has no safe place for tokens: memory, `localStorage` and
IndexedDB are readable by any script that gets into the page. So in a
browser the app's own server logs the user in, as Spring Security does
it for any web page: `oauth2Login()` of `spring_boot_starter_security`
runs the authorization code flow as a confidential client (with a
secret, which a server can keep), holds the tokens in its session, and
gives the browser only an `HttpOnly` session cookie, which no script can
read. This is the backend-for-frontend pattern, the strongest choice for
a web app, and the default (`spring.flutter.security.web.mode=server`).

The app's code is the same as on phones: `login('keycloak')`,
`restore()`, `logout()`, `PrincipalBuilder`, the Feign clients. No
`kIsWeb`, no provider in the code: the registration ids are the
server's (`spring.security.oauth2.client.registration.<id>` there), and
the app has no registration of its own on the web.

```properties
# lib/resources/application-web.properties
# The API on another origin than the page (else leave it out: same origin).
spring.flutter.security.web.server-url=https://api.neon.books
spring.flutter.security.web.user-endpoint=/api/me
spring.flutter.security.web.logout-url=/api/logout
```

| Key | Default | Meaning |
|---|---|---|
| `spring.flutter.security.web.mode` | `server` | `server`: the app's server logs in. `spa`: the browser logs in by itself ([below](#the-web-without-a-server-the-browser-logs-in-spa-mode)) |
| `spring.flutter.security.web.server-url` | the page's origin | The app's server, with its context path if any (`https://api.neon.books`) |
| `spring.flutter.security.web.user-endpoint` | `/user` | The server's "who is logged in" endpoint (below); a path on the server or an absolute URL |
| `spring.flutter.security.web.logout-url` | `/logout` | The server's logout, posted with the CSRF token |
| `spring.flutter.security.web.authorization-base-uri` | `/oauth2/authorization` | Where the server starts a login, followed by `/{registrationId}` (Spring's `authorizationEndpoint().baseUri()`) |

How it works (`ServerOAuth2LoginService`, the `OAuth2LoginService` bean
in a browser):

1. `login('keycloak')` navigates the page to
   `<server-url>/oauth2/authorization/keycloak` and returns `null`. The
   server sends the browser on to the provider and, after the login,
   back to the app (its `defaultSuccessUrl`: the web app's address, from
   the server's configuration, never from a request parameter). The app
   starts again.
2. `restore()`, at startup, asks the user endpoint with the session
   cookie and puts the user it answers into the `SecurityContextHolder`
   (so `PrincipalNotifier`, `PrincipalBuilder` and `@PreAuthorize` see
   it) and publishes an `AuthenticationSuccessEvent`. Nobody logged in
   (`401`, `403`, `204`, a redirect to a login page): `null`. The server
   unreachable or answering something else: a warning in the log,
   `null`.
3. `logout()` posts the logout URL with the CSRF token, clears the
   context and publishes a `LogoutSuccessEvent`; when the server answers
   with the provider's logout page, the page goes there, the provider
   ends its session and sends the browser back to the app.

**The user endpoint.** Spring has no standard "who am I" endpoint, so
the server declares one, a controller of a few lines with Spring's
`Authentication` argument (any kind of login has a name and
authorities). Its answer:

```json
{
  "name": "ada",
  "authorities": ["ROLE_USER", "OIDC_USER", "SCOPE_profile"],
  "registrationId": "keycloak",
  "attributes": {"email": "ada@neon.books"}
}
```

`name` is required; `authorities` (strings, or `{"authority": "..."}`
objects as Jackson writes a Spring `GrantedAuthority`), `registrationId`
and `attributes` are optional, other members are ignored, so the
`{"name": ...}` of Spring's guide "Spring Boot and OAuth2" works as it
is. With `registrationId` the user is an `OAuth2AuthenticationToken`,
without one (a form login of the server) a
`PreAuthenticatedAuthenticationToken`; the principal is an `OAuth2User`
with the attributes either way. The authorities are the server's, used
as they are (no `GrantedAuthoritiesMapper` in the browser).

```dart
// The server (spring_boot_starter_security): GET /user.
@RestController()
class UserController {
  @GetMapping('/user')
  Map<String, Object?> user(Authentication authentication) => {
    'name': authentication.name,
    'authorities': [
      for (final authority in authentication.authorities) authority.authority,
    ],
    if (authentication is OAuth2AuthenticationToken) ...{
      'registrationId': authentication.authorizedClientRegistrationId,
      'attributes': authentication.principal.attributes,
    },
  };
}
```

Spring (Java), the same endpoint:

```java
@GetMapping("/user")
Map<String, Object> user(Authentication authentication) {
  var user = new HashMap<String, Object>();
  user.put("name", authentication.getName());
  user.put("authorities", AuthorityUtils.authorityListToSet(authentication.getAuthorities()));
  if (authentication instanceof OAuth2AuthenticationToken oauth2) {
    user.put("registrationId", oauth2.getAuthorizedClientRegistrationId());
    user.put("attributes", oauth2.getPrincipal().getAttributes());
  }
  return user;
}
```

The package offers no such controller of its own: which user data a
server shows its pages is the server's decision (the attributes may hold
more than a page should see), and a controller is shorter than its
configuration would be.

**The logout answer.** The app logs out with a script request (`fetch`),
which cannot follow a redirect to the provider (another origin), and
Spring's `OidcClientInitiatedLogoutSuccessHandler` answers with such a
redirect. So the server's logout success handler answers the provider's
logout URL (its `end_session_endpoint` with `id_token_hint` and
`post_logout_redirect_uri`) in one of two ways, and the page goes there:

- `200` with `{"logoutUrl": "https://id.neon.books/...logout?..."}`
  (the server guide's `SsoLogoutSuccessHandler`);
- a `2xx` with a `Location` header, such as `202 Accepted` (expose
  `Location` in the CORS configuration for a server on another origin).

Any other success (`204`, a redirect) ends the server's session only.
Only `http` and `https` URLs are followed. A `403` means the CSRF token
was missing; the app logs out locally all the same.

**Cookies and the CSRF token.** In a browser the package declares the
`httpTransport` bean (the Feign starter's backs off): the browser's
`fetch`, asked to send the cookies when the server is on another origin
than the page (`FetchCredentials.include`; same origin needs nothing),
wrapped in `CsrfCookieHttpTransport`, which copies the server's
`XSRF-TOKEN` cookie into the `X-XSRF-TOKEN` header of `POST`, `PUT`,
`PATCH` and `DELETE` requests to that server, never to another origin.
The login service sends its own requests through it too. An application
that declares its own `HttpTransport` keeps it (as in Spring Boot, the
auto-configuration backs off); it then passes
`credentials: FetchCredentials.include` itself and wraps its transport
in `CsrfCookieHttpTransport` for its Feign calls (the login service
wraps it for its own requests anyway).

**The server's side** (`spring_boot_starter_security`), as in the
[server guide](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide)'s
`sso` profile:

- `oauth2Login()` with `defaultSuccessUrl('<the web app>', alwaysUse: true)`;
- CSRF tokens in a cookie the page may read:
  `CookieCsrfTokenRepository.withHttpOnlyFalse()` with
  `CsrfTokenRequestAttributeHandler` (the raw token, as the app sends
  it), and a filter that writes the cookie on every response, so the
  page has it before its first `POST` (Spring's single-page-app recipe);
- for a server on another origin: CORS for the page's origin with
  `allowCredentials: true` (never `*`) and `X-XSRF-TOKEN` among the
  allowed headers; the page and the server on one site
  (`app.neon.books` and `api.neon.books`, or two ports of `localhost`),
  because browsers drop third-party cookies, and the page must be able
  to read the `XSRF-TOKEN` cookie (same host, or a cookie domain shared
  by both);
- the user endpoint and the logout answer above.

**What it protects, and what not.** The tokens never reach the browser:
a script injected into the page cannot steal them and use them
elsewhere. The session cookie is `HttpOnly` (no script reads it); the
CSRF token stops other sites from making the browser send requests with
it. An injected script can still act as the user while the page is open
(it runs in the page, and the browser sends the cookie for it):
Flutter draws on a canvas and never turns data into HTML, so the classic
DOM injection is mostly gone, but foreign scripts in `index.html`
(analytics, tag managers), the supply chain, `HtmlElementView` with
user HTML, `javascript:` URLs and other content on the same origin
remain; keep them out, and send a Content Security Policy with the
page.

Spring has no client side for this: Spring Security logs browsers in on
the server and leaves the page's side to the page (Angular reads the
`XSRF-TOKEN` cookie by itself; a "who am I" endpoint is the
application's).

## The web without a server: the browser logs in (spa mode)

Some web apps have no server of their own: they call the APIs of others,
or an API that accepts the provider's tokens, straight from the browser.
Such an app logs in from the browser itself, as a public client with
PKCE (the browser cannot keep a secret), and holds the tokens in the
page: `spring.flutter.security.web.mode=spa`. Choose `server` whenever
the app has a server: there no token ever reaches the page, which this
mode cannot promise.

The app's code is still the same: `login('keycloak')`, `restore()`,
`logout()`, `PrincipalBuilder`, the Feign clients with the access token.
The registrations are the app's own (as on phones), with the page as the
redirect URI:

```properties
# lib/resources/application-web.properties
spring.flutter.security.web.mode=spa
spring.security.oauth2.client.registration.keycloak.client-id=neon-web
spring.security.oauth2.client.registration.keycloak.scope=openid,profile,email
# The app's own page: {baseUrl} is its origin and base href.
spring.security.oauth2.client.registration.keycloak.redirect-uri={baseUrl}/
spring.security.oauth2.client.registration.keycloak.dpop=auto
spring.security.oauth2.client.provider.keycloak.issuer-uri=https://id.neon.books/realms/neon
```

| Key | Default | Meaning |
|---|---|---|
| `spring.flutter.security.web.mode` | `server` | `spa`: the browser logs in |
| `spring.flutter.security.web.silent-restore` | `true` | Whether `restore()` brings back, after a reload or in a new tab, a user who logged in in this browser (below) |

How it works (`SpaOAuth2LoginService`, the `OAuth2LoginService` bean in
spa mode):

1. `login('keycloak')` builds the registration's authorization request
   (PKCE `S256`, a `state`, a `nonce`; with DPoP the key's thumbprint as
   `dpop_jkt`, which binds the code to the key), keeps it in the tab's
   `sessionStorage` and navigates the page to the provider. The result is
   `null`: the app stops there.
2. The provider sends the browser back to the redirect URI with `code`
   and `state`; the app starts again, and `restore()` finishes the login
   with the checks of the native login: the `state` against forged
   answers, the `iss` of RFC 9207 against mixed-up providers, the
   provider's `error`; the code exchanged at the token endpoint with the
   PKCE verifier (no secret); the ID token's issuer, audience, times and
   `nonce`; the user info's subject. The user goes into the
   `SecurityContextHolder`, an `AuthenticationSuccessEvent` is published.
   The `code` and `state` leave the address bar (`history.replaceState`;
   the app's own parameters and Flutter's route stay), the request leaves
   `sessionStorage`. An answer this tab did not ask for (a reload of the
   answer, an old or forged link) or older than 10 minutes logs nobody
   in. A refused login throws an `OAuth2AuthenticationException` from
   `restore()`, so the app can say why.
3. `logout()` forgets the tokens, clears the context, publishes a
   `LogoutSuccessEvent`, revokes the tokens when the provider has a
   `revocation_endpoint` (best effort), and ends the provider's session:
   the page goes to its `end_session_endpoint` with `id_token_hint` and
   comes back to the app (`postLogoutRedirectUri`, the app's address by
   default). This happens whatever `endSession` says: every tab shares
   the provider's session, and while it lives the next login, or the
   silent login of another tab, passes without a password.

**After a reload: the silent login.** The tokens are gone with a reload
(they live in the tab's memory only). Three ways back were weighed:

- a refresh token in memory: lost with the reload too;
- a hidden iframe with `prompt=none` (the classic "silent renew"): the
  iframe needs the provider's session cookie in a third-party context,
  which Safari, Firefox and Chrome's privacy modes block, so it fails
  exactly where it matters;
- a top-level redirect with `prompt=none`: the page goes to the provider,
  which answers at once from its own (first-party) session cookie,
  without showing anything, and sends it back with a code or with
  `login_required`.

The package takes the third: it works in every browser. When the page
starts without an answer and someone logged in in this browser before,
`restore()` sends it to the provider with `prompt=none` and returns
`null`; at the next start it finishes that login like any other.
`login_required` (or `interaction_required`, `consent_required`,
`account_selection_required`) means nobody is logged in there: no error,
and no second try. Whether someone logged in before is a hint in
`localStorage` (only the registration id, never a token; removed at
logout and on `login_required`), so a visitor who never logged in never
makes the trip. The user sees the page start, a short trip to the
provider (an instant redirect, no page), and the page again with them
logged in; a reload costs that trip. `silent-restore=false` turns it
off: after a reload nobody is logged in until the next `login()`, which
passes without a password while the provider's session lives.

**What is kept where.**

| What | Where | Why |
|---|---|---|
| access, refresh and ID tokens | the tab's memory (`TabOAuth2AuthorizedClientService`) | never `localStorage`, `sessionStorage` or IndexedDB, where any script of the origin, later, and anyone with the disk would find them |
| the authorization request (`state`, `nonce`, PKCE `code_verifier`) | `sessionStorage`, from `login()` until the page is back | the page leaves for the provider and starts again; the verifier is short-lived and useless without the code, which only the provider's redirect carries |
| the hint "logged in with `keycloak`" | `localStorage` | the silent login after a reload; no secret |
| the DPoP key | IndexedDB, as a non-extractable `CryptoKey` | usable, never readable |

**Refresh tokens** stay in memory too. A refresh token in a browser is
exposed to whatever script runs in the page, so the provider must rotate
it: a new one with every refresh, the old one revoked, a reused one
ending the login (Keycloak: "Revoke Refresh Token" in the realm's
settings; Auth0 and Okta: "Refresh Token Rotation"). The package cannot
enforce that, but it notices: a refresh that comes back with the same
refresh token logs a warning, once per registration.

**DPoP with a key the page cannot read.** With `dpop=auto` (on when the
provider's discovery offers ES256) or `dpop=true`, the tokens are bound
to `WebCryptoDPoPKey`, the app's `DPoPKey` in spa mode: an ECDSA P-256
key made by the browser's WebCrypto with `extractable: false`. Its
`CryptoKey` handles are kept in the origin's IndexedDB (the browser
stores the handle, not the key's bytes), so a reload uses the same key;
signing is `crypto.subtle.sign({name: 'ECDSA', hash: 'SHA-256'})`, whose
result is already the raw `R || S` JOSE wants; the public key is
`exportKey('jwk')`. No script, the app's own included, can export the
private key. The key is made at the first proof, so an app whose
providers do not use DPoP never touches WebCrypto. WebCrypto needs a
secure context: `https`, or `http://localhost` in development.

**What the provider must offer.** A public client (no secret) with PKCE,
whose redirect URI is the app's page and whose post-logout redirect URI
is the app; the page's origin allowed (CORS) on the token, user info and
revocation endpoints (Keycloak: the client's "Web origins"; Auth0:
"Allowed Web Origins"; Okta: a "Trusted Origin"). A registration with a
client secret is refused at `login()`. When the token endpoint cannot be
reached from the page (CORS refused), the login fails with a message
that says so and points to `server` mode. Not every provider accepts
public browser clients at its token endpoint: check before.

**What it protects, and what not.** DPoP makes a stolen token useless
elsewhere: a script that reads the tokens out of the page cannot use
them from another machine, because every request needs a proof only the
page's key signs. PKCE and `state` stop forged and stolen answers; the
tokens never touch storage. What it cannot stop: a script running in the
page acts as the user while it runs (it can call the APIs, and ask the
browser to sign with the key; it cannot carry the key away). Flutter
draws on a canvas and never turns data into HTML, so the classic DOM
injection is mostly gone; what remains is foreign scripts in
`index.html` (analytics, tag managers), the supply chain, `HtmlElementView`
with user HTML, `javascript:` URLs, other content on the same origin, and
browser extensions. Keep those out, and send a Content Security Policy.

**The Content Security Policy.** In spa mode the generator gives
`flutter run` a ready policy (`spring.flutter.web.content-security-policy`
sets your own; see the
[configuration reference](https://github.com/farum-azula/spring_core_dart/blob/main/docs/configuration.md#the-content-security-policy)):

```text
default-src 'self'; script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com;
style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:;
font-src 'self' https://fonts.gstatic.com;
connect-src 'self' https://www.gstatic.com https://fonts.gstatic.com <the providers>;
worker-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self';
frame-ancestors 'none'
```

No inline scripts and no `eval`; `'wasm-unsafe-eval'` lets CanvasKit and
Skwasm compile their WebAssembly; `https://www.gstatic.com` serves
CanvasKit unless the app is built with `--no-web-resources-cdn`;
`https://fonts.gstatic.com` serves Flutter's fallback fonts;
`'unsafe-inline'` styles because Flutter's engine writes a `<style>`
element (a nonce would need a server that makes one per answer). Add the
APIs the app calls to `connect-src` (and `ws:`/`wss:` origins for
sockets). Build for production with `flutter build web --csp` (no
dynamically generated code) and send the same policy from the web server
or CDN as the `Content-Security-Policy` header of `index.html`
(`add_header` in nginx, `Header set` in Apache, the host's header rules
for Firebase Hosting, Netlify or a CDN). Where headers cannot be set, a
`<meta http-equiv="Content-Security-Policy" content="...">` in
`web/index.html` is the fallback; browsers ignore `frame-ancestors`
there (send `X-Frame-Options: DENY` from the host if you can). In debug
runs, hot reload evaluates code, which the policy forbids: set
`spring.flutter.web.content-security-policy-report-only=true` in a
development profile to see violations without blocking.

Spring has no browser side of a login: Spring Security's own answer for
browsers is `oauth2Login()` on a server, which is the `server` mode here.

## Tokens and the login window

The app login needs two things from the platform: a safe place for the
tokens it gets, so the user stays logged in after the app restarts, and
the system's login window for the provider's page, so the app never sees
the password and the user's existing login there is reused (single
sign-on). The package brings both, as its own platform code (no other
plugin), and makes them beans:

- **`PlatformSecretStore`**, the app's `SecretStore` bean: `read`,
  `write`, `delete`, `keys` and `deleteAll` of strings by key, in the
  platform's secure storage. Where there is none (the web) the bean is
  an `InMemorySecretStore`, which the login and the template never fill.
- **`PlatformAuthorizationWindow`**, the app's `AuthorizationWindow`
  bean on Android, iOS and macOS: opens the provider's login page in the
  system's login window (a Safari sheet on iOS and macOS, a Chrome tab on
  Android) and waits for the redirect back. It is no browser of the app:
  the system shows the page, the app gets only the redirect.
- **`LoopbackAuthorizationWindow`**, the app's `AuthorizationWindow`
  bean on Windows and Linux: opens the page in the default browser and
  answers the redirect on a one-shot server on `127.0.0.1` (a page
  saying the window can be closed, nothing of the request echoed; five
  minutes without a redirect cancel the login).

`OAuth2LoginService` uses them by itself. An app declares its own
`SecretStore` or `AuthorizationWindow` bean only to replace them. The
app's own secrets go to the same store through `SecretTemplate`
([below](#secrets-of-the-app-secrettemplate)).

| Platform | Secrets | Login window |
|---|---|---|
| iOS | Keychain: generic passwords, this device only, after the first unlock, not synced | `ASWebAuthenticationSession` |
| macOS | Keychain (see below) | `ASWebAuthenticationSession` |
| Android | AES-256-GCM key in the Android Keystore (never leaves it), the encrypted values in a private preferences file | Custom Tab (the default browser without Custom Tabs) |
| Windows | DPAPI (current user), one file per key in `%LOCALAPPDATA%\<app>\spring_secret_store` | the default browser, the redirect on a loopback server |
| Linux | the Secret Service (GNOME Keyring, KWallet) through `libsecret` | the default browser, the redirect on a loopback server |
| Web | none | none: the server logs in |

**Android: declare the redirect.** The provider sends the browser to the
app's redirect URI (`neonbooks:/oauth2/callback`). An activity of the
package catches it; the app declares it with its scheme in
`android/app/src/main/AndroidManifest.xml`, inside `<application>`:

```xml
<activity
    android:name="dev.farumazula.spring_boot_starter_flutter_security.RedirectReceiverActivity"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="neonbooks" />
    </intent-filter>
</activity>
```

Apps that never log in declare nothing. Without the declaration a login
fails at once with an `AuthorizationWindowException`
(`redirect_not_configured`) that shows this snippet. Pick a scheme of
your own (reverse domain, `dev.neon.books`), not one another app may
claim; PKCE makes a code caught by another app useless anyway. A user who
comes back to the app without finishing (back button, closing the tab)
cancels the login: `AuthorizationCancelledException`. A value that no
longer decrypts (an Android backup restored on another phone, whose
Keystore key did not move with it) is deleted and read as missing: the
user logs in again.

**iOS and macOS: nothing to set up** for a custom-scheme redirect: the
scheme of the redirect URI is the one the login session waits for. An
`https` redirect needs iOS 17.4 / macOS 14.4 and the app's associated
domain ([below](#ios-and-macos-https-redirects)); older systems fail
with an `UnsupportedError`. The login reuses Safari's session, and iOS asks
"... wants to use ... to sign in";
`spring.flutter.security.ephemeral-session=true` (or a
`PlatformAuthorizationWindow(preferEphemeralSession: true)` bean of your
own) uses a private session that keeps no cookies and asks nothing: no
prompt on login and logout, but no single sign-on either (every login
asks for the password).

On macOS the tokens go to the data protection keychain (the iOS one)
when the app may use it: a build signed with a team (a development
team in Xcode, which gives the app its application identifier). A
build signed only to run locally (the default of `flutter run`) gets
`errSecMissingEntitlement` there and uses the login keychain instead.
Its items belong to the signature of the build that wrote them; the
store never lets macOS show a password prompt, so a value another build
may not read reads as missing and the next write replaces it. Sign
release builds with your team.

**Linux: `libsecret` at run time.** The store loads `libsecret-1.so.0`
(the `libsecret-1-0` package on Debian and Ubuntu, `libsecret` on Fedora
and Arch) and needs a running Secret Service (GNOME Keyring, KWallet,
KeePassXC). Without them every call throws a `PlatformSecretStoreException`;
the tokens are never written to a plain file.

**Web: the server logs in.** A browser has no secure storage, and any
script injected into the page reads what the app holds. So a Flutter web
app keeps no tokens: no `PlatformSecretStore` and no login window exist
there, and its server logs the user in (`oauth2Login()` of
`spring_boot_starter_security`) and sends only a session cookie; see
[The web: the server logs in](#the-web-the-server-logs-in).

Errors: the store throws a `PlatformSecretStoreException` (its message
names the failure, never a value); the login window throws
`AuthorizationCancelledException` when the user closes the page, a
`StateError` when a login is already running (one at a time), and an
`AuthorizationWindowException` for the rest.

Spring has no such types: Spring Security logs in browsers on a server,
and Java has no apps.

### Android App Links: https redirects

A custom scheme can be claimed by any app; an `https` redirect on a
domain of yours cannot: Android opens it in your app only after the
domain has said so (App Links, Android 6+; Android 12+ opens an
unverified link in the browser, never in an app). Some providers accept
no custom scheme for new clients; then this is the way.

1. In `android/app/src/main/AndroidManifest.xml`, the package's activity
   with an intent filter for exactly the redirect's host and path,
   `android:autoVerify="true"`:

   ```xml
   <activity
       android:name="dev.farumazula.spring_boot_starter_flutter_security.RedirectReceiverActivity"
       android:exported="true">
       <intent-filter android:autoVerify="true">
           <action android:name="android.intent.action.VIEW" />
           <category android:name="android.intent.category.DEFAULT" />
           <category android:name="android.intent.category.BROWSABLE" />
           <data android:scheme="https" />
           <data android:host="books.neon.example" />
           <data android:path="/oauth2/callback" />
       </intent-filter>
   </activity>
   ```

   Give the login a path of its own: the app's other links of the domain
   belong to `MainActivity`.

2. On the domain, `https://books.neon.example/.well-known/assetlinks.json`
   (HTTPS, no redirect, `Content-Type: application/json`):

   ```json
   [{
     "relation": ["delegate_permission/common.handle_all_urls"],
     "target": {
       "namespace": "android_app",
       "package_name": "books.neon.app",
       "sha256_cert_fingerprints": ["14:6D:E9:83:C5:73:06:50:D8:EE:B9:95:2F:34:FC:64:16:A0:83:42:E6:1D:BE:A8:8A:04:96:B2:3F:CF:44:E5"]
     }
   }]
   ```

   The fingerprint is the SHA-256 of the certificate that signs the
   installed app. A debug build:
   `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`;
   your upload or release key: the same with its keystore, or
   `./gradlew signingReport` in `android/`; with Play App Signing, Google
   re-signs the app: copy the SHA-256 of Play Console > Test and release >
   App integrity > App signing key (and list your upload key too for
   builds you install yourself).

3. The redirect URI of the registration is that URL
   (`redirect-uri=https://books.neon.example/oauth2/callback`), and the
   provider must accept it for a public client.

Check the verification on a device:
`adb shell pm get-app-links books.neon.app` (the domain must read
`verified`); `adb shell pm verify-app-links --re-verify books.neon.app`
after changing the file.

The plugin hands over only the redirect of the login that runs: the same
scheme, host, port and exact path as the redirect URI (the query, with
`code` and `state`, is checked in Dart). Any other link of the domain that
reaches the activity is dropped and the login goes on. Before opening the
page it checks (Android 12+) that the host is verified or chosen by the
user for the app, else the login fails at once with an
`AuthorizationWindowException` (`redirect_not_verified`) instead of the
page staying in the browser; an `http://` redirect is refused
(`UnsupportedError`). One known limit of Chrome: a navigation without a
user gesture (a provider that redirects at once because the user is still
logged in there) may stay in the Custom Tab instead of opening the app;
serve a page at the redirect URL that says so, or ask the provider for
`prompt=login`.

### iOS and macOS: https redirects

`ASWebAuthenticationSession` catches an `https` callback for its own
host and path (iOS 17.4, macOS 14.4: `.https(host:path:)`); nothing
leaves the sheet, and the Dart side checks the redirect again. The app
needs the associated domain of the redirect's host with the
`webcredentials` service (the session refuses `https` callbacks without
it), in Xcode under Signing & Capabilities > Associated Domains:

```text
webcredentials:books.neon.example
```

and the domain serves `https://books.neon.example/.well-known/apple-app-site-association`
(HTTPS, no redirect, JSON without a file extension):

```json
{
  "webcredentials": { "apps": ["ABCDE12345.books.neon.app"] },
  "applinks": { "details": [{ "appIDs": ["ABCDE12345.books.neon.app"], "components": [{ "/": "/oauth2/callback" }] }] }
}
```

`ABCDE12345` is the team id. `applinks` (Universal Links) is needed only
for links that open the app outside a login session; the login itself
uses `webcredentials`. Older systems (iOS before 17.4, macOS before
14.4) keep a custom scheme.

## Providers: Google and Apple

What each provider needs from an app, as far as known in October 2026
(neither was tried with a real account here: the code is tested against
fakes; check the provider's console). The server's side of both is in
the security starter's README ("Login with Google", "Sign in with
Apple").

### Login with Google

Google is an OpenID Connect provider; the registration `google` gets
its endpoints from the OAuth2 client's `CommonOAuth2Provider` and needs
only the client id. Which client to create in Google Cloud (APIs &
Services > Credentials > OAuth client ID) and which redirect to use:

| Where | Client type | Redirect URI with this package | Secret |
|---|---|---|---|
| iOS, macOS (`ASWebAuthenticationSession`) | iOS (the bundle id) | the reversed client id: `com.googleusercontent.apps.123-abc:/oauth2redirect` | none |
| Android (Custom Tab) | Android (the package name and the SHA-1 of the signing certificate); "Custom URI scheme" turned on under Advanced settings | the custom scheme the console accepts for the client (the reversed client id, as on iOS) | none |
| Windows, Linux (loopback) | Desktop app | `http://127.0.0.1/callback` (any port) | a `client_secret` that is no secret (below) |
| Web (the server logs in) | Web application | `https://<server>/login/oauth2/code/google` | on the server only |

```properties
spring.security.oauth2.client.registration.google.client-id=123-abc.apps.googleusercontent.com
spring.security.oauth2.client.registration.google.redirect-uri=com.googleusercontent.apps.123-abc:/oauth2redirect
spring.security.oauth2.client.registration.google.scope=openid,profile,email
```

- **Android:** since October 2023 new Android clients may not use custom
  URI schemes unless "Custom URI scheme" is enabled in the client's
  advanced settings; Google points Android apps to its Credential Manager
  ("Sign in with Google" of Google Identity Services), which this package
  does not wrap. Google's Android and iOS clients take no `https`
  redirect URIs, and a "Web application" client (which does) needs its
  secret at the token endpoint, which no app can keep: App Links do not
  help with Google. Without the custom scheme, let the server log the
  user in (the web client) and give the app the server's session.
- **iOS:** the reversed client id scheme needs no setup with
  `ASWebAuthenticationSession`. Loopback redirects are deprecated for
  Android and iOS clients.
- **Desktops:** a "Desktop app" client comes with a `client_secret` that
  Google itself says is not confidential (desktop apps are public
  clients). Set it as `client-secret` when the token endpoint asks for
  it; it proves nothing about the app, PKCE protects the code.
- **Roles:** Google has none. Map the user to authorities yourself, in a
  `GrantedAuthoritiesMapper` bean (from your database or a list), and on
  the server, which decides.
- **Who the user is:** keep users by `sub`, never by e-mail: an e-mail
  address can change owner, and another provider may send an address it
  never verified (account takeover). Use the e-mail only with
  `email_verified=true`, and only to suggest linking accounts.
- **Refresh tokens are not rotated:** Google issues one long-lived
  refresh token (only at the first consent, or with `prompt=consent`).
  It is kept in the `SecretStore` and revoked by `logout()` (Google's
  metadata has a `revocation_endpoint`).
- DPoP: Google does not issue DPoP tokens (`dpop=auto` stays `Bearer`).

### Sign in with Apple

On iOS and macOS the app signs in with the system's own sheet
(`ASAuthorizationAppleIDProvider`: Face ID, Touch ID or the passcode,
the device's Apple Account), not a browser. A registration whose provider
is `apple` (the client's `CommonOAuth2Provider.apple`, an addition to
Spring's) uses it by default; `native-sign-in` says it explicitly:

```properties
# The App ID (bundle id) is the client id of the app's codes.
spring.security.oauth2.client.registration.apple.client-id=books.neon.app
# apple (the default for the apple provider): the sheet on iOS and macOS;
# none: the browser.
spring.security.oauth2.client.registration.apple.native-sign-in=apple
# The app's server exchanges the code (only it can sign Apple's client
# secret): its endpoint is the registration's token endpoint.
spring.security.oauth2.client.provider.apple.token-uri=https://api.neon.example/oauth2/apple/token
```

The app needs the "Sign in with Apple" capability (Xcode, Signing &
Capabilities: the `com.apple.developer.applesignin` entitlement) and an
App ID with Sign in with Apple enabled. `login('apple')`:

1. sends the sheet the scopes (`name`, `email`), a fresh `state`, and the
   SHA-256 hash of a fresh random nonce (Apple puts it into the identity
   token as given);
2. checks the answer: the `state`; the identity token's signature against
   Apple's keys (`https://appleid.apple.com/auth/keys`, the registration's
   `jwk-set-uri`), its issuer (`https://appleid.apple.com`), audience (the
   client id), expiry and issue time, its `nonce` (the hash of this
   login's); its `sub` equal to the sheet's user. The token comes from
   the operating system, not from a TLS connection the app opened, so
   unlike an ID token of the token endpoint it is verified like a
   server does (`JwkSetOidcIdTokenDecoder` of the OAuth2 client);
3. exchanges the authorization code (valid five minutes, once) at the
   registration's token endpoint, as a public client, with no
   `redirect_uri` and no PKCE (the sheet sent none). Apple takes a code
   only with the client secret, a JWT signed with the team's key, which
   no app may hold: the token endpoint is **the app's server**, which
   verifies, exchanges the code with Apple (the security starter's
   `JwtClientSecret`), keeps Apple's refresh token and answers the app
   with the tokens of its own API. This is Apple's flow for apps with a
   server ("the app relays the credentials to the server, which verifies
   them with Apple and manages the session"). An ID token the server
   sends along must name the same user;
4. puts the name (and an e-mail the token lacks), which Apple sends **on
   the first authorization only**, into the user's info; it is stored
   with the login and kept for the next sign-ins of the same user. The
   identity token's claims always win over it. Store it on the server
   too, at once: Apple never sends it again unless the user removes the
   app from their Apple Account.

Any failure is an `OAuth2AuthenticationException` (`invalid_state_parameter`,
`invalid_id_token`, `invalid_nonce`, the server's error); a closed sheet
an `AuthorizationCancelledException`. On Android, Windows and Linux there
is no sheet: the registration uses the browser, which for Apple means an
`https` redirect ([App Links](#android-app-links-https-redirects)),
`response-mode=query` (Apple then sends no name and e-mail; `form_post`
reaches only a server, and the app's window refuses it), and still the
server's token endpoint. Simpler there: let the server log the user in.

The App Store asks an app that offers a third-party login (Google, ...)
to offer an equivalent login that limits data collection to name and
e-mail, lets the user keep the e-mail private, and does not track:
Sign in with Apple is that login (App Review Guideline 4.8). An app that
creates accounts must also let users delete them, which for Sign in with
Apple includes revoking the user's Apple tokens on the server
(`https://appleid.apple.com/auth/revoke`, with the client secret).

## DPoP: tokens bound to the app's key

A `Bearer` token works for whoever holds it. With DPoP (RFC 9449) the
provider binds the tokens to a key pair of the app: every token request
and every API call carries a short proof signed by the key, so a token
copied out of the app (a log, a backup, a proxy) is useless without the
device. The OAuth2 client does it when the registration's `dpop`
property says so: `auto` (the default) when the provider's metadata
announces it (Keycloak, Okta, Auth0, ...), `true` always, `false` never;
see the [client's README](https://github.com/farum-azula/spring_core_dart/tree/main/spring_boot_starter_oauth2_client#dpop-tokens-bound-to-the-apps-key).

The key must live as long as the tokens, or a restart would mean a new
login. This package declares it as the app's `DPoPKey` bean
(`platformDPoPKey`, a `PlatformDPoPKey`), in the safest place each
platform has; the token clients, the user services and the Feign
interceptor use it. It is made at the first proof, not at startup.

| Platform | Where the key lives | Who signs |
|---|---|---|
| iOS, macOS | the Secure Enclave (EC P-256, permanent, tagged `<bundle id>.spring_dpop_key`, after the first unlock, this device only) | the Secure Enclave |
| iOS, macOS without a usable Secure Enclave | a software key of the Keychain with the same tag and protection | the system |
| Android | the Android Keystore (EC P-256, `PURPOSE_SIGN`, SHA-256), in StrongBox when the phone has it, else the trusted execution environment | the Keystore |
| Windows, Linux | a key made in Dart, kept as a private JWK in the `SecretStore` (`oauth2.dpop-key`: DPAPI, the Secret Service) | the app (`SecretStoreDPoPKey`) |
| Web | none here: a page in server mode holds no tokens | — |

Without a usable Secure Enclave means: Macs without one (Intel Macs
without a T2 chip), simulators without one, and macOS builds signed only
to run locally (the default of `flutter run`), which may not use the
data protection keychain the Secure Enclave needs; such a build keeps
the key in the login keychain, as the secret store does. The iOS
simulator of recent Xcode versions on Apple silicon emulates a Secure
Enclave. `PlatformDPoPKey.storage` says where the key ended up
(`secureEnclave`, `keychain`, `strongBox`, `trustedEnvironment`,
`software` for a Keystore without secure hardware, as on emulators,
`secretStore`). The platform code signs in DER; the package turns it
into the raw `R || S` that JOSE wants. No key material, proof or token
is ever logged.

**When the key is lost.** The key is never in a backup and never leaves
the device: an app restored on another phone, reinstalled, or a Keystore
wiped by the system has none. The next proof makes a new key; the stored
tokens carry the thumbprint of the old one
(`SecretStoreOAuth2AuthorizedClientService` keeps the token type and,
for DPoP tokens, the key's RFC 7638 thumbprint), so they are dropped
when loaded, `restore()` finds no login, and the user logs in again. A
key that disappears while the app runs fails the request that needed it
(`PlatformDPoPKeyException`, code `no_key`); the next one makes a new
key, and the refresh token, bound to the old key, is refused: the user
logs in again.

**Logout.** `logout()` deletes the key after revoking and forgetting the
tokens; the next login makes a new one. RFC 9449 lets a key live across
logins, but a key per login means nothing bound to the old login works
any more, and two logins on the device cannot be linked by their key's
thumbprint. Other DPoP tokens of the app (a `client_credentials`
registration) are bound to the old key too: they are dropped at their
next load and fetched again. `SecretStore.deleteAll()` removes the
desktop key (it is a value of the store), not the Secure Enclave's or
the Keystore's; call `PlatformDPoPKey.delete()` for those.

**WebSocket handshakes and calls of your own.** The Feign interceptor
sends `Authorization: DPoP <token>` and a proof by itself. For a request
the framework does not make, `OAuth2AccessTokenHeaders` of the OAuth2
client writes the headers by the token's type; for a WebSocket handshake
the proof's `htu` is the `http(s)` form of the `ws(s)` URL (the handshake
is an HTTP `GET` of it, and the server checks it as such):

```dart
// A handshake interceptor of the app (spring_boot_starter_websocket).
@Component()
class ChatHandshake implements WebSocketHandshakeInterceptor {
  ChatHandshake(this._tokens, this._dPoPKey);
  final OAuth2AuthorizedClientManager _tokens;
  final DPoPKey? _dPoPKey;

  @override
  Future<void> apply(WebSocketHandshake handshake) async {
    final user = SecurityContextHolder.getContext().authentication;
    if (user == null) return;
    final client = await _tokens.authorize(
      OAuth2AuthorizeRequest.withClientRegistrationId('keycloak')
          .principal(user)
          .build(),
    );
    final headers = await OAuth2AccessTokenHeaders(dPoPKey: _dPoPKey).of(
      client!.accessToken,
      method: 'GET',
      url: handshake.url,
    );
    headers.forEach(handshake.headers.set);
  }
}
```

Browsers cannot set headers on a WebSocket handshake: a page in server
mode sends its session cookie with it, and the server knows the user by
the session.

An app declares its own `DPoPKey` bean to keep the key elsewhere; the
package's then backs off (and `logout()` leaves the app's key alone).

Spring has no DPoP on the client's side (Spring Security 7 accepts DPoP
tokens on resource servers only), and Java has no apps.

## Secrets of the app: `SecretTemplate`

The store keeps strings by key; the app may keep its own secrets there,
not only the login's tokens. `SecretTemplate` (a bean) does it with
objects, like Spring Vault's `VaultTemplate`
(secrets by path) and `RedisTemplate` (objects through a serializer):
it writes them as JSON with the application's `ObjectMapper`, under its
namespace (`app.` by default), so the app's keys never meet the login's
(`oauth2.`).

```dart
@Introspected()
class PinSettings {
  const PinSettings({required this.hash, required this.attempts});
  final String hash;
  final int attempts;
}

@Service()
class Pin {
  Pin(this._secrets);
  final SecretTemplate _secrets;

  Future<void> save(String hash) =>
      _secrets.write('pin', PinSettings(hash: hash, attempts: 0));
  Future<PinSettings?> current() => _secrets.read<PinSettings>('pin');
  Future<void> forget() => _secrets.delete('pin');
}
```

`keys()` lists the template's keys and `deleteAll()` removes them; the
store's own `deleteAll()` removes everything, the login's tokens too.

The limits:

- **Small secrets, not data.** Each value is a Keychain item, an
  encrypted preference, a file or a keyring entry: no database, and
  every call is slow. To protect much data (a local database, files),
  encrypt it and keep only its encryption key here.
- **No web.** A browser has no secure storage (memory, `localStorage`
  and IndexedDB are readable by any script of the page), so on the web
  every call of the template throws an `UnsupportedError`; it never falls
  back to memory or `localStorage`. There the server keeps secrets.

## Widgets that follow the user

For display only: the server checks access. The app is in the user's
hands (it can be patched, the API called directly), so hiding a button
protects nothing; the server's checks (a 403) do. The same holds for
`@PreAuthorize` on the app's own beans. These widgets only spare the
user buttons that would fail, like Thymeleaf's `sec:authorize`, which
only decides what a page renders. They are named after the principal
(Spring's word for who is logged in), not after security, so they
promise no protection.

- **`PrincipalNotifier`**, a bean: the current `Authentication` as a
  `Listenable`, changed on every login and logout. It listens to the
  `SecurityContextHolder` (it wraps its strategy in Spring Security's
  `ListeningSecurityContextHolderStrategy`) and to the authentication
  events of `OAuth2LoginService` and the `AuthenticationManager`.
  Work run as another user (`runWithContext`) does not count, and an
  anonymous user counts as nobody.
- **`context.principal`** reads it in `build` and builds the widget
  again when it changes, in any widget.
- **`PrincipalBuilder`** builds with the current authentication (`null`
  when nobody is logged in):

  ```dart
  PrincipalBuilder(
    builder: (context, authentication) => authentication == null
        ? const LoginButton()
        : Text('Hello, ${authentication.name}'),
  )
  ```

- **`PrincipalView`** shows a child for a principal that matches and
  another one (nothing by default) otherwise: `hasRole`, `hasAuthority`,
  `authenticated` (`false`: only for nobody), or a SpEL expression as in
  `@PreAuthorize`, all of which must hold. They are evaluated by the
  application's `MethodSecurityExpressionHandler`, so the role hierarchy
  applies.

  ```dart
  PrincipalView(
    hasRole: 'ADMIN',
    child: const AdminMenu(),
    otherwise: const SizedBox.shrink(),
  )

  PrincipalView(
    expression: "hasRole('ADMIN') or hasAuthority('SCOPE_admin')",
    child: const AdminMenu(),
  )
  ```

Spring has no widgets; the nearest are Thymeleaf's `sec:authorize` and
`sec:authentication`, which decide what a server page renders.

## Login screens

Ready parts of a login screen, so an app does not write the same form
and buttons again: a user name and password form, a button for any
registration of the properties, and the buttons of Google, Apple,
Microsoft and GitHub in the look their owners prescribe. They only start
a login; what happens then is `AuthenticationManager`'s or
`OAuth2LoginService`'s, as above.

**Their design follows the app.** The Flutter starter builds a
`MaterialApp`, a `CupertinoApp` or a plain `WidgetsApp`
(`spring.flutter.app.type`), so the form and `OAuth2LoginButton` adapt
instead of requiring Material (`LoginDesign`, found from the app widget
above them): Material text fields and a `FilledButton` styled by the
app's `ThemeData` (and so by `spring.flutter.theme.components.input.*`
and `button.*`); `CupertinoTextField` and `CupertinoButton.filled` styled
by the `CupertinoTheme`; or plain fields and a button drawn in the
colours of the `SpringTheme`, with neither Material nor Cupertino. Pass
`design:` to choose one. The brand buttons look the same everywhere: the
brand decides their look, not the app.

### The user name and password form: `LoginForm`

```dart
// A login screen that closes once the user is in.
Scaffold(
  appBar: AppBar(title: const Text('Log in')),
  body: Padding(
    padding: const EdgeInsets.all(16),
    child: LoginForm(onSuccess: (_) => Navigator.of(context).pop()),
  ),
)
```

On submit (the button, or Enter in the password field; Enter in the user
name moves to the password) it checks that both fields are filled,
trims the user name (as Spring Security's form login does) and asks the
application's `AuthenticationManager` bean with a
`UsernamePasswordAuthenticationToken`. Meanwhile the button shows
progress and the fields are locked. A success puts the user into the
`SecurityContextHolder` (so `PrincipalNotifier`, `PrincipalBuilder` and
`@PreAuthorize` see them), publishes an
`InteractiveAuthenticationSuccessEvent`, tells the password manager to
save the login and calls `onSuccess`. A failure clears the password,
shows an error and calls `onError`:

- a wrong name or password, an unknown user and a refused account
  (`BadCredentialsException`, `UsernameNotFoundException`, an
  `AccountStatusException`): the same text, so nobody learns which part
  was wrong or which names exist;
- anything else (the server down, `AuthenticationServiceException`): the
  login could not be checked.

The fields carry the `username` and `password` autofill hints (password
managers fill and save them), the password is obscured with a show /
hide control, nothing is logged. `authenticate:` replaces the manager
for an app whose own service logs in (the form then sets no context and
publishes nothing), `authenticationManager:` names another manager.

Customise it with the theme, then with builders: `fieldBuilder` (gets a
`LoginFormField`: the controller, focus, label, error, obscuring and
toggle, autofill hints, keyboard action), `submitButtonBuilder` (a
`LoginFormSubmitButton`: label, `onPressed`, `busy`), `errorBuilder`, and
`errorMessage` for the texts of failures (keep a wrong name and a wrong
password the same). The texts come from the app's messages files, with
these English defaults, or from `usernameLabel`, `passwordLabel` and
`submitLabel`:

```properties
# lib/resources/messages.properties
login-form.username=User name
login-form.password=Password
login-form.submit=Log in
login-form.show-password=Show password
login-form.hide-password=Hide password
login-form.username-required=Enter your user name
login-form.password-required=Enter your password
login-form.bad-credentials=Wrong user name or password
login-form.service-error=The login could not be checked. Try again later.
```

### A button for any registration: `OAuth2LoginButton`

```dart
OAuth2LoginButton(
  'keycloak',
  icon: const Icon(Icons.key),
  onSuccess: (_) => Navigator.of(context).pop(),
  onError: (error) => setState(() => _error = '$error'),
)
```

It calls `OAuth2LoginService.login(registrationId)` (with
`additionalParameters`, such as `prompt=login`), shows progress while
the login runs, and calls `onSuccess` with the user (`null` in a browser,
where the page leaves for the login and the app starts again). The user
closing the login window (`AuthorizationCancelledException`) is no
error: the button is ready again. Any other failure goes to `onError`,
or to `FlutterError.reportError` without one. Its text is "Sign in with
_client name_" (message `login-button.oauth2`, `Sign in with {0}`): the
registration's `client-name` property, else a common provider's name
(`google` is Google, `github` GitHub), else the registration id; it
reads no registration, so it starts no discovery request. `label:`
replaces the text, `login:` the call (for an app whose own service wraps
the login), `builder:` the look.

### The providers' buttons

| Button | Registration id (default) | What the app chooses | Fixed by the brand |
|---|---|---|---|
| `GoogleLoginButton` | `google` | `theme` (light, dark, neutral), `shape` (rectangular, pill), `text` (sign in, sign up, continue), `iconOnly` | the full-colour "G" at 20 × 20; Google Sans Medium 14/20; light `#FFFFFF` with a `#747775` outline and `#1F1F1F` text, dark `#131314` / `#8E918F` / `#E3E3E3`, neutral `#F2F2F2` / none / `#1F1F1F`; 40 high with paddings 12 / 10 / 12 (Android, web, desktop), 44 high with 16 / 12 / 16 (iOS, macOS); corner radius 4 or a pill |
| `AppleLoginButton` | `apple` | `style` (black, white, white with outline), `text`, `iconOnly` with `circular`, `height` (30 and up, 44 by default), `cornerRadius` | Apple's own logo artwork (from the app, below), logo and title of one colour (white or black), the title in the system font (or the app's) at 43 % of the height, at least 140 wide, at least 8 % of the width free after the title, the logo file as high as the button |
| `MicrosoftLoginButton` | `microsoft` | `theme` (light, dark), `text` ("Sign in with Microsoft", "Sign in") | the four-colour logo in its 21 × 21 box; Segoe UI semibold 15; light `#FFFFFF` with a `#8C8C8C` border and `#5E5E5E` text, dark `#2F2F2F` with `#FFFFFF` text; 41 high, 12 before the logo, 12 between, 12 after; square corners |
| `GitHubLoginButton` | `github` | `theme` (dark, light), `shape`, `text`, `iconOnly` | the Invertocat mark in white (dark) or black (light) only, never recoloured; the size of the others (40 high, 12 / 10 / 12, a 20-pixel mark) |

Each is an `OAuth2LoginButton` underneath: the same `onSuccess`,
`onError`, `additionalParameters`, `loginService` and `login`, and a
`registrationId` that may be any id of the properties. No button names a
provider endpoint: the registration does
(`spring.security.oauth2.client.registration.<id>.*` and
`provider.<id>.*`; Google, GitHub and Apple are common providers of the
OAuth2 client, Microsoft's issuer depends on the tenant,
`https://login.microsoftonline.com/<tenant>/v2.0`). Hover, press and
keyboard focus have overlays in the text's colour; a spinner takes the
text's place while the login runs (the logo stays); larger text makes a
button taller, never the logo larger; right-to-left puts the logo on the
right; icon-only buttons still tell a screen reader their full text. The
texts may be translated in the app's messages (Google and Microsoft
invite it; keep the meaning, never "Google" alone):

```properties
login-button.google.sign-in=Sign in with Google
login-button.google.sign-up=Sign up with Google
login-button.google.continue=Continue with Google
login-button.apple.sign-in=Sign in with Apple
login-button.apple.sign-up=Sign up with Apple
login-button.apple.continue=Continue with Apple
login-button.microsoft.sign-in-with=Sign in with Microsoft
login-button.microsoft.sign-in=Sign in
login-button.github.sign-in=Sign in with GitHub
login-button.github.sign-up=Sign up with GitHub
login-button.github.continue=Continue with GitHub
```

**Why no other customisation.** These buttons are their owners' marks,
and the owners publish what may change. Google allows using its brand
only as its branding guidelines describe (anything else needs its
written consent) and asks that its button be at least as prominent as
the others; App Review checks every custom Sign in with Apple button
against the Human Interface Guidelines and rejects buttons that break
them, and the App Store asks an app that offers Google's or another
third-party login to offer an equivalent privacy-focused one (in
practice Sign in with Apple); Microsoft forbids altering its logo;
GitHub allows its mark only in black or white, unaltered. So colours,
logos, fonts, sizes and texts are not parameters; a design the rules do
not cover belongs to `OAuth2LoginButton(builder: ...)`, without the
brand's logo.

**Apple: the logo comes from the app, the sheet from the system.**
Apple's guidelines allow only Apple's logo artwork ("never create a
custom Apple logo"), and Apple's Developer Artwork License lets Apple
Developer Program members use it in their own apps only, never
redistribute it. A library cannot ship it, so `AppleLoginButton` asks the
app for it: download "Sign in with Apple Logo" from
[Apple Design Resources](https://developer.apple.com/design/resources/),
add the files to the app's assets and pass them as `logo` (the PNG files
are made for buttons 44 points high, the default):

```dart
AppleLoginButton(
  logo: (context, artwork) => Image.asset(
    'assets/apple/${artwork.logoOnly ? 'logo-only' : 'left-aligned'}-'
    '${artwork.color.name}.png',
    height: artwork.height,
  ),
  onSuccess: (_) => Navigator.of(context).pop(),
)
```

On iOS and macOS, `OAuth2LoginService.login('apple')` opens Apple's
native sign-in sheet instead of a browser: the button just calls the
login service, which chooses.

**Fonts.** Google Sans and Segoe UI belong to Google and Microsoft and
are not shipped: an app that may use them adds them as fonts of its own;
otherwise the button falls back to Roboto, the app's font or the system
font (on Windows, Segoe UI is the system's). Apple's and GitHub's
buttons use the app's font (the system font by default).

**Sources and terms of the logos.** The logos are drawn as vector paths
in Dart (no image files, no SVG package), transcribed from what each
owner publishes for sign-in buttons; they remain their owners'
trademarks, used as their guidelines allow (see `NOTICE`):

- Google's "G": from `signin-assets.zip` of the
  [Sign in with Google branding guidelines](https://developers.google.com/identity/branding-guidelines)
  (the "G" outline over a conic gradient and six blurred shapes, as in
  the SVG files there). Google may update its artwork; the button follows
  the bundle of October 2026.
- Microsoft's logo: four squares of `ms-symbollockup_mssymbol_19.svg`
  from the
  [Sign in with Microsoft branding guidelines](https://learn.microsoft.com/entra/identity-platform/howto-add-branding-in-apps).
- GitHub's mark: the `mark-github-24` icon of
  [Octicons](https://github.com/primer/octicons) (MIT license,
  © GitHub, Inc.), used under GitHub's
  [logo guidelines](https://brand.github.com/foundations/logo), which
  allow it to show that an app works with GitHub, less prominent than the
  app's own name.
- Apple's logo: not included (above).

Spring has no widgets for this; the nearest is the default login page of
Spring Security (`formLogin()` and `oauth2Login()`), a server page with
a form and one link per registration, labelled with its client name.

## Platforms

Android, iOS, macOS, Windows, Linux and the web (where it has no secure
storage and no login window: the server logs in and keeps the tokens,
`ServerOAuth2LoginService`, or in spa mode the browser logs in and keeps
them in the tab's memory, `SpaOAuth2LoginService`).

The package is a Flutter plugin. Its platform code: Kotlin on Android
(minimum API 24, `androidx.browser` for Custom Tabs, the Android
Keystore for the secrets and the DPoP key), one Swift source for iOS 13+
and macOS 10.15+ (Swift Package Manager and CocoaPods; the Keychain, the
Secure Enclave), and Dart through `dart:ffi` on Windows and Linux, which
builds nothing native.

Run on devices (`example/flutter_guide/integration_test/dpop_key_test.dart`,
each proof checked against its public key with pointycastle): macOS (a
debug build: the Keychain key), the iOS 27 simulator (its emulated
Secure Enclave), an Android 17 emulator (the Keystore without secure
hardware). Not yet on a phone with StrongBox. On Windows and Linux the
stores and the key kept in them are tested against the real systems by
`test/desktop_secret_store_test.dart`, which CI runs on GitHub's Windows
runner (DPAPI) and Linux runner (GNOME Keyring through libsecret).

## What security costs

Measured with Flutter 3.47 (October 2026): a minimal app (a
`SpringApplicationWidget` showing a text) built twice, once with
`spring_boot_starter_flutter` and once with this package instead, which
adds the OAuth2 client, Feign, `spring_security_core` and this plugin.
The app uses none of it; the generated `main.spring.dart` lists their
auto-configurations, whose beans keep the code in the build (tree shaking
cannot remove it).

| Release build | Flutter starter | With this package | Difference |
|---|---|---|---|
| APK arm64-v8a (`--split-per-abi`) | 16.7 MB | 17.2 MB | +0.54 MB |
| APK armeabi-v7a | 14.1 MB | 14.7 MB | +0.61 MB |
| APK x86_64 | 18.1 MB | 18.7 MB | +0.54 MB |
| Web `main.dart.js` | 2.34 MB | 2.71 MB | +0.37 MB (+16 %) |
| Web `main.dart.js`, gzip | 0.70 MB | 0.82 MB | +0.12 MB |

Of the APK's difference, 512 KiB is Dart code (`libapp.so`) and 17 KB
the plugin's Kotlin with what R8 keeps of `androidx.browser` (`classes.dex`, 8 KB
compressed). An app without a login lists only the Flutter starter and
carries none of it.
