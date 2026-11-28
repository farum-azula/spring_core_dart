## Unreleased

- The access token on `RestClient` calls and HTTP service interfaces, as Spring Security 7: `OAuth2ClientHttpRequestInterceptor` sends the token of the registration a call names (`@ClientRegistrationId('partner')` on an interface or a method, or `.attributes(ClientAttributes.clientRegistrationId('partner'))` by hand), else of `spring.security.oauth2.client.restclient.client-registration-id` (none by default); a call that names none goes without a token. Bearer, or DPoP with a fresh proof; a `DPoP-Nonce` of any answer goes into the next proof, a `401` that asks for a nonce is sent once more with it, another `401` marks the token expired so the next call refreshes it. `OAuth2RestClientHttpServiceGroupConfigurer.from(manager)` adds the interceptor to the HTTP service groups.
- The starter depends on `spring_boot_starter_restclient` and re-exports it: the interceptor is on every `RestClientBuilder` the starter makes (`oauth2RestClientCustomizer`; `spring.security.oauth2.client.restclient.enabled=false` turns it off), and the token, discovery and user-info calls go through its transport.
- **Security:** that transport calls only the addresses allowed by hand. The hosts of the providers' endpoints the properties name (`issuer-uri`, `authorization-uri`, `token-uri`, `user-info-uri`, `jwk-set-uri`, and the known providers' own) are allowed by `oauth2ProviderAllowedAddresses`. When a provider is discovered from its `issuer-uri`, the hosts of the token, JWK Set, user-info and revocation endpoints its document names join the allow list once the document's issuer is checked (Google's `oauth2.googleapis.com`, Entra ID's `graph.microsoft.com`), by host name only, so they open public addresses only (`OAuth2ProviderAllowedAddresses.allowDiscovered`); an endpoint named by an address or a `localhost` name, a host in a private network, and every API the application calls with the token go on `spring.http.clients.allowed-addresses`.
- **Breaking: no Feign.** Spring Cloud OpenFeign is feature-complete and Spring points to its HTTP service clients, so the family no longer supports Feign: `OAuth2AccessTokenInterceptor`, `OAuth2AccessTokenErrorDecoder`, `FeignOAuth2Properties` and the `spring.feign.oauth2.*` properties are gone, and the starter no longer depends on `spring_boot_starter_feign`. Declare the API as an HTTP service interface with `@ClientRegistrationId('partner')` (or name the registration on a `RestClient` call with `ClientAttributes.clientRegistrationId`); `spring.security.oauth2.client.restclient.client-registration-id` replaces `spring.feign.oauth2.client-registration-id` for calls that name none. A call that names no registration now goes without a token instead of failing, as in Spring Security.
- The token response clients, `DefaultOAuth2UserService`, `OidcUserService`, `ClientRegistrations` (discovery) and `JwkSetOidcIdTokenDecoder` send their requests with a `RestClient` on the transport they are given, as Spring Security 6.4+ does: the deadline of the calling code applies, and the `RestClient` log shows them (credentials masked). The constructors and the exceptions they promise stay; a provider that cannot be reached is now a `ResourceAccessException` (with the `HttpTransportException` as its cause) behind the `OAuth2AuthorizationException` (`invalid_token_response`) or the `OAuth2AuthenticationException` (`invalid_user_info_response`, `invalid_id_token`), as Spring's `RestClientException`. **Breaking:** `ClientRegistrations.fromIssuerLocation` and `fromOidcIssuerLocation` throw that `ResourceAccessException` instead of the `HttpTransportException`, and without a `transport` they call only the issuer's host instead of any address.
- `OAuth2ClientHttpRequestInterceptor` is a `StreamingClientHttpRequestInterceptor`: it never reads the body, so an upload streamed by the client passes it as a stream instead of being read whole into memory first. A `401` that asks for a DPoP nonce is not sent again with a streamed body that cannot be opened again: the `401` is the answer.

## 0.10.0

