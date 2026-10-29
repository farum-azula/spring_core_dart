import 'dart:io';
import 'dart:typed_data';

import 'package:neon_books_app/main.spring.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

/// The books of the fake server.
const books = [
  {
    'isbn': '9780441013593',
    'title': 'Dune',
    'author': 'Frank Herbert',
    'price': 12.5,
    'available': 3,
  },
  {
    'isbn': '9780345539434',
    'title': 'Cosmos',
    'author': 'Carl Sagan',
    'price': 15.0,
    'available': 1,
  },
  {
    'isbn': '9780486456768',
    'title': 'Leaves of Grass',
    'author': 'Walt Whitman',
    'price': 8.0,
    'available': 0,
  },
];

/// The server guide's API, played in memory: a `MockHttpTransport` for
/// the REST calls and a `MockWebSocketTransport` for the support chat.
/// No server is needed; the tests replace the app's network with these.
class FakeServer {
  FakeServer() {
    answerCatalog();
  }

  final http = MockHttpTransport();
  final sockets = MockWebSocketTransport();

  /// What `springBootTest(overrides:)` takes: the network below the app's
  /// session transport (the bean `networkTransport`), and the sockets.
  List<BeanOverride<Object>> get overrides => [
    BeanOverride<HttpTransport>(http, name: 'networkTransport'),
    BeanOverride<WebSocketTransport>(sockets),
  ];

  /// [overrides] for the web app (the `web` profile) on [page]: there the
  /// starter's `httpTransport` sends the requests, the browser's `fetch`
  /// with the CSRF token of the page's cookie; here the CSRF token goes on
  /// to the fake network.
  List<BeanOverride<Object>> webOverrides(BrowserPage page) => [
    BeanOverride<HttpTransport>(
      CsrfCookieHttpTransport(
        http,
        page: page,
        server: Uri.parse('http://localhost:8080'),
      ),
      name: 'httpTransport',
    ),
    BeanOverride<BrowserPage>(page),
    BeanOverride<WebSocketTransport>(sockets),
  ];

  /// The app as `flutter run` starts it (for `SpringApplicationWidget`),
  /// with [overrides] applied like `springBootTest` does.
  SpringApplication application() {
    final app = springApplication;
    return SpringApplication(
      app.modules,
      autoConfigurations: app.autoConfigurations,
      autoConfigurationMetadata: app.autoConfigurationMetadata,
      dartDefines: app.dartDefines,
      fingerprint: app.fingerprint,
      initializers: [
        ...app.initializers,
        ApplicationContextInitializer.of(
          (context) => context.addBeanFactoryPostProcessor(
            BeanOverrideProcessor(overrides),
          ),
        ),
      ],
    );
  }

  /// The anonymous catalog: one page of [books] (whatever the query),
  /// each book, the covers, and [stockEvents] (then the stream stays
  /// open). A test's own answer to the same request goes before this:
  /// the first unused answer wins, the last one repeats.
  void answerCatalog({List<ServerSentEvent<Object?>> stockEvents = const []}) {
    http
      ..when(HttpMethod.get, '/api/books').respond(
        200,
        json: {'items': books, 'page': 0, 'size': 20, 'total': books.length},
      )
      ..when(
        HttpMethod.get,
        '/api/stock/events',
      ).respondEvents(stockEvents, keepOpen: true);
    for (final book in books) {
      http
        ..when(
          HttpMethod.get,
          '/api/books/${book['isbn']}',
        ).respond(200, json: book)
        ..when(
          HttpMethod.get,
          '/api/books/${book['isbn']}/cover',
        ).respond(200, bytes: cover, headers: {'Content-Type': 'image/png'});
    }
  }

  /// A login of [user] with [roles] (`USER`, `ADMIN`): the CSRF probe,
  /// the form login with a session cookie, `/api/me`, the empty basket.
  void answerLogin(String user, {List<String> roles = const ['USER']}) {
    http
      ..when(HttpMethod.get, '/api/me').respondWith(
        (request) => request.headers['Cookie']?.contains('JSESSIONID') ?? false
            ? HttpResponse(
                200,
                headers: HttpHeaders({'Content-Type': 'application/json'}),
                body: '{"name": "$user", "roles": ${_json(roles)}}'.codeUnits,
              )
            : HttpResponse(
                401,
                headers: HttpHeaders()
                  ..add('Set-Cookie', 'XSRF-TOKEN=token-1; Path=/'),
              ),
      )
      ..when(HttpMethod.post, '/api/login').respondWith(
        (request) => HttpResponse(
          204,
          headers: HttpHeaders()
            ..add('Set-Cookie', 'JSESSIONID=session-1; Path=/; HttpOnly')
            ..add('Set-Cookie', 'XSRF-TOKEN=token-2; Path=/'),
        ),
      )
      ..when(HttpMethod.get, '/api/basket').respond(200, json: {'items': []})
      ..when(HttpMethod.post, '/api/logout').respond(204);
  }

  static String _json(List<String> values) =>
      '[${values.map((value) => '"$value"').join(', ')}]';

  /// The sample cover's bytes (a real PNG).
  static final Uint8List cover = File('assets/images/sample_cover.png')
      .readAsBytesSync();
}
