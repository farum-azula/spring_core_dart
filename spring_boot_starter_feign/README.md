# spring_boot_starter_feign

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Declarative HTTP clients for
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications. You describe a remote API as an abstract class, one method
per endpoint, and inject it like any other bean. Calling a method sends
the HTTP request and gives you the decoded answer.

Calling another service by hand means building URLs, encoding JSON,
sending the request, checking the status and decoding the answer, for
every endpoint. This starter does that part. The methods use the same
mapping annotations as a controller (`@GetMapping`, `@PathVariable()`,
`@RequestBody()`, ...), and the generator writes the implementation at
build time, without reflection. JSON goes through the `ObjectMapper` of
`spring_core_dart`. Error statuses become exceptions you can catch, and
timeouts, logging, retries, request interceptors and fallbacks are set
per client.

Use it in a server that calls other services, or in a Flutter app that
calls its backend. It is the Dart counterpart of Spring Cloud OpenFeign.

## Install

```yaml
dependencies:
  spring_boot_starter_feign: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2   # required: writes the client implementations
```

```bash
dart run build_runner build
```

There is no `@EnableFeignClients`: listing the starter is enough. Every
abstract class with `@FeignClient` in the scanned package becomes a bean,
named after the interface (`CatalogClient` → `catalogClient`).

One import is enough:
`package:spring_boot_starter_feign/spring_boot_starter_feign.dart`
re-exports `spring_boot_dart`, `spring_web_dart` (the mapping annotations)
and `spring_boot_starter_logging`. The starter is the only dependency an
application needs: it brings the others, logging included, as every
Spring Boot starter does.

## A first client

The shop asks a catalog service for books:

```dart
// The catalog service's API, as the shop calls it.
@FeignClient('catalog', url: r'${catalog.url}')
abstract interface class CatalogClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  // GET /books?q=dune&page=2; page is left out when null.
  @GetMapping('/books')
  Future<List<Book>> search(@RequestParam('q') String query, {@RequestParam() int? page});

  // The book is sent as JSON; the answer gives the status and headers too.
  @PostMapping('/books')
  Future<ResponseEntity<Book>> create(@RequestBody() Book book);

  @DeleteMapping('/books/{isbn}')
  Future<void> delete(@PathVariable() String isbn);
}

@Introspected()                       // read and written as JSON without fromJson / toJson
class Book {
  const Book({required this.isbn, required this.title});
  final String isbn;
  final String title;
}

@Service()
class Shop {
  Shop(this.catalog);                 // the generated client, injected like any bean
  final CatalogClient catalog;

  Future<String> title(String isbn) async => (await catalog.find(isbn)).title;
}
```

```properties
# lib/resources/application.properties
catalog.url=https://api.neon.books
```

Classes that the client methods take or return are introspected for
JSON automatically when they are in the same package as the client.

