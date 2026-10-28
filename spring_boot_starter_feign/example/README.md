# spring_boot_starter_feign: examples

This starter turns an abstract class annotated with `@FeignClient`, whose
methods carry `@GetMapping`, `@PostMapping`, ..., into an HTTP client bean
of a [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
application. You write the interface; the generator writes the
implementation.

[`example.dart`](example.dart) is a small Spring Boot application: a shop
that reads books from a catalog service. It starts a local server standing
in for the catalog, then uses the client to read a book, turn a 404 into
`null`, search, and follow a stream of server-sent events.

## Run it

```yaml
dependencies:
  spring_boot_starter_feign: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2   # required: writes the client implementations
```

From the package directory, generate the code, then run the example:

```bash
dart run build_runner build
dart run example/example.dart
```

Among the startup log lines it prints:

```text
Dune
null
[978-0]
978-0: 4 left
978-1: 0 left
```

The sections below walk through the pieces.

## 1. Describe the API

One abstract method per endpoint. The mapping annotations say which
request to send; the return type says how to read the answer.

```dart
@FeignClient('catalog', url: r'${catalog.url}')
abstract interface class CatalogClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  // GET /books?q=...
  @GetMapping('/books')
  Future<List<Book>> search(@RequestParam('q') String query);

  @PostMapping('/books')
  Future<ResponseEntity<Book>> create(@RequestBody() Book book);

  // Server-sent events, see section 5.
  @GetMapping('/stock/events')
  EventStream<StockChange> stock();
}

@Introspected()                       // read from JSON without fromJson
class Book {
  const Book({required this.isbn, required this.title});
  final String isbn;
  final String title;
}
```

The URL comes from the configuration:

```properties
# lib/resources/application.properties
catalog.url=https://api.neon.books
```

The example overrides it at startup with the address of its local
server: `springApplication.run(args, properties: {'catalog.url': ...})`.

## 2. Inject it

The generated client is a bean; ask for the interface in a constructor.

```dart
@Service()
class Shop {
  Shop(this.catalog);
  final CatalogClient catalog;

  Future<String> title(String isbn) async => (await catalog.find(isbn)).title;
}
```

## 3. Handle errors

An error status throws a `FeignException` subclass, so you catch only
the cases you expect. In the example, a book the catalog does not know is
`null` for the shop:

```dart
try {
  return (await catalog.find(isbn)).title;
} on FeignNotFound {
  return null;
}
```

## 4. Add a token to every request

A `RequestInterceptor` bean changes every request before it is sent. This
one adds the user's token, asked again at every attempt so a refreshed
token is used:

```dart
@Bean()
RequestInterceptor auth(TokenStore tokens) =>
    BearerTokenRequestInterceptor(() => tokens.accessToken);
```

## 5. Server-sent events

A method returning `EventStream<T>` reads a `text/event-stream` response.
`EventStream<T>` is a `Stream<T>` of the decoded data, so the usual case
needs no wrapper type; the whole events (id, event name, retry) are in
`.events`. When the connection ends or breaks, the client connects again
and sends `Last-Event-ID`; a `204` from the server ends the stream. That
is how the example's stream ends: the local server sends two events, then
answers the reconnect with `204`.

```dart
await for (final change in catalog.stock()) {
  print('${change.isbn}: ${change.copies} left');
}

// With the event ids:
catalog.stock().events.listen((e) => print('${e.id} ${e.event} ${e.data.copies}'));
```

```properties
# Wait 1 second before reconnecting (3 seconds by default).
spring.cloud.openfeign.client.config.catalog.event-stream.reconnect-delay=1s
```

This is not in Spring: OpenFeign cannot stream, and Spring reads events
as `Flux<ServerSentEvent<T>>` from `WebClient`.

## 6. Test without a server

In tests, `MockHttpTransport` from `spring_boot_starter_test` replaces the
network and answers with prepared responses:

```dart
final server = MockHttpTransport();
final app = springBootTest(springApplication,
    overrides: [BeanOverride<HttpTransport>(server)]);

test('reads a book', () async {
  server.when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1', 'title': 'Dune'});
  expect(await app.getBean<Shop>().title('1'), 'Dune');
});

test('reads stock changes', () async {
  server
    ..when(HttpMethod.get, '/stock/events').respondEvents([
      ServerSentEvent({'isbn': '1', 'copies': 3}, id: '1'),
    ])
    ..when(HttpMethod.get, '/stock/events').respond(204);   // the reconnect ends the stream
  final changes = await app.getBean<CatalogClient>().stock().toList();
  expect(changes.single.copies, 3);
});
```

Everything else (configuration, retries, fallbacks, logging, multipart
uploads) is in the package
[README](https://pub.dev/packages/spring_boot_starter_feign).
