# spring_web_dart

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Spring's `spring-web` for Dart: the **request mapping annotations**
(`@GetMapping`, `@PostMapping`, `@PathVariable`, `@RequestParam`,
`@RequestHeader`, `@RequestBody`), **HTTP types** (`ResponseEntity`,
`HttpHeaders`, `HttpStatus`, `HttpMethod`, `MediaType`), **HTTP and
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
  spring_web_dart: ^0.1.0
```

## Annotations

```dart
@FeignClient('catalog', url: r'${catalog.url}')   // from spring_boot_starter_feign
abstract interface class CatalogClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable('isbn') String isbn);

  @GetMapping('/books')
  Future<List<Book>> search(@RequestParam('q') String query, {@RequestParam() int page = 0});

  @PostMapping('/books', consumes: MediaType.applicationJson)
  Future<ResponseEntity<Book>> create(
    @RequestBody() Book book,
    @RequestHeader('X-Request-Id') String requestId,
  );

  @DeleteMapping('/books/{isbn}')
  Future<void> delete(@PathVariable() String isbn);   // {isbn}: the parameter name
}
```

| Annotation | On | Meaning |
|---|---|---|
| `@GetMapping(path)`, `@PostMapping`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping` | method | HTTP method and path (`/books/{isbn}`); options `headers: ['Name: value']`, `produces` (Accept), `consumes` (Content-Type) |
| `@RequestMapping(path, method: HttpMethod.head)` | method | any method |
| `@PathVariable(['name'])` | parameter | fills `{name}` of the path (URL-encoded) |
| `@RequestParam(['name'])` | parameter | a query parameter; `null` is left out, a list repeats it |
| `@RequestHeader(['name'])` | parameter | a header; `null` is left out |
| `@RequestBody()` | parameter | the body (JSON) |

Without a name, `@PathVariable()`, `@RequestParam()` and `@RequestHeader()`
use the parameter name (the generator keeps parameter names). All mapping
annotations implement `Mapping` (`method`, `path`, `headers`, `produces`,
`consumes`), so code that reads them can use
`annotations.whereType<Mapping>()`.

## HTTP types

| Type | Spring | What |
|---|---|---|
| `ResponseEntity<T>` | `ResponseEntity<T>` | status code, headers and body; `ResponseEntity.ok(body)` |
| `HttpHeaders` | `HttpHeaders` | case-insensitive, several values per name, order and casing kept |
| `HttpStatus` | `HttpStatus` | `HttpStatus.notFound` (an `int`), `reasonPhrase(404)`, `isSuccess` / `isClientError` / `isServerError` |
| `HttpMethod` | `HttpMethod` | `get`, `post`, ...; `value` is `GET`, `parse('post')` |
| `MediaType` | `MediaType` | `applicationJson`, `textPlain`, ... |

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
    headers: HttpHeaders({HttpHeaders.contentType: MediaType.applicationJson}),
    body: utf8.encode('{"isbn":"1"}'),
    timeout: const Duration(seconds: 5),   // the whole exchange
  ),
);
if (response.isSuccess) print(response.bodyText);
transport.close();
```

| Transport | Platforms | Import |
|---|---|---|
| `platformHttpTransport()` | picks the one below | `package:spring_web_dart/spring_web_dart.dart` |
| `IoHttpTransport` | VM, Flutter Android/iOS/desktop (`dart:io` `HttpClient`) | `package:spring_web_dart/io.dart` |
| `FetchHttpTransport` | web, Flutter web (`fetch` through `dart:js_interop`) | `package:spring_web_dart/browser.dart` |
| `MockHttpTransport` | tests | `package:spring_web_dart/testing.dart` |
| your own | e.g. on Dio or `package:http` | implement `HttpTransport` (`send`, `stream`, `close`) |

`IoHttpTransport` follows redirects for `GET` and `HEAD` and aborts the
request when its timeout runs out. `FetchHttpTransport` follows redirects
and aborts through an `AbortController`; on the web the server must allow
the request (CORS) — a blocked request is an `HttpTransportException`.

### Streaming responses

`transport.stream(request)` returns as soon as the status and headers
arrive; the body comes as byte chunks (`StreamedHttpResponse.body`). The
request's timeout covers only the wait for the headers. Cancelling the
subscription closes the connection.

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

`WebSocketTransport.connect(url)` opens a `WebSocketConnection`: incoming
`messages` (`String` for text frames, `Uint8List` for binary), `send`,
`close(code, reason)`, `closeCode`. The declarative client on top is
`@WebSocketClient` in `spring_boot_starter_websocket`.

```dart
final sockets = platformWebSocketTransport();
final socket = await sockets.connect(
  Uri.parse('wss://chat.neon.books/ws'),
  headers: HttpHeaders({'Authorization': 'Bearer $token'}),
  timeout: const Duration(seconds: 5),
);
socket.messages.listen(print);
socket.send('{"text":"hi"}');
await socket.close(WebSocketStatus.normalClosure);
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
