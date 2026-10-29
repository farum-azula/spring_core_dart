// Chapter 6, "Server access": the Feign clients and the WebSocket client
// against the server's API, played by a MockHttpTransport and a
// MockWebSocketTransport (no server needed). The session transport below
// the clients keeps the cookies and sends the CSRF token.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/admin/admin_page.dart';
import 'package:neon_books_app/src/admin/admin_service.dart';
import 'package:neon_books_app/src/api/catalog_client.dart';
import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:neon_books_app/src/app/home_page.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/basket/basket.dart';
import 'package:neon_books_app/src/catalog/book_page.dart';
import 'package:neon_books_app/src/orders/order_service.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart'
    show
        FeignNotFound,
        HttpHeaders,
        HttpMethod,
        HttpResponse,
        HttpTransportException,
        ServerSentEvent;
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart'
    show LogBuffer, SecurityContextHolder;
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

void main() {
  final server = FakeServer();
  final app = springBootTest(springApplication, overrides: server.overrides);

  setUp(() {
    app.markDirty(); // no session, no basket, empty caches
    server.http.reset();
    server.answerCatalog();
  });
  tearDown(SecurityContextHolder.clearContext);

  group('Feign clients', () {
    test('a page of the catalog: query parameters and JSON', () async {
      server.http
        ..reset()
        ..when(HttpMethod.get, '/api/books?q=dune&page=1').respond(
          200,
          json: {
            'items': [books.first],
            'page': 1,
            'size': 1,
            'total': 2,
          },
        );
      server.answerCatalog();

      final page = await app.getBean<CatalogClient>().page(
        query: 'dune',
        page: 1,
      );

      expect(page.items.single.title, 'Dune');
      expect(page.items.single.price, 12.5);
      expect(page.pages, 2);
      final request = server.http.lastRequest;
      expect(
        request.url.toString(),
        'http://localhost:8080/api/books?q=dune&page=1',
      );
      expect(request.headers['Accept'], 'application/json');
    });

    test('a lost connection is tried again (Retryer)', () async {
      server.http
        ..reset()
        ..when(
          HttpMethod.get,
          '/api/books/9780441013593',
        ).fail(HttpTransportException('connection reset'))
        ..when(
          HttpMethod.get,
          '/api/books/9780441013593',
        ).respond(200, json: books.first);

      final book = await app.getBean<CatalogClient>().find('9780441013593');

      expect(book.title, 'Dune');
      expect(server.http.requests, hasLength(2));
    });

    test('a 404 is a FeignNotFound', () async {
      server.http
          .when(HttpMethod.get, '/api/books/0')
          .respond(
            404,
            json: {'status': 404, 'detail': 'No book 0'},
            headers: {'Content-Type': 'application/problem+json'},
          );
      await expectLater(
        app.getBean<CatalogClient>().find('0'),
        throwsA(isA<FeignNotFound>()),
      );
    });
  });

  group('the session', () {
    test('cookies kept, the CSRF token sent with a POST and a PUT', () async {
      server.answerLogin('ada');
      server.http
          .when(HttpMethod.put, '/api/basket/items/9780441013593')
          .respond(204);

      await app.getBean<Session>().login('ada', 'ada-secret');
      await pumpEventQueue(); // the basket's @EventListener
      await app.getBean<Basket>().add(
        const Book(isbn: '9780441013593', title: 'Dune'),
      );

      final [probe, login, me, basket, put] = server.http.requests;
      // No token yet: a GET brings the XSRF-TOKEN cookie.
      expect(probe.url.path, '/api/me');
      expect(probe.headers['Cookie'], isNull);
      // The form login sends it back as a header.
      expect(login.method, HttpMethod.post);
      expect(login.headers['X-XSRF-TOKEN'], 'token-1');
      expect(
        login.headers['Content-Type'],
        startsWith('application/x-www-form-urlencoded'),
      );
      expect(utf8.decode(login.body!), 'username=ada&password=ada-secret');
      // From then on the session cookie, and the new token.
      expect(me.headers['Cookie'], 'XSRF-TOKEN=token-2; JSESSIONID=session-1');
      expect(basket.url.path, '/api/basket');
      expect(put.method, HttpMethod.put);
      expect(put.headers['X-XSRF-TOKEN'], 'token-2');
      expect(put.headers['Cookie'], contains('JSESSIONID=session-1'));
      expect(jsonDecode(utf8.decode(put.body!)), {'quantity': 1});
    });

    test('logout forgets the cookies', () async {
      server.answerLogin('ada');
      final session = app.getBean<Session>();
      await session.login('ada', 'ada-secret');
      await session.logout();

      expect(server.http.lastRequest.url.path, '/api/logout');
      expect(app.getBean<CookieJar>().header, isNull);
    });
  });

  test('ResponseEntity: the order and its Location', () async {
    server.answerLogin('ada');
    server.http
        .when(HttpMethod.post, '/api/orders')
        .respond(
          201,
          json: {
            'id': 7,
            'user': 'ada',
            'lines': [
              {'isbn': '9780441013593', 'title': 'Dune', 'quantity': 1},
            ],
            'total': 12.5,
          },
          headers: {'Location': '/api/orders/7'},
        );
    await app.getBean<Session>().login('ada', 'ada-secret');

    final order = await app.getBean<OrderService>().placeOrder();

    expect(order.id, 7);
    expect(order.lines.single.title, 'Dune');
    final placed = app.getBean<LogBuffer>().records.lastWhere(
      (record) => record.message == 'order placed',
    );
    expect(placed.fields, {'order': 7, 'location': Uri.parse('/api/orders/7')});
  });

  test('multipart: a cover upload', () async {
    server.answerLogin('root', roles: ['USER', 'ADMIN']);
    server.http
        .when(HttpMethod.put, '/api/books/9780441013593/cover')
        .respond(204);
    await app.getBean<Session>().login('root', 'root-secret');

    await app.getBean<AdminService>().uploadCover(
      '9780441013593',
      FakeServer.cover,
    );

    final upload = server.http.lastRequest;
    expect(upload.headers['Content-Type'], startsWith('multipart/form-data'));
    final body = latin1.decode(upload.body!);
    expect(body, contains('name="file"; filename="9780441013593.png"'));
    expect(body, contains('Content-Type: image/png'));
  });

  testWidgets('EventStream: the stock changes as they come', (tester) async {
    server.http.reset();
    server.answerCatalog(
      stockEvents: [
        ServerSentEvent({'isbn': '9780441013593', 'available': 2}, id: '1'),
        ServerSentEvent({'isbn': '9780345539434', 'available': 0}, id: '2'),
      ],
    );
    await showPage(tester, app.context, const HomePage());

    await tester.tap(find.text('Live stock'));
    await tester.pumpAndSettle();

    expect(find.text('Live: changes appear as they happen'), findsOneWidget);
    expect(find.text('2 left'), findsOneWidget);
    expect(find.text('0 left'), findsOneWidget);
    // The book screen shows the newest number.
    await tester.tap(find.text('Catalog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    expect(find.text('2 in stock'), findsOneWidget);
  });

  testWidgets('FeignNotFound: an unknown book', (tester) async {
    server.http
      ..when(HttpMethod.get, '/api/books/0').respond(404)
      ..when(HttpMethod.get, '/api/books/0/cover').respond(404);
    await showPage(tester, app.context, const BookPage('0'));
    expect(find.text('There is no book 0'), findsOneWidget);
  });

  testWidgets('WebSocket: the support chat, with the session cookie', (
    tester,
  ) async {
    server.answerLogin('ada');
    await showPage(tester, app.context, const HomePage());
    await logIn(tester, 'ada', 'ada-secret');
    await openMore(tester, 'Support');

    final socket = (await tester.runAsync(
      () => server.sockets.nextConnection,
    ))!;
    expect(socket.uri.toString(), 'ws://localhost:8080/ws/support');
    expect(socket.headers['Cookie'], contains('JSESSIONID=session-1'));

    socket.pushJson({'from': 'neon-bot', 'text': 'Hello! How can I help?'});
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Hello! How can I help?'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('chat-text')),
      'Where is Dune?',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Where is Dune?'), findsOneWidget);
    expect(socket.sentJson.single, containsPair('text', 'Where is Dune?'));
    expect(socket.sentJson.single, containsPair('from', 'ada'));

    // A logout closes the socket: the next user gets a new handshake.
    await tester.runAsync(() async {
      await app.getBean<Session>().logout();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpAndSettle();
    expect(socket.closedByClient, isTrue);
    expect(find.text('Log in to chat with us'), findsOneWidget);
  });

  testWidgets("ProblemDetail: the server's field errors in the Admin form", (
    tester,
  ) async {
    server.answerLogin('root', roles: ['USER', 'ADMIN']);
    server.http
        .when(HttpMethod.post, '/api/books')
        .respondWith(
          (request) => HttpResponse(
            400,
            headers: HttpHeaders({'Content-Type': 'application/problem+json'}),
            body: utf8.encode(
              jsonEncode({
                'type': 'about:blank',
                'title': 'Bad Request',
                'status': 400,
                'errors': [
                  {'field': 'isbn', 'message': 'ISBN 9780441013593 exists'},
                ],
              }),
            ),
          ),
        );
    await showPage(tester, app.context, const HomePage());
    await logIn(tester, 'root', 'root-secret');
    await openMore(tester, 'Admin');

    await tester.enterText(
      find.byKey(const Key('admin-isbn')),
      '9780441013593',
    );
    await tester.enterText(find.byKey(const Key('admin-title')), 'Dune');
    await tester.enterText(find.byKey(const Key('admin-author')), 'Herbert');
    await tester.enterText(find.byKey(const Key('admin-price')), '12.5');
    await tester.tap(find.text('Add the book'));
    await tester.pumpAndSettle();

    expect(find.byType(AdminPage), findsOneWidget);
    expect(find.text('ISBN 9780441013593 exists'), findsOneWidget);
    final sent = jsonDecode(utf8.decode(server.http.lastRequest.body!));
    expect(sent, {
      'author': 'Herbert',
      'isbn': '9780441013593',
      'price': 12.5,
      'title': 'Dune',
    });
  });
}
