// In an application the starter is picked up automatically: add the
// dependency, describe the API as below and run the generator (it writes
// the implementation of CatalogClient). main() runs the parts that need no
// generated code.
import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_web_dart/testing.dart';

@FeignClient('catalog', url: r'${catalog.url}')
abstract interface class CatalogClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  @GetMapping('/books')
  Future<List<Book>> search(@RequestParam('q') String query);

  @PostMapping('/books')
  Future<ResponseEntity<Book>> create(@RequestBody() Book book);

  /// Server-sent events (`text/event-stream`): a `Stream<StockChange>`
  /// that reconnects by itself; `.events` adds id, event name and retry.
  @GetMapping('/stock/events')
  EventStream<StockChange> stock();
}

@Introspected()
class Book {
  const Book({required this.isbn, required this.title});
  final String isbn;
  final String title;
}

class StockChange {
  const StockChange({required this.isbn, required this.copies});
  final String isbn;
  final int copies;
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

  /// Prints stock changes as they arrive (cancel the subscription to
  /// close the connection).
  StreamSubscription<StockChange> watchStock() => catalog.stock().listen(
    (change) => print('${change.isbn}: ${change.copies} left'),
  );
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
  print(template.headers[HttpHeaders.authorizationHeader]); // Bearer secret

  // The pauses of the default retryer.
  const retryer = DefaultRetryer(maxAttempts: 3);
  final error = RetryableException(-1, 'connection reset');
  print([
    retryer.nextDelay(1, error),
    retryer.nextDelay(2, error),
    retryer.nextDelay(3, error),
  ]); // [0:00:00.100000, 0:00:00.150000, null]

  // What an EventStream method does under the hood: read the event
  // stream, reconnect with Last-Event-ID, stop on 204.
  final server = MockHttpTransport()
    ..when(HttpMethod.get, '/stock/events').respondEvents([
      ServerSentEvent({'isbn': '978-0', 'copies': 4}, id: '1'),
      ServerSentEvent({'isbn': '978-1', 'copies': 0}, id: '2'),
    ])
    ..when(HttpMethod.get, '/stock/events').respond(204);
  final stock = EventStream<String>(
    () => connectServerSentEvents(
      (lastEventId) => server.stream(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('https://api.neon.books/stock/events'),
          headers: HttpHeaders({'Last-Event-ID': ?lastEventId}),
        ),
      ),
      reconnect: const SseReconnect(delay: Duration(milliseconds: 10)),
    ),
  );
  await for (final data in stock) {
    print(
      data,
    ); // {"isbn":"978-0","copies":4}, then {"isbn":"978-1","copies":0}
  }
  print(server.requests.last.headers['Last-Event-ID']); // 2
}
