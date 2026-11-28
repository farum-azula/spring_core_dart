# spring_boot_starter_oauth2_client: examples

This starter gives a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
application Spring Security's OAuth 2.0 client: registrations from
Spring Boot's properties, tokens from the provider's token endpoint, and
the token on the calls of `RestClient` and HTTP service interfaces.

[`example.dart`](example.dart) is a small Spring Boot application, a
service that calls a partner's API with its own access token (the
`client_credentials` grant). It starts a local server playing the
partner's identity provider and API, calls the API twice through an
HTTP service interface, and asks the authorized client manager what it
holds.

## Run it

```yaml
dependencies:
  spring_boot_starter_oauth2_client: ^0.10.0   # brings the RestClient starter

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.10.0
```

From the package directory:

```bash
dart run build_runner build
dart run example/example.dart
```

After the startup lines it logs, through the `example` logger:

```text
... example : orders: [A-1, A-2]
... example : again: 2 orders
... example : token requests: 1
... example : scopes: {orders.read}
... example : principal: anonymousUser
```

## 1. The registration

The client, its secret, the grant and the provider's token endpoint, as
in Spring Boot:

```properties
spring.security.oauth2.client.registration.partner.client-id=shop
spring.security.oauth2.client.registration.partner.client-secret=demo-secret
spring.security.oauth2.client.registration.partner.authorization-grant-type=client_credentials
spring.security.oauth2.client.registration.partner.scope=orders.read
spring.security.oauth2.client.provider.partner.token-uri=http://127.0.0.1:<port>/oauth2/token
```

The secret goes to the token endpoint with HTTP Basic
(`client_secret_basic`, the default). In a real application it comes
from the environment (`${PARTNER_SECRET}`), never from the sources.

## 2. The token on HTTP service calls

```properties
spring.http.serviceclient.orders.base-url=http://127.0.0.1:<port>
```

```dart
@HttpExchange('/orders')
@ClientRegistrationId('partner')
abstract interface class OrdersClient {
  @GetExchange()
  Future<List<Object?>> orders();
}

@SpringBootApplication()
@ImportHttpServices(group: 'orders', types: [OrdersClient])
Future<void> main(List<String> args) async { ... }
```

The generator implements the interface with calls of the group's
`RestClient`, and the starter's `OAuth2ClientHttpRequestInterceptor`
(on every `RestClientBuilder` of the RestClient starter) sends the
token of the registration `@ClientRegistrationId` names: each call
carries `Authorization: Bearer <token>`. The first call gets the token;
the next ones reuse it until it expires within a minute, then the
manager gets a new one. A 401 of the API marks the token expired, so the
next call gets a new one too. A call of a client built by hand names the
registration with
`.attributes(ClientAttributes.clientRegistrationId('partner'))`.

The transport calls only the addresses allowed: the token endpoint is
allowed because the registration's provider names it, the API because it
is the group's base URL.

## 3. The authorized client manager

```dart
final client = await authorizedClients.authorize(
  OAuth2AuthorizeRequest.withClientRegistrationId(
    'partner',
  ).principal(anonymousAuthentication).build(),
);
```

The same manager the interceptor uses, for code that sends the token by
itself (a WebSocket, another HTTP client). A client-credentials token
belongs to the application, so its principal is `anonymousUser`.

Everything else (the grants, discovery, the users of OpenID Connect, the
properties, the differences from Spring) is in the package
[README](https://pub.dev/packages/spring_boot_starter_oauth2_client).
