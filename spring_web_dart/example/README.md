# spring_web_dart: examples

**What it is:** the web part of Spring for Dart — the request mapping
annotations (`@GetMapping`, `@PathVariable`, `@RequestBody`, ...) that Feign
clients of `spring_boot_starter_feign` (and the coming web server) read,
`ResponseEntity`, `HttpHeaders`, `HttpStatus`, and an HTTP transport for
the VM, Flutter and the web. No code generation is needed for this package
alone; Feign clients need `spring_core_dart_generator`.

```yaml
dependencies:
  spring_web_dart: ^0.1.0
```

## 1. Describe an API with annotations

```dart
@FeignClient('catalog', url: r'${catalog.url}') // spring_boot_starter_feign
abstract interface class CatalogClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable('isbn') String isbn);

  @GetMapping('/books')
  Future<List<Book>> search(@RequestParam('q') String query);

  @PostMapping('/books')
  Future<ResponseEntity<Book>> create(
    @RequestBody() Book book,
    @RequestHeader('X-Request-Id') String requestId,
  );
}
```

## 2. Send a request yourself

```dart
final transport = platformHttpTransport();   // dart:io, or fetch on the web
final response = await transport.send(
  HttpRequest(
    method: HttpMethod.get,
    url: Uri.parse('https://api.neon.books/books/978-0'),
    headers: HttpHeaders({HttpHeaders.acceptHeader: MediaType.applicationJson}),
    timeout: const Duration(seconds: 5),
  ),
);
print('${response.statusCode} ${response.bodyText}');
```

## 3. Fake the server in tests

```dart
import 'package:spring_web_dart/testing.dart';

final transport = MockHttpTransport()
  ..when(HttpMethod.get, '/books/978-0').respond(200, json: {'isbn': '978-0'});
// Spring Boot test: BeanOverride<HttpTransport>(transport)
```

[`example.dart`](example.dart) runs all of this against a local server.
The full guide: the package [README](https://pub.dev/packages/spring_web_dart).
