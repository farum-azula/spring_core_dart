// In an application the starter is picked up automatically: add the
// dependency, describe the API as below and run the generator (it writes
// the implementation of CatalogClient). main() runs the parts that need no
// generated code.
import 'dart:convert';

import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

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

@Service()
class Shop {
  Shop(this.catalog);
  final CatalogClient catalog;

  Future<String?> title(String isbn) async {
    try {
      return (await catalog.find(isbn)).title;
    } on FeignNotFound {
      return null;
    }
  }
}

Future<void> main() async {
  // How an error response becomes an exception.
  final notFound = FeignException.errorStatus(
    'CatalogClient#find(String)',
    HttpResponse(
      404,
      body: utf8.encode('no such book'),
      request: HttpRequest(
        method: HttpMethod.get,
        url: Uri.parse('https://api.neon.books/books/1'),
      ),
    ),
  );
  print(notFound.runtimeType); // FeignNotFound

  // An interceptor adding a token to a request.
  final template = RequestTemplate(
    method: HttpMethod.get,
    url: Uri.parse('https://api.neon.books/books/1'),
    methodKey: 'CatalogClient#find(String)',
    clientName: 'catalog',
  );
  await BearerTokenRequestInterceptor(() => 'secret').apply(template);
  print(template.headers[HttpHeaders.authorization]); // Bearer secret

  // The pauses of the default retryer.
  const retryer = DefaultRetryer(maxAttempts: 3);
  final error = RetryableException(-1, 'connection reset');
  print([
    retryer.nextDelay(1, error),
    retryer.nextDelay(2, error),
    retryer.nextDelay(3, error),
  ]); // [0:00:00.100000, 0:00:00.150000, null]
}
