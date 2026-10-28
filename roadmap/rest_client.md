# RestClient, RestTemplate and @HttpExchange (planned, no package of its own)

The layer between the `HttpTransport` of `spring_web_dart` (send a
request, get bytes back) and `@FeignClient` (declared interfaces): call a
URL and get an object back, as Spring's `RestClient` does.

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
  response), `RestTemplate` for those used to it, the
  `@HttpExchange` / `@GetExchange` / `@PostExchange` / ... annotations.
- **`spring_boot_dart`** (Boot 3's `spring-boot-autoconfigure`, Boot 4's
  `spring-boot-restclient`): a `RestClient.Builder` bean from
  `spring.http.client.*` (base URL, timeouts, redirects) on the
  `HttpTransport` bean; `spring_boot_dart` then depends on
  `spring_web_dart` (pure Dart, small).
- **The OAuth2 client**: Bearer tokens on `RestClient` calls, as Spring's
  `OAuth2ClientHttpRequestInterceptor`.

Steps:

1. `RestClient` and `RestTemplate` with the auto-configuration and the
   OAuth2 interceptor (about half a day).
2. Later: `@HttpExchange` interfaces implemented by the generator, as it
   does for `@FeignClient` today (most of it reused). Not urgent: Feign
   covers declared clients; the docs then say when to take which (Spring
   offers `@HttpExchange` as the successor of Feign).

Before Spring AI: the providers' clients are easier on `RestClient` than
on the bare `HttpTransport`.
