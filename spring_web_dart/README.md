# spring_web_dart

Spring's `spring-web` for Dart: the **request mapping annotations**
(`@GetMapping`, `@PostMapping`, `@PathVariable`, `@RequestParam`,
`@RequestHeader`, `@RequestBody`), **HTTP types** (`ResponseEntity`,
`HttpHeaders`, `HttpStatus`, `HttpMethod`, `MediaType`) and an **HTTP client
transport** for the VM, Flutter and the web. Only `spring_core_dart` as a
dependency.

The annotations are read by Feign clients
([`spring_boot_starter_feign`](https://pub.dev/packages/spring_boot_starter_feign)):
an annotated interface becomes an injectable HTTP client. The coming web
server will use the same annotations on controllers.

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
| your own | e.g. on Dio or `package:http` | implement `HttpTransport` (two methods) |

`IoHttpTransport` follows redirects for `GET` and `HEAD` and aborts the
request when its timeout runs out. `FetchHttpTransport` follows redirects
and aborts through an `AbortController`; on the web the server must allow
the request (CORS) — a blocked request is an `HttpTransportException`.

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
