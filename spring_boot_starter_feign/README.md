# spring_boot_starter_feign

Feign clients for [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications, like Spring Cloud OpenFeign: describe an HTTP API as an
abstract class with `@GetMapping`, `@PostMapping`, ... and inject it like
any bean. The generator writes the implementation (no reflection), JSON
goes through the `ObjectMapper` of `spring_core_dart`.

```dart
@FeignClient('catalog', url: r'${catalog.url}')
abstract interface class CatalogClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  @GetMapping('/books')
  Future<List<Book>> search(@RequestParam('q') String query, {@RequestParam() int? page});

  @PostMapping('/books')
  Future<ResponseEntity<Book>> create(@RequestBody() Book book);

  @DeleteMapping('/books/{isbn}')
  Future<void> delete(@PathVariable() String isbn);
}

@Introspected()                       // JSON without fromJson / toJson
class Book {
  const Book({required this.isbn, required this.title});
  final String isbn;
  final String title;
}

@Service()
class Shop {
  Shop(this.catalog);                 // injected like any bean
  final CatalogClient catalog;

  Future<String> title(String isbn) async => (await catalog.find(isbn)).title;
}
```

```properties
# lib/resources/application.properties
catalog.url=https://api.neon.books
```

## Setup

```yaml
dependencies:
  spring_boot_dart: ^0.1.0
  spring_boot_starter_feign: ^0.1.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0   # required: writes the client implementations
```

```bash
dart run build_runner build
```

The starter is found automatically (no `@EnableFeignClients`): every
abstract class with `@FeignClient` in the scanned package becomes a bean,
named after the interface (`catalogClient`). One import is enough:
`package:spring_boot_starter_feign/spring_boot_starter_feign.dart`
re-exports `spring_boot_dart` and `spring_web_dart` (the mapping
annotations).

Classes used by the clients (parameters and results) are introspected for
JSON automatically when they are in the same package.

## Methods

Every method needs one mapping annotation and must return a `Future`.

| Annotation | Request |
|---|---|
| `@GetMapping('/books/{isbn}')` | `GET` |
| `@PostMapping('/books')` | `POST` |
| `@PutMapping`, `@PatchMapping`, `@DeleteMapping` | `PUT`, `PATCH`, `DELETE` |
| `@RequestMapping('/x', method: HttpMethod.head)` | any method |

The path is joined to the client's `url` and `path`. Mapping annotations
also take `headers: ['X-Shop: ${shop.name}']` (placeholders allowed),
`produces` (the `Accept` header, `application/json` by default) and
`consumes` (the `Content-Type` of the body).

Parameters:

| Parameter | Goes to |
|---|---|
| `@PathVariable() String isbn` | `{isbn}` in the path (URL-encoded); `@PathVariable('id')` for another name |
| `@RequestParam('q') String query` | `?q=...`; `null` is left out, a `List` repeats the parameter |
| `@RequestHeader('X-Trace') String? trace` | a header; `null` is left out |
| `@RequestBody() Book book` | the body: objects as JSON (`ObjectMapper`), `String` as text, `Uint8List` as bytes |
| a parameter without annotation | the body (only one such parameter) |

Results:

| Return type | From the response |
|---|---|
| `Future<Book>`, `Future<List<Book>>`, `Future<Map<String, int>>` | the JSON body, through the `ObjectMapper` |
| `Future<Book?>` | `null` for an empty body (or a 404 with `dismiss404`) |
| `Future<void>` | nothing (the status must be 2xx) |
| `Future<String>`, `Future<Uint8List>` | the body as text, as bytes |
| `Future<ResponseEntity<Book>>` | status, headers and the body |

Enums, `DateTime` and other values in paths, query parameters and headers
are written like in JSON (an enum's name or `@JsonValue`, ISO-8601 dates).

Every client is checked when it is created: a `{variable}` without a
`@PathVariable` parameter (or the other way round), a method without a
mapping or a synchronous method stops the application at startup with the
reason, for instance:

```text
Invalid Feign client CatalogClient:
  - CatalogClient.find: the path variable {isbn} of "/books/{isbn}" has no @PathVariable parameter
```

## Configuration

Properties per client name (`@FeignClient('catalog')`), with `default`
for all clients, like Spring Cloud OpenFeign:

```properties
spring.cloud.openfeign.client.config.default.read-timeout=10s
spring.cloud.openfeign.client.config.default.connect-timeout=2s
spring.cloud.openfeign.client.config.catalog.url=https://api.neon.books
spring.cloud.openfeign.client.config.catalog.logger-level=basic
spring.cloud.openfeign.client.config.catalog.dismiss404=true
spring.cloud.openfeign.client.config.catalog.default-request-headers.X-Shop=neon
```

| Property | Meaning |
|---|---|
| `url` | base URL when `@FeignClient(url:)` is not given |
| `read-timeout` | the longest a call may take, reading the response included (`10s`, `PT1M`, milliseconds) |
| `connect-timeout` | connection timeout of the default transport (`default` only) |
| `logger-level` | `none`, `basic`, `headers`, `full` (see Logging) |
| `dismiss404` | a 404 gives `null` (nullable results, `void`) instead of an exception |
| `default-request-headers.<Name>` | a header sent with every request |

`@FeignClient(url:)` wins over the `url` property; `@FeignClient(path:)`
prefixes every path.

## Errors

A response with status ≥ 400 throws a `FeignException` subclass:

| Status | Exception |
|---|---|
| 400, 401, 403, 404, 405, 406, 409, 410, 415, 422, 429 | `FeignBadRequest`, `FeignUnauthorized`, `FeignForbidden`, `FeignNotFound`, `FeignMethodNotAllowed`, `FeignNotAcceptable`, `FeignConflict`, `FeignGone`, `FeignUnsupportedMediaType`, `FeignUnprocessableEntity`, `FeignTooManyRequests` (all `FeignClientException`) |
| 500, 501, 502, 503, 504 | `FeignInternalServerError`, `FeignNotImplemented`, `FeignBadGateway`, `FeignServiceUnavailable`, `FeignGatewayTimeout` (all `FeignServerException`) |
| no response (connection, timeout) | `RetryableException` with status `-1` |
| a body that does not fit the return type | `DecodeException` |

```dart
try {
  await catalog.find(isbn);
} on FeignNotFound {
  return null;
} on FeignException catch (error) {
  log.warning('catalog failed: ${error.status} ${error.responseBody}');
  rethrow;
}
```

Your own exceptions: declare an `ErrorDecoder` bean.

```dart
final class ShopErrors implements ErrorDecoder {
  @override
  Exception decode(String methodKey, HttpResponse response) =>
      response.statusCode == 404
          ? BookNotFound(response.request!.url.path)
          : const DefaultErrorDecoder().decode(methodKey, response);
}

@Configuration()
class FeignSetup {
  @Bean()
  ErrorDecoder errorDecoder() => ShopErrors();
}
```

## Retries

Like Spring Cloud OpenFeign, nothing is retried by default. A `Retryer`
bean retries `RetryableException`s: connection errors, timeouts, and
responses with a `Retry-After` header.

```dart
@Bean()
Retryer retryer() => const DefaultRetryer(maxAttempts: 3);   // 100 ms, 150 ms, ... up to 1 s
```

## Interceptors

Every `RequestInterceptor` bean changes every request before it is sent:
authentication, tracing ids, common query parameters.

```dart
@Configuration()
class FeignSetup {
  @Bean()
  RequestInterceptor auth(TokenStore tokens) =>
      BearerTokenRequestInterceptor(() => tokens.accessToken);   // may be async

  @Bean()
  RequestInterceptor requestIds() => RequestIds();
}

final class RequestIds implements RequestInterceptor {
  @override
  void apply(RequestTemplate template) {
    template.header('X-Request-Id', newId());
    if (template.clientName == 'catalog') template.query('lang', 'en');
  }
}
```

`BasicAuthRequestInterceptor(user, password)` is built in too.

## Fallback

A bean class implementing the interface answers when a call fails:

```dart
@FeignClient('motd', url: r'${motd.url}', fallback: OfflineMotd)
abstract interface class MotdApi {
  @GetMapping('/motd')
  Future<String> messageOfTheDay();
}

@Component()
class OfflineMotd implements MotdApi {
  @override
  Future<String> messageOfTheDay() async => 'offline, try later';
}
```

The generated client is `@Primary`, so injecting `MotdApi` gives the
client, not the fallback. The fallback answers **every** failure — a 404
too — after the retries.

## Logging

With `logger-level` above `none`, each call is logged under
`feign.<Interface>` at debug level (so the debug level must be on, e.g.
`logging.level.feign=debug` with `spring_boot_starter_logging`):

```text
---> GET https://api.neon.books/books/978-0
<--- 200 OK (84 ms)
```

`headers` adds the headers (`Authorization` is masked), `full` the bodies.

## Transport

Requests go through the `HttpTransport` bean: by default
`platformHttpTransport()` of `spring_web_dart` — `dart:io` on the VM and in
Flutter (mobile, desktop), `fetch` on the web (the server must allow your
origin with CORS). Declare your own `HttpTransport` bean to use something
else (e.g. a small adapter over another HTTP library).

## Testing

Replace the transport with `MockHttpTransport` from
`package:spring_web_dart/testing.dart`:

```dart
final server = MockHttpTransport();
final app = springBootTest(
  springApplication,
  overrides: [BeanOverride<HttpTransport>(server)],
  properties: {'catalog.url': 'https://catalog.test'},
);

test('reads a book', () async {
  server.when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1', 'title': 'Dune'});
  expect(await app.getBean<Shop>().title('1'), 'Dune');
  expect(server.lastRequest.headers['Accept'], 'application/json');
});
```

Or replace a whole client: `BeanOverride<CatalogClient>(FakeCatalog())`.

## How it works

`@FeignClient` is marked `@InterfaceProxy` (from `spring_core_dart`): for
such an interface the generator writes a class whose methods hand each call,
with the method's annotations, parameter names and types, to an
`InvocationHandler`. The starter's `feignClientFactory` bean creates that
handler. The client is a regular bean, so AOP applies to it — e.g.
`@Cacheable` on a client method (with `spring_boot_starter_cache`) caches
the responses.

## Differences from Spring Cloud OpenFeign

- No `@EnableFeignClients`: the starter is enough.
- Methods return `Future`s (HTTP is asynchronous in Dart).
- No service discovery or load balancing: every client needs a URL.
- `connect-timeout` is set for all clients (`default`); `read-timeout` per
  client.
- The fallback answers every failure, without a circuit breaker; there is no
  `FallbackFactory` yet.
- Not yet: form and multipart bodies, `@SpringQueryMap`, response streaming.