- No changes of its own: its generated code (`lib/spring_gen/`) is regenerated with spring_core_dart_generator 0.10.0.

## 0.9.0

- Its code names the introspection classes by their new names (`Introspector`, `Introspection`, `IntrospectedProperty`, `IntrospectedMethod`, `IntrospectedConstructor`, `IntrospectedParameter`; spring_core_dart's renames); nothing changes for its users.

## 0.8.4

- No changes of its own; released with the family version 0.8.4.

## 0.8.3

- No changes of its own; released with the family version 0.8.3.

## 0.8.2

- No changes of its own; released with the family version 0.8.2.

## 0.8.1

- No changes of its own; released with the family version 0.8.1.

## 0.8.0

- `AbstractOAuth2Token` (the access, refresh and ID tokens) implements `OAuth2Token` of `spring_security_core`.

## 0.7.4

- No changes of its own; released with the family version 0.7.4.

## 0.7.3

- No changes of its own; released with the family version 0.7.3.

## 0.7.2

- README: the link goes to the package's own page on farum-azula.org, and what the README says was checked against the code and brought up to date.
- The package's page on pub.dev links its documentation, [farum-azula.org](https://farum-azula.org) (`documentation` in `pubspec.yaml`).

## 0.7.1

### Changes

- **Breaking:** the main library no longer re-exports `spring_boot_starter_feign`. It re-exports `spring_security_core` and `spring_web_dart` (whose `HttpTransport` the clients take). The access token on Feign calls (`OAuth2AccessTokenInterceptor`, `OAuth2AccessTokenErrorDecoder`) is unchanged; an application with Feign clients lists `spring_boot_starter_feign` and imports it where it declares them (docs/packages.md).

## 0.7.0

- No changes of its own: its generated code (`lib/spring_gen/`) is regenerated with spring_core_dart_generator 0.7.0.

## 0.6.3

### Changes

- The editor metadata of `spring.security.oauth2.client.*` and `spring.feign.oauth2.*` is made from code and the starter reads the same classes: `OAuth2ClientProperties` (`registration.<id>.*` as `OAuth2ClientRegistrationProperties`, `client-secret-jwt.*`, `provider.<id>.*` as `OAuth2ClientProviderProperties`) and `FeignOAuth2Properties` are bound by the Binder. The hand-written `spring_metadata_additional.json` is gone.

## 0.6.2

- feat: 0.6.2 — the theme (typed keys and messages, states, every component, a theme from a URL), (#20)

## 0.6.1

- No changes of its own; released with the family version 0.6.1.

## 0.6.0

### Breaking

- Properties renamed: `spring.cloud.openfeign.oauth2.*` is `spring.feign.oauth2.*` (`enabled`, `client-registration-id`; Spring Cloud means nothing in Dart). An old name stops the start, naming the new one.

### Changes

- Checked against Project Wycheproof's test vectors (Apache-2.0, `test/fixtures/wycheproof/`): ES256 and RS256 verification of ID tokens, the conversion of DER ECDSA signatures of platform keys (`ECDSA.transcodeSignatureToConcat`) followed by verification, and the signatures of the software DPoP key and the JWT client secret (64-byte `R || S`, deterministic, valid): no bug found.
- Debug lines for the main steps, never with a secret: the token request (`Sending the authorization_code token request of registration keycloak to sso.test/token`, the status of the answer), the discovery documents and JWK Sets fetched (host, path, status, key count), and a refresh of an access token. The query of a URL, tokens, codes, the client secret and its JWT are never logged.

## 0.5.0

### Breaking

- `JwkSetOidcIdTokenDecoder` (the app-side ID token decoder, used for Sign in with Apple) refuses an ID token whose `typ` header is not `JWT` (in any case), blank or missing, as Spring Security 7.1 checks ID tokens: a `logout+jwt`, `at+jwt` or `secevent+jwt` token signed with the same keys is no ID token.

### Changes

- `client-secret-jwt.*` set by environment variables (`..._REGISTRATION_APPLE_CLIENTSECRETJWT_ISSUER`, also `..._CLIENT_SECRET_JWT_...`) was not found: the starter looked for the registrations by the exact key `client-secret-jwt`, so the `clientSecretResolver` bean was missing and Sign in with Apple sent an empty `client_secret`. The keys are now compared without dashes, dots and case, as relaxed binding does.
- `JwkSetOidcIdTokenDecoder` leaves out RSA keys whose exponent is 1, even or over 64 bits.
- `InMemoryClientRegistrationRepository` calls a failed supplier (a discovery of an `issuer-uri`) again only `retryAfterFailure` later (10 seconds by default); calls in between get its error at once, so a provider that is down never gets one request per login started. `clock` lets tests move time.
- That pause and the JWK Set's refetch interval are measured on a monotonic clock, so a device clock set back does not make them last hours.

## 0.4.3

- A registration whose issuer, authorization, token, JWK Set, user-info or redirect URI uses plain `http://` on a host other than `localhost`, `127.0.0.1` or `[::1]` is logged as a warning, once per registration (it still works). `ClientRegistrations.configurationForIssuerLocation`: the metadata lookup of the issuer discovery (the three locations, the issuer check), public so the security starter's resource server uses the same code. The discovery URLs no longer end in an empty `?`.
- DPoP on the client's side (RFC 9449; an addition, Spring Security 7 has none): `DPoPKey`, `SoftwareDPoPKey` (ES256 in Dart, RFC 6979 nonces, `toJwk` / `fromJwk`), `DPoPProofBuilder`, `ECDSA.transcodeSignatureToConcat` (DER to raw `R || S`), `DPoPMode` and `ClientRegistration.dpop` from the registration's `dpop` property (off by default; `auto`: on when the provider's metadata lists ES256 in `dpop_signing_alg_values_supported`). The token response clients send proofs and answer `use_dpop_nonce` once, the user services and the Feign interceptor send `Authorization: DPoP <token>` with a proof, the error decoder remembers `DPoP-Nonce` per server; `OAuth2AccessTokenResponse` reads `token_type: DPoP` (`TokenType.dpop`). New bean `dPoPKey` (a key per run, in memory; `ConditionalOnMissingBean`). `OAuth2ErrorCodes.invalidDPoPProof`, `useDPoPNonce`. `auto` by default: on when the provider announces DPoP and the key outlives the program (`DPoPKey.persistent`: the apps' keys of the Flutter security package), so servers, whose default key lives for one run, keep `Bearer` unless `dpop=true`. `LoadableDPoPKey` (a key made or read on first use; `DPoPProofBuilder` awaits its `load()`), `OAuth2AccessTokenHeaders` (the `Authorization` and `DPoP` headers of a token for a request the starter does not make: a WebSocket handshake, a call of your own; the Feign interceptor uses it), and `ws` / `wss` URLs in proofs as `http` / `https` (`htu` is the handshake's HTTP URI).
- First version: OAuth 2.0 and OpenID Connect clients from Spring Boot's `spring.security.oauth2.client.*` properties (`ClientRegistration`, `CommonOAuth2Provider`, issuer discovery at first use), the token endpoint (`authorization_code` with PKCE, `refresh_token`, `client_credentials`; `client_secret_basic`, `client_secret_post`, `none`), authorized clients (`InMemoryOAuth2AuthorizedClientService`) refreshed by `AuthorizedClientServiceOAuth2AuthorizedClientManager` (one refresh at a time), OAuth 2.0 and OIDC users with `OidcIdTokenValidator` and `TokenEndpointOidcIdTokenDecoder`, the shared DPoP types (`JwkThumbprint`, `DPoPProofClaims`), and `OAuth2AccessTokenInterceptor` for Feign (`spring.cloud.openfeign.oauth2.*`). The login of apps (`OAuth2LoginService`, `AuthorizationWindow`, `SecretStore`, `SecretTemplate`) is in `spring_boot_starter_flutter_security`.
