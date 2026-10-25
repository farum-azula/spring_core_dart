# spring_boot_starter_feign

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

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
  spring_boot_dart: ^0.2.1
  spring_boot_starter_feign: ^0.2.1

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.2.1   # required: writes the client implementations
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

Every method needs one mapping annotation and must return a `Future` —
or an `EventStream<T>` for server-sent events (see below).

| Annotation | Request |
|---|---|
| `@GetMapping('/books/{isbn}')` | `GET` |
| `@PostMapping('/books')` | `POST` |
| `@PutMapping`, `@PatchMapping`, `@DeleteMapping` | `PUT`, `PATCH`, `DELETE` |
| `@RequestMapping.of(path: '/x', method: HttpMethod.head)` | any method (`GET` by default) |

The path is joined to the client's `url` and `path`; without a path
(`@GetMapping()`) the request goes to the client's `url` and `path` itself
(`@FeignClient(url: 'https://api.shop.test', path: '/api')` →
`https://api.shop.test/api`). A query in the path
(`@GetMapping('/books?sort=title')`) is sent as written, the parameters of
the call appended to it. Mapping annotations
also take `headers: ['X-Shop=${shop.name}']` (Spring's `Name=value`,
placeholders allowed; server conditions such as `'!X-Debug'` are ignored,
Feign's `'Name: value'` stops the application), `produces` (the `Accept`
header, `application/json` by default) and `consumes` (the `Content-Type`
of the body). With a path they are written with the `.of` constructor, as
Dart cannot combine an optional positional parameter with named ones:
`@GetMapping.of(path: '/books', headers: ['X-Shop=neon'])`.

Parameters:

| Parameter | Goes to |
|---|---|
| `@PathVariable() String isbn` | `{isbn}` in the path (URL-encoded, a `/` stays a `/`: see `decode-slash`); `@PathVariable('id')` for another name |
| `@RequestParam('q') String query` | `?q=...`; `null` is left out, a `List` repeats the parameter |
| `@RequestParam() Map<String, Object?> filters` | one query parameter per entry (`?author=...&year=...`; a `List` value repeats it, `null` is left out) |
| `@RequestHeader('X-Trace') String? trace` | a header; `null` is left out, a `List` gives several values |
| `@RequestHeader() Map<String, String> headers` | one header per entry |
| `@CookieValue('SESSION') String session` | a cookie: the cookies of a call go in one `Cookie: a=1; b=2` header; `null` is left out |
| `@RequestBody() Book book` | the body: objects as JSON (`ObjectMapper`), `String` as text, `Uint8List` as bytes; with `consumes: MediaType.applicationFormUrlencoded` (or that `Content-Type` header) a `Map` or object is sent as a form (`name=value&...`, see below) |
| a parameter without annotation | the body (only one such parameter) |

`@PathVariable`, `@RequestParam` and `@RequestHeader` follow Spring's
`required` (default `true`) and `defaultValue` (a `String`), written with
the `.of` constructor: `@RequestParam.of(name: 'sort', defaultValue: 'asc')
String? sort`.

| Argument `null` | Result |
|---|---|
| with `defaultValue` | the default value is sent |
| required (the default, for a non-nullable parameter) | an `ArgumentError` naming the parameter and the annotation value, before anything is sent |
| not required (`required: false`, or a nullable parameter) | the query parameter or header is left out; a path variable (required unless `required: false`, whatever its type) becomes an empty string |

As Spring does for Kotlin and `@Nullable` parameters, a nullable Dart
query parameter or header (`String? q`) is never required, whatever
`required` says; use a non-nullable parameter to require a value.

Results:

