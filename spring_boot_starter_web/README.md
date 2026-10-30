# spring_boot_starter_web

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

A web server for [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications. You write controller classes whose methods carry
annotations such as `@GetMapping('/books/{isbn}')`; the starter routes
each HTTP request to the right method, fills its parameters from the
path, query, headers and body, and turns what it returns into the
response.

It takes care of the work around a REST API that you would otherwise
write by hand:

- JSON in and out, through the `ObjectMapper` of `spring_core_dart`;
- validation of request bodies with `@Valid()`;
- errors as standard `ProblemDetail` JSON bodies;
- server-sent events from a `Stream`;
- file uploads (`multipart/form-data`) and downloads with `Range`
  support;
- filters, interceptors, CORS and sessions.

Use it for a backend in Dart, or for a local server inside a Flutter app
on mobile or desktop (a local API, a companion server). The server is
`dart:io`'s `HttpServer`, behind a factory you can replace. The
generator writes all the routing code at build time: there is no
reflection.

```dart
@RestController()
@RequestMapping('/api/books')
class BookController {
  BookController(this.books);             // injected like any bean
  final BookService books;

  // GET /api/books/978-0 → the book as JSON
  @GetMapping('/{isbn}')
  Future<Book> find(@PathVariable() String isbn) => books.find(isbn);

  // GET /api/books?q=dune&page=2
  @GetMapping()
  Future<List<Book>> search(
    @RequestParam('q') String query, {
    @RequestParam('page') int page = 0,   // missing: the Dart default
  }) => books.search(query, page: page);

  // POST /api/books → 201 Created with a Location header; an invalid body is a 400
  @PostMapping()
  Future<ResponseEntity<Book>> create(@RequestBody() @Valid() NewBook book) async {
    final created = await books.create(book);
    return ResponseEntity.created(Uri.parse('/api/books/${created.isbn}'))
        .body(created);
  }

  // DELETE /api/books/978-0 → 204 No Content
  @DeleteMapping('/{isbn}')
  @ResponseStatus(HttpStatus.noContent)
  void delete(@PathVariable() String isbn) => books.delete(isbn);

  // A browser's EventSource gets every change as it happens.
  @GetMapping('/changes')
  EventStream<Book> changes() => EventStream(
    () => books.changes().map((b) => ServerSentEvent(b, id: b.isbn)),
  );
}

class NewBook {                           // introspected for JSON: the controller uses it
  const NewBook({required this.isbn, required this.title});

  @NotBlank()
  @Size(min: 10, max: 13)
  final String isbn;

  @NotBlank()
  final String title;
}
```

```properties
# lib/resources/application.properties
server.port=8080
```

An error is answered with a `ProblemDetail`, for example when
`books.find` throws a `ResponseStatusException(HttpStatus.notFound, 'No book 123')`:

```text
GET /api/books/123      → 404 application/problem+json
{"type":"about:blank","title":"Not Found","status":404,"detail":"No book 123","instance":"/api/books/123"}
```

Spring (Java):

```java
@RestController
@RequestMapping("/api/books")
class BookController {
  @GetMapping("/{isbn}")
  Book find(@PathVariable String isbn) { ... }

  @PostMapping
  ResponseEntity<Book> create(@RequestBody @Valid NewBook book) { ... }
}
```

*In the guides:* [server, 3. Web](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#3-web).

## Setup

```yaml
dependencies:
  spring_boot_starter_web: ^0.4.3

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3   # required: describes the controllers
  spring_boot_starter_test: ^0.4.3     # MockMvc, springBootTest
  test: ^1.25.0
```

```dart
// bin/main.dart
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
```

```bash
dart run build_runner build
dart run bin/main.dart
# INFO  Web server started on port 8080 (http)
```

Nothing else to switch on (there is no `@EnableWebMvc`): every
`@RestController` in the scanned package is mapped, and the server
starts once the context is ready. One import is enough:
`package:spring_boot_starter_web/spring_boot_starter_web.dart` also
exports `spring_boot_dart`, `spring_web_dart` (the annotations,
`ResponseEntity`, `ProblemDetail`, the server request and response) and
`spring_boot_starter_logging`. As with every Spring Boot starter, it is
the only dependency the application needs.

The classes the controllers take and return are introspected for JSON
automatically when they are in the same package.

**Stopping with `Ctrl+C`.** For `Ctrl+C` or `SIGTERM` to stop the server
gracefully, the application must close its context on those signals:
set `spring.main.register-shutdown-hook=true`. It is `false` by default
here, unlike in Spring Boot; see
[Configuration](../docs/configuration.md#11-reference-the-application).

## Controllers

A controller is a bean whose methods answer HTTP requests.
`@RestController()` declares one; `@RequestMapping('/api/books')` on the
class is the path prefix of every method, and its `produces`, `consumes`
and `headers` apply to all of them. A plain `@Controller()` is mapped
the same way: there are no views, so the return value is always the
response body.

| Annotation | Request |
|---|---|
| `@GetMapping('/{isbn}')` | `GET` |
| `@PostMapping()`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping` | `POST`, `PUT`, `PATCH`, `DELETE`; without a path, the class's path |
| `@RequestMapping.of(path: '/x', method: HttpMethod.head)` | any method |
| `@GetMapping.of(path: '/x', produces: 'text/csv', consumes: ..., headers: ['X-Api=2'])` | the same, with conditions: `produces` must suit the `Accept` header and `consumes` the `Content-Type` (comma-separated media types); `headers` are `Name`, `!Name`, `Name=value`, `Name!=value` |

Paths are path patterns (`PathPattern` of `spring_web_dart`), and
`${...}` placeholders in them are filled from the configuration:

| Pattern | Matches |
|---|---|
| `/books` | the path itself; a trailing slash matters (`/books/` is another path, as in Spring 6) |
| `/books/{isbn}` | one segment, captured as `isbn` (decoded) |
| `/books/{isbn:\d+}` | one segment matching the regular expression |
| `/files/{*path}` | the rest of the path, with its leading `/` |
| `/static/**`, `/b?ok`, `/*.json` | wildcards: any number of segments, one character, part of a segment |

Matrix parameters are left out of the matching, as in Spring:
`/books/1111;v=1` is `/books/1111`. The server answers a path with an
encoded `/`, `\` or NUL (`%2F`, `%5C`, `%00`) with a 400 before any
filter, as Tomcat does, so `..%2F..%2Fsecret` never reaches a path
variable; so is a `.` or `..` segment that matrix parameters hide
(`/files/..;/secret`), and a `%` escape in the path or the query that is
not UTF-8 (`/%FF`, `/%C0%AF`, `?id=%FF`). A raw `\` (not encoded) never
reaches the server: `dart:io` reads it as `/` first (see
[Differences from Spring](#differences-from-spring)).

When several mappings match, the most specific pattern wins
(`/books/new` before `/books/{isbn}`), then the mapping with more
conditions. As in Spring, every `GET` mapping also answers `HEAD` (the
headers and `Content-Length`, no body), and `OPTIONS` is answered with
an `Allow` header.

### Parameters

Each parameter of a controller method says where its value comes from.

| Parameter | Value |
|---|---|
| `@PathVariable() String isbn` | `{isbn}` of the path; `@PathVariable('id')` for another name |
| `@RequestParam('q') String query` | a query parameter, or else a field of a form body (`application/x-www-form-urlencoded`) or a text field of a multipart form. `List<int> ids` takes `?id=1&id=2` or `?id=1,2`; a `Map<String, String>` takes all of them; a `MultipartFile` takes the uploaded file of that name |
| `@RequestHeader('X-Trace') String? trace` | a header; an `HttpHeaders` or `Map` parameter takes all of them |
| `@CookieValue('session') String session` | a cookie |
| `@RequestBody() Book book` | the body: JSON through the `ObjectMapper` (`application/json`, `*+json`). Without a `Content-Type` the body is `application/octet-stream`, as in Spring: a 415 for an object in a `POST`, `PUT` or `PATCH`, a missing body when there is none. Also a `String`, `Uint8List` or `List<int>` (any `Content-Type`), a `Stream<Uint8List>` (unread, for big uploads), or a `Map` from a form (`application/x-www-form-urlencoded`) |
| `@RequestBody() @Valid() NewBook book` | the body, validated (`@Validated([Group])` for groups): a violation is a 400 |
| `@RequestPart('file') MultipartFile file` | a part of a `multipart/form-data` upload: a file, a text field or a JSON part; see [Files](#files-uploads-and-downloads) |
| `ServerHttpRequest`, `ServerHttpResponse` | the request and the response |
| `HttpHeaders`, `HttpMethod`, `Uri` | the request's headers, method and URI |
| `Principal` | the user an authentication filter set (`request.principal`); a non-nullable `Principal` without one is a 401 |
| a simple value or a `MultipartFile` without annotation (`String q`, `int page`) | the query parameter (or uploaded file) of that name, as if it had `@RequestParam` |

Simple values are `String`, `int`, `double`, `num`, `bool` (`true`,
`on`, `yes`, `1`, ...), `BigInt`, `DateTime` (ISO 8601), `Duration`
(`10s`), `Uri`, enums (by name in any case, or by `@JsonValue`), and
lists or sets of them. A text that does not convert is a 400 that names
the parameter.

**Required or optional comes from the Dart parameter**, where Spring has
`required` and `defaultValue`:

| Value missing | Result |
|---|---|
| nullable parameter (`String? q`) | `null` |
| optional named or positional parameter (`{int page = 0}`) | left out of the call: its Dart default applies |
| otherwise | 400 `Required parameter 'q' is not present.` (also for headers and cookies) |

So `@RequestParam(name = "sort", required = false) String sort` is
`@RequestParam('sort') String? sort`, and `@RequestHeader(name =
"X-Lang", defaultValue = "en") String lang` is `@RequestHeader('X-Lang')
String lang = 'en'`.

`@Valid()` uses the application's `Validator` bean. With several
`Validator` beans and none of them `@Primary`, no validator is chosen and
`@Valid()` bodies are not checked, without a warning.

### Results

What a method returns decides the response:

| Return type | Response |
|---|---|
| `void`, `null`, `Future<void>` | the status (200, or `@ResponseStatus`), no body |
| an object, `List`, `Map` | JSON through the `ObjectMapper` (`application/json`, or the mapping's `produces`); 406 when `Accept` excludes it |
| `String` | `text/plain;charset=UTF-8` (or `produces`) |
| `Uint8List` | `application/octet-stream` (or `produces`) |
| `Resource` (`FileSystemResource`, `ByteArrayResource`) | a download: the media type from the file name, `Content-Length`, `Range` and `Last-Modified`; see [Files](#files-uploads-and-downloads) |
| `Stream<Uint8List>`, `Stream<List<int>>` | raw bytes as they come (`application/octet-stream`, or `produces`) |
| `StreamingResponseBody` | bytes the handler writes itself |
| `ResponseEntity<T>` | its status, headers and body (`ResponseEntity.ok(x)`, `.created(uri).body(x)`, `.notFound().build()`); with an `ETag` or `Last-Modified`, conditional `GET`s and `HEAD`s get a 304 (see below) |
| `ProblemDetail`, an `ErrorResponse` | `application/problem+json` with its status |
| `EventStream<T>`, `Stream<T>` (other than bytes) | server-sent events (`text/event-stream`); NDJSON with `produces: 'application/x-ndjson'` |
| `SseEmitter` | server-sent events sent from anywhere |

A `Future` of any of these is awaited. A `Future` of a stream is not
allowed: return the stream itself (the startup check reports it).

`@ResponseStatus(HttpStatus.created)` sets the status of a normal
answer. With a reason, `@ResponseStatus(HttpStatus.gone, reason:
'Retired')`, the result is ignored and the answer is an error with that
detail.

A `ResponseEntity` with a status of 200 and an `ETag` or `Last-Modified`
(`.eTag(book.version)`, `.lastModified(book.updatedAt)`) answers a
browser or cache that revalidates, as Spring's
`HttpEntityMethodProcessor` does, for `GET` and `HEAD`:
`If-None-Match` with its tag (compared weakly: `W/` is ignored; a list,
or several headers) is a 304 without a body, and so is, without
`If-None-Match`, an `If-Modified-Since` at or after `Last-Modified`
(whole seconds); an `If-Unmodified-Since` before it is a 412. The 304
keeps the other headers (`Cache-Control`, `Vary`, the CORS ones). As in
Spring, `If-None-Match: *` is not a match for a `GET`, other methods'
`If-Match` and `If-Unmodified-Since` are not checked (the handler checks
them), and neither are the bodies written as they come (event streams,
`StreamingResponseBody`).

### Checked at startup

Every controller is checked when the context starts, so a mistake shows
up at once instead of on the first request. The application stops with
the whole list when it finds:

- a `{variable}` without a `@PathVariable` parameter, or the other way
  round;
- a parameter nothing can fill, or a `@RequestParam` that is not a
  simple value;
- two `@RequestBody` parameters;
- two methods mapping the same request (method, pattern and conditions);
- an invalid `produces`;
- an `@ExceptionHandler` without an exception;
- a method returning a `Future` of a stream.

```text
Invalid controllers:
  - BookController.find: the path variable {isbn} of "/api/books/{isbn}" has no @PathVariable parameter
  - Ambiguous mapping: OrderController.list and OrderController.all both map GET /api/orders
```

Set `logging.level.spring.web.mvc=debug` to see every mapping
(`Mapped GET /api/books/{isbn} -> BookController.find`).

## Errors: `ProblemDetail`

Errors are answered with a problem (RFC 9457,
`application/problem+json`): a JSON body with the status, a title and a
detail, which clients can read the same way for every error. It is
Spring 6's `ProblemDetail`. Two kinds of answers are plain text instead,
as in Spring: a refused CORS request (a `403` with `Invalid CORS
request`, as Spring's `DefaultCorsProcessor` answers), and a WebSocket
handshake the WebSocket starter refuses (a `403` for an origin or a
`HandshakeInterceptor`, a `400` for a request that asks for no upgrade
or a path variable that does not convert, as Spring's handshake
handler). The server's own checks of a handshake (a repeated or
malformed `Sec-WebSocket-Key`: 400; another `Sec-WebSocket-Version`: 426
with `Sec-WebSocket-Version: 13`) are problems.

| Cause | Status |
|---|---|
| no mapping for the path | 404 |
| the path is mapped, but not for this method | 405 with `Allow` |
| `Content-Type` not in `consumes`, not JSON (or missing) for a `@RequestBody` object, or not a media type at all | 415 with `Accept` |
| nothing in `produces` (or JSON) suits `Accept` | 406 |
| a required value missing, a value that does not convert, an unreadable body, a form with a `%` escape that is malformed or not UTF-8, unmet `headers` conditions | 400 |
| a request body that sends nothing for `server.connection-timeout` (60 s) | 408 |
| `@Valid` violations | 400 with `errors`: `[{"field": "isbn", "message": "...", "rejectedValue": ""}]` (messages from the `MessageSource`) |
| a body above `server.max-http-request-body-size` | 413 |
| an upload above `spring.servlet.multipart.max-file-size` or `max-request-size`, or with more than `max-part-count` parts | 413 (`MaxUploadSizeExceededException`) |
| a malformed multipart request, or `@RequestPart` on a request that is not multipart | 400 (`MultipartRequestException`) |
| `throw ResponseStatusException(HttpStatus.notFound, 'No book 9')` | its status and detail |
| an `ErrorResponse` or `ErrorResponseException` | its status, headers and problem |
| any other exception | 500 `Internal Server Error`, with no detail; the exception is logged with its stack trace under `spring.web.mvc` |
| answered by the server before any filter: a method `HttpMethod` does not know, a missing client certificate (`server.ssl.client-auth=need`), a malformed or missing `Host` (or one that is not the host of an absolute target), an encoded `/`, `\` or NUL in the path, a `.` or `..` segment behind matrix parameters, a `%` escape that is not UTF-8 | 501, 403, 400, 400, 400, 400 |
| a handler fails after the response was committed | no error answer can follow: the connection is dropped without finishing the response, as Tomcat does |

A 5xx answer that an exception asks for (a `ResponseStatusException`,
the 503 of a refused session) is logged as a warning without a stack
trace, at most once every 10 seconds for the same kind; only unexpected
exceptions are logged as errors.

To answer an exception your own way, write an `@ExceptionHandler`
method. On a controller it handles the errors of that controller's
methods; on a `@ControllerAdvice` or `@RestControllerAdvice` bean it
handles them for every controller. The method takes the exception, and
optionally the `ServerHttpRequest`, `ServerHttpResponse` or
`HttpHeaders`, and returns whatever a handler may return:

```dart
@RestControllerAdvice()
class ApiErrors {
  // The parameter's type picks the exceptions; the isbn helps the client.
  @ExceptionHandler()
  @ResponseStatus(HttpStatus.notFound)
  ProblemDetail notFound(BookNotFoundException e) =>
      ProblemDetail.forStatusAndDetail(HttpStatus.notFound, 'No book ${e.isbn}')
        ..setProperty('isbn', e.isbn);

  // A ResponseEntity when the answer needs its own headers or status.
  @ExceptionHandler()
  ResponseEntity<ProblemDetail> conflict(StateError e) =>
      ResponseEntity.status(HttpStatus.conflict)
          .body(ProblemDetail.forStatusAndDetail(HttpStatus.conflict, e.message));

  // Listed types match by exact runtime type; nothing to say but the status.
  @ExceptionHandler([TimeoutException])
  @ResponseStatus(HttpStatus.gatewayTimeout)
  void timeout() {}
}
```

A controller's own handlers come first. Then the advice beans are
tried in `@Order`, as in Spring: the first bean that has a handler for
the error answers it, even when a later bean has a more specific one.
Within one controller or bean, the handler for the most specific type
wins: an exact type listed in `@ExceptionHandler([...])` first, then the
parameter type that is a subtype of the others. Advice handlers also see
the 404, 405, 406 and 415 errors of the lookup and the errors of other
handler mappings (WebSocket handshakes). An exception thrown by a filter
skips them and gets the default answer.

An advice applies to every controller unless `@ControllerAdvice.of` (or
`@RestControllerAdvice.of`) narrows it, as Spring's attributes do: to
the controllers of some libraries (`basePackages`, prefixes of library
URIs instead of Java packages), of some types (`assignableTypes`, their
subtypes too) or carrying some annotation (`annotations`). A narrowed
advice does not see errors raised before a controller method was chosen
(a 404, a 405).

```dart
// Only the admin controllers answer validation errors this way.
@RestControllerAdvice.of(basePackages: ['package:shop/admin/'])
@Order(1)
class AdminErrors { ... }
```

## Server-sent events

Server-sent events let the server push a series of messages over one
long response, which a browser reads with `EventSource`: notifications,
progress, live data. Return an `EventStream<T>`, or any `Stream<T>`
that is not a byte stream (see [Files](#files-uploads-and-downloads)).
Each item is one event, its data written as JSON (a `String` as it is).
`ServerSentEvent<T>` items keep their `id`, `event`, `retry` and
`comment`. The stream is listened to when the response starts and
cancelled when the client goes away. It is paused while an event is
being written, so a client that reads slowly slows the stream down
instead of filling the server's memory. A `ResponseEntity` of an
`EventStream`, a `Stream` or an `SseEmitter` writes the same events
with its own status and headers.

```dart
// Every change, with the isbn as the event id.
@GetMapping('/changes')
EventStream<Book> changes() => EventStream(
  () => books.changes().map((book) => ServerSentEvent(book, id: book.isbn)),
);

// A reconnecting EventSource sends the last id it saw: resume from there.
@GetMapping('/resume')
Stream<Book> resume(@RequestHeader('Last-Event-ID') String? lastId) =>
    books.changesAfter(lastId);

// One JSON object per line instead of events.
@GetMapping.of(path: '/export', produces: 'application/x-ndjson')
Stream<Book> export() => books.all();
```

Any method may answer with a stream, `POST` included, as MCP's
Streamable HTTP does.

**`SseEmitter`** is for events that come from elsewhere, later: a
service or an event listener. The controller method creates and returns
the emitter, the application keeps it, and other code calls `send`.
Events sent before the response is ready are buffered.

```dart
@GetMapping('/notifications')
SseEmitter subscribe() {
  final emitter = SseEmitter(timeout: const Duration(minutes: 30));
  notifications.add(emitter);
  // Forget the emitter once the client is gone or it timed out.
  emitter.onCompletion(() => notifications.remove(emitter));
  return emitter;
}

// Elsewhere, when an order is placed:
for (final emitter in notifications) {
  emitter.send(ServerSentEvent(order, event: 'order', id: order.id));
}
```

An emitter has `send`, `complete()`, `completeWithError(e)`,
`onCompletion`, `onTimeout`, `onError` and `isComplete`. Sending after
the client went away throws a `StateError`. Await `send` to go at the
client's pace; when sends are not awaited and 1000 events wait for a
client that reads nothing, `send` fails with a `StateError` and the
emitter ends. Without its own timeout, an emitter ends after
`spring.mvc.async.request-timeout`, or never when that is not set (in
Spring on Tomcat, the container's 30 seconds apply).

Proxies often close connections that stay quiet.
`spring.mvc.sse.heartbeat-interval=15s` writes a comment line at that
interval to keep idle streams open (a property of this starter, not of
Spring Boot).

`dart:io` sends the response headers only with the first bytes of the
body. So that the client sees the response before the first event,
every `text/event-stream` response starts with an empty comment line
(`:`), which clients ignore. When the server stops, open streams are
closed.

## Files: uploads and downloads

### Uploads: `multipart/form-data`

A browser form with `enctype="multipart/form-data"`, `curl -F` or a
Feign client sends files as a multipart request. The starter reads it
once per request and binds its parts to the handler's parameters:

```dart
@PostMapping.of(path: '/api/books', consumes: MediaType.multipartFormData)
Future<Book> create(
  @RequestPart('book') @Valid() NewBook book,          // a JSON part, validated
  @RequestPart('cover') MultipartFile cover,           // a file
  @RequestParam('note') String note, {                 // a text field
  @RequestPart('pages') List<MultipartFile>? pages,     // optional
}) async {
  final created = await books.create(book, note: note);
  // Keep the cover: temporary files are deleted when the request ends.
  await cover.transferTo('/var/shop/covers/${created.isbn}.png');
  return created;
}
```

| Parameter | Value |
|---|---|
| `@RequestPart('file') MultipartFile file` | the file of that part (the first one if there are several) |
| `@RequestPart('files') List<MultipartFile> files` | every file of that name. When there is none: a 400 if required, `null` if nullable, an empty list for a non-nullable optional parameter |
| `@RequestPart('note') String note`, `int`, ... | a text field, converted like a request parameter (or the text of a file part) |
| `@RequestPart('data') Uint8List data` | the raw bytes of the part (`List<int>` too) |
| `@RequestPart('book') @Valid() NewBook book` | a part read as JSON into the type through the `ObjectMapper`, validated with `@Valid` |
| `@RequestPart('cover') MultipartFile? cover` | optional: `null` when there is none |
| `@RequestParam('file') MultipartFile file` | the same as `@RequestPart`, for files |
| `@RequestParam('note') String note` | a text field of the form (the query string is looked at first) |
| `MultipartFile file` without annotation | the file named like the parameter |

A missing required part is a 400 `Required part 'cover' is not
present.`, and `@RequestPart` on a request that is not multipart is a
400.

`MultipartFile` (from `spring_web_dart`) has `name`, `originalFilename`,
`contentType`, `size`, `isEmpty`, `headers`, `bytes` (a `Future`),
`openRead()` (a stream, without loading the file) and
`transferTo(path)`, which moves the temporary file to `path` (or copies
it when it cannot be moved). After `transferTo`, the file can no longer
be read or moved again.

**Limits and temporary files** use Spring Boot's
[`spring.servlet.multipart.*`](../docs/configuration.md#18-reference-web-server)
keys:

```properties
spring.servlet.multipart.max-file-size=5MB        # one file (or part); 1MB by default, -1: no limit
spring.servlet.multipart.max-request-size=20MB    # the whole request; 10MB by default, -1: no limit
spring.servlet.multipart.max-part-count=100       # files and fields together; 50 by default, -1: no limit
spring.servlet.multipart.file-size-threshold=64KB # smaller files stay in memory; 0B by default: all go to disk
spring.servlet.multipart.location=/var/tmp/shop   # a private directory is made in it; the system's temporary directory by default
spring.servlet.multipart.enabled=false            # don't parse multipart requests
```

- Above a limit, the upload is a 413 (`MaxUploadSizeExceededException`)
  and reading stops there. The resolver reads uploads with
  `max-request-size` instead of `server.max-http-request-body-size`;
  anything else that reads a multipart body (a `@RequestBody() String`)
  keeps the server's limit. `max-part-count` is this starter's own key:
  Spring Boot sets the same limit on Tomcat with
  `server.tomcat.max-part-count` (50).
- Files are streamed to temporary files as they arrive, so a whole
  upload is never held in memory. They are **deleted when the request
  ends**, whatever the handler did: keep a file with `transferTo` or by
  copying `openRead()`. An upload that fails on the way (a limit, a
  broken body, a client that goes away) leaves nothing behind either.
  The files are in a directory of the process that only its user can
  open (`0700`), with random names. Without `dart:io` (on the web),
  files stay in memory.

To send files from a client, see the Feign starter's
[Files and multipart](../spring_boot_starter_feign/README.md#files-and-multipart).

### Downloads: `Resource`

To serve a file, return a `Resource` from `spring_core_dart`
(`FileSystemResource`, `ByteArrayResource`). The starter streams it and
answers the HTTP caching and range headers for you:

```dart
// A cover image from disk. The pattern lets only digits into the file
// name: a path variable is decoded, so never put it into a path as it is.
@GetMapping(r'/api/books/{isbn:\d+}/cover')
Resource cover(@PathVariable() String isbn) =>
    FileSystemResource('/var/shop/covers/$isbn.png');

// A generated report the browser saves as report.csv.
@GetMapping('/api/report')
ResponseEntity<Resource> report() => ResponseEntity.status(HttpStatus.ok)
    .contentType('text/csv')
    .header('Content-Disposition', ['${ContentDisposition.attachment(filename: 'report.csv')}'])
    .body<Resource>(ByteArrayResource(utf8.encode(reports.csv())));
```

- **Headers:** `Content-Type` from the file name (`MediaTypeFactory`;
  `application/octet-stream` when unknown) unless the `ResponseEntity`
  sets one, `Content-Length`, and `Accept-Ranges: bytes`. A
  `ResponseEntity<Resource>` keeps its status and headers, such as a
  `Content-Disposition` that names the download.
- **A file is streamed** from disk (`FileSystemResource.openRead(start,
  end)`), never read whole. A resource that does not exist is a 404.
- **`Last-Modified`** (files): a `GET` or `HEAD` with an
  `If-Modified-Since` at or after it is a 304 without a body.
- **`Range`:** one range (`bytes=0-99`, `bytes=500-`, `bytes=-100`) is a
  206 with `Content-Range`; a range past the end is a 416
  (`Content-Range: bytes */length`). Several ranges or a malformed
  header get the whole content (200), as RFC 9110 allows. `If-Range`
  with a date applies the range only if the file has that
  `Last-Modified`.
- `HEAD` answers the same headers without the body.
- **A path variable in a file name:** the server refuses an encoded
  `/`, `\` or NUL in the path and `.` / `..` segments (`MockMvc` does
  not), but a variable can still hold characters a file name should
  not; restrict it with a pattern (`{isbn:\d+}`) or check it before
  building the path.

### Byte streams and `StreamingResponseBody`

A handler **declared** to return `Stream<Uint8List>` or
`Stream<List<int>>` writes the chunks as raw bytes, as they come
(`application/octet-stream`, or the mapping's `produces`). Any other
`Stream<T>` is still server-sent events. For a body produced on the
fly, return a `StreamingResponseBody`: the handler writes to a
`ResponseBodySink` (`add(bytes)`, `write(text)`, `flush()`,
`addStream(stream)`):

```dart
// A CSV export written row by row, never held whole in memory.
@GetMapping.of(path: '/api/books.csv', produces: 'text/csv')
StreamingResponseBody export() => StreamingResponseBody((out) async {
  await for (final book in books.all()) {
    out.write('${book.isbn},${book.title}\n');
    await out.flush();
  }
});

@GetMapping('/api/backup')
Stream<Uint8List> backup() => storage.openBackup();   // bytes, not events
```

Both can be the body of a `ResponseEntity`, for example to add a
`Content-Disposition`.

### Testing uploads and downloads

```dart
await app.mockMvc.multipart('/api/books', files: [
  MockMultipartFile('cover', 'dune.png', 'image/png', pngBytes),
  MockMultipartFile('book', null, 'application/json', utf8.encode('{"isbn": "9780441013593", "title": "Dune"}')),
], params: {'note': 'first edition'}).andExpect(status: 200);

final result = await app.mockMvc
    .get('/api/books/9780441013593/cover', headers: {'Range': 'bytes=0-99'})
    .andExpect(status: 206, headers: {'Content-Range': 'bytes 0-99/48213'})
    .andReturn();
expect(result.response.bodyBytes, hasLength(100));
```

A `MockMultipartFile` without a file name is a plain part; with
`application/json` it is a JSON part for `@RequestPart`. More in
[docs/testing.md](../docs/testing.md#files-uploads-and-downloads).

## Sessions: `HttpSession`

HTTP forgets everything between two requests. A session remembers data
for one client across requests, such as a shopping cart or the
logged-in user: the data stays on the server, and the client only holds
a random id in a cookie (`JSESSIONID` by default) that it sends back.
Browsers need this; APIs called by programs usually send a token
instead and never create a session. The security starter keeps the
logged-in user in one.

Code that has the request gets the session with `request.getSession()`.
The first call creates the session and sends its cookie;
`getSession(create: false)` only looks and returns `null` when there is
none.

```dart
// Each visitor has a cart that lives as long as the session.
@PostMapping('/cart')
void add(ServerHttpRequest request, @RequestParam() String item) {
  final session = request.getSession()!;
  final cart = session.getAttribute('cart') as List<String>? ?? [];
  session.setAttribute('cart', [...cart, item]);
}
```

A session has `id`, `creationTime`, `lastAccessedTime`,
`maxInactiveInterval`, `isNew`, `getAttribute`, `setAttribute`
(`null` removes), `removeAttribute`, `attributeNames`, `invalidate()`
(as a logout does) and `isInvalidated`. After a login, call
`await request.changeSessionId()`: the session keeps its data under a
new id, so an id someone saw before the login stops working. The
client never chooses an id: an unknown id from a cookie is ignored.

```properties
server.servlet.session.timeout=15m              # without a request; 30m by default, seconds without a unit
server.servlet.session.cookie.name=SHOPSESSION  # JSESSIONID by default
server.servlet.session.cookie.same-site=strict  # lax by default; strict, none, or unset
server.servlet.session.max-sessions=50000       # 10000 by default; -1: no limit
```

| Property | Default |
|---|---|
| `server.servlet.session.timeout` | `30m` |
| `server.servlet.session.cookie.name` | `JSESSIONID` |
| `server.servlet.session.cookie.path` | the context path, or `/` |
| `server.servlet.session.cookie.domain` | none |
| `server.servlet.session.cookie.http-only` | `true` |
| `server.servlet.session.cookie.secure` | secure when the request came over HTTPS |
| `server.servlet.session.cookie.same-site` | `lax` |
| `server.servlet.session.max-sessions` | `10000` (`-1`: no limit) |

Anyone can open a session with a request, so their number is limited
(`max-sessions`). At the limit, a new session takes the place of an
expired one, then of the oldest one its client never came back with,
then of the least recently used one without a login. When only
sessions that hold a login are left (the security starter's
`SPRING_SECURITY_CONTEXT`), it takes the place of the least recently
used login of the user who holds the most sessions, if that user holds
two or more: one account logging in again and again cannot lock the
others out, and nobody loses their last session. Users are told apart
by `InMemoryHttpSessionRepository.principalKeyAttribute` when set
(the security starter sets it to the user's name with the login's
source, so that the same name from two login sources counts as two
users), else by the name in
`InMemoryHttpSessionRepository.principalNameAttribute` (Spring Session's
`PRINCIPAL_NAME_INDEX_NAME`), which the security starter sets at each
login too. When every login left belongs to another user, the new
session is refused with a `TooManyActiveSessionsException`, a `503`, as
Tomcat refuses sessions above its `maxActiveSessions`.

Sessions live in memory by default (`InMemoryHttpSessionRepository`):
they are lost when the process stops and are not shared between
several instances of the application. To keep them in a database or
Redis, declare your own `HttpSessionRepository` bean; the in-memory one
then backs off. When a repository answers with `Future`s, use
`request.getSessionAsync()`.

Spring (Java), where the session can also be a handler parameter:

```java
@PostMapping("/cart")
void add(HttpSession session, @RequestParam String item) {
  List<String> cart = (List<String>) session.getAttribute("cart");
  ...
  session.setAttribute("cart", cart);
}
```

Spring Boot leaves `SameSite` unset and has no session limit of its
own (Tomcat's `maxActiveSessions`, unlimited by default, refuses every
new session above it). Here the cookie is `SameSite=Lax`, and the
number of sessions is limited so clients cannot fill the memory by
opening sessions; at the limit a session without a login makes room
(with a warning, at most once a minute), as described above.

## Filters

A filter runs around every request, before the controller is even
looked up: request ids, logging, authentication. Declare a `WebFilter`
bean; filters run in `@Order`. The security starter's filter chain is
one of them. `OncePerRequestFilter` adds `shouldNotFilter` to skip some
requests:

```dart
// Every answer carries an id the logs can be searched by.
@Component()
@Order(Ordered.highestPrecedence)
class RequestIdFilter extends OncePerRequestFilter {
  @override
  bool shouldNotFilter(ServerHttpRequest request) => request.path == '/health';

  @override
  Future<void> doFilterInternal(request, response, chain) {
    response.headers.set('X-Request-Id', newId());
    return chain.doFilter(request, response);
  }
}
```

A filter can answer itself by not calling the chain, or pass a wrapped
request or response on: `ServerHttpRequestDecorator` and
`ServerHttpResponseDecorator` forward everything and let you override
one member (the path, the headers, the principal).

Every request runs in its own `Zone`, so
`RequestContextHolder.currentRequest` is the request anywhere in its
handling, across `await`s.

## Interceptors and argument resolvers: `WebMvcConfigurer`

A bean that mixes in `WebMvcConfigurer` customizes how controllers are
called:

- **interceptors** run before and after the controller method, and know
  which method it is (unlike a filter);
- **CORS mappings** set CORS rules for path patterns (see [CORS](#cors));
- **argument resolvers** fill parameters of your own types.

```dart
@Configuration()
class WebConfig with WebMvcConfigurer {
  @override
  void addInterceptors(InterceptorRegistry registry) => registry
      .addInterceptor(TimingInterceptor())
      .addPathPatterns(['/api/**'])
      .excludePathPatterns(['/api/health']);

  @override
  void addCorsMappings(CorsRegistry registry) => registry
      .addMapping('/api/**')
      .allowedOrigins(['https://shop.example'])
      .allowedMethods(['GET', 'POST']);

  @override
  void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) =>
      resolvers.add(TenantResolver());
}

// Logs how long each controller method took.
final class TimingInterceptor with HandlerInterceptor {
  @override
  bool preHandle(request, response, handler) {   // false: the interceptor answered
    request.attributes['start'] = DateTime.now();
    return true;
  }

  @override
  void afterCompletion(request, response, handler, error) =>
      log.info('${handler.description} took '
          '${DateTime.now().difference(request.attributes['start'] as DateTime)}');
}

// A `Tenant tenant` parameter gets the tenant of the X-Tenant header.
final class TenantResolver implements HandlerMethodArgumentResolver {
  @override
  bool supportsParameter(MethodParameter parameter) => parameter.type.type == Tenant;

  @override
  Object? resolveArgument(parameter, request, response) =>
      Tenant(request.headers['X-Tenant'] ?? 'default');
}
```

- `HandlerInterceptor`: `preHandle`, `postHandle` (with the result,
  before it is written), `afterCompletion` (also after an error; it
  gets the exception even when an `@ExceptionHandler` answered it). As
  in Spring, an interceptor runs only when a `WebMvcConfigurer`
  registers it: a `HandlerInterceptor` bean alone is not picked up.
- `HandlerMethodArgumentResolver`: `supportsParameter` is asked once per
  parameter at startup (`parameter.type`, `parameter.name`,
  `parameter.annotation<A>()`), `resolveArgument` once per request (it
  may return a `Future`).

## CORS

A browser keeps a page of `https://shop.example` from reading the
answers of `https://api.example` unless the API allows it with
`Access-Control-Allow-...` headers (CORS). For most requests the browser
first asks with an `OPTIONS` "pre-flight" request. The starter answers
both from the rules you declare, in one of three ways:

```dart
// On a controller (or a method): the shop's pages may call it.
@RestController()
@CrossOrigin(origins: ['https://shop.example'], maxAge: 3600)
class BookController { ... }

// For many paths at once, a bean (its rules alone, where it has some):
@Bean()
CorsConfigurationSource corsConfigurationSource() => UrlBasedCorsConfigurationSource()
  ..registerCorsConfiguration(
    '/api/**',
    CorsConfiguration(
      allowedOriginPatterns: ['https://*.example'],
      allowCredentials: true,
    )..applyPermitDefaultValues(), // GET, HEAD, POST and every header
  );

// Or WebMvcConfigurer.addCorsMappings, shown above.
```

- **`@CrossOrigin`** on a class or method takes `origins`,
  `originPatterns`, `methods`, `allowedHeaders`, `exposedHeaders`,
  `allowCredentials`, `allowPrivateNetwork` and `maxAge` (in seconds).
  What it leaves out gets these defaults, as in Spring: every origin,
  the method the handler is mapped to (`DELETE` for a `@DeleteMapping`;
  `GET` alone for a `@GetMapping`, so a cross-origin `HEAD` needs
  `methods: ['GET', 'HEAD']`), every request header, and a pre-flight
  cache of 30 minutes.
- **`WebMvcConfigurer.addCorsMappings`** gets the defaults of
  `applyPermitDefaultValues()` for what a mapping leaves out: every
  origin, `GET`, `HEAD` and `POST`, every header, 30 minutes. Its list
  methods add to what is there; Spring's replace it.
- **A `CorsConfigurationSource` bean named `corsConfigurationSource`**
  is the rules the security starter's CORS filter applies, as Spring
  Security applies the bean of that name: where it has a configuration
  for a request, that configuration alone decides, neither `@CrossOrigin`
  nor the `WebMvcConfigurer` mappings widen it (Spring MVC leaves a
  request the filter answered as it is). The router applies it the same
  way, so CORS works the same with and without the security starter.
  Where it has none (`null`), `@CrossOrigin` and the mappings apply. The
  name counts, not the type: a `@Bean` method `corsConfigurationSource()`
  gives it; a bean of the type with another name (`apiCors`, or a
  library's) is ignored, as by Spring Security, and several such beans
  never fail the start. (Spring MVC alone does not read such a bean.)
- **A `CorsConfiguration` you build** is used as it is: empty lists allow
  no origin and no request header, and empty `allowedMethods` allow only
  `GET` and `HEAD`. Call `applyPermitDefaultValues()` for the defaults
  above.

Every cross-origin request is checked, as Spring's `DefaultCorsProcessor`
checks it: its origin, and its method, the one a pre-flight announces
or an actual request's own. So an allowed origin's `DELETE`, `PUT`,
`HEAD` or `OPTIONS` that the rules do not list is refused with a 403
before the handler runs (with the security starter, before the security
checks), even if the browser sent no pre-flight. `allowPrivateNetwork`
(Chrome's Private Network Access, for a server on `localhost` or an
office network called from a public site) answers a pre-flight with
`Access-Control-Request-Private-Network: true` with
`Access-Control-Allow-Private-Network: true`; like `allowCredentials`,
it cannot go with all origins (`*`): `@CrossOrigin` stops the startup,
a mapping fails every request to its paths (500) and a bean every
cross-origin one, as in Spring.

**Behind a proxy that terminates TLS** (or that changes the host or the
port), the server sees `http` and its own address, and the starter does
not read `Forwarded` or `X-Forwarded-*` headers yet. Browsers send an
`Origin` with every `POST`, `PUT`, `PATCH` and `DELETE`, to their own
site too, so there the application's own pages count as another origin,
and their requests are checked as cross-origin ones: the origin, and the
method. Under `addCorsMappings` rules for `/**` with the defaults (`GET`,
`HEAD`, `POST`), a page's own `PUT` or `DELETE` is a 403; with origins
that leave out the site's own, its `POST` too (with or without the
security starter). Spring does the same without
`server.forward-headers-strategy`. Give CORS rules only to the paths
other sites call (`/api/public/**` rather than `/**`), or list the
site's own origin and every method its pages send
(`allowedOrigins(['https://shop.example', ...])`,
`allowedMethods(['GET', 'HEAD', 'POST', 'PUT', 'DELETE'])`), or
terminate TLS in the application (`server.ssl.*`). The security
starter's DPoP proofs have the same limit (see its README).

Origins are checked as Spring's `CorsConfiguration` checks them, by
`AllowedOrigins` (from `spring_web_dart`; the WebSocket starter checks
handshakes with it too):

- `origins` / `allowedOrigins` are whole origins, compared without case
  (`https://shop.example`); `*` allows any, but not with
  `allowCredentials`.
- `originPatterns` / `allowedOriginPatterns` are compared with case: `*`
  matches any text, as Spring's `.*` (`https://*.shop.example` takes
  `https://eu.shop.example`, not `https://shop.example`;
  `*.shop.example` takes any scheme and `*localhost*` any
  `localhost` origin), and a port list at the end takes the ports listed
  (`http://localhost:[3000,3001]`) or, with `[*]`, any port or none
  (`http://localhost:[*]` takes `http://localhost` too). The origin is
  echoed back, so patterns work with `allowCredentials`.
- A value may list several, separated by commas
  (`'https://a.example, https://b.example'`, handy when it comes from one
  property), and a trailing `/` is ignored, in the values and in the
  `Origin` header. The allowed origin is echoed as the browser sent it.

As in Spring, `https://*.example.com` also takes
`https://evil.com/.example.com`: no browser sends such an `Origin`, and
the CORS answer binds browsers only (any other client sends what it
likes). Two differences from Spring:

- An `Origin` longer than 1024 characters is refused
  (`AllowedOrigins.maxOriginLength`; a real origin is under 300: a host
  has at most 253). A pattern is matched in time that grows with the
  origin's length, however many `*` it has, where Spring's regular
  expressions take the square or the cube of it with two or three.
- An `Origin` with a character other than visible US-ASCII (a space, a
  control character, a letter beyond ASCII) is refused with a 403, as
  Spring refuses one it cannot parse, and so is a pre-flight that asks
  for such a method or header, even where `*` allows any: no browser
  sends one, and `dart:io` could not echo it (Spring echoes it).

The rules are combined as in Spring: the global ones (the
`WebMvcConfigurer` mappings) first, then the class, then the method.
Values one side sets are merged with the other side's (a `*` makes the
result `*`), but the defaults of `@CrossOrigin` or
`applyPermitDefaultValues()` never widen what the other side sets, as
Spring's default markers: `@CrossOrigin(methods: ['PUT'])` on a handler
under `/api/**` keeps the global origins, and adds `PUT` to the global
methods. `@CrossOrigin(allowCredentials: true)` without `origins` or
`originPatterns` stops the startup, as in Spring (all origins cannot be
allowed with credentials), and so does `allowPrivateNetwork: true`.

