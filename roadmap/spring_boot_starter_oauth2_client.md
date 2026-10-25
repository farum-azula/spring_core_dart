# spring_boot_starter_oauth2_client (planned)

Spring Security for outgoing requests: tokens for the clients the family
already has — `@FeignClient`, `@WebSocketClient`, the coming `RestClient`.
For a Flutter app this is the half that matters: an app is almost always a
client. The security context comes from
[spring_security_core](spring_security_core.md).

## Tokens on every request

Registrations and providers with Spring Boot's properties; a Feign client
just names its registration (Spring Cloud OpenFeign's
`spring.cloud.openfeign.oauth2.*`), and an interceptor adds
`Authorization: Bearer ...`:

```properties
spring.security.oauth2.client.registration.neon.client-id=books-app
spring.security.oauth2.client.registration.neon.scope=openid,profile,orders
spring.security.oauth2.client.provider.neon.issuer-uri=https://auth.neon.books
spring.cloud.openfeign.oauth2.enabled=true
spring.cloud.openfeign.oauth2.client-registration-id=neon
```

```dart
@FeignClient('orders', url: r'${orders.url}')
abstract interface class OrdersClient { ... }   // the token is added by itself
```

- The provider's endpoints from OpenID discovery
  (`.well-known/openid-configuration`).
- Refresh before expiry; on a 401, refresh once and repeat the request;
  one refresh at a time when many requests need it together.
- WebSocket handshakes get the token too (a header on the VM and mobile, a
  query parameter or protocol in browsers, which send no headers).

## Grants

- Client credentials, for server-to-server calls.
- Authorization code with PKCE, for apps: the login page opens in the
  browser (`url_launcher`, a Flutter team plugin), the redirect comes back
  through an app link on mobile, a loopback server on `127.0.0.1` on
  desktop, or the page itself on the web. Apps are public clients: no
  client secret in an app, ever.
- OpenID Connect: the ID token becomes the `Authentication` in the security
  context (name, claims, authorities); user info on demand.

## Storage and logout

- Authorized clients in an `OAuth2AuthorizedClientRepository`: in memory on
  servers, the `TokenStore` (Keychain / Keystore) of
  [spring_boot_starter_flutter](spring_boot_starter_flutter.md) in apps, so a restarted app is still
  logged in.
- Logout: token revocation, the context cleared, `LogoutSuccessEvent`
  published.
