# spring_boot_starter_oauth2_client

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Single sign-on for [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications with OAuth 2.0 and OpenID Connect: log the user of an app in
with Keycloak, Google, Auth0, Okta or any other provider, keep them logged
in across restarts, and send their token with every Feign call. Servers
use the same registrations to call other services with their own
(client-credentials) tokens.

An app that talks to an API on behalf of its user needs the user's
access token, and getting one safely is a lot of protocol: the login page
in the system browser, a random `state` against forged redirects, PKCE so
that a stolen code is useless, a `nonce` and the checks of the ID token
(issuer, audience, expiry), the token endpoint, the refresh before the
token expires (once, even when ten calls ask at the same time), revoking
the tokens at logout, and somewhere safe to keep them. This starter does
all of it from Spring Boot's `spring.security.oauth2.client.*`
properties; the app calls `login`, `logout`, and its Feign clients just
work. It is pure Dart: the VM, desktop and mobile Flutter apps (with the
Flutter starter's secure storage and system browser), and, for client
credentials, the web.

```properties
# lib/resources/application.properties
spring.security.oauth2.client.registration.keycloak.client-id=neon-app
spring.security.oauth2.client.registration.keycloak.scope=openid,profile,email
spring.security.oauth2.client.registration.keycloak.redirect-uri=http://127.0.0.1/callback
spring.security.oauth2.client.provider.keycloak.issuer-uri=https://sso.example.com/realms/neon

# Every Feign call carries the user's token.
spring.cloud.openfeign.oauth2.enabled=true
spring.cloud.openfeign.oauth2.client-registration-id=keycloak
```

```dart
@Service()
class Account {
  Account(this._login);
  final OAuth2LoginService _login;

  Future<void> start() => _login.restore();             // logged in from last time?
  Future<void> signIn() => _login.login('keycloak');    // the system browser
  Future<void> signOut() => _login.logout();            // revoke, forget
  String? get who => _login.user?.name;
}
```

It is the Dart counterpart of `spring-boot-starter-oauth2-client` (Spring
Security's `spring-security-oauth2-client` and `-oauth2-core`), plus the
login of apps, which Spring does not have.

## Setup

```yaml
dependencies:
  spring_boot_starter_oauth2_client: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2
```

```bash
dart run build_runner build
```

One import is enough:
`package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart`
re-exports `spring_boot_starter_feign` (and through it `spring_web_dart`,
`spring_boot_dart` and logging) and `spring_security_core`.

## Which flow where

| Client | Flow | Tokens live |
|---|---|---|
| Server pages | `oauth2Login()` of the security starter: the server is a confidential client | on the server, in the session |
| Flutter web | the same, the server is the app's backend | on the server; the browser has only the `HttpOnly` session cookie |
| Flutter iOS, Android, macOS | `OAuth2LoginService`: authorization code + PKCE, a public client (RFC 8252), the system browser | the Flutter starter's `TokenStore` (Keychain, Keystore) |
| Flutter Windows, Linux, the Dart VM | the same, the redirect to a loopback server on `127.0.0.1` | the Flutter starter's `TokenStore` (DPAPI, libsecret); in memory on the VM |
| Server to server | client credentials, `OAuth2AuthorizedClientManager` | in memory |

An app never has a client secret (anyone can extract it): leave
`client-secret` out and the registration is a public client
(`client-authentication-method=none`); PKCE protects its codes instead.
A web page never holds tokens either (any injected script could read
them): `OAuth2LoginService.login` refuses to run there.

## Registrations

A registration is one client of one provider. Its properties are Spring
Boot's:

| `spring.security.oauth2.client.registration.<id>.` | |
|---|---|
| `client-id` | required |
| `client-secret` | servers only |
| `client-authentication-method` | `client_secret_basic`, `client_secret_post`, `none` |
| `authorization-grant-type` | `authorization_code` (logins), `client_credentials` (server to server) |
| `redirect-uri` | a template: `{baseUrl}`, `{registrationId}`, `{action}`, ... |
| `scope` | `openid,profile,email` or a YAML list |
| `client-name` | shown to users |
| `provider` | the provider id, when it is not the registration id |

| `spring.security.oauth2.client.provider.<id>.` | |
|---|---|
| `issuer-uri` | everything else is discovered (`/.well-known/openid-configuration`, then RFC 8414) |
| `authorization-uri`, `token-uri`, `user-info-uri`, `jwk-set-uri` | or each endpoint by hand |
| `user-info-authentication-method` | `header` (default), `form` |
| `user-name-attribute` | the attribute that names the user (`sub`, `login`, `email`) |

Google, GitHub, Facebook and Okta need only the client: a registration
named after them (or with `provider=github`) gets their endpoints from
`CommonOAuth2Provider`, exactly as in Spring.

```properties
spring.security.oauth2.client.registration.github.client-id=Iv1.8a61f9b3a7aba766
```

**Discovery happens at the first use, not at startup** (Spring Boot asks
the provider while the application starts). An app must start offline;
until the provider can be reached, `login` fails and `restore` brings the
user back from what it stored. The provider's metadata must name exactly
the configured issuer, or the registration is refused.

**Redirect URIs.** On the VM and desktops the default loopback browser
receives the redirect on `http://127.0.0.1:<any free port><path>`; the
provider must accept a loopback redirect with any port (RFC 8252 §7.3:
Keycloak `http://127.0.0.1/*`, Google desktop clients). Spring's default
template `{baseUrl}/login/oauth2/code/{registrationId}` works too:
`{baseUrl}` is `http://127.0.0.1` in an app. On iOS and Android the
Flutter starter catches a redirect to the app's own scheme
(`neonbooks:/oauth2/callback`).

Declare a `ClientRegistrationRepository` bean to keep registrations
elsewhere:

```dart
@Bean()
ClientRegistrationRepository registrations() =>
    InMemoryClientRegistrationRepository([
      CommonOAuth2Provider.google
          .getBuilder('google')
          .clientId('1234.apps.googleusercontent.com')
          .build(),
    ]);
```

## The login of an app

`OAuth2LoginService.login('keycloak')`:

1. builds the authorization request: a random `state` (32 bytes of
   `Random.secure()`), a PKCE verifier (64 bytes) and its `S256`
   challenge, and for `openid` a random `nonce` (its SHA-256 hash is
   sent);
2. opens the provider's page in the `AuthorizationBrowser` and waits for
   the redirect;
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
   tokens in the `OAuth2AuthorizedClientService` (the `TokenStore`) and
   publishes an `AuthenticationSuccessEvent`.

Any failure is an `OAuth2AuthenticationException` whose `error.errorCode`
says why; a closed page is an `AuthorizationCancelledException`.

`restore()` at startup brings the user back from the stored tokens and
refreshes them when they expire within a minute; a refresh token the
provider refuses (`invalid_grant`) logs the user out, an unreachable
provider does not. `logout()` revokes the refresh and access tokens (RFC
7009, when the provider has a `revocation_endpoint`), forgets them,
clears the context and publishes a `LogoutSuccessEvent`;
`logout(endSession: true)` also ends the provider's session in the
browser (OpenID Connect RP-initiated logout, with the ID token as
`id_token_hint`).

The ID token's signature is not checked in an app: it comes straight
from the token endpoint over TLS, which OpenID Connect Core §3.1.3.7
allows (`TokenEndpointOidcIdTokenDecoder`). Tokens with `alg: none` are
refused all the same. Declare an `OidcIdTokenDecoder` bean to check
signatures too.

## Tokens on Feign calls

With `spring.cloud.openfeign.oauth2.enabled=true`, every Feign client gets
the `OAuth2AccessTokenInterceptor`: `Authorization: Bearer <token>` of
the logged-in user (or, for a `client_credentials` registration, of the
client), refreshed through the `OAuth2AuthorizedClientManager` when it
expires within a minute. The registration is
`spring.cloud.openfeign.oauth2.client-registration-id`, else the Feign
client's name, as in Spring Cloud OpenFeign.

When the API answers 401 to a token that looked valid, the
`OAuth2AccessTokenErrorDecoder` marks it expired, so the next call
refreshes it. The failed call itself is not repeated: Feign's
interceptors do not see responses, and its `ErrorDecoder` and `Retryer`
belong to the application. The starter declares the decoder only when the
application has no `ErrorDecoder`; wrap yours to keep the behaviour:

```dart
@Bean()
ErrorDecoder errorDecoder(OAuth2AccessTokenInterceptor tokens) =>
    OAuth2AccessTokenErrorDecoder(MyErrorDecoder(), tokens);
```

## Tokens anywhere else

The `OAuth2AuthorizedClientManager` hands out valid tokens; concurrent
callers for one registration and principal share one refresh, so a
rotating refresh token is never sent twice:

```dart
final client = await manager.authorize(
  OAuth2AuthorizeRequest.withClientRegistrationId('partner')
      .principal(anonymousAuthentication) // client credentials: no user
      .build(),
);
headers.set('Authorization', 'Bearer ${client!.accessToken.tokenValue}');
```

## Where tokens are kept

`TokenStore` is a small secret store (`read`, `write`, `delete` of
strings). The default, `InMemoryTokenStore`, forgets everything when the
program stops; the Flutter starter replaces it with the Keychain, the
Android Keystore, DPAPI or libsecret. Declare a `TokenStore` bean for
your own. The `TokenStoreOAuth2AuthorizedClientService` writes each
authorized client as JSON under
`oauth2.authorized-client.<registration>.<principal>`, and the login keeps
what `restore` needs under `oauth2.login`. Nothing in the starter logs a
token, a code, a verifier or a secret.

## Replacing the defaults

Each bean of the starter backs off when the application declares one of
its type: `ClientRegistrationRepository`, `TokenStore`,
`AuthorizationBrowser`, `OAuth2AuthorizedClientService`,
`OAuth2AuthorizedClientManager`, the three
`OAuth2AccessTokenResponseClient<...>`, `OidcIdTokenDecoder`,
`OAuth2UserService<OAuth2UserRequest, OAuth2User>`,
`OAuth2UserService<OidcUserRequest, OidcUser>`, `OAuth2LoginService`,
`OAuth2AccessTokenInterceptor` and `ErrorDecoder`.

Another starter's auto-configuration replaces them the same way, provided
its module is registered first: the module of the Flutter starter
(`springBootStarterFlutterAutoConfiguration`) is (this starter's module
says `after` it); any other says
`@AutoConfigurationModule(before: ['springBootStarterOauth2ClientAutoConfiguration'])`
and guards its beans with `ConditionalOnMissingBean`.

## Differences from Spring

- `ClientRegistrationRepository.findByRegistrationId`, the authorized
  client service, the manager, the token clients and the user services
  return `Future`s.
- Issuer discovery happens at the first use of a registration, not at
  startup; a failure is retried at the next use.
- An `authorization_code` registration without a client secret and
  without `client-authentication-method` is a public client (`none`),
  even for a common provider that says `client_secret_basic`.
- PKCE is on for every `authorization_code` registration, confidential
  clients included (Spring: public clients, or by customizer).
- The token response clients run on the `HttpTransport` of
  `spring_web_dart`: `DefaultAuthorizationCodeTokenResponseClient`,
  `DefaultRefreshTokenTokenResponseClient`,
  `DefaultClientCredentialsTokenResponseClient` (Spring 7's
  `RestClient*TokenResponseClient`).
- `AuthorizedClientServiceOAuth2AuthorizedClientManager` needs its
  provider (Spring defaults to client credentials alone), runs one
  authorization at a time per registration and principal, and removes
  the stored client after `invalid_grant` or `invalid_token`.
- `OAuth2AuthorizedClient` keeps the ID token too, for the logout's
  `id_token_hint` after a restart.
- A refreshed ID token is checked as OpenID Connect Core §12.2 says
  (same issuer and subject), as Spring Security 6.3's
  `OidcAuthorizedClientRefreshedEventListener` does.
- The app login (`OAuth2LoginService`, `AuthorizationBrowser`,
  `LoopbackAuthorizationBrowser`, `TokenStore`) and revocation
  (`OAuth2TokenRevocationClient`) have no Spring counterpart.
- No JWT signature checks in this package (the security starter has
  them, and on a server its `oidcIdTokenDecoder` bean replaces this
  package's); no `oauth2Login()` (the security starter's), no DPoP, no
  `private_key_jwt` or `client_secret_jwt`, no password or device grants.