*In the guides:* [server, 9. Feign](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#9-feign), [app, 6. Server access](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#6-server-access).

## Methods

Each method describes one endpoint. It needs exactly one mapping
annotation, which gives the HTTP method and the path. It must return a
`Future`, because HTTP calls are asynchronous, or an `EventStream<T>` for
server-sent events (see [Server-sent events](#server-sent-events)).

| Annotation | Request |
|---|---|
| `@GetMapping('/books/{isbn}')` | `GET` |
| `@PostMapping('/books')` | `POST` |
| `@PutMapping`, `@PatchMapping`, `@DeleteMapping` | `PUT`, `PATCH`, `DELETE` |
| `@RequestMapping.of(path: '/x', method: HttpMethod.head)` | any method (`GET` by default) |

The method's path is added to the client's `url` and `path`. A mapping
without a path (`@GetMapping()`) calls the client's URL and path
themselves: with `@FeignClient(url: 'https://api.shop.test', path: '/api')`
it calls `https://api.shop.test/api`. A query written in the path
(`@GetMapping('/books?sort=title')`) is sent as written, and the call's
own query parameters are appended to it.

A mapping annotation can also set:

- `headers`: fixed headers sent with every call of the method, written
  as Spring writes them, `Name=value`, with `${...}` placeholders
  resolved from the configuration (`'X-Shop=${shop.name}'`). Spring's
  server-side conditions such as `'!X-Debug'` are ignored. Feign's own
  syntax, `'Name: value'`, stops the application at startup.
- `produces`: the `Accept` header (`application/json` by default).
- `consumes`: the `Content-Type` of the body.

With a path, these are written with the `.of` constructor, because a Dart
constructor cannot have both an optional positional parameter and named
ones: `@GetMapping.of(path: '/books', headers: ['X-Shop=neon'])`.

### Parameters

Each parameter's annotation says where its argument goes in the request:

| Parameter | Goes to |
|---|---|
| `@PathVariable() String isbn` | `{isbn}` in the path, URL-encoded; a `/` in the value stays a `/` (see `decode-slash`). `@PathVariable('id')` for another name |
| `@RequestParam('q') String query` | `?q=...`; `null` is left out, a `List` repeats the parameter |
| `@RequestParam() Map<String, Object?> filters` | one query parameter per entry (`?author=...&year=...`); a `List` value repeats it, `null` is left out |
| `@RequestHeader('X-Trace') String? trace` | a header; `null` is left out, a `List` gives several values |
| `@RequestHeader() Map<String, String> headers` | one header per entry |
| `@CookieValue('SESSION') String session` | a cookie. All cookies of a call go in one `Cookie: a=1; b=2` header; `null` is left out |
| `@RequestBody() Book book` | the body: an object as JSON (through the `ObjectMapper`), a `String` as text, a `Uint8List` as bytes. With `consumes: MediaType.applicationFormUrlencoded` (or that `Content-Type` header), a `Map` or an object is sent as a form (see [Form bodies](#form-bodies)) |
| `@RequestPart('file') MultipartFile file` | one part of a `multipart/form-data` body (see [Files and multipart](#files-and-multipart)) |
| a parameter without annotation | the body (only one such parameter is allowed) |

Whether an argument may be left out follows from the Dart parameter
itself. Java's `required` and `defaultValue` attributes have no
counterpart here:

| Parameter | An argument of `null` |
|---|---|
| nullable (`String? sort`) | the query parameter, header or part is left out; a path variable becomes an empty string |
| with a default value (`{String sort = 'asc'}`) | not possible; without an argument, the default is sent |
| non-nullable | not possible |

Paths, query parameters, headers and cookies take single values (or
lists of them). Enums, `DateTime` and similar values are written as in
JSON: an enum by its name or its `@JsonValue`, a date in ISO-8601. A
parameter whose type is an object, meaning a class the `ObjectMapper`
writes as a JSON object (`@RequestParam() Book book`), stops the
application at startup: pass its fields as separate parameters or as a
`Map` instead. When only the runtime value can tell, as for a parameter of
type `Object`, an object fails the call with an `EncodeException`.

### Results

The return type says how the response is read:

| Return type | From the response |
|---|---|
| `Future<Book>`, `Future<List<Book>>`, `Future<Map<String, int>>` | the JSON body, read through the `ObjectMapper` |
| `Future<Book?>` | `null` for an empty body (or for a 404 with `dismiss404`) |
| `Future<void>` | nothing; the status must be 2xx |
| `Future<String>`, `Future<Uint8List>` | the body as text, or as bytes |
| `Future<ResponseEntity<Book>>` | the status, the headers (read-only) and the body |
| `Future<ResponseEntity<void>>` | the status and headers; the body is ignored |
| `Future<HttpResponse>` | the raw response, whatever its status: no error decoding, no `dismiss404` (Feign's `Response`) |
| `EventStream<OrderEvent>`, `Stream<OrderEvent>` | the events of a `text/event-stream` response (see [Server-sent events](#server-sent-events)) |

A non-nullable result with an empty body, or a body that does not fit
the type, throws a `DecodeException`.

### Form bodies

Some APIs, such as login endpoints, expect an HTML-form body instead of
JSON. With `consumes: MediaType.applicationFormUrlencoded`, the body
parameter is sent as `name=value` pairs: the entries of a `Map`, or the
properties of an object as the `ObjectMapper` writes them. The pairs are
URL-encoded in the `charset` of the content type (UTF-8 by default), a
`List` value repeats the name, and `null` values are left out.

```dart
// The login form of an older service.
@PostMapping.of(path: '/login', consumes: MediaType.applicationFormUrlencoded)
Future<void> login(@RequestBody() Map<String, String> form);
// sends: username=neo&password=s3cr%3Ft
```

This is what Spring Cloud OpenFeign's `SpringFormEncoder` does.

### Checked at startup

Every client is checked when it is created, so a mistake in an interface
shows up when the application starts, not at the first call. The
application stops with the reasons when it finds:

- a `{variable}` in the path without a `@PathVariable` parameter, or the
  other way round;
- a method without a mapping annotation, or with several;
- a method that returns neither a `Future` nor an event stream;
- an object as a path, query, header or cookie value;
- a header written in Feign's `Name: value` syntax;
- a client without a URL.

```text
Invalid Feign client CatalogClient:
  - CatalogClient.find: the path variable {isbn} of "/books/{isbn}" has no @PathVariable parameter
```

## Files and multipart

To upload files, give a method `@RequestPart` parameters: it then sends a
`multipart/form-data` body, one part per parameter. `consumes:
MediaType.multipartFormData` is optional; any other `consumes` stops the
application at startup.

```dart
// Uploads a book's cover with its description.
@PostMapping.of(path: '/books/{isbn}/files', consumes: MediaType.multipartFormData)
Future<UploadResult> upload(
  @PathVariable() String isbn,
  @RequestPart('file') MultipartFile file,   // a file part
  @RequestPart('meta') FileMeta meta,        // an object: a JSON part
  @RequestPart('note') String note,          // a text field
  @RequestParam('draft') bool draft,         // still a query parameter: ?draft=false
);

await books.upload(
  '978-0',
  InMemoryMultipartFile('file', bytes, originalFilename: 'cover.png'),
  FileMeta(title: 'Cover'),
  'first edition',
  false,
);
```

| `@RequestPart('x')` parameter | Part |
|---|---|
| `MultipartFile` | a file. Its `filename` and content type come from the file (else the content type is guessed from the file name, else `application/octet-stream`). The part is named after the annotation, not after `file.name` |
| `List<MultipartFile>` | one file part per file, all named `x` |
| `Uint8List`, `List<int>` | a file part without a file name (`application/octet-stream`) |
| `String`, numbers, `bool`, enums, `DateTime` (or a `List` of them) | a text field (one per item), written as query parameters are |
| an object, a `Map`, a `List` of objects | a JSON part (`application/json`), written with the client's `ObjectMapper` |

`MultipartFile` is the same type controllers receive (from
`spring_web_dart`), so a file a controller received can be passed on as
it is. `InMemoryMultipartFile` builds one from bytes, or from text with
`InMemoryMultipartFile.fromString`. A nullable parameter
(`@RequestPart('note') String? note`) leaves its part out for `null`.

`@RequestParam`, `@RequestHeader` and `@PathVariable` work as on any other
method; `@RequestParam` stays in the query, as in Spring Cloud OpenFeign.
The `Content-Type` is `multipart/form-data; boundary=...` and replaces
`consumes`. A method with both `@RequestPart` and `@RequestBody`, or a
parameter with `@RequestPart` and another annotation, stops the
application at startup.

The body is built in memory once per call, reading each file once, so
retries send the same bytes. There is no streaming upload yet.

## Server-sent events

Some services push updates over a long-lived response in the
`text/event-stream` format: order statuses, prices, progress. A method
that returns `EventStream<T>` reads such a response. `EventStream<T>` is a
`Stream<T>` of the decoded data, so the usual case needs no wrapper type;
the whole events, with their `id`, `event` and `retry` fields, are
available through `.events`.

```dart
@FeignClient('orders', url: r'${orders.url}')
abstract interface class OrdersClient {
  @GetMapping('/shops/{shop}/orders/events')
  EventStream<OrderEvent> events(@PathVariable() String shop);
}

// Only the data:
await for (final order in orders.events('neon')) {
  print(order.status);
}

// The whole events, when the id or event name matters:
orders.events('neon').events.listen((e) {
  print('${e.id} ${e.event}: ${e.data.status}');
});
```

- Each event's data is read like a JSON body, through the `ObjectMapper`.
  `EventStream<String>` gives the data as sent. An event that cannot be
  read arrives as an error on the stream (a `DecodeException`), and the
  stream goes on.
- The stream is cold: each listener opens its own connection. Cancelling
  the subscription (or `break` in `await for`) closes it.
- The request carries `Accept: text/event-stream` (`produces` changes it)
  and `Cache-Control: no-cache`. Interceptors run for every connection,
  so a refreshed token is used when the stream reconnects.
- `read-timeout` covers only the wait for the response headers; after
  that, the stream may stay quiet as long as it likes.
- `Stream<T>` works as a return type too (you get an `EventStream<T>`).
  `Future<EventStream<T>>` is rejected at startup: return the stream
  directly, it connects when someone listens.

The stream reconnects as a browser's `EventSource` does. When the
response ends or the connection breaks, the client connects again after a
delay (a `retry:` field from the server replaces the configured one) and
sends the last event id in `Last-Event-ID`. A `204 No Content` ends the
stream. An error status ends it with the `FeignException` of the
`ErrorDecoder`, unless that exception is a `RetryableException`, which
reconnects.

```properties
spring.cloud.openfeign.client.config.orders.event-stream.reconnect=true
spring.cloud.openfeign.client.config.orders.event-stream.reconnect-delay=3s
spring.cloud.openfeign.client.config.orders.event-stream.max-attempts=10
```

| Property | Meaning |
|---|---|
| `event-stream.reconnect` | connect again after the connection ended or broke (default `true`) |
| `event-stream.reconnect-delay` | the wait before connecting again, until the server sends `retry:` (default `3s`) |
| `event-stream.max-attempts` | how many connections in a row may end without an event before the stream gives up (default: no limit) |

With a `fallback`, the fallback's stream takes over when the stream fails
before its first event. Later failures reach the listener.

In tests, `MockHttpTransport` answers with events:

```dart
server
  ..when(HttpMethod.get, '/shops/neon/orders/events').respondEvents([
    ServerSentEvent({'id': 1, 'status': 'NEW'}, id: '1'),
  ])
  ..when(HttpMethod.get, '/shops/neon/orders/events').respond(204); // the reconnect: stop
```

**This differs from Spring.** Spring Cloud OpenFeign cannot stream at all.
Spring's own answer is `Flux<ServerSentEvent<OrderEvent>>` (or
`Flux<OrderEvent>`) from `WebClient` or an `@HttpExchange` interface, with
reconnection left to `retryWhen`. Here `EventStream<T>` folds the event
wrapper into the stream and reconnects by itself; the `event-stream.*`
properties are additions of this starter.

## Configuration

Each client is configured under its name (`@FeignClient('catalog')`).
The name `default` applies to every client; a client's own setting wins.
The keys are those of Spring Cloud OpenFeign:

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
| `url` | — | the base URL when `@FeignClient(url:)` is not given or is empty. `http://` is put in front of a URL without a scheme |
| `read-timeout` | `60s` | the longest wait for data: for the response, then between two chunks of the body. It is not a limit for the whole call, as in Feign. `10s`, `PT1M` or milliseconds; `0` for none |
| `connect-timeout` | `10s` | the connection timeout of the default transport. Read under `default` only, for all clients; `0` for none |
| `logger-level` | `none` | `none`, `basic`, `headers` or `full` (see [Logging](#logging)) |
| `dismiss404` | `false` | a 404 gives `null` (nullable results) or a `ResponseEntity` instead of an exception; a `void` method still throws, as in Feign |
| `default-request-headers.<Name>` | — | a header added to every request that has none of that name once the interceptors ran. `a,b` or a YAML list gives two values |
| `default-query-parameters.<name>` | — | a query parameter added to every request that has none of that name once the interceptors ran. `a,b` or a YAML list gives two values |
| `retryer` | — | the client's `Retryer`: a bean name, or a class name matching exactly one bean (see [Per-client configuration](#per-client-configuration)) |
| `error-decoder` | — | the client's `ErrorDecoder`, by bean name or class name |
| `request-interceptors` | — | more `RequestInterceptor`s for the client: a list of bean names or class names, those under `default` first |
| `follow-redirects` | `true` | whether redirects are followed; with `false`, a 3xx answer is an error status |
| `spring.cloud.openfeign.client.decode-slash` | `true` | one setting for all clients: a `/` in a `@PathVariable` value stays a `/` (`false`: it is sent as `%2F`) |

The `default-request-headers` and `default-query-parameters` of a client
add to those of `default`, and win for the same name.

The on/off properties (`dismiss404`, `follow-redirects`,
`event-stream.reconnect`, `decode-slash`) take `true` / `false` in any
case, and also `on` / `off`, `yes` / `no`, `1` / `0`, as Spring Boot's
binding does. Another value stops the application with an error naming
the key.

`@FeignClient(url:)` wins over the `url` property, and
`@FeignClient(path:)` is put before every method's path. The annotation
has more attributes, as in Spring Cloud OpenFeign:

| Attribute | Meaning |
|---|---|
| `contextId: 'catalog-admin'` | the configuration key to use instead of the name (`...config.catalog-admin.*`), for example for two clients of one service with different settings |
| `qualifiers: ['books']` | more names that select the client bean with `@Qualifier('books')` |
| `primary: false` | the client bean is not `@Primary` (it is by default) |
| `dismiss404: true` | the same as the `dismiss404` property |
| `configuration: [CatalogFeignConfig]` | configuration classes whose beans apply to this client only (see below) |

### Per-client configuration

Sometimes one service needs other credentials or another retry policy
than the rest. `@FeignClient(configuration:)` lists classes whose
`Retryer`, `ErrorDecoder` and `RequestInterceptor` beans configure that
client only:

```dart
// The catalog needs its own account and a few retries.
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

A listed class must be a `@Configuration()` bean; the application stops
otherwise. Beans of a configuration class never reach the other clients.
For each client the starter picks:

- **Retryer and error decoder**: the `retryer` / `error-decoder`
  property when set; else the bean of the client's configuration classes;
  else the application's bean; else no retries and the
  `DefaultErrorDecoder`. Two candidate beans at one level need one of them
  to be `@Primary`.
- **Interceptors**: the application's `RequestInterceptor` beans and
  those of the client's configuration classes, all together in `@Order`;
  then the beans that the `request-interceptors` property names. The
  property adds to the beans, it does not replace them. A bean that is
  both an interceptor bean and named in the property runs once.

## Errors

A response with a status of 400 or more throws a `FeignException`
subclass, so callers catch exactly the cases they handle:

| Status | Exception |
|---|---|
| 400, 401, 403, 404, 405, 406, 409, 410, 415, 422, 429 | `FeignBadRequest`, `FeignUnauthorized`, `FeignForbidden`, `FeignNotFound`, `FeignMethodNotAllowed`, `FeignNotAcceptable`, `FeignConflict`, `FeignGone`, `FeignUnsupportedMediaType`, `FeignUnprocessableEntity`, `FeignTooManyRequests` (all `FeignClientException`) |
| another 4xx | `FeignClientException` |
| 500, 501, 502, 503, 504 | `FeignInternalServerError`, `FeignNotImplemented`, `FeignBadGateway`, `FeignServiceUnavailable`, `FeignGatewayTimeout` (all `FeignServerException`) |
| another 5xx | `FeignServerException` |
| a response with a `Retry-After` header | `RetryableException` with the response's status |
| no response (connection failed, timeout) | `RetryableException` with status `-1` |
| a body that does not fit the return type | `DecodeException` |
| arguments that cannot be written into the request | `EncodeException`, before anything is sent |

```dart
// A missing book is not an error for the shop; anything else is.
try {
  await catalog.find(isbn);
} on FeignNotFound {
  return null;
} on FeignException catch (error) {
  log.warning('catalog failed: ${error.status} ${error.responseBody}');
  rethrow;
}
```

To throw exceptions of your own domain instead, or to read the error
document a service sends, declare an `ErrorDecoder` bean. It is called for
every status outside 2xx, except a dismissed 404 and methods returning
`HttpResponse`:

```dart
// The catalog's 404 becomes the shop's own exception;
// every other status keeps the default handling.
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

Returning a `RetryableException` from a decoder makes that answer
retryable, for example every 503.

## Retries

A remote service may be briefly out of reach, time out, or ask to be
called later. A `Retryer` bean tries such calls again, so the code around
each call does not have to. As in Spring Cloud OpenFeign, nothing is
retried by default.

Only `RetryableException`s are retried: connection errors, timeouts, and
responses with a `Retry-After` header (in seconds or as an HTTP date). An
error status alone is not retried. Every attempt is built again from the
arguments and goes through the interceptors, so a token refreshed in the
meantime reaches the retry.

```dart
// Up to 3 attempts per call: pauses of 150 ms, then 225 ms.
@Bean()
Retryer retryer() => const DefaultRetryer(maxAttempts: 3);
```

`DefaultRetryer` works as Feign's `Retryer.Default`: by default 5
attempts in all, pauses of `period` × 1.5ⁿ (150 ms, 225 ms, 338 ms, ...
with the default `period` of 100 ms), never longer than `maxPeriod`
(1 second). When the server sent `Retry-After`, it waits until then
instead, still at most `maxPeriod`.

## Interceptors

A `RequestInterceptor` changes every request before it is sent. Use it
for what all calls need and no method should repeat: an authentication
header, a tracing id, a common query parameter. Every `RequestInterceptor`
bean applies to every client, in `@Order`.

```dart
@Configuration()
class FeignSetup {
  // The user's token; the function may be async, and it is asked again
  // at every attempt.
  @Bean()
  RequestInterceptor auth(TokenStore tokens) =>
      BearerTokenRequestInterceptor(() => tokens.accessToken);

  @Bean()
  RequestInterceptor requestIds() => RequestIds();
}

// Every call carries a request id; the catalog also gets the language.
final class RequestIds implements RequestInterceptor {
  @override
  void apply(RequestTemplate template) {
    template.header('X-Request-Id', newId());
    if (template.clientName == 'catalog') template.query('lang', 'en');
  }
}
```

- `template.header(name, value)` adds a value, as Feign's does. To
  replace a header, call `removeHeader(name)` first.
- `apply` may return a `Future`, for example to fetch a fresh token; the
  call waits for it. An exception fails the call.
- The interceptors run for every attempt of a call, retries included, each
  time on a new template. The `default-request-headers`,
  `default-query-parameters` and the default `Accept` header are added
  after them, for names they did not set.
- `BearerTokenRequestInterceptor(token)` sends `Authorization: Bearer ...`
  and adds nothing when `token` returns `null`.
- `BasicAuthRequestInterceptor(user, password)` sends HTTP Basic
  credentials, encoded in ISO-8859-1 as Feign does; pass `encoding: utf8`
  for other characters.

## Fallback

A fallback answers instead of the remote service when a call fails, for
example with cached or placeholder data. It is a bean class that
implements the same interface:

```dart
@FeignClient('motd', url: r'${motd.url}', fallback: OfflineMotd)
abstract interface class MotdApi {
  @GetMapping('/motd')
  Future<String> messageOfTheDay();
}

// What the app shows while the service is unreachable.
@Component()
class OfflineMotd implements MotdApi {
  @override
  Future<String> messageOfTheDay() async => 'offline, try later';
}
```

The fallback answers **every** failure, a 404 too, after the retries. The
generated client is `@Primary` (unless `@FeignClient(primary: false)`), so
injecting `MotdApi` gives the client, not the fallback.

## Logging

To see what a client sends and receives, set its `logger-level` above
`none`. Each call is then logged under the logger `feign.<Interface>` at
debug level, so that level must be on too, for example
`logging.level.feign=debug` with `spring_boot_starter_logging`:

```text
---> GET https://api.neon.books/books/978-0
<--- 200 OK (84 ms)
```

| `logger-level` | Logged |
|---|---|
| `none` | nothing (the default) |
| `basic` | the method and URL of each request, the status and time of each response, failed connections (`<--- ERROR ...`), retries (`---> RETRYING ...`) and event-stream reconnects (`---> RECONNECTING ...`) |
| `headers` | `basic` plus the request and response headers; `Authorization` is masked |
| `full` | `headers` plus the bodies |

As in Feign, failed connections and retries are not logged at `none`.

## Transport

Requests go through the `HttpTransport` bean. By default it is
`platformHttpTransport()` of `spring_web_dart`: `dart:io` on the VM and in
Flutter (mobile, desktop), `fetch` on the web, where the server must allow
your origin with CORS. Declare your own `HttpTransport` bean to send
through something else, such as a small adapter over another HTTP
library, or a mock in tests.

## Testing

In tests, replace the transport with `MockHttpTransport`, which answers
with prepared responses and records what was sent. It comes with
`spring_boot_starter_test`, the tests' dev dependency, and plays the part
of Spring's `MockRestServiceServer`:

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

To test code that uses a client without HTTP at all, replace the whole
client: `BeanOverride<CatalogClient>(FakeCatalog())`.

## How it works

`@FeignClient` is marked `@InterfaceProxy` (from `spring_core_dart`). For
such an interface the generator writes a class whose methods hand each
call, with the method's annotations, parameter names and types, to an
`InvocationHandler`. The starter's `feignClientFactory` bean creates that
handler. The client is a regular bean, so AOP applies to it: for example,
`@Cacheable` on a client method (with `spring_boot_starter_cache`) caches
the responses.

## Differences from Spring Cloud OpenFeign

- No `@EnableFeignClients`: the starter is enough.
- Methods return `Future`s, because HTTP is asynchronous in Dart.
- No service discovery or load balancing: every client needs a URL.
- `connect-timeout` is one setting for all clients (`default`);
  `read-timeout` is per client.
- The fallback answers every failure, without a circuit breaker; there is
  no `FallbackFactory` yet.
- `Accept: application/json` is sent by default (`text/event-stream` for
  event streams); Spring Cloud OpenFeign sends `Accept` only for
  `produces`.
- Spaces in query parameters are sent as `+` (form encoding); Feign sends
  `%20`.
- `Authorization` is masked (`***`) in the `headers` and `full` logs.
- The logger is `feign.<Interface>` (`feign.CatalogClient`); Feign's
  `Slf4jLogger` logs under the interface's fully qualified class name.
- Each retry starts from a new template; Feign runs the interceptors again
  on the same one, where header values pile up.
- `@FeignClient(configuration:)` classes are ordinary `@Configuration()`
  beans. Dart cannot create a class by reflection, so they cannot be kept
  out of the application context as Spring's child contexts do; the
  starter instead keeps their beans away from the other clients, which is
  what Spring does when the class is not component-scanned. Only
  `Retryer`, `ErrorDecoder` and `RequestInterceptor` beans are per client
  (not `Decoder`, `Encoder`, `Contract`, `Client`, `Logger.Level`).
- The `retryer`, `error-decoder` and `request-interceptors` properties
  name beans, by bean name or by a class name matching exactly one bean;
  Spring creates the class when there is no bean of it.
- `primary` and `qualifiers` are read by the generator; there is no
  `<contextId>FeignClient` alias. A method may have several `Map`
  parameters (Feign: one query map and one header map).
- Server-sent events (`EventStream<T>`, `event-stream.*` properties) are
  an addition: OpenFeign has no streaming.
- Form bodies take the object's properties as the `ObjectMapper` writes
  them (`@JsonProperty` names), not feign-form's `@FormProperty`; a nested
  object in a form fails the call with an `EncodeException`.
- Multipart bodies are built in memory (no streaming upload); a list of
  plain values in a `@RequestPart` is sent as one text field per item.
- Not yet: `@SpringQueryMap`, streaming of other response bodies
  (downloads).
