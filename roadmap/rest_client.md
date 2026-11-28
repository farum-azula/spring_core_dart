# RestClient and @HttpExchange (0.10.1)

The layer above the `HttpTransport` of `spring_web_dart` (send a request,
get bytes back): call a URL and get an object back, as Spring's
`RestClient` does, and declared interfaces (`@HttpExchange`) on it, as
Spring's HTTP service clients.

```dart
final book = await rest.get()
    .uri('/api/books/{isbn}', isbn)
    .retrieve()
    .body<Book>();
```

Where, as in Spring 7 / Boot 4 (there is no `spring-boot-starter-http`
in Spring):

- **`spring_web_dart`** (Spring's `spring-web`; it runs on the VM, in
  Flutter and in browsers, unlike `spring_boot_starter_web`, the
  `dart:io` server): `RestClient` (fluent, URI templates, bodies through
  the `ObjectMapper`, 4xx / 5xx as `RestClientResponseException` and its
  subclasses, `onStatus` handlers, interceptors, `exchange` for the raw
  response), the
  `@HttpExchange` / `@GetExchange` / `@PostExchange` / ... annotations.
- **`spring_boot_starter_restclient`** (new; Boot 4's
  `spring-boot-starter-restclient`): the `httpTransport` bean, a
  `RestClient.Builder` bean from `spring.http.*` (timeouts, redirects) on
  it, `RestClientCustomizer`, the HTTP service groups. It depends on
  `spring_boot_dart` and `spring_web_dart`, as the web starter does. `spring_boot_dart` never depends on `spring_web_dart`: an
  application without HTTP gets none of it.
- **The OAuth2 client**: Bearer tokens on `RestClient` calls, as Spring's
  `OAuth2ClientHttpRequestInterceptor`.

Steps:

1. `RestClient` with the auto-configuration and the
   OAuth2 interceptor (about half a day).
2. `@HttpExchange` interfaces implemented by the generator, as direct
   `RestClient` calls: done in 0.10.1, and the only declared HTTP client
   of the family, as Spring offers HTTP service clients for declared
   interfaces.

Before Spring AI: the providers' clients are easier on `RestClient` than
on the bare `HttpTransport`.

## The family's calls on `RestClient` (0.10.1)

The owner, 27 November 2026: once `RestClient` exists, the family stops
repeating its work by hand. Three layers, as in Spring:

| Layer | Spring | The family |
|---|---|---|
| Bytes in, bytes out | `ClientHttpRequestFactory` | `HttpTransport` (`dart:io`, `fetch`, mock) |
| A URL in, an object out | `RestClient` | `RestClient` (new) |
| A declared interface | HTTP service clients | `@HttpExchange` |

Moves onto `RestClient` (a JSON request, a status check and a JSON answer
written by hand today):

- `spring_boot_starter_oauth2_client`: `token_response_clients.dart`,
  `user_services.dart`, `client_registrations.dart`,
  `jwk_set_oidc_id_token_decoder.dart` (Spring Security 6.4+ is on
  `RestClient` too);
- `spring_boot_starter_security`: `jwt_decoder.dart`;
- `spring_boot_starter_flutter_security`:
  `oauth2_token_revocation_client.dart`, `server_oauth2_login_service.dart`;
- `spring_boot_starter_supabase`: `supabase_http.dart`;
- `example/static_site`: `server_info.dart`.

Stays on the transport:

- its decorators, which must see every request, those of `RestClient`
  and the others alike: `RecordingHttpTransport` (the debug network
  recorder), `CsrfCookieHttpTransport`, `ServerCredentialsHttpTransport`;
- raw bytes and streams, where `RestClient` adds nothing: the remote
  file cache, theme images, scene models, `SseConnection`;
- `spring_web_dart`'s transports, multipart encoding and mocks.

`RestClient` sits on the same `httpTransport` bean, so the decorators
keep working unchanged. Order: `RestClient`, then these files one by
one, then `@HttpExchange`. The Supabase starter is measured before and
after.

No `RestTemplate` (the owner, 26 November 2026): Spring Framework 7.1
deprecated it for removal (`@Deprecated(since = "7.1", forRemoval =
true)`), and Spring Boot 4.2 deprecated `RestTemplateBuilder`,
`RestTemplateCustomizer`, its auto-configuration and `TestRestTemplate`;
`RestClient` is their replacement, `RestTestClient` in tests. The family
never had it and will not.