Pre-flight requests (`OPTIONS` with `Origin` and
`Access-Control-Request-Method`) are answered for mapped paths, never
passed to a handler; one for a method no handler of the path maps is
decided by the global rules alone (a 403 when they refuse it, never a
405), as in Spring. A pre-flight to a mapped path without CORS rules
gets a 200 with no CORS header and no `Vary`, as in Spring: the browser
then blocks the request it announced. On a path with CORS rules, a
cross-origin request from an origin they do not allow is a 403. On a
path without rules, the request is handled without CORS headers, and
the browser keeps the answer from the page.

A pre-flight cannot say which `Content-Type` or `Accept` the request it
announces will send, so it is answered from the rules of the first
handler of its path and method (the most specific pattern, then the
most conditions). **This differs from Spring** whenever more than one
handler matches the pre-flight's path and announced method and all of
them have `@CrossOrigin` rules, whatever their specificity: the
handlers mapped to exactly that path when there are some (`GET /items`
producing JSON for one origin, CSV for another), else every pattern
that matches (`/items/{id}` and `/items/**` for `/items/7`). Spring
then allows the pre-flight from any origin, with credentials, and
leaves the check to the actual request. Here an origin the first
handler's rules do not allow gets a 403 for the pre-flight (safer: no
origin gets more than one handler's rules); give such handlers the
same CORS rules. The actual request is checked against the rules of
the handler that answers it, chosen with all its conditions, with and
without the security starter.

