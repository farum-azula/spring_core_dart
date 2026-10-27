// Chapter 13, the advanced extension points: what bin/advanced.dart
// prints, checked.
@TestOn('vm')
library;

import 'package:neon_books_server/src/advanced/alarm_registrar.dart';
import 'package:neon_books_server/src/advanced/bean_init_timer.dart';
import 'package:neon_books_server/src/advanced/demos.dart';
import 'package:neon_books_server/src/advanced/import_batch.dart';
import 'package:neon_books_server/src/advanced/lifecycle_probe.dart';
import 'package:neon_books_server/src/advanced/stock_report_printer.dart';
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/stock/stock_feed.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/main.spring.dart';
import 'support/app.dart';

void main() {
  group('with the advanced profile', () {
    final app = neonBooks(profiles: ['dev', 'test', 'advanced']);

    test('a BeanPostProcessor saw the beans created after it', () {
      final timings = app.getBean<BeanInitTimer>().timings;
      expect(timings, contains('catalogService'));
    });

    test('every lifecycle callback, in order', () {
      expect(lifecycleEvents, [
        'constructor',
        '@Autowired method',
        'setBeanName(lifecycleProbe)',
        'setBeanFactory',
        'setEnvironment',
        'setApplicationContext',
        '@PostConstruct',
        'afterPropertiesSet',
        'initMethod',
      ]);
    });

    test('stop() and start(): lifecycle beans stop and start again', () {
      final feed = app.getBean<StockFeed>();
      app.context.stop();
      expect(feed.isRunning, isFalse);
      app.context.start();
      expect(feed.isRunning, isTrue);
    });

    test('a custom scope: one ImportBatch per import', () {
      final importer = app.getBean<CatalogImporter>();
      final first = importer.import(const [
        NewBook(
          isbn: '9780062316097',
          title: 'Sapiens',
          author: 'Yuval Noah Harari',
          price: 14.99,
          year: 2011,
          tags: ['history'],
        ),
        NewBook(isbn: '9780141439518', title: 'Emma', author: 'J', price: 5),
      ]);
      expect(first.isbns, ['9780062316097']);
      expect(first.rejected, ['9780141439518: year, tags']); // Catalogued
      final second = importer.import(const []);
      expect(second, isNot(same(first)));
      expect(app.getBean<Catalog>().get('9780062316097').title, 'Sapiens');
    });

    test('a bean definition registered by hand', () {
      expect(app, hasBeanNamed('lowStockAlarm'));
      expect(
        app.getBean<LowStockAlarm>().ringing(),
        containsAll(['Leaves of Grass', 'The Little Prince']),
      );
    });

    test('@Configurable: autowireBean fills an object made with new', () {
      final printer = StockReportPrinter();
      app.context.autowireCapableBeanFactory.autowireBean(printer);
      expect(printer.print(), startsWith('NEON Books, low on: '));
    });

    test('SpEL used directly', () {
      final results = spel(
        app.getBean<Catalog>().all(),
        app.getBean<BeanIntrospector>(),
      );
      expect(results['#books.?[price > 10].![title]'], [
        'Cosmos',
        'Sapiens',
        'The Hobbit',
      ]);
      expect(results['#books.^[year < 1900]?.title'], 'Leaves of Grass');
      expect(results['SimpleEvaluationContext'], 'Dune');
    });

    test('DataBinder and BeanWrapper', () {
      final (settings, errors) = bindShopSettings({
        'name': 'Ignored',
        'opensAt': '22',
        'closesAt': '20',
        'maxBasketSize': 'many',
      }, app.getBean<BeanIntrospector>());
      expect(settings.name, 'NEON Books'); // disallowed field
      expect(errors, [
        'maxBasketSize: typeMismatch.shop.maxBasketSize',
        'shop: ValidOpeningHours.shop',
        'opensAt via BeanWrapper: 22',
      ]);
    });
  });

  group('without the profile (the server)', () {
    final app = neonBooks();

    test('none of these beans exist', () {
      expect(app, doesNotHaveBean<BeanInitTimer>());
      expect(app, doesNotHaveBean<ImportBatchScope>());
      expect(app, doesNotHaveBean<LowStockAlarm>());
    });
  });

  test('closing: the destroy callbacks, in order', () async {
    final context = await springApplication.runAsync(
      const [],
      properties: {
        'spring.profiles.active': 'test,advanced',
        'spring.main.web-application-type': 'none',
        'spring.main.banner-mode': 'off',
        'logging.console.enabled': false,
      },
    );
    lifecycleEvents.clear();
    await context.closeAsync();
    expect(lifecycleEvents, [
      'DestructionAwareBeanPostProcessor(lifecycleProbe)',
      '@PreDestroy',
      'DisposableBean.destroy',
      'destroyMethod',
    ]);
  });

  test('parent and child contexts', () {
    final (child, heard) = parentAndChild();
    expect(child, 'child bean with the parent clock: 9780441013593');
    expect(heard, ['parent: 9780441013593']);
  });

  test('startup failure reports: a missing bean, a cycle', () {
    final reports = failureReports();
    expect(reports['missing bean'], contains('APPLICATION FAILED TO START'));
    expect(
      reports['missing bean'],
      contains("Bean 'shop' required a bean of type Clock"),
    );
    expect(reports['cycle'], contains('clock → shop → clock'));
  });
}
