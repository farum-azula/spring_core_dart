// A declarative HTTP client in a Spring Boot application: describe the API,
// the generator writes its implementation and picks the starter up
// (example.spring.dart, from `dart run build_runner build`). JSON goes
// through the ObjectMapper, error statuses become FeignExceptions.
//
//   dart run example/example.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

import 'example.spring.dart';

@FeignClient('catalog', url: r'${catalog.url}')
abstract interface class CatalogClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  @GetMapping('/books')
  Future<List<Book>> search(@RequestParam('q') String query);

  /// Server-sent events (`text/event-stream`): a stream that reconnects by
  /// itself with `Last-Event-ID` and ends when the server answers 204.
  @GetMapping('/stock/events')
  EventStream<StockChange> stock();
}

@Introspected()
class Book {
  const Book({required this.isbn, required this.title});
  final String isbn;
  final String title;
}

@Introspected()
class StockChange {
  const StockChange({required this.isbn, required this.copies});
  final String isbn;
  final int copies;
}

@Service()
class Shop {
  Shop(this.catalog);
  final CatalogClient catalog;

  /// The title, or `null` when the catalog answers 404.
  Future<String?> title(String isbn) async {
    try {
      return (await catalog.find(isbn)).title;
    } on FeignNotFound {
      return null;
    }
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final server = await _catalogServer();
  final context = springApplication.run(
    args,
    properties: {'catalog.url': 'http://127.0.0.1:${server.port}'},
  );
  final shop = context.getBean<Shop>();
  final catalog = context.getBean<CatalogClient>();

  print(await shop.title('978-0')); // Dune
  print(await shop.title('404')); // null
  print([for (final book in await catalog.search('du')) book.isbn]); // [978-0]
  await for (final change in catalog.stock()) {
    print('${change.isbn}: ${change.copies} left'); // 978-0: 4, 978-1: 0
  }

  await context.closeAsync();
  await server.close(force: true);
}

/// A local server standing in for the real catalog.
Future<io.HttpServer> _catalogServer() async {
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  var streamed = false;
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
      case '/stock/events' when !streamed:
        streamed = true;
        response
          ..headers.contentType = io.ContentType('text', 'event-stream')
          ..write('id: 1\ndata: {"isbn":"978-0","copies":4}\n\n')
          ..write('id: 2\ndata: {"isbn":"978-1","copies":0}\n\n');
      case '/stock/events':
        response.statusCode = io.HttpStatus.noContent; // no more events
      default:
        response.statusCode = io.HttpStatus.notFound;
    }
    await response.close();
  });
  return server;
}
