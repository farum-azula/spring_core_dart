# spring_web_dart

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

The shared web vocabulary of the Spring for Dart packages: the
annotations that describe an HTTP call, the types of HTTP itself
(headers, status codes, media types, response bodies, errors), and
clients that send HTTP and WebSocket requests on the VM, in Flutter and
in the browser.

You describe an HTTP endpoint once, with annotations on a Dart method:

```dart
@GetMapping('/books/{isbn}')
Future<Book> find(@PathVariable() String isbn);
```

Two other packages read the same annotations from opposite sides:

- [`spring_boot_starter_web`](https://pub.dev/packages/spring_boot_starter_web)
  is a web server. On a `@RestController` class, the method above
  answers `GET /books/978-0`.
- [`spring_boot_starter_feign`](https://pub.dev/packages/spring_boot_starter_feign)
  is an HTTP client. On a `@FeignClient` interface, the method above
  sends `GET /books/978-0` and reads the answer into a `Book`.

So most applications never add this package by hand: it comes with
those starters, and with
[`spring_boot_starter_websocket`](https://pub.dev/packages/spring_boot_starter_websocket)
for `@WebSocketClient` interfaces and `@WebSocketEndpoint` classes. Add
it directly when you want only the HTTP and WebSocket clients, or when
you write a library that reads the annotations or works with the server
types. Its only dependency is `spring_core_dart`, and it needs no code
generation by itself.

```yaml
dependencies:
  spring_web_dart: ^0.4.3
```

*In the guides:* [server, 3. Web](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#3-web), [app, 6. Server access](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#6-server-access).

## A first request

With this package alone you can send HTTP requests from any platform.
`platformHttpTransport()` picks `dart:io` on the VM and in mobile or
desktop Flutter, and the browser's `fetch` on the web:

```dart
import 'package:spring_web_dart/spring_web_dart.dart';

Future<void> main() async {
  final transport = platformHttpTransport();
  final response = await transport.send(
    HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('https://api.neon.books/books/978-0'),
      headers: HttpHeaders({HttpHeaders.acceptHeader: MediaType.applicationJson}),
      timeout: const Duration(seconds: 5), // give up on a slow server
    ),
  );
  // Every status is a response; only network failures throw.
  if (response.statusCode.is2xxSuccessful) print(response.bodyText);
  transport.close();
}
```

In an application you rarely build requests yourself: a Feign client
builds them from the annotations below.

## Request mapping annotations

These annotations say which HTTP call a method stands for: the HTTP
method, the path, and where each parameter goes (path, query string,
header, cookie or body). A server uses them to route a request to the
method; a client uses them to build the request.

```dart
// A client for a book catalog (`@FeignClient` comes from
// spring_boot_starter_feign). A @RestController uses the same annotations.
@FeignClient('catalog', url: r'${catalog.url}')
abstract interface class CatalogClient {
  // GET /books/978-0
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable('isbn') String isbn);

  // GET /books?q=dune&page=0: `page` is optional thanks to its default.
  @GetMapping('/books')
  Future<List<Book>> search(@RequestParam('q') String query, {@RequestParam() int page = 0});

  // GET /books?author=...&year=...: one query parameter per map entry.
  // The header is sent with every call.
  @GetMapping.of(path: '/books', headers: ['X-Api-Version=2'])
  Future<List<Book>> filter(@RequestParam() Map<String, Object?> filters);

  // POST /books with the book as JSON, plus a request id for the logs.
  @PostMapping.of(path: '/books', consumes: MediaType.applicationJson)
  Future<ResponseEntity<Book>> create(
    @RequestBody() Book book,
    @RequestHeader('X-Request-Id') String requestId,
  );

  // No path: the client's base path itself (`${catalog.url}`).
  @GetMapping()
  Future<List<Book>> all({@RequestParam('sort') String sort = 'title'});

  // Without a name, {isbn} is bound to the parameter called isbn.
  @DeleteMapping('/books/{isbn}')
  Future<void> delete(@PathVariable() String isbn);
}
```

| Annotation | On | Meaning |
|---|---|---|
| `@GetMapping([path])`, `@PostMapping`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping` | method | The HTTP method and the path (`/books/{isbn}`). Without a path (`@GetMapping()`), the base path: the client's, or the controller class's. |
| `@GetMapping.of({path, headers, produces, consumes})`, also `@PostMapping.of` and the others | method | The same, with every attribute by name. `headers` are `'Name=value'` entries, `produces` is the media type of the answer (`Accept`), `consumes` the media type of the body (`Content-Type`). |
| `@RequestMapping([path])`, `@RequestMapping.of({path, method, headers, produces, consumes})` | method, class | Any HTTP method (`method: HttpMethod.head`; `GET` by default). On a controller class: the path prefix of every method. |
| `@PathVariable([name])` | parameter | Fills `{name}` in the path. A client percent-encodes the value. |
| `@RequestParam([name])` | parameter | A query parameter. A `List` repeats it; a `Map` stands for all query parameters. |
| `@RequestHeader([name])` | parameter | A header. A `List` gives several values; a `Map` stands for all headers. |
| `@CookieValue([name])` | parameter | A cookie, sent in the `Cookie` header (`Cookie: name=value; ...`). |
| `@RequestBody()` | parameter | The body, as JSON for an object. |
| `@RequestPart([name])` | parameter | One part of a `multipart/form-data` body: a file (`MultipartFile`, `List<MultipartFile>`), a text field, or an object sent as a JSON part. |

Without a name, `@PathVariable()`, `@RequestParam()`, `@RequestHeader()`,
`@CookieValue()` and `@RequestPart()` use the parameter's own name (the
generator keeps parameter names).

**Required or optional comes from the Dart parameter.** There is no
`required` or `defaultValue` attribute:

- a nullable parameter (`String? q`) is optional. A client leaves a
  `null` argument out; for a path variable it writes an empty string. A
  server passes `null` when the request has no value;
- a parameter with a default value (`{int page = 0}`) is optional too,
  and the default is used when there is no value;
- any other parameter is required. A server answers 400 when the value
  is missing.

**For code that reads the annotations.** All mapping annotations
implement `Mapping` (`method`, `path`, `headers`, `produces`,
`consumes`; `path` is `''` when there is none), so a library finds any
of them with `annotations.whereType<Mapping>()`. They and
`@ExceptionHandler` carry `@BeanMethodAnnotation()`: the generator then
records the annotated methods (parameters, their annotations, the result
type) in the bean definition, which is where the web server finds them.

Spring (Java), where `required` and `defaultValue` say what the Dart
parameter says:

```java
@GetMapping("/books")
List<Book> search(@RequestParam("q") String query,
    @RequestParam(defaultValue = "0") int page);
```

## Controller annotations

These annotations turn a class into a web controller and decide how its
answers and errors look. The web server
([`spring_boot_starter_web`](https://pub.dev/packages/spring_boot_starter_web))
reads them. They live in this package so that other packages can see
them without depending on the server.

```dart
@RestController()
@RequestMapping('/api/books')
@CrossOrigin(origins: ['https://shop.neon.books']) // the shop's pages may call it
class BookController {
  BookController(this.books);
  final BookService books;

  // POST /api/books answers 201 Created instead of 200.
  @PostMapping()
  @ResponseStatus(HttpStatus.created)
  Future<Book> create(@RequestBody() Book book) => books.create(book);

  // A book that is already there becomes a 409 for every method above.
  @ExceptionHandler()
  ProblemDetail duplicate(DuplicateBookException e) =>
      ProblemDetail.forStatusAndDetail(HttpStatus.conflict, e.message);
}
```

| Annotation | On | Spring | Meaning |
|---|---|---|---|
| `@RestController([name])` | class | `@RestController` | A bean whose mapped methods answer requests; the return value is the response body. |
| `@RequestMapping('/api/books')` | class | the same | The path prefix of every method, and `produces`, `consumes`, `headers` for all of them. |
| `@ResponseStatus(HttpStatus.created, reason: ...)` | method, controller class | the same | The status of a normal answer. With `reason`, the result is ignored and the answer is an error with the reason as its detail. |
| `@ExceptionHandler([types])` | method | the same | Handles exceptions thrown by the controller's methods (by every controller's, in an advice). The exception parameter's type picks them, or `types`, matched by exact runtime type. |
| `@ControllerAdvice([name])`, `@RestControllerAdvice([name])` | class | the same | Exception handlers for every controller, tried in `@Order`. |
| `@CrossOrigin(origins:, originPatterns:, methods:, allowedHeaders:, exposedHeaders:, allowCredentials:, allowPrivateNetwork:, maxAge:)` | class, method | the same | Lets web pages of other origins call the controller (CORS). `maxAge` is in seconds. |

`@CrossOrigin()` with no arguments allows every origin, the method the
handler is mapped to (`DELETE` for a `@DeleteMapping`, `GET` alone for
a `@GetMapping`), every request header, no credentials, and a
pre-flight cache of 30 minutes, as in Spring.

On a server, the mapping's `headers` are conditions the request must
meet: `'Name'` (present), `'!Name'` (absent), `'Name=value'` and
`'Name!=value'`. `produces` and `consumes` take one media type or a
comma-separated list.

## HTTP types

The building blocks of requests and responses, shared by the server,
the clients and tests.

| Type | Spring | What |
|---|---|---|
| `ResponseEntity<T>` | `ResponseEntity<T>` | A status code, headers and a body, for a controller that needs more than a body. `ResponseEntity.ok(body)`, `ResponseEntity.created(uri).body(x)`, `ResponseEntity.notFound().build()`. |
| `HttpHeaders` | `HttpHeaders` | Headers by name, case-insensitive, several values per name, order and casing kept. `forEach((name, values))`, `toSingleValueMap()`; typed accessors `contentType`, `accept`, `eTag`, `ifNoneMatch`, `lastModified`, `date`, `contentDisposition`, `location`, `contentLength`; `setBearerAuth`, `setBasicAuth`; name constants such as `HttpHeaders.contentTypeHeader`. |
| `HttpStatus` | `HttpStatus` | Every Spring 7 status as an `int` constant (`notFound`, `unprocessableContent`, `contentTooLarge`, ...), with `reasonPhrase`, `series`, `is2xxSuccessful`, `is4xxClientError`, `isError`, ...; `valueOf(404)`, `resolve(599)`. |
| `HttpStatusCode` | `HttpStatusCode` | Any status code, also one without a constant: `HttpStatusCode.valueOf(599).is5xxServerError`. The `statusCode` of a response has this type. |
| `HttpStatusSeries` | `HttpStatus.Series` | `informational`, `successful`, `redirection`, `clientError`, `serverError`. |
| `HttpMethod` | `HttpMethod` | `get`, `post`, ...; `value` is the text (`GET`), `parse('POST')` reads it. |
| `MediaType` | `MediaType` | Media type constants as strings (`applicationJson`, `applicationProblemJson`, ...) and `MediaType.parse` for an object with `includes` and `isCompatibleWith`. |

```dart
// Headers of a call to an API that wants a token.
final headers = HttpHeaders()
  ..contentType = MediaType.applicationJson
  ..setBearerAuth(token);
headers.forEach((name, values) => log.debug('$name: ${values.join(', ')}'));

// Status codes are ints, so they compare directly.
if (response.statusCode.is2xxSuccessful) { ... }
if (response.statusCode == HttpStatus.notFound) { ... }
HttpStatus.valueOf(503).reasonPhrase; // 'Service Unavailable'
```

`HttpHeaders`, `HttpStatus`, `HttpRequest` and `HttpResponse` have the
same names as classes of `dart:io`. In a file that needs both, import
`dart:io` with a prefix (`import 'dart:io' as io;`) or `hide` them.

### Errors: `ProblemDetail`

An API error needs a body a client can read. `ProblemDetail` is the
standard one (RFC 9457, `application/problem+json`): a status, a short
title, a detail text, and any extra fields. The web server writes one
for its own errors, and a controller can return or throw one.

| Type | Spring | What |
|---|---|---|
| `ProblemDetail` | `ProblemDetail` | The error body: `type` (`about:blank` by default), `title` (the status's reason phrase by default), `status`, `detail`, `instance`, extra `properties`. `forStatus`, `forStatusAndDetail`, `setProperty`, `toJson`, `fromJson`. |
| `ErrorResponse` | `ErrorResponse` | An exception that knows its answer: `statusCode`, `headers`, `body` (a `ProblemDetail`). |
| `ErrorResponseException` | the same | An `ErrorResponse` to throw or extend: `ErrorResponseException(status, body:, headers:, cause:)`. |
| `ResponseStatusException` | the same | The shortest way to fail with a status: `throw ResponseStatusException(HttpStatus.notFound, 'No book 9')`. |

```dart
// The answer to a request for a book that does not exist.
final problem = ProblemDetail.forStatusAndDetail(HttpStatus.notFound, 'No book 978-0')
  ..setProperty('isbn', '978-0'); // lets the client show which one
problem.toJson();
// {type: about:blank, title: Not Found, status: 404, detail: No book 978-0, isbn: 978-0}
```

### Multipart and files

Uploads travel as `multipart/form-data`: one body made of parts, each a
form field or a file. These types read and write such bodies; the
server and the Feign clients both use them.

| Type | Spring | What |
|---|---|---|
| `MultipartFile` | `MultipartFile` | An uploaded file: `name`, `originalFilename`, `contentType`, `size`, `isEmpty`, `headers`, `bytes`, `openRead()`, `transferTo(path)`. |
| `InMemoryMultipartFile` | `MockMultipartFile` (roughly) | A `MultipartFile` held in memory, such as a file a client sends (`InMemoryMultipartFile.fromString(name, text)`). |
| `MultipartParser` | the parsing of `StandardServletMultipartResolver` | Reads a `multipart/*` body part by part as it arrives: `MultipartParser.boundaryOf(contentType)`, `bind(body)`. |
| `MultipartBody`, `MultipartBodyPart` | `MultipartBodyBuilder` | Writes a `multipart/form-data` body from `MultipartBodyPart.field`, `.file` and `.json` parts; `contentType` (with the boundary), `encode()`. |
| `MediaTypeFactory` | `MediaTypeFactory` | The media type of a file name's extension: `MediaTypeFactory.getMediaType('cover.png')` is `image/png`, `null` when unknown. |

```dart
// Upload a book with its cover through a bare transport.
final body = MultipartBody([
  MultipartBodyPart.field('title', 'Dune'),
  MultipartBodyPart.file('cover', bytes, filename: 'dune.png'), // image/png from the name
]);
await transport.send(HttpRequest(
  method: HttpMethod.post,
  url: Uri.parse('https://api.neon.books/books'),
  headers: HttpHeaders({HttpHeaders.contentTypeHeader: body.contentType}),
  body: body.encode(),
));
```

How a controller receives the parts, the upload limits and file
downloads are described in the web starter's
[Files](../spring_boot_starter_web/README.md#files-uploads-and-downloads)
section. `MockMultipartFile`, in `package:spring_web_dart/testing.dart`,
is the test file for `MockMvc.multipart`.

## HTTP transport

An `HttpTransport` sends one `HttpRequest` and returns an `HttpResponse`
with the status, the headers and the body bytes. It is the layer under
the Feign clients, and you can replace it: a mock in tests, or your own
on top of Dio or `package:http`.

Every status code is a normal response, a 404 or a 500 included. Only
network failures and timeouts throw an `HttpTransportException`
(`isTimeout` tells which).

```dart
final transport = platformHttpTransport(connectTimeout: const Duration(seconds: 3));
final response = await transport.send(
  HttpRequest(
    method: HttpMethod.post,
    url: Uri.parse('https://api.neon.books/books'),
    headers: HttpHeaders({HttpHeaders.contentTypeHeader: MediaType.applicationJson}),
    body: utf8.encode('{"isbn":"1"}'),
    readTimeout: const Duration(seconds: 60), // a slow report: wait longer for data
  ),
);
if (response.statusCode.is2xxSuccessful) log.info(response.bodyText);
transport.close();
```

A request has two optional timeouts. `readTimeout` is the longest wait
for data: first for the response, then between two chunks of the body.
It is the read timeout of Spring and Feign. `timeout` is a deadline for
the whole exchange. When either runs out, the request is aborted with an
`HttpTransportException` whose `isTimeout` is true. With
`followRedirects: false`, a `3xx` response is returned instead of
followed.

| Transport | Platforms | Import |
|---|---|---|
| `platformHttpTransport()` | picks one of the two below | `package:spring_web_dart/spring_web_dart.dart` |
| `IoHttpTransport` | VM, Flutter on Android, iOS and desktop (`dart:io` `HttpClient`) | `package:spring_web_dart/io.dart` |
| `FetchHttpTransport` | web, Flutter web (`fetch` through `dart:js_interop`) | `package:spring_web_dart/browser.dart` |
| `MockHttpTransport` | tests | `package:spring_web_dart/testing.dart`; in an application, from `spring_boot_starter_test` |
| your own | e.g. on Dio or `package:http` | implement `HttpTransport` (`send`, `stream`, `close`) |

`IoHttpTransport` follows redirects as far as `HttpClient` does (`GET`
and `HEAD`, and `303` after a `POST`), and aborts the request when a
timeout runs out. `FetchHttpTransport` follows redirects
(`followRedirects: false` gives the browser's opaque redirect, status 0)
and aborts through an `AbortController`. On the web the server must
allow the request with CORS headers; a blocked request is an
`HttpTransportException`.

### Streaming responses

For a large download or an endless response, `transport.stream(request)`
returns as soon as the status and the headers arrive, and the body
comes as byte chunks (`StreamedHttpResponse.body`). The request's
`timeout` and `readTimeout` cover only the wait for the headers.
Cancelling the subscription closes the connection.

```dart
final response = await transport.stream(request);
// An error answer is short: read it whole for the message.
if (!response.isSuccess) throw StateError((await response.read()).bodyText);
await for (final chunk in response.body) { ... }
```

## Server-sent events

Server-sent events (`text/event-stream`) let a server push a series of
messages over one long HTTP response: notifications, progress, live
prices. The type for such a stream is `EventStream<T>`. It **is** a
`Stream<T>` of the events' data, so the usual case needs no wrapper
type. When the event id or name matters, `.events` gives the whole
events (`ServerSentEvent<T>` with `data`, `id`, `event`, `retry`,
`comment`).

```dart
@FeignClient('orders', url: r'${orders.url}')
abstract interface class OrdersClient {
  @GetMapping('/orders/events')
  EventStream<OrderEvent> events();
}

// Only the data: each event's JSON read as an OrderEvent.
await for (final order in orders.events()) {
  log.info(order.status);
}
// The whole events, when the event name tells the kinds apart.
orders.events().events.listen((e) => log.info('${e.id} ${e.event} ${e.data}'));
```

`EventStream` is cold: nothing happens until someone listens, each
listener opens its own connection, and cancelling (or `break` in
`await for`) closes it. `EventStream.fromIterable`, `EventStream.of` and
`EventStream.fromEvents` build one for fallbacks and tests. A
`@RestController` method can return one too; the web starter then
writes the events as the response.

Under the Feign method, two pieces do the work, and both run on any
`HttpTransport`:

- `connectServerSentEvents` opens the connection and reconnects the way
  a browser's `EventSource` does. `SseReconnect` sets the rules: it
  waits the delay, or the one the server sent in `retry:`, and sends
  `Last-Event-ID` so the server can resume. A `204 No Content` answer
  stops the stream.
- `SseDecoder` parses the body following the HTML specification.

> **Differs from Spring.** Spring has no `EventStream`: `WebClient` and
> `@HttpExchange` interfaces return `Flux<ServerSentEvent<T>>` (or
> `Flux<T>`), and Spring Cloud OpenFeign cannot stream at all. Here the
> event wrapper is folded into the stream type, and reconnection is
> built in (in Spring it is `Flux.retryWhen`).

## WebSocket transport

A WebSocket is a connection that stays open so both sides can send
messages at any time: chat, live updates, games.
`WebSocketTransport.connect(url)` opens one and returns a
`WebSocketSession`:

- `messages`: the incoming messages, a `String` for a text frame and a
  `Uint8List` for a binary one;
- `sendMessage`, `acceptedProtocol`, `isOpen`;
- `close([status])` and `closeStatus`, with `CloseStatus` and its
  constants (`CloseStatus.normal`, `goingAway`, `policyViolation`, ...;
  `withReason`, `equalsCode`).

The declarative client on top of it, an interface with
`@WebSocketClient`, comes from `spring_boot_starter_websocket`.

```dart
final sockets = platformWebSocketTransport();
final session = await sockets.connect(
  Uri.parse('wss://chat.neon.books/ws'),
  headers: HttpHeaders({'Authorization': 'Bearer $token'}), // not on the web, see below
  timeout: const Duration(seconds: 5),
);
session.messages.listen(log.info);
session.sendMessage('{"text":"hi"}');
await session.close(); // CloseStatus.normal; to say why:
// await session.close(CloseStatus.policyViolation.withReason('no token'));
```

| Transport | Platforms | Import |
|---|---|---|
| `platformWebSocketTransport()` | picks one of the two below | `package:spring_web_dart/spring_web_dart.dart` |
| `IoWebSocketTransport` | VM, Flutter on Android, iOS and desktop (`dart:io` `WebSocket`) | `package:spring_web_dart/io.dart` |
| `BrowserWebSocketTransport` | web, Flutter web (`WebSocket` through `dart:js_interop`) | `package:spring_web_dart/browser.dart` |
| `MockWebSocketTransport` | tests | `package:spring_web_dart/testing.dart`; in an application, from `spring_boot_starter_test` |

Browsers send no custom headers with the WebSocket handshake, so
`BrowserWebSocketTransport` fails when `headers` is not empty. On the
web, pass a token as a query parameter or as a protocol instead.

`sendMessage` does not wait: the message waits in memory until the
network takes it. On `dart:io` (`IoWebSocketSession`, on both the client
and the web starter's server) a session gives up when more than 512 KB
wait or what was sent has not left within 10 seconds, as Spring's
`ConcurrentWebSocketSessionDecorator` does: the connection is dropped
and `closeStatus` is 4500 (`CloseStatus.sessionNotReliable`). So a loop
that sends faster than the network takes ends in 4500. Where Spring's
`sendMessage` blocks until the message is out, `await session.flush()`
(`IoWebSocketSession`) waits for it: a sender that awaits it after each
message goes at the network's pace. Set other limits with
`IoWebSocketTransport(sendBufferSizeLimit:, sendTimeLimit:)`.

```dart
// A large export, sent as fast as the server reads it.
final session = await IoWebSocketTransport().connect(url) as IoWebSocketSession;
for (final chunk in export) {
  session.sendMessage(chunk);
  await session.flush(); // fails with a WebSocketException if the connection ends
}
```

The connection goes on being read while messages wait to be sent, so two
sides that both send more than the network holds do not wait for each
other. A connection that breaks (reset by the other side) ends
`messages`, with `closeStatus` 1006 (`CloseStatus.noCloseFrame`) and the
error as the reason; over TLS, where the input often ends before the
write fails, `messages` waits for the write (a second at most). After
`close(status)`, `closeStatus` is that `status` unless the other side
answered with its own close frame. A session listens to its connection
from the start, paused until `messages` is listened to: a session closed
before anyone listened still gives `messages` that end once the close
is done (what arrived in between is dropped).

A message from the server larger than 8 KB (text or binary, Tomcat's
default for Spring's `StandardWebSocketClient`) is not read on `dart:io`:
the session is closed with 1009 (message too big). The text limit counts
UTF-8 bytes, where Tomcat counts characters. Raise the limits with
`IoWebSocketTransport(maxTextMessageSize:, maxBinaryMessageSize:)` or
`platformWebSocketTransport(maxTextMessageSize: ...)` (`-1`: no limit);
the browser has no such limit. In Spring the limits are set in code, on
the client's `WebSocketContainer`. A ping between the fragments of a
message is answered at once (a pong there is taken) and the message
arrives whole, on the client and the web starter's server; until its
final fragment, a message takes the memory of its payload, however many
fragments (empty ones too) it comes in. A plain `dart:io` `WebSocket`
(and an `IoWebSocketSession` made from one) loses the fragments before a
ping or a pong, and sends them back in the answer to a ping. The
handshake fails when the server picks
a subprotocol the client did not offer or any extension (none is
offered, so messages are not compressed), as RFC 6455 asks, and a
redirect is not followed, as in browsers.

## Server side

The interfaces a web server and the application meet on. The web
starter's `dart:io` server and its `MockMvc` both implement them, so
filters, controllers and WebSocket endpoints never see which server is
behind them. You use them when you write a filter or a handler by hand,
or a library that plugs into the server.

| Type | Spring | What |
|---|---|---|
| `ServerHttpRequest` | `ServerHttpRequest` | `method`, `uri`, `path`, `headers`, `queryParameters`, `cookies`, `remoteAddress`, `isSecure`, `attributes`, `principal`; `body` (a stream, read once) with `readBodyBytes`, `readBodyText`, `contentType`; `isWebSocketUpgrade`, `upgradeToWebSocket`. |
| `ServerHttpResponse` | `ServerHttpResponse` | `statusCode` and `headers` (until `isCommitted`), `addCookie(ResponseCookie(...))`, `add`, `write`, `flush`, `addStream`, `close`, `done` (closed, or the client went away); `send(status, text)`. |
| `ServerHttpRequestDecorator`, `ServerHttpResponseDecorator` | the same | Forward everything to a delegate. Extend one and override a single member, for example in a filter that changes the path or the principal. |
| `AllowedOrigins` | `CorsConfiguration`'s origin checks | The browser origins a server allows, checked as Spring checks `allowedOrigins` and `allowedOriginPatterns`: `checkOrigin(origin)` gives the `Access-Control-Allow-Origin` value or `null`. Origins are compared without case, patterns with case; patterns take `*` (`https://*.shop.example`) and a port list at the end (`http://localhost:[3000,3001]`, `[*]`: any port or none); values may list several, separated by commas, and a trailing `/` is ignored. The web starter's CORS and the WebSocket starter's handshake check both use it. A pattern's `*` matches any text, as Spring's `.*` (`*.shop.example` takes any scheme). One difference from Spring: an origin longer than `maxOriginLength` (1024) characters is never allowed. Patterns are matched in time that grows with the origin's length (no backtracking regular expression). |
| `ResponseCookie` | `ResponseCookie` | A `Set-Cookie` value: `maxAge`, `domain`, `path`, `secure`, `httpOnly`, `sameSite`, `partitioned`. |
| `Principal` | `java.security.Principal` | Who sent the request (`name`); set by an authentication filter. |
| `HttpHandler`, `FunctionHttpHandler` | `HttpHandler` | Answers one request. The web starter's dispatcher is one. |
| `HandlerMapping` | `HandlerMapping` | Finds the handler for a request (`getHandler`, or `null`). The web starter asks every `HandlerMapping` bean, in `@Order`. |
| `RequestContextHolder` | `RequestContextHolder` | `currentRequest`: the request being handled, from anywhere in its handling. Each request runs in its own `Zone`. |
| `PathPattern` | `PathPattern` | Path patterns such as `/books/{isbn}`, `{isbn:\d+}`, `{*rest}`, `*`, `?`, `**`: `match(path)?.variables`, `matches`, `combine`; `compareTo` sorts the most specific first. |

```dart
final pattern = PathPattern.parse('/books/{isbn}');
pattern.match('/books/978-0')?.variables; // {isbn: 978-0}
pattern.matches('/books/');               // false: a trailing slash matters, as in Spring 6

// A health check answered before any controller is looked at.
final class HealthMapping implements HandlerMapping {
  @override
  HttpHandler? getHandler(ServerHttpRequest request) => request.path == '/health'
      ? FunctionHttpHandler((request, response) => response.send(200, 'UP'))
      : null;
}
```

For tests, `package:spring_web_dart/testing.dart` has
`MockServerHttpRequest`, `MockServerHttpResponse` (with `bodyText`,
`json`, and `events` and `eventStream` for server-sent events) and
`WebSocketSessionPair` (two sessions connected in memory). An
application gets them, with `MockMvc` on top, from
`spring_boot_starter_test`.

## Testing: `MockHttpTransport`

A fake server for tests of code that calls HTTP services, such as a
Feign client. It answers with responses prepared in advance, without a
network, and records every request so the test can check what was
sent. It plays the role of Spring's `MockRestServiceServer`. In a
Spring Boot application, import it from `spring_boot_starter_test`,
the test dependency the application has anyway.

```dart
import 'package:spring_web_dart/testing.dart';

final transport = MockHttpTransport();
transport.when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1', 'title': 'Dune'});
transport.when(HttpMethod.get, '/books?q=dune').respond(200, json: []); // the query must match
transport.when(HttpMethod.get, 'https://api.neon.books/stock').respond(503);
// A retry test: the first call fails, the second one succeeds.
transport.when(HttpMethod.get, '/flaky').fail(HttpTransportException('down'));
transport.when(HttpMethod.get, '/flaky').respond(200, body: 'up');
// An answer computed from the request: echo the posted book.
transport
    .when(HttpMethod.post, '/books')
    .respondWith((request) => HttpResponse(201, body: request.body!, request: request));

// In a Spring Boot test, the Feign clients then talk to the mock.
final app = springBootTest(springApplication, overrides: [BeanOverride<HttpTransport>(transport)]);

expect(transport.lastRequest.headers['Accept'], 'application/json');
expect(transport.requests, hasLength(2));
```

Several answers for the same request are used in order, and the last
one repeats. A request nobody prepared throws a `StateError` that lists
the prepared ones.

For event streams, `respondEvents([...])` answers with a
`text/event-stream` body. Data that is not a `String` is written as
JSON, and `keepOpen: true` keeps the response open. `respondStream(status,
() => chunks)` answers with any streamed body.

```dart
transport
  ..when(HttpMethod.get, '/orders/events').respondEvents([
    ServerSentEvent({'id': 1, 'status': 'NEW'}, id: '1'),
  ])
  ..when(HttpMethod.get, '/orders/events').respond(204); // the reconnect stops
```

## Testing: `MockWebSocketTransport`

A fake WebSocket server for tests: the test plays the server side of
every connection the client opens.

```dart
final sockets = MockWebSocketTransport();
// In a Spring Boot test: overrides: [BeanOverride<WebSocketTransport>(sockets)]

final server = await sockets.nextConnection;    // waits for the client to connect
server.pushJson({'from': 'ann', 'text': 'hi'}); // server → client
expect(server.sentJson, [{'text': 'hello'}]);   // what the client sent
await server.drop();                            // connection lost (1006)
sockets.failNextConnect();                      // the next connect fails
```

## Differences from Spring

- **Mapping `headers`** use Spring's `'Name=value'` syntax. A client
  sends them; the entries that are only conditions for a server
  (`'Name'`, `'!Name'`, `'Name!=value'`) are ignored, as Spring Cloud
  OpenFeign does. Feign's own `'Name: value'` is rejected at startup.
- **Attributes next to a positional `path`** are written with the `.of`
  constructor. Dart cannot combine an optional positional parameter
  with named ones, so `@GetMapping('/books', produces: ...)` is
  `@GetMapping.of(path: '/books', produces: ...)`. `@GetMapping()` and
  `@GetMapping('/books')` stay as in Spring. `produces` and `consumes`
  are one `String`, comma-separated for several media types, not a list.
- **No `required` or `defaultValue`** on `@RequestParam`,
  `@RequestHeader`, `@PathVariable`, `@RequestPart` and `@RequestBody`:
  the Dart parameter says it. A nullable parameter is optional
  (`required = false`), a default value is the value used when there is
  none (`defaultValue`), any other parameter is required. So
  `@RequestParam(name = "page", defaultValue = "0") int page` is
  `@RequestParam('page') int page = 0`.
- **`HttpStatus` constants are `int`s** (an extension type), not enum
  values. They compare with status codes directly, `toString()` is the
  number (there is no `name()`), `100 Continue` is `HttpStatus.continue_`
  (as in `dart:io`), and the deprecated aliases (`PAYLOAD_TOO_LARGE`,
  `UNPROCESSABLE_ENTITY`) are left out. The `statusCode` of a response
  is an `HttpStatusCode`, also an `int`.
- **`HttpHeaders` name constants end in `Header`**
  (`HttpHeaders.contentTypeHeader`, as in `dart:io`), because the typed
  accessors use the plain names (`headers.contentType`). `contentType`
  is a `String`, `accept` a `List<MediaType>`, `lastModified` and `date`
  are `DateTime?` (`null` where Spring has `-1`), and
  `contentDisposition` is `null` when there is none (Spring: an empty
  one). `operator []` gives the first value and `getAll` all of them;
  `toMap()` joins several values with `, ` while `toSingleValueMap()`
  keeps the first.
- **`MediaType` constants are `String`s** (Spring's `..._VALUE`
  constants), so they work in annotations. `MediaType.parse` gives a
  `MediaType` object (Spring's `parseMediaType`) with `includes`,
  `isCompatibleWith`, `charset` and `qualityValue`. Parameters follow
  Spring's rules: tokens or quoted values, a parameter without `=` is
  ignored, the last of a repeated name is kept. A `charset` only has to
  be a legal name, though: Dart knows few encodings (UTF-8, ISO-8859-1,
  US-ASCII), so `charset` is `null` for the others instead of an
  "unsupported charset" error, and `HttpResponse.bodyText` falls back to
  UTF-8.
- **`ResponseEntity` builders** end in `body(...)` or `build<T>()`.
  `ResponseEntity.ok(body)` is a constructor; Spring's `ok()` builder is
  `ResponseEntity.status(HttpStatus.ok)`. `ResponseEntity.of` takes a
  nullable body, as `ofNullable` does, since Dart has no `Optional`.
  `==` compares lists, sets and maps in the body by content.
- **`HttpHeaders.addAll(name, values)`** adds the values of one name.
  Spring's `addAll(HttpHeaders)` is `addHeaders(other)` and its
  `putAll(HttpHeaders)` is `putAll(other)`, since Dart has no overloads.
  `size` counts names.
- **`HttpMethod.parse`** is case-sensitive like Spring's
  `HttpMethod.valueOf`, but throws on any other text, `'get'` included;
  Spring's `valueOf` creates a new method.
- **Timeouts:** an `HttpRequest` has a `readTimeout` (the longest wait
  for data, Spring's read timeout) and a `timeout` (a deadline for the
  whole exchange, which Spring's request factories do not have).
- **`WebSocketSession`** hands out the incoming messages as a `Stream`,
  where Spring calls a `WebSocketHandler`. `sendMessage` takes a
  `String` (text) or a `List<int>` (binary) instead of a `TextMessage` or
  `BinaryMessage`, and `closeStatus` tells how the session closed, which
  Spring passes to `afterConnectionClosed`. `sendMessage` does not block:
  on `dart:io`, `IoWebSocketSession.flush()` waits until what was sent
  has left. `IoWebSocketTransport` does not follow handshake redirects
  (Tomcat's client follows them; browsers do not).
