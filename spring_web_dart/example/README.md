# spring_web_dart: example

[`example.dart`](example.dart) shows the parts of `spring_web_dart` that
work on their own, without a Spring application:

1. the **mapping annotations** on an interface, as a Feign client
   carries them;
2. a real HTTP request sent with the **platform transport** to a small
   local server;
3. **`MockHttpTransport`** answering the same kind of request in a test,
   without any server.

No code generation is needed for this package alone. Feign clients and
controllers, which read the annotations, need
`spring_core_dart_generator`.

```yaml
dependencies:
  spring_web_dart: ^0.4.2
```

## Run it

From the `spring_web_dart` directory:

```sh
dart run example/example.dart
```

It logs through a `SpringLog` named `example`
(`const log = SpringLog('example')`, set to `info` in `main` because
without an application only warnings show):

```text
[example] INFO: 200 {"isbn":"978-0","title":"Dune"}
[example] INFO: {"isbn":"1"}, Not Found
```

## 1. Describe an API with annotations

The annotations say which HTTP call each method stands for. Here they
sit on a plain interface; with `@FeignClient` from
`spring_boot_starter_feign` on the class, the generator turns it into a
working HTTP client, and a `@RestController` uses the same annotations
to answer the calls.

```dart
abstract interface class CatalogApi {
  // GET /books/978-0
  @GetMapping('/books/{isbn}')
  Future<Map<String, Object?>> find(@PathVariable('isbn') String isbn);

  // POST /books with a JSON body and a request id header.
  @PostMapping.of(path: '/books', consumes: MediaType.applicationJson)
  Future<ResponseEntity<Map<String, Object?>>> create(
    @RequestBody() Map<String, Object?> book,
    @RequestHeader('X-Request-Id') String requestId,
  );
}
```

## 2. Send a request yourself

The example starts a `dart:io` server on a free local port that stands
in for a real API, then sends it a request.
`platformHttpTransport()` uses `dart:io` here and the browser's `fetch`
on the web. Every status code comes back as a response; only network
failures and timeouts throw.

```dart
final transport = platformHttpTransport(
  connectTimeout: const Duration(seconds: 3),
);
final response = await transport.send(
  HttpRequest(
    method: HttpMethod.get,
    url: Uri.parse('http://127.0.0.1:${server.port}/books/978-0'),
    headers: HttpHeaders({
      HttpHeaders.acceptHeader: MediaType.applicationJson,
    }),
    timeout: const Duration(seconds: 5), // the whole exchange
  ),
);
log.info('${response.statusCode} ${response.bodyText}');
// 200 {"isbn":"978-0","title":"Dune"}
transport.close();
```

## 3. Fake the server in tests

`MockHttpTransport` answers with responses prepared in advance and
records what was sent, so a test of code that calls a service needs no
network. In a Spring Boot application, `spring_boot_starter_test`
exports it, and `BeanOverride<HttpTransport>(mock)` puts it under the
Feign clients.

```dart
import 'package:spring_web_dart/testing.dart';

final mock = MockHttpTransport()
  ..when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1'})
  ..when(HttpMethod.get, '/books/2').respond(HttpStatus.notFound);

final missing = await mock.send(
  HttpRequest(method: HttpMethod.get, url: Uri.parse('https://api/books/2')),
);
HttpStatus.valueOf(missing.statusCode).reasonPhrase; // 'Not Found'
```

The package [README](https://pub.dev/packages/spring_web_dart) explains
every part: the annotations, the HTTP types, server-sent events,
WebSockets and the server-side interfaces.
