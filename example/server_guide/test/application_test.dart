// Chapter 1, the application and its beans: stereotypes, @Bean methods,
// injection styles, collections, @Primary / @Qualifier / @Fallback,
// lifecycle callbacks and runners.
@TestOn('vm')
library;

import 'package:neon_books_server/src/catalog/book_controller.dart';
import 'package:neon_books_server/src/catalog/book_repository.dart';
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/catalog/cover_store.dart';
import 'package:neon_books_server/src/orders/order_listeners.dart';
import 'package:neon_books_server/src/orders/order_service.dart';
import 'package:neon_books_server/src/shop/payments.dart';
import 'package:neon_books_server/src/shop/pricing.dart';
import 'package:neon_books_server/src/shop/startup.dart';
import 'package:neon_books_server/src/stock/restock_job.dart';
import 'package:neon_books_server/src/stock/stock_feed.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart'
    show RoleHierarchy;
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/main.spring.dart';
import 'support/app.dart';

void main() {
  group('the dev application', () {
    final app = neonBooks();

    test('stereotypes are beans under their type and interfaces', () {
      expect(app, hasSingleBean<CatalogService>());
      // @Repository InMemoryBookRepository, found by its interface.
      expect(app.getBean<BookRepository>(), isA<InMemoryBookRepository>());
      expect(app, hasBeanNamed('bookController'));
    });

    test('@Bean: lazy, an alias, an init method, a prototype', () {
      final factory = app.context.beanFactory;
      // Lazy: created on first use only (the first cover request).
      expect(factory.containsSingleton('coverStore'), isFalse);
      final covers = app.getBean<BookController>().covers.getObject();
      expect(covers.isOpen, isTrue); // initMethod: 'open'
      expect(app.context.getBeanByName('covers'), same(covers)); // alias
      // A prototype: a new builder for every lookup, here through the
      // @Lookup method of the abstract OrderMailer.
      final mailer = app.getBean<OrderMailer>();
      expect(mailer.newReceipt(), isNot(same(mailer.newReceipt())));
      // A static @Bean method (SecurityConfig.roleHierarchy).
      expect(app, hasSingleBean<RoleHierarchy>());
    });

    test('constructor, field and setter injection, @Value with SpEL', () {
      final orders = app.getBean<OrderService>();
      expect(orders.checkout, same(app.getBean<Checkout>())); // field
      expect(orders.shippingDelay, const Duration(milliseconds: 50));
      // #{shopProperties.name.toUpperCase()}
      expect(app.getBean<StartupAnnouncement>().banner, 'NEON BOOKS');
      // No bean or property for it: the Dart default value stays.
      expect(app.getBean<BookController>().recentLimit, 5);
      // A primary constructor (class StockReport(this._stock)).
      expect(app, hasSingleBean<StockReport>());
    });

    test('List and Map injection in @Order, the @Primary composite', () {
      final best = app.getBean<BestDiscount>();
      expect(best.rules.map((r) => r.runtimeType), [
        BulkDiscount,
        PoetryDiscount,
      ]); // @Order(1), @Order(2); never itself
      expect(best.rulesByName.keys, ['bulkDiscount', 'poetryDiscount']);
      expect(app.getBean<PriceRule>(), same(best)); // @Primary
    });

    test('the dev gateway; the fallback by @Qualifier', () {
      final checkout = app.getBean<Checkout>();
      expect(checkout.gateway, isA<SandboxGateway>()); // @Profile dev
      expect(checkout.backup, isA<OfflineGateway>()); // @Qualifier('offline')
    });

    test('a @Lazy reference to itself goes through the proxy', () {
      final catalog = app.getBean<Catalog>();
      expect(AopUtils.isAopProxy(catalog), isTrue);
      expect(AopUtils.getTarget(catalog), isA<CatalogService>());
      expect(catalog.get('9780441013593').title, 'Dune');
    });

    test('runners ran in @Order: sample data, then the announcement', () {
      expect(app.getBean<BookRepository>().count(), 8);
      final lines = app
          .getBean<LogBuffer>()
          .query(const LogQuery(logger: 'neon_books_server'))
          .map((r) => r.message)
          .toList();
      final loaded = lines.indexWhere((l) => l.contains('sample books'));
      final announced = lines.indexWhere((l) => l.contains('8 books'));
      expect(loaded, greaterThanOrEqualTo(0));
      expect(announced, greaterThan(loaded));
      // SmartInitializingSingleton ran before the runners.
      expect(
        lines.indexWhere((l) => l.contains('baskets up to 10 books')),
        lessThan(loaded),
      );
    });

    test('SmartLifecycle beans run while the context does', () {
      expect(app.getBean<StockFeed>().isRunning, isTrue);
    });
  });

  group('without a profile', () {
    final app = neonBooks(profiles: ['test']);

    test('the @Fallback gateway is the one injected', () {
      expect(app.getBean<Checkout>().gateway, isA<OfflineGateway>());
      expect(app.getBean<BookRepository>().count(), 0); // no sample data
    });
  });

  test('closing: lifecycle stop, @PreDestroy, destroy methods', () async {
    final context = await springApplication.runAsync(
      const [],
      properties: {
        'spring.profiles.active': 'dev',
        'spring.main.web-application-type': 'none',
        'spring.main.banner-mode': 'off',
        'logging.console.enabled': false,
        'neon.stock.restock-initial-delay': '1h',
      },
    );
    final feed = context.getBean<StockFeed>();
    final covers = context.getBean<CoverStore>();
    expect(covers.isOpen, isTrue);
    await context.closeAsync();
    expect(feed.isRunning, isFalse); // SmartLifecycle.stop
    expect(covers.isOpen, isFalse); // the inferred destroy method `close`
  });
}
