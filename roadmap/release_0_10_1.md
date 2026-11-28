# Release 0.10.1

Set by the owner on 27 November 2026. Items 1 and 2 of
[release_1_0.md](release_1_0.md) come forward to this release, with
method retries. Each part gets its own plan and the owner's word before
work starts.

## 1. `RestClient` and `spring_boot_starter_restclient`

See [rest_client.md](rest_client.md).

- `spring_web_dart`: `RestClient` (fluent calls, URI templates with
  variables as a list or a map, bodies through the `ObjectMapper`,
  `retrieve` / `toEntity` / `toBodilessEntity` / `exchange`, `onStatus`
  and `defaultStatusHandler`, interceptors, `RestClient.builder()`,
  `clone` / `mutate`); `RestClientResponseException`,
  `HttpClientErrorException`, `HttpServerErrorException`,
  `ResourceAccessException`; the `@HttpExchange` / `@GetExchange` / ...
  annotations and `@ImportHttpServices`.
- `spring_boot_starter_restclient` (new; depends on `spring_boot_dart`
  and `spring_web_dart`, never the other way): the `httpTransport` bean
  (moved from the Feign starter), the `RestClient.Builder` bean (a new
  one per injection), `RestClientCustomizer`, `spring.http.clients.*`
  (timeouts, redirects), HTTP service groups with
  `spring.http.serviceclient.<group>.*` (base URL, default headers,
  timeouts, redirects) and `RestClientHttpServiceGroupConfigurer`.
- The generator implements `@HttpExchange` interfaces as direct
  `RestClient` calls: no invocation handler, no plan read at startup.
  Build errors: a `{variable}` without its `@PathVariable`,
  `@RequestBody` on a GET, `@RequestPart` without multipart, an
  interface without `@ImportHttpServices`, one group with two base URLs.
- The OAuth2 client: `OAuth2ClientHttpRequestInterceptor` and
  `@ClientRegistrationId` on HTTP service interfaces (Bearer and DPoP),
  as Spring Security 7.
- **Outgoing addresses closed by default** (the owner: security first,
  not discussed). Every address is denied until allowed by hand, private
  networks and loopback included: an `InetAddressFilter` as Boot 4's,
  set by properties or a bean. On `dart:io` the resolved address is the
  one checked and the one connected to (`HttpClient.connectionFactory`,
  against DNS rebinding), again on each redirect. In a browser only
  address literals can be checked; the docs say so.
- The family's own JSON calls move onto `RestClient`; the decorators and
  raw byte streams stay on the transport (the list in rest_client.md).

## 2. `@Retryable`, `@ConcurrencyLimit`, `RetryTemplate` in core

See [spring_boot_starter_retry.md](spring_boot_starter_retry.md). No
starter of their own: as Spring Framework 7, they are in
`spring_core_dart`.

## 3. Feign leaves no trace

Spring Cloud OpenFeign is feature-complete and Spring points to its HTTP
service clients. The family follows Spring as closely as it can, so when
Spring stops developing something, the family stops supporting it.

- The Feign starter is out of CI (done locally, committed with the new
  starter), its README says why; 0.10.1 is its last version, then
  `discontinued` on pub.dev. Its code stays in the repository for now
  (the owner, 27 November 2026): no starter, example or tool depends on
  it any more.
- Everything else moves to `RestClient` and `@HttpExchange`, and no
  mention of Feign stays (some 240 files outside the package): the OAuth2
  client (the Feign token interceptor, `FeignOAuth2Properties`), the
  Supabase starter (edge functions, its `Retryer` becomes a
  `RetryTemplate`), the Flutter security starter, the web starter's
  tests, the generator's Feign generation (reused for `@HttpExchange`),
  `example/flutter_guide`, `example/server_guide`, `example/supabase`,
  the tools, READMEs, roadmap, the Zed extension, NOTICE. Past CHANGELOG
  entries stay: they are history.
- The site (some 466 files): the Feign pages go, every example moves to
  the HTTP client.
- Dota Passport (some 30 files): moves to the HTTP client, on the
  owner's word, as every Dota change.

## 4. The site: discontinued packages

- On the components page, at the bottom, a section of its own:
  discontinued packages, each with its reason. Feign's: Spring Cloud
  OpenFeign is feature-complete and Spring points to HTTP service
  clients; the family follows Spring, so it no longer supports Feign;
  use `spring_boot_starter_restclient`.
- The same reason in Feign's CHANGELOG and in the site's changelog for
  0.10.1.
