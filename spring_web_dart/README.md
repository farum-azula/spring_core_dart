# spring_web_dart

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Spring's `spring-web` for Dart: the **request mapping annotations**
(`@GetMapping`, `@PostMapping`, `@PathVariable`, `@RequestParam`,
`@RequestHeader`, `@CookieValue`, `@RequestBody`), **HTTP types**
(`ResponseEntity`, `HttpHeaders`, `HttpStatus`, `HttpMethod`, `MediaType`),
**HTTP and
WebSocket client transports** for the VM, Flutter and the web, and
**server-sent events** (`EventStream<T>`). Only `spring_core_dart` as a
dependency.

The annotations are read by Feign clients
([`spring_boot_starter_feign`](https://pub.dev/packages/spring_boot_starter_feign)):
an annotated interface becomes an injectable HTTP client. WebSocket
interfaces (`@WebSocketClient`) come from
[`spring_boot_starter_websocket`](https://pub.dev/packages/spring_boot_starter_websocket).
The coming web server will use the same annotations on controllers.

```yaml
dependencies:
  spring_web_dart: ^0.2.1
```

## Annotations

```dart
@FeignClient('catalog', url: r'${catalog.url}')   // from spring_boot_starter_feign
abstract interface class CatalogClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable('isbn') String isbn);

  @GetMapping('/books')
  Future<List<Book>> search(@RequestParam('q') String query, {@RequestParam() int page = 0});

  @GetMapping.of(path: '/books', headers: ['X-Api-Version=2'])
  Future<List<Book>> filter(@RequestParam() Map<String, Object?> filters);  // ?author=...&year=...

  @PostMapping.of(path: '/books', consumes: MediaType.applicationJson)
  Future<ResponseEntity<Book>> create(
    @RequestBody() Book book,
    @RequestHeader('X-Request-Id') String requestId,
  );

  @GetMapping()                                       // no path: the base path of the client
  Future<List<Book>> all(@RequestParam.of(name: 'sort', defaultValue: 'title') String? sort);

  @DeleteMapping('/books/{isbn}')
  Future<void> delete(@PathVariable() String isbn);   // {isbn}: the parameter name
}
```

| Annotation | On | Meaning |
|---|---|---|
| `@GetMapping([path])`, `@PostMapping`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping` | method | HTTP method and path (`/books/{isbn}`); no path (`@GetMapping()`) maps the base path of the client (or the path of the class) |
| `@GetMapping.of({path, headers, produces, consumes})` (also `@PostMapping.of`, ...) | method | the same with every attribute by name: `headers: ['Name=value']` (Spring's syntax), `produces` (Accept), `consumes` (Content-Type) |
| `@RequestMapping([path])`, `@RequestMapping.of({path, method, headers, produces, consumes})` | method | any method (`method: HttpMethod.head`; `GET` by default) |
| `@PathVariable(['name'])`, `@PathVariable.of({name, required})` | parameter | fills `{name}` of the path (URL-encoded) |
| `@RequestParam(['name'])`, `@RequestParam.of({name, required, defaultValue})` | parameter | a query parameter; `null` is left out, a list repeats it, a `Map` gives one per entry |
| `@RequestHeader(['name'])`, `@RequestHeader.of({name, required, defaultValue})` | parameter | a header; `null` is left out, a list gives several values, a `Map` one header per entry |
| `@CookieValue(['name'])` | parameter | a cookie (`Cookie: name=value; ...`); `null` is left out |
| `@RequestBody({required})` | parameter | the body (JSON) |

Without a name, `@PathVariable()`, `@RequestParam()`, `@RequestHeader()` and
`@CookieValue()` use the parameter name (the generator keeps parameter
names). All mapping annotations implement `Mapping` (`method`, `path`,
`headers`, `produces`, `consumes`; `path` is `''` for none), so code that
reads them can use `annotations.whereType<Mapping>()`.

`required` is `true` by default, as in Spring. A required parameter that is
`null` is an error naming it, a `defaultValue` (a `String`, sent as is)
replaces `null` and implies `required: false`, and a `null` that is not
required is left out. The parameter type counts too, as for Kotlin or
`@Nullable` parameters in Spring: `String? q` is not required whatever
`required` says, and a Dart default value (`{int page = 0}`) is simply the
argument. A path variable is required unless `required: false` (whatever
its type); then `null` gives an empty string.

## HTTP types

| Type | Spring | What |
|---|---|---|
| `ResponseEntity<T>` | `ResponseEntity<T>` | status code, headers and body; `ResponseEntity.ok(body)`, `created(uri).body(x)`, `notFound().build()` |
| `HttpHeaders` | `HttpHeaders` | case-insensitive, several values per name, order and casing kept; `forEach((name, values))`, `toSingleValueMap()`, `contentType`, `accept`, `eTag`, `ifNoneMatch`, `lastModified`, `date`, `contentDisposition`, `location`, `contentLength`, `setBearerAuth`, `setBasicAuth`; name constants `HttpHeaders.contentTypeHeader`, ... |
| `HttpStatus` | `HttpStatus` | every Spring 7 constant (`notFound`, `unprocessableContent`, `contentTooLarge`, ...) as an `int`; `reasonPhrase`, `series`, `is2xxSuccessful`, `is4xxClientError`, `isError`, ...; `valueOf(404)`, `resolve(599)` |
| `HttpStatusCode` | `HttpStatusCode` | any code (`statusCode` of responses): `HttpStatusCode.valueOf(599).is5xxServerError` |
| `HttpStatusSeries` | `HttpStatus.Series` | `informational`, `successful`, `redirection`, `clientError`, `serverError` |
| `HttpMethod` | `HttpMethod` | `get`, `post`, ...; `value` is `GET`, `parse('POST')` |
| `MediaType` | `MediaType` | `applicationJson`, `applicationProblemJson`, ...; `parse`, `includes`, `isCompatibleWith` |

```dart
final headers = HttpHeaders()
  ..contentType = MediaType.applicationJson
  ..setBearerAuth(token);
headers.forEach((name, values) => print('$name: ${values.join(', ')}'));

if (response.statusCode.is2xxSuccessful) { ... }
if (response.statusCode == HttpStatus.notFound) { ... }
HttpStatus.valueOf(503).reasonPhrase;   // 'Service Unavailable'
```

`HttpHeaders`, `HttpStatus`, `HttpRequest` and `HttpResponse` share their
names with `dart:io` classes; in a file that needs both, import `dart:io`
with a prefix (`import 'dart:io' as io;`) or `hide` them.

## HTTP transport

`HttpTransport` sends an `HttpRequest` and returns an `HttpResponse` with
status, headers and body bytes. Every status code is a response; network
failures and timeouts throw `HttpTransportException` (`isTimeout`).

```dart
final transport = platformHttpTransport(connectTimeout: const Duration(seconds: 3));
final response = await transport.send(
  HttpRequest(
    method: HttpMethod.post,
    url: Uri.parse('https://api.neon.books/books'),
    headers: HttpHeaders({HttpHeaders.contentTypeHeader: MediaType.applicationJson}),
    body: utf8.encode('{"isbn":"1"}'),
    readTimeout: const Duration(seconds: 60),   // each wait for data
  ),
);
if (response.statusCode.is2xxSuccessful) print(response.bodyText);
transport.close();
```

Two optional timeouts: `readTimeout` is the longest wait for data — for
the response, then between two chunks of the body (Spring's and Feign's
read timeout); `timeout` is a deadline for the whole exchange. When one
runs out the request is aborted with an `HttpTransportException`
(`isTimeout`). `followRedirects: false` returns a `3xx` response instead of
following it.

| Transport | Platforms | Import |
|---|---|---|
| `platformHttpTransport()` | picks the one below | `package:spring_web_dart/spring_web_dart.dart` |
| `IoHttpTransport` | VM, Flutter Android/iOS/desktop (`dart:io` `HttpClient`) | `package:spring_web_dart/io.dart` |
| `FetchHttpTransport` | web, Flutter web (`fetch` through `dart:js_interop`) | `package:spring_web_dart/browser.dart` |
| `MockHttpTransport` | tests | `package:spring_web_dart/testing.dart` |
| your own | e.g. on Dio or `package:http` | implement `HttpTransport` (`send`, `stream`, `close`) |

`IoHttpTransport` follows redirects as far as `HttpClient` does (`GET` and
`HEAD`, `303` after a `POST`) and aborts the request when a timeout runs
out. `FetchHttpTransport` follows redirects (`followRedirects: false`
gives the browser's opaque redirect, status 0) and aborts through an
`AbortController`; on the web the server must allow the request (CORS) — a
blocked request is an `HttpTransportException`.

### Streaming responses

`transport.stream(request)` returns as soon as the status and headers
arrive; the body comes as byte chunks (`StreamedHttpResponse.body`). The
request's `timeout` and `readTimeout` cover only the wait for the headers.
Cancelling the subscription closes the connection.

```dart
final response = await transport.stream(request);
if (!response.isSuccess) throw StateError((await response.read()).bodyText);
await for (final chunk in response.body) { ... }
```

## Server-sent events

A `text/event-stream` response is a stream of events. The type for it is
`EventStream<T>`: it **is** a `Stream<T>` of the data, so the usual case
needs no wrapper type; the whole events (`ServerSentEvent<T>` with `id`,
`event`, `retry`, `comment`) are there through `.events`.

```dart
@FeignClient('orders', url: r'${orders.url}')
abstract interface class OrdersClient {
  @GetMapping('/orders/events')
  EventStream<OrderEvent> events();
}

await for (final order in orders.events()) {
  print(order.status);
}
orders.events().events.listen((e) => print('${e.id} ${e.event} ${e.data}'));
```

`EventStream` is cold: each listener opens its own connection, cancelling
(or `break` in `await for`) closes it. `EventStream.fromIterable`,
`EventStream.of` and `EventStream.fromEvents` build one for fallbacks and
tests.

Under the Feign method: `connectServerSentEvents` opens the connection and
reconnects like the browser's `EventSource` (`SseReconnect`: after the
delay or the server's `retry:`, sending `Last-Event-ID`; `204 No Content`
stops), and `SseDecoder` parses the body following the HTML specification.
Both work on any `HttpTransport`, Feign or not.

> **Differs from Spring.** Spring has no `EventStream`: `WebClient` and
> `@HttpExchange` interfaces return `Flux<ServerSentEvent<T>>` (or
> `Flux<T>`), and Spring Cloud OpenFeign cannot stream at all. Here the
> event wrapper is folded into the stream type, and reconnection is
> built in (in Spring it is `Flux.retryWhen`).

## WebSocket transport

`WebSocketTransport.connect(url)` opens a `WebSocketSession` (Spring's
name): incoming `messages` (`String` for text frames, `Uint8List` for
binary), `sendMessage`, `acceptedProtocol`, `isOpen`, `close([status])` and
`closeStatus`, with `CloseStatus` and Spring's constants
(`CloseStatus.normal`, `goingAway`, `policyViolation`, ...;
`withReason`, `equalsCode`). The declarative client on top is
`@WebSocketClient` in `spring_boot_starter_websocket`.

```dart
final sockets = platformWebSocketTransport();
final session = await sockets.connect(
  Uri.parse('wss://chat.neon.books/ws'),
  headers: HttpHeaders({'Authorization': 'Bearer $token'}),
  timeout: const Duration(seconds: 5),
);
session.messages.listen(print);
session.sendMessage('{"text":"hi"}');
await session.close();          // CloseStatus.normal; or e.g.
// await session.close(CloseStatus.policyViolation.withReason('no token'));
```

| Transport | Platforms | Import |
|---|---|---|
| `platformWebSocketTransport()` | picks the one below | `package:spring_web_dart/spring_web_dart.dart` |
| `IoWebSocketTransport` | VM, Flutter Android/iOS/desktop (`dart:io` `WebSocket`) | `package:spring_web_dart/io.dart` |
| `BrowserWebSocketTransport` | web, Flutter web (`WebSocket` through `dart:js_interop`) | `package:spring_web_dart/browser.dart` |
| `MockWebSocketTransport` | tests | `package:spring_web_dart/testing.dart` |

Browsers send no custom headers with the WebSocket handshake:
`BrowserWebSocketTransport` fails when `headers` is not empty, so pass a
token as a query parameter or a protocol on the web.

## Testing: `MockHttpTransport`

Prepared answers instead of a server, and a record of what was sent (like
Spring's `MockRestServiceServer`):

```dart
import 'package:spring_web_dart/testing.dart';

final transport = MockHttpTransport();
transport.when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1', 'title': 'Dune'});
transport.when(HttpMethod.get, '/books?q=dune').respond(200, json: []);    // query must match
transport.when(HttpMethod.get, 'https://api.neon.books/stock').respond(503);
transport.when(HttpMethod.get, '/flaky').fail(HttpTransportException('down'));
transport.when(HttpMethod.get, '/flaky').respond(200, body: 'up');          // second call
transport
    .when(HttpMethod.post, '/books')
    .respondWith((request) => HttpResponse(201, body: request.body!, request: request));

// In a Spring Boot test the Feign clients then talk to the mock:
final app = springBootTest(springApplication, overrides: [BeanOverride<HttpTransport>(transport)]);

expect(transport.lastRequest.headers['Accept'], 'application/json');
expect(transport.requests, hasLength(2));
```

Several `when` for the same request answer in order, the last one repeats.
A request nobody expected throws a `StateError` that lists the expected
ones.

Event streams: `respondEvents([...])` answers with a `text/event-stream`
body (data that is not a `String` is written as JSON; `keepOpen: true`
keeps the response open), `respondStream(status, () => chunks)` with any
streamed body.

```dart
transport
  ..when(HttpMethod.get, '/orders/events').respondEvents([
    ServerSentEvent({'id': 1, 'status': 'NEW'}, id: '1'),
  ])
  ..when(HttpMethod.get, '/orders/events').respond(204); // the reconnect stops
```

## Testing: `MockWebSocketTransport`

Plays the server of every connection:

```dart
final sockets = MockWebSocketTransport();
// In a Spring Boot test: withBean<WebSocketTransport>(sockets)

final server = await sockets.nextConnection;   // waits for the client to connect
server.pushJson({'from': 'ann', 'text': 'hi'}); // server → client
expect(server.sentJson, [{'text': 'hello'}]);   // what the client sent
server.drop();                                   // connection lost (1006)
sockets.failNextConnect();                       // the next connect fails
```

## Differences from Spring

- **Mapping `headers`** use Spring's `'Name=value'`. A client sends them;
  entries that are only conditions for a server (`'Name'`, `'!Name'`,
  `'Name!=value'`) are ignored, as Spring Cloud OpenFeign does. Feign's
  `'Name: value'` is rejected at startup.
- **Attributes next to a positional `path` or `name`** are written with the
  `.of` constructor: Dart cannot combine an optional positional parameter
  with named ones, so `@GetMapping('/books', produces: ...)` is
  `@GetMapping.of(path: '/books', produces: ...)` and
  `@RequestParam('page', required: false)` is
  `@RequestParam.of(name: 'page', required: false)`. `@GetMapping()` and
  `@GetMapping('/books')` stay as in Spring. `produces` and `consumes`
  take one media type, not a list.
- **`@CookieValue` has no `required:` / `defaultValue:`**: a `null`
  cookie is left out. `@RequestBody(required:)` exists.
- **`HttpStatus` constants are `int`s** (an extension type), not enum
  values: they compare with status codes directly, `toString()` is the
  number (no `name()`), `100 Continue` is `HttpStatus.continue_` (as in
  `dart:io`), and the deprecated aliases (`PAYLOAD_TOO_LARGE`,
  `UNPROCESSABLE_ENTITY`) are left out. The `statusCode` of responses is an
  `HttpStatusCode` (also an `int`).
- **`HttpHeaders` name constants end in `Header`**
  (`HttpHeaders.contentTypeHeader`, as in `dart:io`), because the typed
  accessors use the plain names (`headers.contentType`); `contentType` is a
  `String`, `accept` a `List<MediaType>`, `lastModified` / `date` are
  `DateTime?` (`null` instead of `-1`) and `contentDisposition` is `null`
  when there is none (Spring: an empty one). `operator []` gives the first
  value, `getAll` all of them, and `toMap()` joins several values with `, `
  (`toSingleValueMap()` keeps the first).
- **`MediaType` constants are `String`s** (Spring's `..._VALUE`
  constants), so they work in annotations; `MediaType.parse` gives a
  `MediaType` object (Spring's `parseMediaType`) with `includes`,
  `isCompatibleWith`, `charset`, `qualityValue`. Parameters follow
  Spring's rules (tokens or quoted values, a parameter without `=`
  ignored, the last of a repeated name kept), but a `charset` only has to
  be a legal name: Dart knows few encodings (UTF-8, ISO-8859-1, US-ASCII),
  so `charset` is `null` for the others instead of an "unsupported
  charset" error, and `HttpResponse.bodyText` falls back to UTF-8.
- **`ResponseEntity` builders** end in `body(...)` or `build<T>()`;
  `ResponseEntity.ok(body)` is a constructor (Spring's `ok()` builder is
  `ResponseEntity.status(HttpStatus.ok)`). `ResponseEntity.of` takes a
  nullable body (Dart has no `Optional`), like `ofNullable`. `==` compares
  lists, sets and maps in the body by content.
- **`HttpHeaders.addAll(name, values)`** adds the values of one name;
  `addHeaders(other)` is Spring's `addAll(HttpHeaders)` and `putAll(other)`
  its `putAll(HttpHeaders)` (Dart has no overloads). `size` counts names.
- **`HttpMethod.parse`** is case-sensitive like Spring's
  `HttpMethod.valueOf`, but throws on any other text, `'get'` included
  (Spring's `valueOf` creates a new method).
- **Timeouts:** an `HttpRequest` has a `readTimeout` (the longest wait for
  data, Spring's read timeout) and a `timeout` (a deadline for the whole
  exchange, which Spring's request factories do not have).
- **`WebSocketSession`** hands out the incoming messages as a `Stream`
  (Spring calls a `WebSocketHandler`), `sendMessage` takes a `String` (text)
  or a `List<int>` (binary) instead of `TextMessage` / `BinaryMessage`, and
  `closeStatus` tells how it closed (Spring passes it to
  `afterConnectionClosed`).