| Return type | From the response |
|---|---|
| `Future<Book>`, `Future<List<Book>>`, `Future<Map<String, int>>` | the JSON body, through the `ObjectMapper` |
| `Future<Book?>` | `null` for an empty body (or a 404 with `dismiss404`) |
| `Future<void>` | nothing (the status must be 2xx) |
| `Future<String>`, `Future<Uint8List>` | the body as text, as bytes |
| `Future<ResponseEntity<Book>>` | status, headers and the body (read-only headers) |
| `Future<ResponseEntity<void>>` | status and headers; the body is ignored |
| `Future<HttpResponse>` | the raw response (Feign's `Response`): any status, no error decoding, no `dismiss404` |
| `EventStream<OrderEvent>`, `Stream<OrderEvent>` | the events of a `text/event-stream` response (see Server-sent events) |

Form bodies work like Spring Cloud OpenFeign's `SpringFormEncoder`: the
entries of a `Map` (or the properties of an object, as the `ObjectMapper`
writes them) become `name=value` pairs, URL-encoded in the `charset` of
the content type (UTF-8 by default); a `List` value repeats the name and
`null` values are left out.

```dart
@PostMapping.of(path: '/login', consumes: MediaType.applicationFormUrlencoded)
Future<void> login(@RequestBody() Map<String, String> form);
// username=neo&password=s3cr%3Ft
```

Enums, `DateTime` and other values in paths, query parameters, headers and
cookies are written like in JSON (an enum's name or `@JsonValue`, ISO-8601
dates); they must be single values (or lists of them). An object there —
a class the `ObjectMapper` writes as a JSON object, e.g. `@RequestParam()
Book book` — stops the application at startup; pass its fields as
parameters or a `Map` instead (a value whose type only tells at runtime,
such as `Object`, fails the call with an `EncodeException`).

Every client is checked when it is created: a `{variable}` without a
`@PathVariable` parameter (or the other way round), a method without a
mapping, a synchronous method (other than an event stream), an object as
a parameter value or a header in Feign's syntax stops the application at
startup with the reason, for instance:

```text
Invalid Feign client CatalogClient:
  - CatalogClient.find: the path variable {isbn} of "/books/{isbn}" has no @PathVariable parameter
```

## Server-sent events

A method returning `EventStream<T>` reads a `text/event-stream` response.
`EventStream<T>` **is** a `Stream<T>` of the decoded data, so the type stays
short; the whole events (with `id`, `event`, `retry`) are there through
`.events` when you need them:

```dart
@FeignClient('orders', url: r'${orders.url}')
abstract interface class OrdersClient {
  @GetMapping('/shops/{shop}/orders/events')
  EventStream<OrderEvent> events(@PathVariable() String shop);
}

// the data:
await for (final order in orders.events('neon')) {
  print(order.status);
}

// the whole events:
orders.events('neon').events.listen((e) {
  print('${e.id} ${e.event}: ${e.data.status}');
});
```

- Each event's data is read like a JSON body (through the `ObjectMapper`);
  `EventStream<String>` gives the data as sent. An event that cannot be read
  is an error on the stream (a `DecodeException`), the stream goes on.
- The stream is cold: every listener opens its own connection, cancelling the
  subscription (or `break` in `await for`) closes it.
- `Accept: text/event-stream` and `Cache-Control: no-cache` are sent
  (`produces` changes `Accept`); interceptors run for every connection, so a
  refreshed token is used on reconnect. `read-timeout` covers the wait for
  the response headers only (a stream may stay quiet as long as it likes).
- `Stream<T>` works as a return type too (you get an `EventStream<T>`).
  `Future<EventStream<T>>` is rejected at startup: return the stream
  directly, it connects when listened to.

Reconnection works like the browser's `EventSource`: when the response ends
or the connection breaks, the client connects again after a delay (the
server's `retry:` wins), sending the last event id in `Last-Event-ID`. A
`204 No Content` ends the stream; an error status ends it with the
`FeignException` of the `ErrorDecoder` (a `RetryableException` reconnects).

```properties
spring.cloud.openfeign.client.config.orders.event-stream.reconnect=true
spring.cloud.openfeign.client.config.orders.event-stream.reconnect-delay=3s
spring.cloud.openfeign.client.config.orders.event-stream.max-attempts=10
```

| Property | Meaning |
|---|---|
| `event-stream.reconnect` | connect again after the connection ended or broke (default `true`) |
| `event-stream.reconnect-delay` | the wait before connecting again, until the server sends `retry:` (default `3s`) |
| `event-stream.max-attempts` | connections in a row without an event before the stream gives up (default: no limit) |

With a `fallback`, the fallback's stream takes over when the stream fails
before its first event; later failures reach the listener.

In tests, `MockHttpTransport` answers with events:

```dart
server
  ..when(HttpMethod.get, '/shops/neon/orders/events').respondEvents([
    ServerSentEvent({'id': 1, 'status': 'NEW'}, id: '1'),
  ])
  ..when(HttpMethod.get, '/shops/neon/orders/events').respond(204); // then stop
```

**This differs from Spring.** Spring Cloud OpenFeign cannot stream at all;
Spring's own answer is `Flux<ServerSentEvent<OrderEvent>>` (or
`Flux<OrderEvent>`) from `WebClient` or an `@HttpExchange` interface, with
reconnection left to `retryWhen`. Here `EventStream<T>` folds the event
wrapper into the stream, reconnects by itself, and the `event-stream.*`
properties are additions of this starter.

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
spring.cloud.openfeign.client.config.catalog.default-query-parameters.lang=en
spring.cloud.openfeign.client.config.catalog.follow-redirects=false
spring.cloud.openfeign.client.config.catalog.retryer=catalogRetryer
spring.cloud.openfeign.client.config.catalog.error-decoder=com.example.ShopErrors
spring.cloud.openfeign.client.config.catalog.request-interceptors[0]=requestIds
spring.cloud.openfeign.client.decode-slash=false
```

| Property | Default | Meaning |
|---|---|---|
| `url` | — | base URL when `@FeignClient(url:)` is not given (or empty); `http://` is put in front of one without a scheme |
| `read-timeout` | `60s` | the longest wait for data — for the response, then between two chunks of the body — not a limit for the whole call, like Feign's (`10s`, `PT1M`, milliseconds; `0` for none) |
| `connect-timeout` | `10s` | connection timeout of the default transport (`default` only; `0` for none) |
| `logger-level` | `none` | `none`, `basic`, `headers`, `full` (see Logging) |
| `dismiss404` | `false` | a 404 gives `null` (nullable results) or a `ResponseEntity` instead of an exception; a `void` method still throws, like Feign |
| `default-request-headers.<Name>` | — | a header sent with every request that has none of that name (after the interceptors; `a,b` or a YAML list gives two values) |
| `default-query-parameters.<name>` | — | a query parameter added to every request that has none of that name (after the interceptors; `a,b` or a YAML list gives two) |
| `retryer` | — | the `Retryer` of the client: a bean name, or a class name matching one bean (see Per-client configuration) |
| `error-decoder` | — | the `ErrorDecoder` of the client (bean or class name) |
| `request-interceptors` | — | more `RequestInterceptor`s for the client (a list of bean or class names) |
| `follow-redirects` | `true` | whether redirects are followed |
| `spring.cloud.openfeign.client.decode-slash` | `true` | for all clients: a `/` in a `@PathVariable` value stays a `/` (`false`: `%2F`) |

The on/off properties (`dismiss404`, `follow-redirects`,
`event-stream.reconnect`, `decode-slash`) take `true` / `false` in any case
(also `on` / `off`, `yes` / `no`, `1` / `0`), like Boot's binding; other
values fail naming the key.

`@FeignClient(url:)` wins over the `url` property; `@FeignClient(path:)`
prefixes every path. More attributes, as in Spring Cloud OpenFeign:

| Attribute | Meaning |
|---|---|
| `contextId: 'catalog-admin'` | the configuration key instead of the name (`...config.catalog-admin.*`), e.g. for two clients of one service |
| `qualifiers: ['books']` | more names that select the client bean with `@Qualifier('books')` |
| `primary: false` | the client bean is not `@Primary` (it is by default) |
| `dismiss404: true` | like the `dismiss404` property |
| `configuration: [CatalogFeignConfig]` | configuration classes whose beans apply to this client only (see below) |

### Per-client configuration

Like Spring Cloud OpenFeign, `@FeignClient(configuration:)` lists classes
whose `Retryer`, `ErrorDecoder` and `RequestInterceptor` beans configure
that client only:

```dart
@FeignClient('catalog', url: r'${catalog.url}',
    configuration: [CatalogFeignConfig])
abstract interface class CatalogClient { ... }

@Configuration()
class CatalogFeignConfig {
  @Bean()
  Retryer catalogRetryer() => const DefaultRetryer(maxAttempts: 3);

  @Bean()
  RequestInterceptor catalogAuth() =>
      BasicAuthRequestInterceptor('shop', 's3cret');
}
```

The client's own `Retryer` / `ErrorDecoder` win over the application's;
its interceptors run together with the application's, in `@Order`. Beans
of a configuration class never reach the other clients. The `retryer`,
`error-decoder` and `request-interceptors` properties win over both.

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
responses with a `Retry-After` header (seconds or an HTTP date). Every
attempt is built again from the arguments and goes through the
interceptors, so a refreshed token reaches the retry.

```dart
@Bean()
Retryer retryer() => const DefaultRetryer(maxAttempts: 3);   // 150 ms, 225 ms, ... up to 1 s, like Feign
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

`template.header(name, value)` adds a value, like Feign's; to replace a
header, `removeHeader(name)` first. The interceptors run for every attempt
of a call (retries too) on a new template; the `default-request-headers`,
`default-query-parameters` and the default `Accept` come after them, for
names they did not set. `BasicAuthRequestInterceptor(user, password)` is
built in too (ISO-8859-1 like Feign's; `encoding: utf8` for other
characters).

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

The generated client is `@Primary` (unless `@FeignClient(primary: false)`),
so injecting `MotdApi` gives the client, not the fallback. The fallback answers **every** failure — a 404
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
Failed connections (`<--- ERROR ...`) and retries (`---> RETRYING ...`) are
logged only above `none` too, like Feign.

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
- `Accept: application/json` is sent by default (`text/event-stream` for
  event streams); Spring Cloud OpenFeign sends `Accept` only for `produces`.
- Spaces in query parameters are sent as `+` (form encoding), Feign sends
  `%20`.
- `Authorization` is masked (`***`) in the `headers` and `full` logs.
- The logger is `feign.<Interface>` (`feign.CatalogClient`); Feign's
  `Slf4jLogger` logs under the interface's fully qualified class name.
- Each retry starts from a new template (Feign runs the interceptors again
  on the same one, where header values pile up).
- `@FeignClient(configuration:)` classes are ordinary `@Configuration()`
  beans (Dart cannot create a class by reflection, so they are not kept
  out of the application context as in Spring's child contexts); the
  starter instead keeps their beans away from the other clients, which is
  what Spring does when the class is not component-scanned. Only
  `Retryer`, `ErrorDecoder` and `RequestInterceptor` beans are per client
  (not `Decoder`, `Encoder`, `Contract`, `Client`, `Logger.Level`).
- The `retryer`, `error-decoder` and `request-interceptors` properties
  name beans (by bean name, or by a class name matching exactly one bean);
  Spring creates the class when there is no bean of it.
- `primary` and `qualifiers` are read by the generator; there is no
  `<contextId>FeignClient` alias. A method may have several `Map`
  parameters (Feign: one query map and one header map).
- Server-sent events (`EventStream<T>`, `event-stream.*` properties) are an
  addition: OpenFeign has no streaming.
- Form bodies take the object's properties as the `ObjectMapper` writes
  them (`@JsonProperty` names), not feign-form's `@FormProperty`; a nested
  object in a form fails the call with an `EncodeException`.
- Not yet: multipart bodies, `@SpringQueryMap`, streaming of other
  response bodies (downloads).