Every answer of a handler with CORS rules gets
`Vary: Origin, Access-Control-Request-Method, Access-Control-Request-Headers`,
a CORS request or not (no `Origin`, the server's own origin, an allowed
or a refused one), as Spring's `DefaultCorsProcessor` adds it: a cache
in between then keeps the answers to different origins apart. Each name
is added once, next to the names already in `Vary` (a filter's, in any
case). A handler's own `Vary` (of a `ResponseEntity` or an
`ErrorResponse`) adds its names to these, as Spring's
`HttpEntityMethodProcessor` merges them, rather than replacing them; on
a handler without CORS rules it is written as it is. With the security
starter (its CORS filter is on by default),
the filter adds them to every request with CORS rules, before the
security checks, so its own 401 and 403 answers have them too. Answers
of handlers without rules get none.

## The server

The `webServerFactory` bean is an `IoWebServerFactory` (`dart:io`'s
`HttpServer`, from `package:spring_boot_starter_web/io.dart`),
configured from the `server.*` properties:

```properties
server.port=8080                         # 0: a free port
server.address=127.0.0.1                 # all interfaces by default (127.0.0.1 in Flutter apps)
server.shutdown=graceful                 # or immediate
spring.lifecycle.timeout-per-shutdown-phase=20s
server.servlet.context-path=/shop        # a prefix of every mapping
server.max-http-request-body-size=10MB   # 413 above (10MB by default), whatever the type; -1: no limit
server.connection-timeout=60s            # a body that sends nothing this long: 408; idle connections close; 0 or -1: no limit
server.compression.enabled=true          # gzip, for clients that accept it
server.compression.mime-types=text/html,application/json   # Spring Boot's list by default
server.compression.min-response-size=2KB # the default
server.websocket.max-text-message-size=64KB    # 8KB by default; -1: no limit
server.websocket.send-buffer-size-limit=1MB    # 512KB by default: more waiting drops the connection
server.websocket.send-time-limit=20s           # 10s by default
server.ssl.certificate=/etc/shop/cert.pem
server.ssl.certificate-private-key=/etc/shop/key.pem
```

