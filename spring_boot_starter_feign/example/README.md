# spring_boot_starter_feign: examples

**What it does:** turns an abstract class with `@GetMapping`,
`@PostMapping`, ... into an HTTP client bean of a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) app. You
write the interface; the generator writes the implementation.

## Setup

```yaml
dependencies:
  spring_boot_starter_feign: ^0.4.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.0   # required: writes the client implementations
```

```bash
dart run build_runner build
```

## 1. Describe the API

```dart
@FeignClient('catalog', url: r'${catalog.url}')
abstract interface class CatalogClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  @GetMapping('/books')
  Future<List<Book>> search(@RequestParam('q') String query);

  @PostMapping('/books')
  Future<ResponseEntity<Book>> create(@RequestBody() Book book);

  @GetMapping('/stock/events')
  EventStream<StockChange> stock();    // server-sent events, see 5
}

@Introspected()
class Book {
  const Book({required this.isbn, required this.title});
  final String isbn;
  final String title;
}
```

```properties
# lib/resources/application.properties
catalog.url=https://api.neon.books
```

## 2. Inject it

```dart
@Service()
class Shop {
  Shop(this.catalog);
  final CatalogClient catalog;

  Future<String> title(String isbn) async => (await catalog.find(isbn)).title;
}
```

## 3. Handle errors

```dart
try {
  await catalog.find(isbn);
} on FeignNotFound {
  return null;
}
```

## 4. Add a token to every request

```dart
@Bean()
RequestInterceptor auth(TokenStore tokens) =>
    BearerTokenRequestInterceptor(() => tokens.accessToken);
```

## 5. Server-sent events

A method returning `EventStream<T>` reads a `text/event-stream` response.
`EventStream<T>` is a `Stream<T>` of the decoded data, so no wrapper type
in the usual case; the whole events (id, event name, retry) are in
`.events`. A lost connection is opened again with `Last-Event-ID`; a
`204` from the server ends the stream.

```dart
await for (final change in catalog.stock()) {
  print('${change.isbn}: ${change.copies} left');
}

catalog.stock().events.listen((e) => print('${e.id} ${e.event} ${e.data.copies}'));
```

```properties
spring.cloud.openfeign.client.config.catalog.event-stream.reconnect-delay=1s
```

Not in Spring: OpenFeign cannot stream; Spring reads events as
`Flux<ServerSentEvent<T>>` from `WebClient`.

## 6. Test without a server

```dart
final server = MockHttpTransport();               // from spring_boot_starter_test
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
    ..when(HttpMethod.get, '/stock/events').respond(204);   // ends the stream
  final changes = await app.getBean<CatalogClient>().stock().toList();
  expect(changes.single.copies, 3);
});
```

[`example.dart`](example.dart) is a Spring Boot application with the
client above against a local server: a book, a 404 as `null`, a search and
an event stream. Everything else — configuration, retries,
fallbacks, logging: the package
[README](https://pub.dev/packages/spring_boot_starter_feign).
