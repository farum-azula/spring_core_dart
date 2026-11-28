# spring_boot_starter_oauth2_client

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-boot-starter-oauth2-client](https://farum-azula.org/components/spring-boot-starter-oauth2-client)

OAuth 2.0 and OpenID Connect clients for
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications: Spring Security's OAuth2 client with Spring Boot's
auto-configuration. A service calls another service with its own
(client-credentials) token; a server logs its users in with Keycloak,
Google, Auth0, Okta or any other provider (through the security
starter's `oauth2Login()`); a Flutter app logs its user in (through
[`spring_boot_starter_flutter_security`](../spring_boot_starter_flutter_security)).
All of them use the registrations, token endpoint clients and authorized
clients of this starter.

Calling an API with an access token is more protocol than it looks: the
provider's endpoints (discovered from its issuer), the token endpoint
with the right client authentication, the refresh before the token
expires (once, even when ten calls ask at the same time), the token
renewed after the API rejects it, and for logins PKCE, `state`, `nonce`
and the checks of the ID token. This starter does all of it from Spring
Boot's `spring.security.oauth2.client.*` properties; the application's
HTTP service interfaces and `RestClient` calls just work. It is pure
Dart and runs wherever `spring_boot_dart` runs: the VM, Flutter, the
web.

```properties
# lib/resources/application.properties
spring.security.oauth2.client.registration.partner.client-id=shop
spring.security.oauth2.client.registration.partner.client-secret=${PARTNER_SECRET}
spring.security.oauth2.client.registration.partner.authorization-grant-type=client_credentials
spring.security.oauth2.client.registration.partner.scope=orders.read
spring.security.oauth2.client.provider.partner.token-uri=https://id.partner.example/oauth2/token

# The partner's API, an HTTP service group.
spring.http.serviceclient.orders.base-url=https://api.partner.example
```

```dart
// Every call carries the partner's token.
@HttpExchange('/orders')
@ClientRegistrationId('partner')
abstract interface class OrdersClient {
  @GetExchange()
  Future<List<Order>> orders(); // Authorization: Bearer <token>
}

@SpringBootApplication()
@ImportHttpServices(group: 'orders', types: [OrdersClient])
Future<void> main(List<String> args) => springApplication.runAsync(args);
```

It is the Dart counterpart of `spring-boot-starter-oauth2-client` (Spring
Security's `spring-security-oauth2-client` and `-oauth2-core`), with
Spring Security 7's `OAuth2ClientHttpRequestInterceptor` and
`@ClientRegistrationId` on Spring Boot 4's `spring-boot-starter-restclient`.

## Setup

```yaml
dependencies:
  spring_boot_starter_oauth2_client: ^0.10.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.10.0
```

```bash
dart run build_runner build
```

One import is enough:
`package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart`
re-exports `spring_security_core` and `spring_boot_starter_restclient`
(with `spring_web_dart`: `RestClient`, `@HttpExchange` and
`@ImportHttpServices`; and through them `spring_boot_dart` and logging).

## Which flow where

| Client | Flow | Package |
|---|---|---|
| Server to server | client credentials, `OAuth2AuthorizedClientManager` | this one |
| Server pages, Flutter web | `oauth2Login()`: the server is a confidential client, the tokens stay in its session; the browser has only the `HttpOnly` session cookie | [`spring_boot_starter_security`](../spring_boot_starter_security) |
| Flutter iOS, Android, macOS, Windows, Linux | the app login: authorization code + PKCE, a public client (RFC 8252), the system's login window, the tokens in the platform's secure storage | [`spring_boot_starter_flutter_security`](../spring_boot_starter_flutter_security) |

The logins build on this starter: its registrations, its
`authorization_code` token client, its user services, its authorized
clients and their refresh.

## Registrations

A registration is one client of one provider. Its properties are Spring
Boot's:

| `spring.security.oauth2.client.registration.<id>.` | |
|---|---|
| `client-id` | required |
| `client-secret` | confidential clients (servers); none for an app |
| `client-authentication-method` | `client_secret_basic`, `client_secret_post`, `none` |
| `authorization-grant-type` | `authorization_code` (logins), `client_credentials` (server to server) |
| `redirect-uri` | a template: `{baseUrl}`, `{registrationId}`, `{action}`, ... |
| `scope` | `openid,profile,email` or a YAML list |
| `client-name` | shown to users |
| `provider` | the provider id, when it is not the registration id |
| `dpop` | `auto` (default), `true`, `false`: tokens bound to the app's key ([DPoP](#dpop-tokens-bound-to-the-apps-key); not in Spring Boot) |
| `response-mode` | `query` (default), `form_post`: the provider posts the response to the redirect URI, which only a server receives ([below](#apple-the-response-as-a-form-post-and-a-jwt-client-secret); not in Spring Boot) |
| `native-sign-in` | `none`, `apple` (default for the `apple` provider): apps (`spring_boot_starter_flutter_security`) sign in with Sign in with Apple's sheet on iOS and macOS instead of the browser (not in Spring Boot) |
| `client-secret-jwt.*` | a client secret that is a JWT signed with the client's own key (`issuer`, `key-id`, `private-key-location` or `private-key`, `audience`, `lifetime`; [below](#apple-the-response-as-a-form-post-and-a-jwt-client-secret); not in Spring Boot) |

| `spring.security.oauth2.client.provider.<id>.` | |
|---|---|
| `issuer-uri` | everything else is discovered (`/.well-known/openid-configuration`, then RFC 8414) |
| `authorization-uri`, `token-uri`, `user-info-uri`, `jwk-set-uri` | or each endpoint by hand |
| `user-info-authentication-method` | `header` (default), `form`, `query` |
| `user-name-attribute` | the attribute that names the user (`sub`, `login`, `email`) |

Google, GitHub, Facebook and Okta need only the client: a registration
named after them (or with `provider=github`) gets their endpoints from
`CommonOAuth2Provider`, exactly as in Spring. So does Apple
(`CommonOAuth2Provider.apple`, this package's addition).

```properties
spring.security.oauth2.client.registration.github.client-id=Iv1.8a61f9b3a7aba766
```

**Discovery happens at the first use, not at startup** (Spring Boot asks
the provider while the application starts), so an application, and an
app above all, starts while the provider cannot be reached. The
provider's metadata must name exactly the configured issuer, or the
registration is refused. A failed discovery is tried again 10 seconds
later at the earliest; until then every use gets its error at once, so a
provider that is down never gets one request per login started. The 10
seconds are measured on a monotonic clock: a device clock set back (by
hand, or a time server) does not make them last hours. The
security starter's resource server
(`JwtDecoders.fromIssuerLocation`) finds the metadata with the same code
(`ClientRegistrations.configurationForIssuerLocation`), so the places
asked and the issuer check are the same for both.

**Plain `http://` is warned about.** An issuer, authorization, token, JWK
Set, user-info or redirect URI with `http://` on a host other than
`localhost`, `127.0.0.1` or `[::1]` is logged as a warning once per
registration (`spring.security.oauth2.client.registration`); the
registration still works. An app trusts its ID tokens because TLS brought
them from the provider: over `http://` anyone on the way can read or
change them.

**Redirect URIs** are Spring's templates
(`{baseUrl}/login/oauth2/code/{registrationId}` by default):
`expandRedirectUri` fills them in with the server's address, or
`http://127.0.0.1` where there is none (an app's loopback redirect).

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

### Apple: the response as a form post and a JWT client secret

Sign in with Apple needs two things other providers do not:

- **`response_mode=form_post`** when the login asks for the name or the
  e-mail: the provider's page posts the response to the redirect URI.
  `ResponseMode` on the registration (`response-mode`) puts it into the
  authorization request (`OAuth2AuthorizationRequest.responseMode`);
  `OAuth2AuthorizationResponse.fromParameters` reads a posted form (its
  `additionalParameters` keep the rest, such as Apple's `user`). The
  security starter's `oauth2Login()` receives the post; an app's login
  window cannot.
- **A client secret that is a JWT** the server signs ES256 with the
  team's key, at most six months valid: `JwtClientSecret`, made from the
  registration's `client-secret-jwt.*` properties by the
  `clientSecretResolver` bean (a `JwtClientSecretResolver`, an
  `OAuth2ClientSecretResolver` the token response clients ask for the
  secret of each request):

  ```properties
  spring.security.oauth2.client.registration.apple.client-id=books.neon.web
  spring.security.oauth2.client.registration.apple.client-authentication-method=client_secret_post
  spring.security.oauth2.client.registration.apple.client-secret-jwt.issuer=ABCDE12345
  spring.security.oauth2.client.registration.apple.client-secret-jwt.key-id=XYZ987KEY1
  spring.security.oauth2.client.registration.apple.client-secret-jwt.private-key-location=file:/run/secrets/AuthKey_XYZ987KEY1.p8
  # audience: the provider's issuer-uri by default; lifetime: 1h by default (at most 180d)
  ```

  The key (PKCS #8, Apple's `.p8`) is read at the first token request;
  it is never logged, shown by `toString` or put into an error. A
  registration that has a JWT secret but sends none (`none`) is refused,
  never sent without it.

The apps' side of Sign in with Apple (the system's sheet) checks Apple's
identity token, which comes from the operating system and not from the
token endpoint, with `JwkSetOidcIdTokenDecoder`: the signature with the
registration's JWK Set (RS256 by default, ES256 on request; `alg: none`,
HS*, keys inside the token and weak RSA keys refused; an unknown `kid`
fetches the keys again, at most once a minute, measured on a monotonic
clock), the `typ` header (`JWT`
in any case, blank or none, as the security starter's
`OidcIdTokenDecoderFactory` and Spring Security 7.1's
`JwtTypeValidator.jwt()`: a `logout+jwt`, `at+jwt` or `secevent+jwt`
token signed with the same keys is refused), then the claims.

## Tokens on RestClient calls and HTTP service interfaces

The starter depends on
[`spring_boot_starter_restclient`](../spring_boot_starter_restclient)
and puts `OAuth2ClientHttpRequestInterceptor` (Spring Security 7's) on
every `RestClientBuilder` that starter makes: the injected builders and
the builders of the HTTP service groups. It sends a token only on the
calls that name a registration, so a client that also calls public
endpoints needs nothing more:

```dart
// Every call of the interface carries the partner's token.
@HttpExchange('/orders')
@ClientRegistrationId('partner')
abstract interface class OrderService {
  @GetExchange()
  Future<List<Order>> orders(); // Authorization: Bearer <token>
}

// One call, by hand.
final orders = await rest.get()
    .uri('/orders')
    .attributes(ClientAttributes.clientRegistrationId('partner'))
    .retrieve()
    .body<String>();
```

`@ClientRegistrationId` goes on the interface (every method) or on a
method; it is a request attribute (`HttpRequestAttribute`), which the
generated call sets. The token is the one of the user of the security
context, or, for a `client_credentials` registration, of the client;
it comes from the `OAuth2AuthorizedClientManager` at each call, so it is
refreshed when it expires within a minute. A registration that does not
exist, or a login that is needed, fails the call before it is sent.

| Property | Default | |
|---|---|---|
| `spring.security.oauth2.client.restclient.enabled` | `true` | Whether the starter's builders get the interceptor |
| `spring.security.oauth2.client.restclient.client-registration-id` | none | The registration of the calls that name none. Every such call, to any host, then carries this token: set it only when the application calls nothing else |

After the answer:

- a DPoP-bound token goes as `Authorization: DPoP <token>` with a fresh
  proof ([below](#dpop-tokens-bound-to-the-apps-key)); a `DPoP-Nonce` of
  any answer goes into the next proof for that server, and a `401` that
  asks for one (`WWW-Authenticate: DPoP error="use_dpop_nonce"`) is sent
  once more with it;
- another `401` marks the token expired, so the next call refreshes it;
  the call itself is not repeated.

To put the interceptor on the HTTP service groups alone (with
`restclient.enabled=false`), or with a manager of your own, declare the
group configurer:

```dart
@Bean()
OAuth2RestClientHttpServiceGroupConfigurer oauth2Groups(
  OAuth2AuthorizedClientManager manager,
) => OAuth2RestClientHttpServiceGroupConfigurer.from(manager);
```

**Allowed addresses.** The RestClient starter's transport, which the
token, discovery, JWK Set and user-info calls go through too, calls only
the addresses allowed by hand. The hosts of the providers' endpoints the
properties name (`issuer-uri`, `authorization-uri`, `token-uri`,
`user-info-uri`, `jwk-set-uri`, and the endpoints of `google`,
`github`, `facebook` and `apple`) are allowed with them. When a
provider is discovered from its `issuer-uri`, the hosts of the token,
JWK Set, user-info and revocation endpoints its document names join the
list once the document's issuer is checked (Google's
`oauth2.googleapis.com`, Microsoft Entra ID's `graph.microsoft.com`), so
a configured provider just works. They are taken by host name only, so
they open public addresses only: an endpoint the document names by an
address or a `localhost` name, a host that resolves to a private
network (a provider in the same Docker network), and the APIs the
application calls with the token go on
`spring.http.clients.allowed-addresses` (or are the `base-url` of an
HTTP service group). A denied call fails with a
`ResourceAccessException` whose `FilteredHostException` names the host
and the property.

**The starter's own calls.** The token response clients, the user
services, discovery and `JwkSetOidcIdTokenDecoder` are `RestClient` instances on
the `httpTransport` bean, as Spring Security 7's are `RestClient` instances:
they follow no redirect, and a provider that cannot be reached is a
`ResourceAccessException` behind the exception each promises
(`OAuth2AuthorizationException` with `invalid_token_response`,
`OAuth2AuthenticationException` with `invalid_user_info_response` or
`invalid_id_token`). They are built on the transport, not on the
`RestClientBuilder` bean, so the application's customizers and
interceptors do not apply to them.

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

## DPoP: tokens bound to the app's key

A `Bearer` token works for whoever holds it. A DPoP token (RFC 9449) is
bound to a key pair of the client: every token request and every API
call carries a short JWT, the *proof*, signed with the private key, and
the token is useless without it. The security starter's resource server
accepts both.

```properties
# auto (the default): on when the key outlives the program (an app's)
# and the provider's discovered metadata lists ES256 in
# dpop_signing_alg_values_supported; true: always (a provider configured
# by hand, or a server with a key of its own); false: Bearer tokens.
spring.security.oauth2.client.registration.my-provider.dpop=false
```

`auto` applies only to a key that outlives the program
(`DPoPKey.persistent`): the apps' keys of the Flutter security package
(the Secure Enclave, the Android Keystore, WebCrypto, the `SecretStore`
on desktops). A server's default key is made in memory for one run, so
on a server `auto` keeps `Bearer` tokens, as before: nothing changes
for `oauth2Login()` unless a registration says `dpop=true` (then
declare a `DPoPKey` bean that survives restarts and, with several
instances sharing sessions, is shared). Providers that do not announce
DPoP get `Bearer` everywhere.

When a registration uses DPoP:

- the token response clients (`authorization_code`, `refresh_token`,
  `client_credentials`) send a `DPoP` proof for `POST` to the token
  endpoint; when the provider answers `use_dpop_nonce` with a
  `DPoP-Nonce` header, the request goes once more with that nonce, and
  the provider's last nonce goes into the next proofs. A `token_type` of
  `DPoP` (any case) becomes `TokenType.dpop`; a provider may still issue
  `Bearer` (RFC 9449 allows it), and the token stays `Bearer`. A `DPoP`
  token for a request without a proof is refused. The refresh of a DPoP
  token always carries a proof: its refresh token is bound too;
- the `RestClient` interceptor sends `Authorization: DPoP <token>` and
  a fresh proof for each call (`htm` the method, `htu` the URL without
  query and fragment, `ath` the token's hash). It remembers the
  `DPoP-Nonce` of any answer per server for the next proofs; a 401 that
  asks for a nonce is sent once more with it and leaves the token alone;
- the user services send DPoP tokens to the user-info endpoint the same
  way, a nonce answered once.

The key is the `DPoPKey` bean: `algorithm` (`ES256`), `publicJwk` and
`sign`, which returns the raw `R || S` that JOSE wants
(`ECDSA.transcodeSignatureToConcat` converts the DER of platform keys).
The starter declares a `SoftwareDPoPKey`, an ES256 key made in Dart,
**generated for each run and kept in memory**. Tokens bound to it die
with the process, the refresh token too: after a restart the refresh
fails (`invalid_grant`, or a refused proof) and the user logs in again.
An app that keeps its login across restarts must keep its key:
`spring_boot_starter_flutter_security` registers its own (the Secure
Enclave or the Keychain on iOS and macOS, the Android Keystore, a key
kept in its `SecretStore` on Windows and Linux), and its module comes
first, so this one backs off; anyone else declares a `DPoPKey` bean, for
example a `SoftwareDPoPKey` restored with `fromJwk` from where `toJwk`
stored it. A key whose public part is known only once the platform
answered implements `LoadableDPoPKey`: `DPoPProofBuilder` awaits its
`load()` first. `toJwk` holds the
private key: never log it. Nothing in the starter logs a key, a proof or
a token, and the `RestClient` log masks the `DPoP` header like
`Authorization`.

For a request the starter does not make (an `HttpTransport` call of
your own, a WebSocket handshake), `OAuth2AccessTokenHeaders` writes the
headers by the token's type: `Bearer <token>`, or `DPoP <token>` and a
fresh proof. A `ws` / `wss` URL goes into the proof's `htu` as `http` /
`https`: `htu` is the HTTP URI of the request (RFC 9449 §4.2), and a
handshake is an HTTP `GET` of it, which the server checks as such.
Browsers cannot set headers on a handshake; a page sends its session
cookie instead.

```dart
// The token of the logged-in user on a WebSocket handshake.
final client = await manager.authorize(request);
final headers = await OAuth2AccessTokenHeaders(dPoPKey: key).of(
  client!.accessToken,
  method: 'GET',
  url: handshake.url, // wss://api.example.com/ws/chat
);
headers.forEach(handshake.headers.set);
```

## Authorized clients

An `OAuth2AuthorizedClient` holds the tokens of one principal for one
registration; the `OAuth2AuthorizedClientService` keeps them. The
starter's, as Spring Boot's, is an `InMemoryOAuth2AuthorizedClientService`:
right for client-credentials tokens, forgotten when the program stops.
Declare an `OAuth2AuthorizedClientService` bean to keep them elsewhere (a
database); `spring_boot_starter_flutter_security` declares one on the
platform's secure storage, so an app's login survives a restart.

The manager refreshes an `authorization_code` client with its refresh
token when the access token expires within a minute, and gets a new
`client_credentials` token the same way; a refresh the provider refuses
(`invalid_grant`) removes the client, an unreachable provider does not.
Nothing in the starter logs a token, a code, a verifier or a secret.

## OpenID Connect users and ID tokens

`OidcUserService` and `DefaultOAuth2UserService` load the user of a
login (the user info endpoint, whose `sub` must be the ID token's);
`OidcIdTokenValidator` checks an ID token's issuer, audience, `azp`,
expiry and issue time (60 seconds of skew) and its `nonce`. The ID tokens
of logins and of refreshes are read by the `OidcIdTokenDecoder` bean. The
starter's, `TokenEndpointOidcIdTokenDecoder`, checks the claims but not
the signature: the token comes straight from the token endpoint over
TLS, which OpenID Connect Core §3.1.3.7 allows, and this package has no
JWK machinery. Tokens with `alg: none` are refused all the same. The
security starter replaces it with a decoder that checks the signature
with the provider's JWK Set, as Spring does; declare an
`OidcIdTokenDecoder` bean of your own for any other rule.

## Replacing the defaults

Each bean of the starter backs off when the application declares one of
its type: `ClientRegistrationRepository`, `OAuth2AuthorizedClientService`,
`OAuth2AuthorizedClientManager`, the three
`OAuth2AccessTokenResponseClient<...>`, `OidcIdTokenDecoder`,
`OAuth2UserService<OAuth2UserRequest, OAuth2User>`,
`OAuth2UserService<OidcUserRequest, OidcUser>`,
`OAuth2ClientHttpRequestInterceptor` and `DPoPKey`.

Another auto-configuration replaces them the same way, provided its
module is registered first:
`@AutoConfigurationModule(before: ['springBootStarterOauth2ClientAutoConfiguration'])`,
with its beans guarded by `ConditionalOnMissingBean`. The security
starter does so for the `OidcIdTokenDecoder`, the Flutter security
package for the `OAuth2AuthorizedClientService` (and, next, the
`DPoPKey`).

## Differences from Spring

- **Tokens on `RestClient` calls.** Spring Security's
  `OAuth2ClientHttpRequestInterceptor` has no default registration and
  no DPoP, removes the authorized client after a `401` (here the token
  is marked expired, so a refresh token survives) and is put on a
  builder by hand or by `OAuth2RestClientHttpServiceGroupConfigurer`;
  here the starter puts it on every builder of the RestClient starter.
- **What the starter brings.** In Spring, `spring-boot-starter-oauth2-client`
  brings web security and `oauth2Login()` too. Here this package is the
  client only, because it must also run in Flutter apps and browsers,
  which have no `dart:io` server. A server lists
  `spring_boot_starter_security` instead: it depends on this package,
  re-exports it, and adds `oauth2Login()`. An app lists
  `spring_boot_starter_flutter_security`, which adds the app login.
- `ClientRegistrationRepository.findByRegistrationId`, the authorized
  client service, the manager, the token clients and the user services
  return `Future` values.
- Issuer discovery happens at the first use of a registration, not at
  startup; a failure is retried at a use 10 seconds later or more. Its
  metadata lookup is
  public (`ClientRegistrations.configurationForIssuerLocation`; Spring's
  `JwtDecoderProviderConfigurationUtils` is internal), and the security
  starter's resource server uses it too.
- A registration with plain `http://` URIs outside loopback is logged as
  a warning (Spring Boot says nothing).
- An `authorization_code` registration without a client secret and
  without `client-authentication-method` is a public client (`none`),
  even for a common provider that says `client_secret_basic`.
- PKCE is on for every `authorization_code` registration, confidential
  clients included, as in Spring Security 7.1.
- The token response clients are `RestClient` instances on the `HttpTransport`
  they are given: `DefaultAuthorizationCodeTokenResponseClient`,
  `DefaultRefreshTokenTokenResponseClient`,
  `DefaultClientCredentialsTokenResponseClient` (Spring 7's
  `RestClient*TokenResponseClient`, whose `RestClient` is set with
  `setRestClient`).
- `AuthorizedClientServiceOAuth2AuthorizedClientManager` needs its
  provider (Spring defaults to client credentials alone), runs one
  authorization at a time per registration and principal, and removes
  the stored client after `invalid_grant` or `invalid_token`.
- `OAuth2AuthorizedClient` keeps the ID token too: the refresh checks a
  new one against it, and a logout without a session (an app after a
  restart) needs it as `id_token_hint`.
- A refreshed ID token is checked as OpenID Connect Core §12.2 says
  (same issuer and subject), as Spring Security 6.3's
  `OidcAuthorizedClientRefreshedEventListener` does.
- The starter declares the token response clients, the user services
  and an `OidcIdTokenDecoder` as beans (Spring creates them inside its
  configurers), and the authorized client manager as Spring Security's
  `OAuth2AuthorizedClientManagerRegistrar` does.
- `TokenEndpointOidcIdTokenDecoder` trusts TLS instead of checking the
  signature (Spring's `OidcIdTokenDecoderFactory` always checks it; the
  security starter's bean does).
- JWT signature checks only in `JwkSetOidcIdTokenDecoder`, for ID tokens
  that did not come from the token endpoint (Sign in with Apple's sheet;
  RS256 and ES256); the full JOSE code is the security starter's, and on
  a server its `oidcIdTokenDecoder` bean replaces this package's. No
  `oauth2Login()` (the security starter's), no `private_key_jwt` or
  `client_secret_jwt` (`client_assertion`), no password or device
  grants.
- Additions for Sign in with Apple: `CommonOAuth2Provider.apple`,
  `ResponseMode` (`response-mode`), `OAuth2AuthorizationResponse.fromParameters`
  and its `additionalParameters`, `OAuth2ClientSecretResolver`,
  `JwtClientSecret` and `JwtClientSecretResolver` (`client-secret-jwt.*`;
  a Spring application writes a parameters converter for Apple). The
  code token request leaves `redirect_uri` out when the authorization
  request had none (RFC 6749 §4.1.3).
- DPoP on the client's side is an addition: Spring Security 7 has none
  (spring-security#18228 proposes `ClientSettings.requireDpop`). The
  `dpop` registration property, `ClientRegistration.dpop` (`DPoPMode`),
  `DPoPKey`, `SoftwareDPoPKey`, `DPoPProofBuilder`,
  `ECDSA.transcodeSignatureToConcat` (Nimbus' name), the `DPoPKey` bean
  and the DPoP parts of the token clients, user services and `RestClient`
  interceptor are this port's; `OAuth2AccessTokenResponse` reads
  `token_type: DPoP` as Spring Security 6.5 does.
- Not there yet: the token exchange (RFC 8693) and JWT bearer
  (RFC 7523) grants, `tls_client_auth`, a database-backed authorized
  client service; a WebCrypto DPoP key on the web (the Flutter security
  package's). The full list:
  [docs/security-spring-comparison.md](../docs/security-spring-comparison.md).