Every property, with YAML next to it, is in the
[configuration reference](../docs/configuration.md#18-reference-web-server).

- **Start and stop.** The `webServerStartStopLifecycle` bean starts the
  server when the context is ready and stops it when the context
  closes. It is a `SmartLifecycle` in the same phase as Spring Boot's
  `WebServerStartStopLifecycle` (`SmartLifecycle.defaultPhase - 2048`).
  `dart:io` binds the socket asynchronously; its `started` future
  completes once the server listens. Then the port is published as the
  `local.server.port` property and in a `WebServerInitializedEvent`
  (`@EventListener() void on(WebServerInitializedEvent e)`).
- **Graceful shutdown** (the default): the server takes no new
  connections, running requests get up to
  `spring.lifecycle.timeout-per-shutdown-phase` (30 s by default), open
  event streams and WebSocket sessions are closed at once (1001), then
  whatever is left. The same property is the timeout of the context's
  lifecycle processor (the `lifecycleProcessor` bean of
  `spring_boot_dart`, as in Spring Boot), so the beans are destroyed
  only after the requests finished. `server.shutdown=immediate` closes
  everything right away.
- **A port in use** fails the start, as in Spring Boot: the application
  waits for the server to listen before the `ApplicationStartedEvent`,
  the runners and the `ApplicationReadyEvent`, so none of them happen;
  the `ApplicationFailedEvent` is published, the context closes,
  `runAsync` throws the `PortInUseException` (from `run`, it is thrown
  uncaught) and the program ends with a non-zero exit code. The report:

  ```text
  Web server failed to start. Port 8080 was already in use.

  Action: Identify and stop the process that is listening on port 8080, or
  configure this application to listen on another port (server.port; 0 picks a free one).
  ```

- **No server:** `spring.main.web-application-type=none` keeps the beans
  (and `MockMvc`) but starts no server, for example for a command-line
  task of the same application.
- **TLS** with PEM files (`server.ssl.*`); `server.ssl.client-auth=need`
  (or `want`) asks for client certificates. HTTP/1.1 only: `dart:io` has
  no HTTP/2.
- **Compression** (`server.compression.enabled=true`) gzips the
  responses of `server.compression.mime-types` (Spring Boot's list:
  HTML, XML, plain text, CSS, JavaScript, JSON) of at least
  `min-response-size` (2 KB), or of a length not known yet, for clients
  that send `Accept-Encoding: gzip`. Event streams are compressed only
  when `text/event-stream` is listed (each flush sends what is
  compressed so far). As with Tomcat, an answer with a strong `ETag` is
  never compressed (the tag promises those very bytes; a weak `W/"..."`
  one is), and every answer that would be compressed for a client that
  takes gzip gets `Vary: Accept-Encoding`, also when this client does
  not take it, so a cache keeps the two apart (once, and a `*` among
  the `Vary` names leaves `Vary: *` alone).
- **Bodies the handler does not read** (or stops reading, at a limit),
  such as an upload answered with a 413 or a 415: the answer goes out
  first, then up to 2 MB (Tomcat's `max-swallow-size`) are read and
  dropped, for at most 5 seconds, so the client sees the answer and the
  connection can serve the next request. A longer or slower body closes
  the connection.
- **Stalled bodies and idle connections:** a body that sends nothing
  for `server.connection-timeout` (60 s, Tomcat's `connectionTimeout`)
  while it is read ends with a 408 problem, and the connection closes;
  the same timeout closes idle keep-alive connections. `0` or a negative
  value (`-1`) means no limit, as in Tomcat. There is no
  limit on the number of connections (Tomcat's `max-connections`,
  8192): put a proxy in front, or rely on the system's limit of open
  files.
- **An error after the response was committed** (the status and
  headers, maybe part of the body, are out): no error answer can
  follow, so the connection is dropped without finishing the response
  (a chunked body gets no final chunk), as Tomcat does; the client sees
  a broken response, not a short one that looks complete.
- **Answers without a body or a type:** an answer whose media type the
  application did not set has no `Content-Type` (`dart:io`'s default
  `text/plain; charset=utf-8` is not sent), as with Tomcat. A 204, a 304
  and the 101 of a WebSocket handshake have no `Content-Length` (RFC 9110
  forbids it on a 1xx or 204) and no `Transfer-Encoding`, a 304 no
  `Content-Type` either, so a cache that updates its stored answer with
  a 304's headers keeps the right type; what a handler writes to them is
  dropped, as Tomcat drops it. A `HEAD` keeps the `Content-Type` and
  `Content-Length` of the `GET`.
- **`Host`:** an HTTP/1.1 request without one, a malformed one, or an
  absolute target (`GET http://a.example/ HTTP/1.1`) whose host is not
  the `Host` header's is a 400, as Tomcat answers. `dart:io` keeps the
  last of two `Host` headers, so such a request is served for the last
  one (Tomcat answers 400).
- **`%` escapes:** one that does not decode to UTF-8 (`/%FF`,
  `?id=%FF`) is a 400. A `%` without two hex digits after it is read as
  a plain `%` by `dart:io` (`/a%G1` is the path `/a%25G1`), where Tomcat
  answers 400; it can never decode to a separator.
- **`Content-Length` and `Transfer-Encoding` together:** `dart:io`
  accepts such a request and reads the body as chunked, where RFC 9112
  asks a server to refuse it (Tomcat answers 400). Behind a proxy that
  reads it the other way, requests can be smuggled: use a proxy that
  refuses these requests (most do), or none.

To change the settings in code, declare a `WebServerFactoryCustomizer`
bean. To replace the server entirely, declare your own
`WebServerFactory` bean; the default one then backs off
(`@ConditionalOnMissingBean`):

```dart
@Component()
class PortCustomizer implements WebServerFactoryCustomizer {
  @override
  void customize(ConfigurableWebServerFactory factory) =>
      factory.settings = factory.settings.copyWith(port: 9090);
}

@Configuration()
class ServerConfig {
  @Bean()
  WebServerFactory webServerFactory() => MyServerFactory();   // getWebServer(HttpHandler)
}
```

Everything above the server (routing, binding, filters, errors) works on
`ServerHttpRequest` and `ServerHttpResponse` from `spring_web_dart` and
never imports `dart:io`. Another server therefore needs only a
`WebServer` and its factory, and `MockMvc` is one more caller of the
same `HttpHandler`.

### Handler mappings

The `dispatcherHandler` bean plays the role of Spring's
`DispatcherServlet`: it runs the filters, then asks every
`HandlerMapping` bean in order for a handler. The controllers come at
order 0, the WebSocket endpoints of `spring_boot_starter_websocket` at
order 1. A starter or the application adds its own by declaring a
`HandlerMapping` bean:

```dart
// A health check answered without a controller.
@Component()
@Order(10)
class HealthMapping implements HandlerMapping {
  @override
  HttpHandler? getHandler(ServerHttpRequest request) => request.path == '/health'
      ? FunctionHttpHandler((request, response) => response.send(200, 'UP'))
      : null;
}
```

## Flutter

The starter works in a Flutter app on Android, iOS, macOS, Windows and
Linux. It runs in the main isolate with the same beans as the widgets.
`HttpServer`'s I/O is asynchronous and does not block the UI, but heavy
synchronous work in a handler does: move it into `Isolate.run`.

- **`127.0.0.1` by default:** an app opens no port to the network unless
  `server.address` says so.
- **In the background** the context pauses: the server stops and frees
  the port, and starts again when the app comes back
  (`spring.flutter.lifecycle.pause-in-background`).
- **Platform permissions:** macOS needs the
  `com.apple.security.network.server` entitlement; Android needs
  `INTERNET` in the release manifest; on iOS, binding beyond localhost
  asks for local network access (`NSLocalNetworkUsageDescription`).
- **The web** has no server sockets: the application fails at startup
  with an error that says so. Use the clients (Feign, WebSocket) there,
  or set `spring.main.web-application-type=none`.

## WebSocket endpoints

With [`spring_boot_starter_websocket`](../spring_boot_starter_websocket/README.md)
in the dependencies too, `@WebSocketEndpoint` beans and
`WebSocketConfigurer` handlers are served on the same port, and their
handshakes pass through the same filters:

```dart
@WebSocketEndpoint('/ws/rooms/{room}')
class ChatEndpoint {
  // Each message is answered with an acknowledgement, sent back as JSON.
  @OnMessage()
  Ack message(@PathVariable() String room, ChatMessage message) => Ack(room);
}
```

The WebSocket starter's
[Server endpoints](../spring_boot_starter_websocket/README.md#server-endpoints)
section describes them. The server reads at most 8 KB per message
(Tomcat's default in Spring): a larger text or binary message is not
read, and the session is closed with `1009` (message too big). Raise the
limits with `server.websocket.max-text-message-size` and
`server.websocket.max-binary-message-size` (this starter's keys; Spring
sets them on the container). The text limit counts UTF-8 bytes, where
Tomcat counts characters. No extension is negotiated, so messages are
never compressed (permessage-deflate).

What a session sends waits in memory until the client takes it. As
Spring's `ConcurrentWebSocketSessionDecorator` does, a session gives
up when more than `server.websocket.send-buffer-size-limit` (512 KB)
waits, or when what was sent has not left within
`server.websocket.send-time-limit` (10 s): the connection is dropped
(a close frame could not get through either), and the handler's
`afterConnectionClosed` gets 4500 (`CloseStatus.sessionNotReliable`)
with the reason. The pongs that answer pings wait with the messages, so
a client that sends pings and reads nothing reaches the limit too. The
session goes on reading the client while messages wait, so a client
that sends a lot while the server does too is not held up. A burst
larger than the limit that the network cannot take at once drops the
session too, as in Spring: raise the limit for such bursts, or await
`flush()` on the session (`IoWebSocketSession`, the `delegate` of a
`DefaultServerWebSocketSession`) after each message to send at the
client's pace. A client that goes away while messages wait (a reset)
ends the session with 1006 (`CloseStatus.noCloseFrame`) and the error
as the reason, also over TLS, where the input often ends before the
write fails (the session waits for the write, a second at most); after
`close(status)` from the server, the handler gets that `status`.

## Testing

`spring_boot_starter_test` calls the controllers in memory with
`MockMvc`: no socket, but the same dispatcher, filters and error
handling. It can also start a real server on a free port.

```dart
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/main.spring.dart';

void main() {
  final app = springBootTest(springApplication);   // WebEnvironment.mock: no server

  test('finds a book', () async {
    await app.mockMvc.get('/api/books/1111').andExpect(
      status: 200,
      contentType: MediaType.applicationJson,
      json: {'isbn': '1111', 'title': 'Dune'},
    );
  });

  test('rejects an invalid book', () async {
    await app.mockMvc
        .post('/api/books', json: {'isbn': '', 'title': ''})
        .andExpect(status: 400, contentType: MediaType.applicationProblemJson);
  });

  test('streams changes', () async {
    final result = await app.mockMvc.get('/api/books/changes').andReturn();
    // Skip the leading ':' comment line: wait for the first real event.
    final next = result.response.eventStream.firstWhere((e) => e.data != null);
    await app.mockMvc.post('/api/books', json: {'isbn': '5555', 'title': 'Vurt'});
    expect((await next).id, '5555');
    await result.cancel();
  });
}
```

`springBootTest(springApplication, webEnvironment: WebEnvironment.randomPort)`
starts the real server on a free port (`app.localServerPort`), for a
Feign client or `dart:io`'s `HttpClient` to call. In a test class:
`@SpringBootTest(webEnvironment: ...)`, `@Autowired() late MockMvc mvc;`,
`@LocalServerPort() late int port;`. Web tests are described in full in
[docs/testing.md](../docs/testing.md#17-web-tests-mockmvc).

`ApplicationContextRunner` starts no server unless the test sets
`spring.test.web-environment=random-port`.

## How it works

`@GetMapping`, `@PostMapping`, ..., `@ExceptionHandler` are marked
`@BeanMethodAnnotation()` (from `spring_core_dart`). For a bean with
such methods, the generator writes a description of each one into the
bean definition (`BeanDefinition.annotatedMethods`: the parameters with
their names, types and annotations, the result type, and an invoker). It
also introspects the parameter and result types of the bean's package
for JSON. At startup, `RequestMappingHandlerMapping` reads these
descriptions, checks them and builds the routes. Handlers are called on
the bean as the context holds it, so AOP advice on a controller
(`@Cacheable`, method validation, the security starter's
`@PreAuthorize`) applies.

## Differences from Spring

- **Errors are `ProblemDetail`** (`application/problem+json`), except
  the plain-text answers Spring gives too (a refused CORS request or
  WebSocket handshake). Spring Boot's default is the `/error` JSON
  (`timestamp`, `status`, `error`, `path`) unless
  `spring.mvc.problemdetails.enabled=true`; here there is no `/error`
  endpoint and no `ErrorController`.
- **`@ControllerAdvice.of(basePackages: ...)` takes library URI
  prefixes** (`package:shop/admin/`) instead of Java packages, and
  `annotations` match a controller's annotation by its exact type;
  there is no `basePackageClasses`.
- **`@ExceptionHandler([types])` matches exact runtime types**, because
  Dart cannot test whether a `Type` is a subtype of another. Subtypes
  match through the type of the exception parameter
  (`@ExceptionHandler() void on(StateError e)`).
- **`@ResponseStatus` goes on handler methods** or the controller class,
  not on exception classes, whose annotations cannot be read at
  runtime: throw a `ResponseStatusException` or implement
  `ErrorResponse` instead.
- **A pre-flight that several handlers match** (with `@CrossOrigin`
  each; no handler of exactly that path, or several) gets the first
  one's CORS rules; Spring allows it from any origin with credentials,
  whatever the handlers' specificity (see [CORS](#cors)).
- **CORS values outside visible US-ASCII are refused with a 403**: an
  `Origin`, or a pre-flight's requested method or headers, with a space,
  a control character or a letter beyond ASCII, even where `*` allows
  any. Spring echoes such a method or header (no browser sends one), and
  refuses such an `Origin` too.
- **An `Origin` longer than 1024 characters is never allowed** (CORS
  and WebSocket handshakes: a 403), whatever the rules, `*` included; a
  real origin is under 300 characters. Spring checks any length, and its
  patterns' regular expressions slow down with it.
- **Custom argument resolvers are asked before the built-in ones**
  (Spring asks them after), so a starter can take over any parameter,
  as the security starter's `@AuthenticationPrincipal` does.
- **No `@ModelAttribute` and no binding of forms to objects.** Form
  fields reach a handler through `@RequestParam` (one field, a list, or
  all of them as a `Map`) or a `@RequestBody() Map<String, String>`.
- **No `HttpSession` parameter:** a handler gets the session with
  `request.getSession()`. The session cookie is `SameSite=Lax` and the
  number of sessions is limited (`server.servlet.session.max-sessions`;
  a login is pushed out only for a user who holds the most sessions,
  else a new session is refused with `503`).
- **Multipart without a servlet container:** the
  `spring.servlet.multipart.*` keys keep Boot's names, but the temporary
  files are this starter's own (`file-size-threshold` is `0B`: every
  file goes to disk). Only `multipart/form-data` parts are bound, not
  `multipart/mixed`, for `@RequestPart`.
- **A declared `Stream<Uint8List>` or `Stream<List<int>>` result is raw
  bytes.** Spring MVC has no byte stream result; Spring WebFlux writes a
  `Flux<DataBuffer>` the same way. Other streams are server-sent events.
- **Resources: one byte range** per request. Several ranges get the
  whole content, not `multipart/byteranges`, and resources have no
  `ETag`.
- **Event streams start with a `:` comment line**, because `dart:io`
  sends the headers with the first body bytes.
- **An `SseEmitter` without a timeout never times out** when
  `spring.mvc.async.request-timeout` is not set: there is no servlet
  container whose default applies (Tomcat's 30 seconds in Spring). It
  ends when it is completed, when the client goes away, or when the
  server stops. Give it a timeout, or set the property.
- **WebSocket message limits and compression are the server's:**
  `server.websocket.max-text-message-size` and `max-binary-message-size`
  (8 KB each, Tomcat's defaults) are this starter's keys; Spring sets
  them on the container (`ServletServerContainerFactoryBean`). The text
  limit counts UTF-8 bytes; Tomcat counts characters. permessage-deflate
  is not offered, while Tomcat negotiates it.
- **Every WebSocket session has send limits**
  (`server.websocket.send-buffer-size-limit`, 512 KB, and
  `send-time-limit`, 10 s; past them the connection is dropped with
  4500), Spring's `ConcurrentWebSocketSessionDecorator` defaults. In
  Spring they apply to STOMP sessions and to sessions you decorate; a
  plain handler on Tomcat blocks the sending thread instead (up to
  Tomcat's 20 s blocking send timeout). Await `IoWebSocketSession.flush()`
  after `sendMessage` to wait the same way.
- **Stalled request bodies get a 408** after `server.connection-timeout`
  (60 s); with Tomcat the read fails after its `connectionTimeout` and
  Spring answers 400. There is no connection limit (Tomcat's
  `max-connections`). Two `Host` headers and a `%` without two hex
  digits are accepted (`dart:io`), where Tomcat answers 400.
- **A raw `\` in the request target is a `/`:** `dart:io` parses the
  target before the server sees it and keeps no raw form, so
  `/files/..\..\secret` arrives as `/secret` (its `..` resolved), and
  raw bytes past ASCII are read as Latin-1 (`/café` sent as UTF-8
  arrives as `/caf%C3%83%C2%A9`). Tomcat answers 400 to both. Filters,
  security rules and controllers all see the same path, but a proxy in
  front whose rules look at paths must refuse a `\` itself.
- **HTTP/1.1 only**; `server.http2.enabled` is not read.
- **TLS from PEM file paths**, not `classpath:` locations; no keystores
  or SSL bundles.
- **More startup checks** than Spring: a path variable without a
  parameter, a parameter nothing can fill, an invalid
  `@ExceptionHandler`.
- `server.max-http-request-body-size`, `spring.mvc.sse.heartbeat-interval`,
  `spring.servlet.multipart.max-part-count` (Boot's
  `server.tomcat.max-part-count`), `server.connection-timeout` (Boot
  2.0's key; Boot 4's is `server.tomcat.connection-timeout`) and
  `server.websocket.*` are this starter's own properties.
- `MockMvc` takes named expectations (`andExpect(status: 200, json:
  ...)`, matchers allowed) instead of `status().isOk()` and
  `jsonPath(...)`.

## Not yet

- `@ConditionalOnWebApplication`, test slices (`@WebMvcTest`).
- `ResponseBodyEmitter` (a `Stream<T>` result covers SSE and NDJSON).
- Several byte ranges as `multipart/byteranges`, `ETag` for resources,
  `@RequestPart` with `multipart/mixed`.
- Static files (`lib/resources/static/`), forwarded headers
  (`server.forward-headers-strategy`), `spring.web.cors.*`,
  `server.max-http-request-header-size`.
- Flutter: a warning when a handler blocks the main isolate, decoding
  big JSON bodies in another isolate, the whole server in a background
  isolate (`server.isolate: background`).
- Other servers (`shelf`, Rust over FFI), STOMP, the actuator over HTTP.
  See the [roadmap](../roadmap/spring_boot_starter_web.md).
