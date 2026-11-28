// RestClient in a Spring Boot application: an HTTP service interface
// (`BookService`), which the generator implements with calls of the
// RestClient of the group `catalog` (set by
// `spring.http.serviceclient.catalog.*`), and a service that builds its
// own client from the RestClientBuilder bean. The generator picks the
// starter up (example.spring.dart, from `dart run build_runner build`);
// JSON goes through the ObjectMapper, error statuses become
// RestClientResponseExceptions, and the catalog's host is allowed because
// it is the group's base URL (every other address is denied).
//
//   dart run example/example.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

import 'spring_gen/example.spring.dart';

@Introspected()
class Book {
  const Book({required this.isbn, required this.title});
  final String isbn;
  final String title;
}

/// The catalog's API: the generator writes the class that calls it, a bean
/// once `@ImportHttpServices` (on `main`) imports it.
@HttpExchange('/books')
abstract interface class BookService {
  /// `GET /books/{isbn}`.
  @GetExchange('/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  /// `GET /books?q=...`.
  @GetExchange()
  Future<List<Book>> search(@RequestParam() String q);
}

/// The catalog, on its HTTP service.
@Service()
class Catalog {
  Catalog(this.books);

  final BookService books;

  /// The book, or `null` when the catalog answers 404.
  Future<Book?> find(String isbn) async {
    try {
      return await books.find(isbn);
    } on HttpClientErrorException catch (error) {
      if (error.statusCode == HttpStatus.notFound) {
        return null;
      }
      rethrow;
    }
  }

  /// The books whose title holds [query].
  Future<List<Book>> search(String query) => books.search(query);
}

/// Reads from the catalog once the application has started and logs what
/// it got; `@Log` gives it the `log` getter.
@Component()
@Log(topic: 'example')
class ShopTour implements CommandLineRunner {
  ShopTour(this.catalog, this.builder);

  final Catalog catalog;

  /// A new builder of its own, set up from `spring.http.clients.*`.
  final RestClientBuilder builder;

  @override
  Future<void> run(List<String> args) async {
    final dune = await catalog.find('978-0');
    final missing = await catalog.find('404');
    final isbns = [for (final book in await catalog.search('du')) book.isbn];
    log
      ..info('title: ${dune?.title}') // title: Dune
      ..info('title: ${missing?.title}') // title: null
      ..info('search: $isbns'); // search: [978-0]
    // Not on the allow list: denied before anything is sent.
    try {
      await builder
          .build()
          .get()
          .uri('http://169.254.169.254/latest')
          .retrieve()
          .body<String>();
    } on ResourceAccessException catch (error) {
      log.info('denied: ${error.isRetryable ? 'retryable' : 'for good'}');
    }
  }
}

@SpringBootApplication()
@ImportHttpServices(group: 'catalog', types: [BookService])
Future<void> main(List<String> args) async {
  final server = await _catalogServer();
  final context = await springApplication.runAsync(
    args,
    properties: {
      'spring.http.serviceclient.catalog.base-url':
          'http://127.0.0.1:${server.port}',
    },
  );

  await context.closeAsync();
  await server.close(force: true);
}

/// A local server standing in for the real catalog.
Future<io.HttpServer> _catalogServer() async {
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    void json(Object body) => response
      ..headers.contentType = io.ContentType.json
      ..write(jsonEncode(body));
    switch (request.uri.path) {
      case '/books/978-0':
        json({'isbn': '978-0', 'title': 'Dune'});
      case '/books':
        json([
          {'isbn': '978-0', 'title': 'Dune'},
        ]);
      default:
        response.statusCode = io.HttpStatus.notFound;
    }
    await response.close();
  });
  return server;
}
