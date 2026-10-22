// A tiny catalog service on a local port, for the Feign client of the tour
// (VM only: dart:io).
import 'dart:convert';
import 'dart:io';

/// Serves `/books/{isbn}`, `/books?q=`, `POST /books` and a failing
/// `/motd` on `http://127.0.0.1:<port>`.
class DemoCatalogServer {
  DemoCatalogServer._(this._server);

  final HttpServer _server;

  static final _books = <String, Map<String, Object?>>{
    '978-0': {
      'isbn': '978-0',
      'title': 'Dune',
      'author': {'name': 'Frank Herbert'},
    },
    '978-1': {
      'isbn': '978-1',
      'title': 'Dune Messiah',
      'author': {'name': 'Frank Herbert'},
    },
  };

  /// Starts the server on a free port.
  static Future<DemoCatalogServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    return DemoCatalogServer._(server);
  }

  /// The base URL.
  String get url => 'http://127.0.0.1:${_server.port}';

  /// Requests served so far.
  static int requests = 0;

  /// Stops the server.
  Future<void> close() => _server.close(force: true);

  static Future<void> _handle(HttpRequest request) async {
    requests++;
    final response = request.response;
    final path = request.uri.path;
    void json(int status, Object? body) {
      response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
    }

    if (request.method == 'GET' && path.startsWith('/books/')) {
      final book = _books[path.substring('/books/'.length)];
      book == null ? json(404, {'error': 'no such book'}) : json(200, book);
    } else if (request.method == 'GET' && path == '/books') {
      final query = (request.uri.queryParameters['q'] ?? '').toLowerCase();
      json(200, [
        for (final book in _books.values)
          if ((book['title']! as String).toLowerCase().contains(query)) book,
      ]);
    } else if (request.method == 'POST' && path == '/books') {
      final book = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      _books[book['isbn']! as String] = book;
      response.headers.set('Location', '/books/${book['isbn']}');
      json(201, book);
    } else {
      json(500, {'error': 'motd service is down'});
    }
    await response.close();
  }
}
