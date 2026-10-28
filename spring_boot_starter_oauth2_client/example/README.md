# spring_boot_starter_oauth2_client: examples

This starter logs the user of a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) app in
with an OAuth 2.0 / OpenID Connect provider and sends their token with
every Feign call.

[`example.dart`](example.dart) is a small Spring Boot application. It
starts a local server playing the identity provider and the API, logs in
through the loopback browser (a scripted "user" stands in for the system
browser), calls the API through a Feign client with the user's token, and
logs out, which revokes the tokens.

## Run it

```yaml
dependencies:
  spring_boot_starter_oauth2_client: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2
```

From the package directory:

```bash
dart run build_runner build
dart run example/example.dart
```

After the startup lines it logs, through the `example` logger:

```text
... example : restored: false
... example : signed in: Ada Lovelace <ada@example.com>
... example : the API sees: user-1
... example : signed out; tokens revoked: 2
```

## 1. The registration

The provider is described by its issuer; its endpoints are discovered at
the first login:

```properties
spring.security.oauth2.client.registration.local.client-id=demo-app
spring.security.oauth2.client.registration.local.scope=openid,profile,email
spring.security.oauth2.client.registration.local.redirect-uri=http://127.0.0.1/callback
spring.security.oauth2.client.provider.local.issuer-uri=http://127.0.0.1:<port>
```

No client secret: an app is a public client and PKCE protects its codes.

## 2. Log in and out

```dart
@Service()
class Account {
  Account(this._login, this._api);
  final OAuth2LoginService _login;
  final ApiClient _api;

  Future<bool> start() async => await _login.restore() != null;
  Future<String> signIn() async { ... await _login.login('local') ... }
  Future<void> signOut() => _login.logout();
}
```

`login` opens the provider's page, checks the redirect (`state`, `iss`),
exchanges the code with the PKCE verifier, checks the ID token (issuer,
audience, expiry, nonce) and loads the user info. `logout` revokes the
tokens at the provider.

## 3. The token on Feign calls

```properties
spring.cloud.openfeign.oauth2.enabled=true
spring.cloud.openfeign.oauth2.client-registration-id=local
```

```dart
@FeignClient('api', url: r'${api.url}')
abstract interface class ApiClient {
  @GetMapping('/me')
  Future<Map<String, Object?>> me();
}
```

Each call carries `Authorization: Bearer <the user's token>`, refreshed
when it expires within a minute.

## 4. The browser

A real app keeps the starter's `LoopbackAuthorizationBrowser` (the system
browser and a one-shot server on `127.0.0.1`) or, in Flutter, the Flutter
starter's. The example declares its own `AuthorizationBrowser` bean so a
script can play the user; any bean of that type replaces the starter's.

Everything else (the flows, the checks, the properties, the differences
from Spring) is in the package
[README](https://pub.dev/packages/spring_boot_starter_oauth2_client).
