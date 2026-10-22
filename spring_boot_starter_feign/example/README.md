# spring_boot_starter_feign: examples

**What it does:** turns an abstract class with `@GetMapping`,
`@PostMapping`, ... into an HTTP client bean of a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) app. You
write the interface; the generator writes the implementation.

## Setup

```yaml
dependencies:
  spring_boot_dart: ^0.1.0
  spring_boot_starter_feign: ^0.1.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0   # required: writes the client implementations
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

## 5. Test without a server

```dart
final server = MockHttpTransport();               // package:spring_web_dart/testing.dart
final app = springBootTest(springApplication,
    overrides: [BeanOverride<HttpTransport>(server)]);

test('reads a book', () async {
  server.when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1', 'title': 'Dune'});
  expect(await app.getBean<Shop>().title('1'), 'Dune');
});
```

[`example.dart`](example.dart) runs the pieces that need no generated code
(errors, retries, interceptors). Everything else — configuration, retries,
fallbacks, logging: the package
[README](https://pub.dev/packages/spring_boot_starter_feign).
