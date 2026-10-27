// Chapter 2, "State in beans": the basket, the catalog and the session are
// beans the widgets share; a widget rebuilds only when it read the state
// that changed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/app/home_page.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/basket/basket.dart';
import 'package:neon_books_app/src/basket/basket_badge.dart';
import 'package:neon_books_app/src/catalog/book_tile.dart';
import 'package:neon_books_app/src/catalog/catalog_page.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart'
    show HttpMethod;
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

void main() {
  final server = FakeServer();
  final app = springBootTest(springApplication, overrides: server.overrides);

  setUp(() {
    app.markDirty(); // a fresh basket and catalog for every test
    server.http.reset();
    server.answerCatalog();
  });

  testWidgets('a book added from the list: only the badge rebuilds', (
    tester,
  ) async {
    await showPage(tester, app.context, const HomePage());
    expect(find.text('Dune'), findsOneWidget);

    final rebuilt = await rebuiltBy(() async {
      await tester.tap(find.byTooltip('Add to basket').first);
      await tester.pump();
    });

    // The badge read basket.count: rebuilt. The tile only called
    // basket.add, the page and the list read nothing of the basket.
    expect(rebuilt, contains(BasketBadge));
    expect(rebuilt, isNot(contains(BookTile)));
    expect(rebuilt, isNot(contains(CatalogList)));
    expect(rebuilt, isNot(contains(HomePage)));
    expect(
      find.descendant(of: find.byType(BasketBadge), matching: find.text('1')),
      findsOneWidget,
    );
    expect(app.getBean<Basket>().count, 1);
  });

  testWidgets('context.basket is the Basket bean', (tester) async {
    await showPage(tester, app.context, const HomePage());
    final context = tester.element(find.byType(CatalogPage));
    expect(context.basket, same(app.getBean<Basket>()));
    expect(context.bean<Basket>(), same(context.basket));
  });

  testWidgets('a search rebuilds the list, not the page with the field', (
    tester,
  ) async {
    server.http
        .when(HttpMethod.get, '/api/books?q=dune&page=0')
        .respond(
          200,
          json: {
            'items': [books.first],
            'page': 0,
            'size': 20,
            'total': 1,
          },
        );
    await showPage(tester, app.context, const HomePage());
    await tester.enterText(find.byKey(const Key('catalog-search')), 'dune');

    final rebuilt = await rebuiltBy(() async {
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    });

    expect(find.text('Cosmos'), findsNothing);
    expect(find.text('Dune'), findsOneWidget);
    expect(rebuilt, contains(CatalogList));
    expect(rebuilt, isNot(contains(CatalogPage)));
    expect(server.http.lastRequest.url.queryParameters, {
      'q': 'dune',
      'page': '0',
    });
  });

  testWidgets('the basket screen follows the bean, whoever changes it', (
    tester,
  ) async {
    await showPage(tester, app.context, const HomePage());
    await tester.tap(find.text('Basket'));
    await tester.pumpAndSettle();
    expect(find.text('The basket is empty'), findsOneWidget);

    // A service (here the test) changes the bean: the screen follows.
    final basket = app.getBean<Basket>();
    await tester.runAsync(
      () => basket.add(
        const Book(isbn: '9780441013593', title: 'Dune', price: 12.5),
      ),
    );
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('25.00'), findsNothing);

    await tester.tap(find.byTooltip('One more'));
    await tester.pump();
    expect(find.text('25.00'), findsOneWidget);
    expect(basket.count, 2);
  });
}
