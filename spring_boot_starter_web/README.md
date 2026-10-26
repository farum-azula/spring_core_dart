# spring_boot_starter_web

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Spring MVC for [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications: `@RestController` classes with `@GetMapping`,
`@PostMapping`, ... answer HTTP requests, JSON goes through the
`ObjectMapper` of `spring_core_dart`, `@Valid` bodies are checked, errors
are `ProblemDetail`s, streams become server-sent events, files go up as
`multipart/form-data` and down as `Resource`s (with `Range`). The server is
`dart:io`'s `HttpServer` behind a replaceable `WebServerFactory`; it runs
on the VM and inside Flutter apps on mobile and desktop (a local API, a
companion server). The generator writes everything at build time, no
reflection.

```dart
@RestController()
@RequestMapping('/api/books')
class BookController {
  BookController(this.books);             // injected like any bean
  final BookService books;

  @GetMapping('/{isbn}')
  Future<Book> find(@PathVariable() String isbn) => books.find(isbn);

  @GetMapping()
  Future<List<Book>> search(
    @RequestParam('q') String query, {
    @RequestParam.of(name: 'page', defaultValue: '0') int page = 0,
  }) => books.search(query, page: page);

  @PostMapping()
  Future<ResponseEntity<Book>> create(@RequestBody() @Valid() NewBook book) async {
    final created = await books.create(book);
    return ResponseEntity.created(Uri.parse('/api/books/${created.isbn}'))
        .body(created);
  }

  @DeleteMapping('/{isbn}')
  @ResponseStatus(HttpStatus.noContent)
  void delete(@PathVariable() String isbn) => books.delete(isbn);

  @GetMapping('/changes')
  EventStream<Book> changes() => EventStream(
    () => books.changes().map((b) => ServerSentEvent(b, id: b.isbn)),
  );
}

class NewBook {                           // introspected: the controller uses it
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

## Setup

```yaml
dependencies:
  spring_boot_starter_web: ^0.3.1

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.3.1   # required: describes the controllers
  spring_boot_starter_test: ^0.3.1     # MockMvc, springBootTest
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

The starter is found automatically (no `@EnableWebMvc`): every
`@RestController` in the scanned package is mapped, and the server starts
when the context is ready. One import is enough:
`package:spring_boot_starter_web/spring_boot_starter_web.dart` re-exports
`spring_boot_dart`, `spring_web_dart` (the annotations, `ResponseEntity`,
`ProblemDetail`, the server request and response) and
`spring_boot_starter_logging`. The starter is the only dependency an
application needs, like every Spring Boot starter.

Classes used by the controllers (parameters and results) are introspected
for JSON automatically when they are in the same package.

For `Ctrl+C` / `SIGTERM` to stop the server gracefully, let the
application close its context on those signals:
`spring.main.register-shutdown-hook=true` (it is `false` by default here,
see [Configuration](../docs/configuration.md#11-reference-the-application)).

## Controllers

`@RestController()` makes a bean whose mapped methods answer requests;
`@RequestMapping('/api/books')` on the class is the path prefix of every
method (its `produces`, `consumes` and `headers` apply to them too). A
plain `@Controller()` is mapped the same way (there are no views: the
return value is always the body).

| Annotation | Request |
|---|---|
| `@GetMapping('/{isbn}')` | `GET` |
| `@PostMapping()`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping` | `POST`, `PUT`, `PATCH`, `DELETE`; no path: the class's path |
| `@RequestMapping.of(path: '/x', method: HttpMethod.head)` | any method |
| `@GetMapping.of(path: '/x', produces: 'text/csv', consumes: ..., headers: ['X-Api=2'])` | the same with conditions: `produces` against `Accept`, `consumes` against `Content-Type` (comma-separated types), `headers` as `Name`, `!Name`, `Name=value`, `Name!=value` |

Paths are Spring's path patterns (`PathPattern` of `spring_web_dart`), with
`${...}` placeholders resolved from the configuration:

| Pattern | Matches |
|---|---|
| `/books` | the path itself; a trailing slash matters (`/books/` is another path, as in Spring 6) |
| `/books/{isbn}` | one segment, captured as `isbn` (decoded) |
| `/books/{isbn:\d+}` | one segment matching the regular expression |
| `/files/{*path}` | the rest of the path, with its leading `/` |
| `/static/**`, `/b?ok`, `/*.json` | wildcards: segments, one character, part of a segment |

The most specific pattern wins (`/books/new` before `/books/{isbn}`),
then the mapping with more conditions. `HEAD` is answered by every `GET`
mapping (the headers and `Content-Length`, no body) and `OPTIONS` with
`Allow`, as in Spring.

### Parameters

| Parameter | Value |
|---|---|
| `@PathVariable() String isbn` | `{isbn}` of the path; `@PathVariable('id')` for another name |
| `@RequestParam('q') String query` | a query parameter (or a text field of a multipart form); `List<int> ids` takes `?id=1&id=2` or `?id=1,2`; `Map<String, String>` all of them; a `MultipartFile` the file of that name |
| `@RequestHeader('X-Trace') String? trace` | a header; `HttpHeaders` or a `Map` for all of them |
| `@CookieValue('session') String session` | a cookie |
| `@RequestBody() Book book` | the body: JSON through the `ObjectMapper` (`application/json`, `*+json` or no `Content-Type`); `String`, `Uint8List` / `List<int>`, `Stream<Uint8List>` (unread, for big uploads); a `Map` from a form (`application/x-www-form-urlencoded`) |
| `@RequestBody() @Valid() NewBook book` | the body, validated (`@Validated([Group])` for groups): a violation is a 400 |
| `@RequestPart('file') MultipartFile file` | a part of a `multipart/form-data` upload: files, text fields, a JSON part; see [Files](#files-uploads-and-downloads) |
| `ServerHttpRequest`, `ServerHttpResponse` | the request and the response |
| `HttpHeaders`, `HttpMethod`, `Uri` | the request's headers, method, URI |
| `Principal` | the user an authentication filter set (`request.principal`); a non-nullable `Principal` without one is a 401 |
| a simple value or a `MultipartFile` without annotation (`String q`, `int page`) | a query parameter (or uploaded file) of that name, like Spring's default `@RequestParam` |

Simple values are `String`, `int`, `double`, `num`, `bool` (`true`, `on`,
`yes`, `1`, ...), `BigInt`, `DateTime` (ISO 8601), `Duration` (`10s`),
`Uri`, enums (by name, any case, or `@JsonValue`) and lists or sets of
them. A text that does not convert is a 400 naming the parameter.

`required` and `defaultValue` work as in Spring, written with the `.of`
constructor: `@RequestParam.of(name: 'sort', required: false)`,
`@RequestHeader.of(name: 'X-Lang', defaultValue: 'en')`. A nullable type
or a Dart default value makes a parameter optional too:

| Value missing | Result |
|---|---|
| with `defaultValue` | the default value, converted |
| nullable parameter (`String? q`) | `null` |
| optional named or positional parameter (`{int page = 0}`) | left out: its Dart default applies |
| otherwise | 400 `Required parameter 'q' is not present.` (also header, cookie) |

### Results

| Return type | Response |
|---|---|
| `void`, `null`, `Future<void>` | the status (200, or `@ResponseStatus`), no body |
| an object, `List`, `Map` | JSON through the `ObjectMapper` (`application/json`, or the mapping's `produces`); 406 when `Accept` excludes it |
| `String` | `text/plain;charset=UTF-8` (or `produces`) |
| `Uint8List` | `application/octet-stream` (or `produces`) |
| `Resource` (`FileSystemResource`, `ByteArrayResource`) | a download: the media type from the file name, `Content-Length`, `Range` and `Last-Modified`; see [Files](#files-uploads-and-downloads) |
| `Stream<Uint8List>`, `Stream<List<int>>` | raw bytes as they come (`application/octet-stream`, or `produces`) |
| `StreamingResponseBody` | bytes the handler writes itself |
| `ResponseEntity<T>` | its status, headers and body (`ResponseEntity.ok(x)`, `.created(uri).body(x)`, `.notFound().build()`) |
| `ProblemDetail`, an `ErrorResponse` | `application/problem+json` with its status |
| `EventStream<T>`, `Stream<T>` (other than bytes) | server-sent events (`text/event-stream`); NDJSON with `produces: 'application/x-ndjson'` |
| `SseEmitter` | server-sent events sent from anywhere |

A `Future` of any of them is awaited (but not a `Future` of a stream:
return the stream). `@ResponseStatus(HttpStatus.created)` sets the status
of a normal answer; `@ResponseStatus(HttpStatus.gone, reason: 'Retired')`
turns it into an error with that detail.

### Checked at startup

Every controller is checked when the context starts. A `{variable}`
without a `@PathVariable` parameter (or the other way round), a parameter
nothing can fill, two `@RequestBody` parameters, a `@RequestParam` that is
not a simple value, two methods mapping the same request (method, pattern
and conditions), an invalid `produces`, or an `@ExceptionHandler` without
an exception stops the application with the whole list:

```text
Invalid controllers:
  - BookController.find: the path variable {isbn} of "/api/books/{isbn}" has no @PathVariable parameter
  - Ambiguous mapping: OrderController.list and OrderController.all both map GET /api/orders
```

Set `logging.level.spring.web.mvc=debug` to see every mapping
(`Mapped GET /api/books/{isbn} -> BookController.find`).

## Errors: `ProblemDetail`

Errors are answered with RFC 9457 problems (`application/problem+json`),
like Spring 6's `ProblemDetail`:

| Cause | Status |
|---|---|
| no mapping for the path | 404 |
| the path is mapped, not for this method | 405 with `Allow` |
| `Content-Type` not in `consumes`, or not JSON for a `@RequestBody` object | 415 with `Accept` |
| nothing in `produces` (or JSON) matches `Accept` | 406 |
| a required value missing, a value that does not convert, an unreadable body, unmet `headers` conditions | 400 |
| `@Valid` violations | 400 with `errors`: `[{"field": "isbn", "message": "...", "rejectedValue": ""}]` (messages from the `MessageSource`) |
| a body above `server.max-http-request-body-size` | 413 |
| an upload above `spring.servlet.multipart.max-file-size` / `max-request-size` | 413 (`MaxUploadSizeExceededException`) |
| a malformed multipart request, or `@RequestPart` on a request that is not multipart | 400 (`MultipartRequestException`) |
| `throw ResponseStatusException(HttpStatus.notFound, 'No book 9')` | its status and detail |
| an `ErrorResponse` / `ErrorResponseException` | its status, headers and problem |
| any other exception | 500 `Internal Server Error`, no detail (the exception is logged under `spring.web.mvc`) |

Your own answers come from `@ExceptionHandler` methods: on a controller
for its own handlers, on a `@ControllerAdvice` / `@RestControllerAdvice`
for every handler (several advice beans are tried in `@Order`). The
method takes the exception (and optionally the `ServerHttpRequest`,
`ServerHttpResponse`, `HttpHeaders`) and returns what a handler returns:

```dart
@RestControllerAdvice()
class ApiErrors {
  @ExceptionHandler()                            // types from the parameter
  @ResponseStatus(HttpStatus.notFound)
  ProblemDetail notFound(BookNotFoundException e) =>
      ProblemDetail.forStatusAndDetail(HttpStatus.notFound, 'No book ${e.isbn}')
        ..setProperty('isbn', e.isbn);

  @ExceptionHandler()
  ResponseEntity<ProblemDetail> conflict(StateError e) =>
      ResponseEntity.status(HttpStatus.conflict)
          .body(ProblemDetail.forStatusAndDetail(HttpStatus.conflict, e.message));

  @ExceptionHandler([TimeoutException])          // exact runtime types
  @ResponseStatus(HttpStatus.gatewayTimeout)
  void timeout() {}
}
```

The handler for the most specific type wins: an exact type of
`@ExceptionHandler([...])` first, then the parameter type that is a
subtype of the others. A controller's own handlers come before the advice.
Advice handlers also see the 404 / 405 / 406 / 415 of the lookup and the
errors of other handler mappings (WebSocket handshakes); exceptions
thrown by a filter go straight to the default answer.

## Server-sent events

Return an `EventStream<T>` (or any `Stream<T>` that is not a byte
stream, see [Files](#files-uploads-and-downloads)): each item is an event,
its data written as JSON (a `String` as it is). `ServerSentEvent<T>` items
keep their `id`, `event`, `retry` and `comment`. The stream is listened to
when the response starts and cancelled when the client goes away.

```dart
@GetMapping('/changes')
EventStream<Book> changes() => EventStream(
  () => books.changes().map((book) => ServerSentEvent(book, id: book.isbn)),
);

@GetMapping('/resume')
Stream<Book> resume(@RequestHeader.of(name: 'Last-Event-ID', required: false) String? lastId) =>
    books.changesAfter(lastId);

@GetMapping.of(path: '/export', produces: 'application/x-ndjson')
Stream<Book> export() => books.all();            // one JSON object per line
```

A `POST` (or any method) may answer with a stream too, as MCP's
Streamable HTTP does.

**`SseEmitter`**, like Spring MVC's, is for events pushed from elsewhere
(a service, an event listener). Events sent before the response is ready
are buffered:

```dart
@GetMapping('/notifications')
SseEmitter subscribe() {
  final emitter = SseEmitter(timeout: const Duration(minutes: 30));
  notifications.add(emitter);
  emitter.onCompletion(() => notifications.remove(emitter));
  return emitter;
}

// Elsewhere:
for (final emitter in notifications) {
  emitter.send(ServerSentEvent(order, event: 'order', id: order.id));
}
```

`send`, `complete()`, `completeWithError(e)`, `onCompletion`, `onTimeout`,
`onError`, `isComplete`. Sending after the client went away throws a
`StateError`. Without its own timeout an emitter ends after
`spring.mvc.async.request-timeout` (no limit when not set).
`spring.mvc.sse.heartbeat-interval=15s` writes a comment line at that
interval, so proxies keep idle streams open (this starter's own property).

The response headers go out with the first bytes of the body (`dart:io`
sends none before), so every `text/event-stream` response starts with an
empty comment line (`:`), which clients ignore: the client sees the response before
the first event. When the server stops, open streams are closed.

## Files: uploads and downloads

### Uploads: `multipart/form-data`

A `multipart/form-data` request (a browser form with
`enctype="multipart/form-data"`, `curl -F`, a Feign client) is read once
per request, like Spring's `StandardServletMultipartResolver`, and bound
to the handler's parameters:

```dart
@PostMapping.of(path: '/api/books', consumes: MediaType.multipartFormData)
Future<Book> create(
  @RequestPart('book') @Valid() NewBook book,          // a JSON part, validated
  @RequestPart('cover') MultipartFile cover,           // a file
  @RequestParam('note') String note, {                 // a text field
  @RequestPart.of(name: 'pages', required: false) List<MultipartFile>? pages,
}) async {
  final created = await books.create(book, note: note);
  await cover.transferTo('/var/shop/covers/${created.isbn}.png');
  return created;
}
```

| Parameter | Value |
|---|---|
| `@RequestPart('file') MultipartFile file` | the file of that part (the first one if several) |
| `@RequestPart('files') List<MultipartFile> files` | every file of that name (when there is none: a 400 if required, else `null`, or an empty list for a non-nullable optional parameter) |
| `@RequestPart('note') String note`, `int`, ... | a text field, converted like a request parameter (or the text of a file part) |
| `@RequestPart('data') Uint8List data` | the raw bytes of the part (`List<int>` too) |
| `@RequestPart('book') @Valid() NewBook book` | a part read as JSON through the `ObjectMapper` into the type, validated with `@Valid` |
| `@RequestPart.of(name: 'cover', required: false) MultipartFile? cover` | optional, like `@RequestParam.of` (a nullable type or a Dart default does it too) |
| `@RequestParam('file') MultipartFile file` | the same as `@RequestPart` for files |
| `@RequestParam('note') String note` | a text field of the form, like a servlet's parameters (the query string is looked at first) |
| `MultipartFile file` without annotation | the file named like the parameter |

A missing required part is a 400 `Required part 'cover' is not present.`;
`@RequestPart` on a request that is not multipart is a 400.
`MultipartFile` (from `spring_web_dart`) has `name`, `originalFilename`,
`contentType`, `size`, `isEmpty`, `headers`, `bytes` (a `Future`),
`openRead()` (a stream, without loading the file) and `transferTo(path)`,
which moves the temporary file to `path` (copies it when it cannot be
moved).

**Limits and temporary files** (Spring Boot's
[`spring.servlet.multipart.*`](../docs/configuration.md#18-reference-web-server)):

```properties
spring.servlet.multipart.max-file-size=5MB        # one file (or part); 1MB by default, -1: no limit
spring.servlet.multipart.max-request-size=20MB    # the whole request; 10MB by default, -1: no limit
spring.servlet.multipart.file-size-threshold=64KB # smaller files stay in memory; 0B by default: all go to disk
spring.servlet.multipart.location=/var/tmp/shop   # the system's temporary directory by default
spring.servlet.multipart.enabled=false            # don't parse multipart requests
```

- Above a limit the upload is a 413 (`MaxUploadSizeExceededException`);
  reading stops there. `server.max-http-request-body-size` does not apply
  to multipart requests: their own limits do.
- Files are streamed to temporary files as they arrive (no whole upload
  in memory) and **deleted when the request ends**, whatever the handler
  did; keep a file with `transferTo` or by copying `openRead()`. Without
  `dart:io` (the web) files stay in memory.

Sending files from a client: see the Feign starter's
[Files and multipart](../spring_boot_starter_feign/README.md#files-and-multipart).

### Downloads: `Resource`

Return a `Resource` from `spring_core_dart` (`FileSystemResource`,
`ByteArrayResource`), like Spring's `ResourceHttpMessageConverter`:

```dart
@GetMapping('/api/books/{isbn}/cover')
Resource cover(@PathVariable() String isbn) =>
    FileSystemResource('/var/shop/covers/$isbn.png');

@GetMapping('/api/report')
ResponseEntity<Resource> report() => ResponseEntity.status(HttpStatus.ok)
    .contentType('text/csv')
    .header('Content-Disposition', ['${ContentDisposition.attachment(filename: 'report.csv')}'])
    .body<Resource>(ByteArrayResource(utf8.encode(reports.csv())));
```

- **Headers:** `Content-Type` from the file name (`MediaTypeFactory`,
  `application/octet-stream` when unknown) unless the `ResponseEntity`
  sets one, `Content-Length`, `Accept-Ranges: bytes`. A
  `ResponseEntity<Resource>` keeps its status and headers
  (`Content-Disposition` for a download with a name).
- **A file is streamed** from disk (`FileSystemResource.openRead(start, end)`),
  never read whole. A resource that does not exist is a 404.
- **`Last-Modified`** (files): a `GET` / `HEAD` with an `If-Modified-Since`
  at or after it is a 304 without a body.
- **`Range`:** one range (`bytes=0-99`, `bytes=500-`, `bytes=-100`) is a
  206 with `Content-Range`; a range past the end is a 416
  (`Content-Range: bytes */length`). Several ranges or a malformed header
  get the whole content (200), as RFC 9110 allows. `If-Range` with a date
  applies the range only if the file has that `Last-Modified`.
- `HEAD` answers the same headers without the body.

### Byte streams and `StreamingResponseBody`

A handler **declared** to return `Stream<Uint8List>` or `Stream<List<int>>`
writes the chunks as raw bytes, as they come (`application/octet-stream`,
or the mapping's `produces`); any other `Stream<T>` is still server-sent
events. For a body produced on the fly, return a `StreamingResponseBody`,
like Spring's: the handler writes to a `ResponseBodySink` (`add(bytes)`,
`write(text)`, `flush()`, `addStream(stream)`):

```dart
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

Both can be the body of a `ResponseEntity` (for `Content-Disposition`).

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

A `MockMultipartFile` without a file name is a plain part (with
`application/json`, a JSON part for `@RequestPart`). See
[docs/testing.md](../docs/testing.md#files-uploads-and-downloads).

## Filters

`WebFilter` beans run around every request, in `@Order`, before the
handler is looked up (like servlet filters; Spring Security's filter
chain will be one of them). `OncePerRequestFilter` adds
`shouldNotFilter`:

```dart
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

A filter can answer itself (not calling the chain), or pass a wrapped
request or response: `ServerHttpRequestDecorator` and
`ServerHttpResponseDecorator` forward everything and let you override one
member (the path, the headers, the principal).

Every request runs in its own `Zone`: `RequestContextHolder.currentRequest`
is the request anywhere in its handling, across `await`s.

## Interceptors, argument resolvers: `WebMvcConfigurer`

A bean implementing `WebMvcConfigurer` (a mixin) customizes the
controllers, like Spring's:

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

final class TimingInterceptor with HandlerInterceptor {
  @override
  bool preHandle(request, response, handler) {   // false: the interceptor answered
    request.attributes['start'] = DateTime.now();
    return true;
  }

  @override
  void afterCompletion(request, response, handler, error) =>
      print('${handler.description} took '
          '${DateTime.now().difference(request.attributes['start'] as DateTime)}');
}

final class TenantResolver implements HandlerMethodArgumentResolver {
  @override
  bool supportsParameter(MethodParameter parameter) => parameter.type.type == Tenant;

  @override
  Object? resolveArgument(parameter, request, response) =>
      Tenant(request.headers['X-Tenant'] ?? 'default');
}
```

- `HandlerInterceptor`: `preHandle`, `postHandle` (with the result, before
  it is written), `afterCompletion` (also after an error). As in Spring,
  an interceptor runs only when a `WebMvcConfigurer` registers it; a
  `HandlerInterceptor` bean alone is not picked up.
- `HandlerMethodArgumentResolver`: `supportsParameter` is asked once per
  parameter at startup (`parameter.type`, `parameter.name`,
  `parameter.annotation<A>()`), `resolveArgument` per request (may return
  a `Future`).

## CORS

```dart
@RestController()
@CrossOrigin(origins: ['https://shop.example'], maxAge: 3600)
class BookController { ... }

// or for every controller, a bean (Spring Security's .cors() will use it too):
@Bean()
CorsConfigurationSource corsConfigurationSource() => UrlBasedCorsConfigurationSource()
  ..registerCorsConfiguration('/api/**',
      CorsConfiguration(allowedOriginPatterns: ['https://*.example'], allowCredentials: true));
```

`@CrossOrigin` on a class or method (`origins`, `originPatterns`,
`methods`, `allowedHeaders`, `exposedHeaders`, `allowCredentials`,
`maxAge` in seconds; what it leaves out gets Spring's defaults: every
origin and header, the handler's methods, 30 minutes),
`WebMvcConfigurer.addCorsMappings`, and a `CorsConfigurationSource` bean
are combined like Spring's (global first, then the class, then the
method). Pre-flight requests (`OPTIONS` with `Origin` and
`Access-Control-Request-Method`) are answered for mapped paths. On a path
with a CORS configuration, a cross-origin request from an origin it does
not allow is a 403; on a path without one, the request is handled without
CORS headers (and the browser keeps the answer from the page).

## The server

The `webServerFactory` bean is an `IoWebServerFactory` (`dart:io`'s
`HttpServer`, from `package:spring_boot_starter_web/io.dart`) configured
from `server.*`:

```properties
server.port=8080                         # 0: a free port
server.address=127.0.0.1                 # all interfaces by default (127.0.0.1 in Flutter apps)
server.shutdown=graceful                 # or immediate
spring.lifecycle.timeout-per-shutdown-phase=20s
server.servlet.context-path=/shop        # a prefix of every mapping
server.max-http-request-body-size=10MB   # 413 above; -1: no limit
server.compression.enabled=true          # gzip for clients that accept it
server.ssl.certificate=/etc/shop/cert.pem
server.ssl.certificate-private-key=/etc/shop/key.pem
```

Every property, with YAML next to it, is in the
[configuration reference](../docs/configuration.md#18-reference-web-server).

- **Lifecycle.** `webServerStartStopLifecycle` (a `SmartLifecycle`, like
  Spring Boot's `WebServerStartStopLifecycle`, in the same phase:
  `SmartLifecycle.defaultPhase - 2048`) starts the server when the context
  is ready and stops it when the context closes. `dart:io` binds the
  socket asynchronously: its `started` future completes once the server
  listens. Then the port is published as the `local.server.port` property
  and a `WebServerInitializedEvent` (`@EventListener() void on(WebServerInitializedEvent e)`).
- **Graceful shutdown** (the default): no new connections, running
  requests get up to `spring.lifecycle.timeout-per-shutdown-phase`
  (30 s), open event streams and WebSocket sessions are closed at once
  (1001), then whatever is left. `server.shutdown=immediate` closes
  everything right away.
- **A port in use** stops the application with Spring Boot's report:

  ```text
  Web server failed to start. Port 8080 was already in use.

  Action: Identify and stop the process that is listening on port 8080, or
  configure this application to listen on another port (server.port; 0 picks a free one).
  ```

- **No server:** `spring.main.web-application-type=none` keeps the beans
  (and `MockMvc`) but starts no server, e.g. for a command-line task of
  the same application.
- **TLS** with PEM files (`server.ssl.*`); `server.ssl.client-auth=need`
  asks for client certificates. HTTP/1.1 only (`dart:io` has no HTTP/2).

Change the settings in code with a `WebServerFactoryCustomizer` bean, or
replace the server entirely with your own `WebServerFactory` bean (the
default one backs off, `@ConditionalOnMissingBean`):

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
`ServerHttpRequest` / `ServerHttpResponse` of `spring_web_dart` and never
imports `dart:io`, so another server needs only a `WebServer` and its
factory. `MockMvc` is one more caller of the same `HttpHandler`.

### Handler mappings

The `dispatcherHandler` bean (Spring's `DispatcherServlet`) runs the
filters, then asks every `HandlerMapping` bean in order for a handler:
the controllers at order 0, the WebSocket endpoints of
`spring_boot_starter_websocket` at order 1. A starter (or the
application) adds its own by declaring a `HandlerMapping` bean:

```dart
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
Linux, in the main isolate with the same beans as the widgets (the I/O of
`HttpServer` is asynchronous and does not block the UI; move heavy
synchronous work into `Isolate.run`).

- **`127.0.0.1` by default:** an app opens no port to the network unless
  `server.address` says so.
- **In the background** the context pauses, so the server stops and frees
  the port, and starts again when the app comes back
  (`spring.flutter.lifecycle.pause-in-background`).
- **Platform permissions:** macOS needs the
  `com.apple.security.network.server` entitlement; Android needs
  `INTERNET` in the release manifest; on iOS, binding beyond localhost
  asks for local network access (`NSLocalNetworkUsageDescription`).
- **The web** has no server sockets: the application fails at startup
  with an error saying so. Use the clients (Feign, WebSocket) there.

## WebSocket endpoints

With [`spring_boot_starter_websocket`](../spring_boot_starter_websocket/README.md)
listed too, `@WebSocketEndpoint` beans and `WebSocketConfigurer` handlers
are served on the same port, through the same filters:

```dart
@WebSocketEndpoint('/ws/rooms/{room}')
class ChatEndpoint {
  @OnMessage()
  Ack message(@PathVariable() String room, ChatMessage message) => Ack(room);
}
```

See the WebSocket starter's *Server* section.

## Testing

`spring_boot_starter_test` calls the controllers in memory with
`MockMvc` (no socket; the same dispatcher, filters and error handling),
or starts a real server on a free port:

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
    final next = result.response.eventStream.firstWhere((e) => e.data != null);
    await app.mockMvc.post('/api/books', json: {'isbn': '5555', 'title': 'Vurt'});
    expect((await next).id, '5555');
    await result.cancel();
  });
}
```

`springBootTest(webEnvironment: WebEnvironment.randomPort)` starts the
real server on a free port (`app.localServerPort`), for a Feign client or
`dart:io`'s `HttpClient` against it. As a test class:
`@SpringBootTest(webEnvironment: ...)`, `@Autowired() late MockMvc mvc;`,
`@LocalServerPort() late int port;`. Everything about web tests is in
[docs/testing.md](../docs/testing.md#17-web-tests-mockmvc).

`ApplicationContextRunner` starts no server unless the test sets
`spring.test.web-environment=random-port`.

## How it works

`@GetMapping`, `@PostMapping`, ..., `@ExceptionHandler` are marked
`@BeanMethodAnnotation()` (from `spring_core_dart`): for a bean with such
methods the generator writes their description into the bean definition
(`BeanDefinition.annotatedMethods`: parameters with names, types and
annotations, the result type, an invoker), and introspects the parameter
and result types of the bean's package for JSON. At startup
`RequestMappingHandlerMapping` reads these descriptions, checks them and
builds the routes. Handlers are called on the bean as the context holds
it, so AOP advice on a controller (`@Cacheable`, method validation, later
`@PreAuthorize`) applies.

## Differences from Spring

- **Errors are always `ProblemDetail`** (`application/problem+json`).
  Spring Boot's default is the `/error` JSON
  (`timestamp`, `status`, `error`, `path`) unless
  `spring.mvc.problemdetails.enabled=true`; here there is no `/error`
  endpoint and no `ErrorController`.
- **`@ExceptionHandler([types])` matches exact runtime types** (Dart
  cannot test whether a `Type` is a subtype of another); subtypes match
  through the type of the exception parameter
  (`@ExceptionHandler() void on(StateError e)`).
- **`@ResponseStatus` goes on handler methods** (or the controller class),
  not on exception classes, whose annotations cannot be read at runtime:
  throw a `ResponseStatusException` or implement `ErrorResponse` instead.
- **Custom argument resolvers are asked before the built-in ones**
  (Spring asks them after), so a starter can take over any parameter
  (security's `@AuthenticationPrincipal`).
- **No `@ModelAttribute` and no form binding to objects**: a form body
  (`application/x-www-form-urlencoded`) is read only into a
  `@RequestBody() Map<String, String>`; `@RequestParam` reads the query
  string and the text fields of a multipart form (Spring also sees
  url-encoded form fields there).
- **Multipart without a servlet container:** the
  `spring.servlet.multipart.*` keys keep Boot's names; temporary files are
  this starter's own (`file-size-threshold` is `0B`: every file goes to
  disk). Only `multipart/form-data` parts are bound (no `multipart/mixed`
  for `@RequestPart`).
- **A declared `Stream<Uint8List>` / `Stream<List<int>>` result is raw
  bytes** (Spring MVC has no byte stream result; Spring WebFlux writes a
  `Flux<DataBuffer>` the same way). Other streams are server-sent events.
- **Resources: one byte range** per request (several are answered with
  the whole content, not `multipart/byteranges`); no `ETag` for resources.
- **Event streams start with a `:` comment line**, because `dart:io`
  sends the headers with the first body bytes.
- **HTTP/1.1 only**; `server.http2.enabled` is not read.
- **TLS from PEM file paths** (not `classpath:` locations, no keystores
  or SSL bundles).
- **More startup checks** than Spring: a path variable without a
  parameter, a parameter without a role, an invalid `@ExceptionHandler`.
- `server.max-http-request-body-size` and
  `spring.mvc.sse.heartbeat-interval` are this starter's own properties.
- `MockMvc` takes named expectations (`andExpect(status: 200, json: ...)`,
  matchers allowed) instead of `status().isOk()` and `jsonPath(...)`.

## Not yet

- `@ConditionalOnWebApplication`, test slices (`@WebMvcTest`).
- `ResponseBodyEmitter` (a `Stream<T>` result covers SSE and NDJSON),
  `HttpSession` (response cookies exist:
  `response.addCookie(ResponseCookie(...))`).
- Several byte ranges as `multipart/byteranges`, `ETag` for resources,
  `@RequestPart` with `multipart/mixed`.
- Static files (`lib/resources/static/`), forwarded headers
  (`server.forward-headers-strategy`), `spring.web.cors.*`,
  `server.max-http-request-header-size`.
- Flutter: a warning when a handler blocks the main isolate, decoding big
  JSON bodies in another isolate, the whole server in a background
  isolate (`server.isolate: background`).
- Other servers (`shelf`, Rust over FFI), STOMP, the actuator over HTTP,
  the security starter. See the [roadmap](../roadmap/spring_boot_starter_web.md).
