// The app against the real server guide (example/server_guide), over real
// sockets: the contract of the two guides (README "API") checked end to
// end. Tagged `e2e`: it needs the server running.
//
//   (cd ../server_guide && dart run bin/main.dart) &
//   flutter test --tags e2e
//
// E2E_API_HOST names another server (default localhost:8080).
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/admin/admin_service.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/basket/basket.dart';
import 'package:neon_books_app/src/catalog/catalog_service.dart';
import 'package:neon_books_app/src/orders/order_service.dart';
import 'package:neon_books_app/src/stock/live_stock.dart';
import 'package:neon_books_app/src/support/support_chat.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

const _dune = '9780441013593';

/// Waits (for real time) until [done] is true.
Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  // flutter_test answers every HttpClient with 400: this test talks to
  // a real server.
  setUpAll(() => HttpOverrides.global = null);

  final host = Platform.environment['E2E_API_HOST'] ?? 'localhost:8080';
  final app = springBootTest(springApplication, properties: {'api.host': host});

  tearDown(SecurityContextHolder.clearContext);

  test('the catalog, a book and its cover, anonymously', () async {
    final catalog = app.getBean<CatalogService>();
    final page = await catalog.page('', 0);
    expect(page.items.map((b) => b.isbn), contains(_dune));
    final dune = await catalog.find(_dune);
    expect(dune?.title, 'Dune');
    final cover = await catalog.cover(_dune);
    expect(cover, isNotNull);
    expect(cover!.take(4), [0x89, 0x50, 0x4E, 0x47]); // PNG
  });

  test('a wrong password is refused', () async {
    final session = app.getBean<Session>();
    await expectLater(session.login('ada', 'wrong'), throwsA(anything));
    expect(session.isLoggedIn, isFalse);
  });

  test(
    'a user logs in, fills the basket, orders, and is not an admin',
    () async {
      final session = app.getBean<Session>();
      await session.login('ada', 'ada-secret');
      expect(session.isLoggedIn, isTrue);
      expect(session.user, 'ada');
      expect(session.isAdmin, isFalse);

      final dune = (await app.getBean<CatalogService>().find(_dune))!;
      final basket = app.getBean<Basket>();
      await basket.setQuantity(_dune, 1, book: dune);
      final order = await app.getBean<OrderService>().placeOrder();
      expect(order.lines.map((l) => l.isbn), contains(_dune));

      await expectLater(
        app.getBean<AdminService>().deleteBook(_dune),
        throwsA(isA<AccessDeniedException>()),
      );
      await session.logout();
      expect(session.isLoggedIn, isFalse);
    },
  );

  test('an admin adds a book with a cover', () async {
    final session = app.getBean<Session>();
    await session.login('root', 'root-secret');
    expect(session.isAdmin, isTrue);
    final isbn = '978${DateTime.now().millisecondsSinceEpoch % 10000000000}'
        .padRight(13, '0')
        .substring(0, 13);
    final book = NewBook()
      ..isbn = isbn
      ..title = 'End to End'
      ..author = 'The Test'
      ..price = 9.5;
    final added = await app.getBean<AdminService>().addBook(book);
    expect(added.isbn, isbn);
    final png = await File('assets/images/sample_cover.png').readAsBytes();
    await app.getBean<AdminService>().uploadCover(isbn, png);
    await app.getBean<AdminService>().deleteBook(isbn);
    await session.logout();
  });

  test('live stock events arrive', () async {
    final stock = app.getBean<LiveStock>()..start();
    addTearDown(stock.stop);
    final session = app.getBean<Session>();
    await session.login('ada', 'ada-secret');
    final dune = (await app.getBean<CatalogService>().find(_dune))!;
    await app.getBean<Basket>().setQuantity(_dune, 1, book: dune);
    await app.getBean<OrderService>().placeOrder();
    await _until(() => stock.recent.isNotEmpty, 'a stock event');
    await session.logout();
  });

  test('the support chat answers a logged-in user', () async {
    final session = app.getBean<Session>();
    await session.login('ada', 'ada-secret');
    final chat = app.getBean<SupportChat>()..join();
    await chat.send('Hello');
    await _until(
      () => chat.messages.any((m) => m.from != 'ada' && m.from.isNotEmpty),
      'an answer of the support bot',
    );
    await session.logout();
  });
}
