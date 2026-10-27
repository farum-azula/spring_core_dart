// Chapter 8, caching and scheduling: @Cacheable / @CachePut / @CacheEvict
// with SpEL keys, the @Scheduled jobs and the TaskScheduler.
@TestOn('vm')
library;

import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/book_repository.dart';
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/orders/order_service.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart'
    show CacheManager;
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart'
    show ScheduledAnnotationBeanPostProcessor;
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_security_core/testing.dart';
import 'package:test/test.dart';

import 'support/app.dart';

/// The real repository, counting the lookups that reach it.
class CountingRepository extends InMemoryBookRepository {
  int lookups = 0;
  int listings = 0;

  @override
  Book? findByIsbn(String isbn) {
    lookups++;
    return super.findByIsbn(isbn);
  }

  @override
  List<Book> findAll() {
    listings++;
    return super.findAll();
  }
}

const dune = '9780441013593';

void main() {
  final repository = CountingRepository();
  final app = neonBooks(overrides: [BeanOverride<BookRepository>(repository)]);

  group('@Cacheable', () {
    test('a book is looked up once (key #isbn)', () {
      final catalog = app.getBean<Catalog>();
      repository.lookups = 0;
      catalog
        ..get(dune)
        ..get(dune)
        ..findAll([dune, dune]); // through the @Lazy self reference
      expect(repository.lookups, 1);
    });

    test("misses are not cached (unless: '#result == null')", () {
      final catalog = app.getBean<Catalog>();
      repository.lookups = 0;
      catalog
        ..find('9780000000000')
        ..find('9780000000000');
      expect(repository.lookups, 2);
    });

    test("catalog pages by query and page (key: #query + '|' + #page)", () {
      final catalog = app.getBean<Catalog>();
      repository.listings = 0;
      catalog
        ..search('poetry', 0)
        ..search('poetry', 0)
        ..search('poetry', 1);
      expect(repository.listings, 2);
    });

    test('@CacheEvict: a stock change drops the book and the pages', () {
      final catalog = app.getBean<Catalog>();
      final before = catalog.get(dune).available;
      catalog.changeStock(dune, 2);
      repository.lookups = 0;
      expect(catalog.get(dune).available, before + 2);
      catalog.get(dune);
      expect(repository.lookups, 1); // evicted: looked up again, once
    });

    test('@CachePut: an added book is cached under its ISBN', () async {
      final catalog = app.getBean<Catalog>();
      await withMockUser(
        () => catalog.add(
          const NewBook(
            isbn: '9780307474278',
            title: 'The Road',
            author: 'Cormac McCarthy',
            price: 9,
          ),
        ),
        username: 'root',
        roles: ['ADMIN'],
      );
      repository.lookups = 0;
      expect(catalog.get('9780307474278').title, 'The Road');
      expect(repository.lookups, 0);
      final caches = app.getBean<CacheManager>();
      expect(caches.cacheNames, containsAll(['books', 'catalog']));
    });
  });

  group('scheduling', () {
    test('the @Scheduled jobs: a fixed delay and a cron', () {
      final tasks = app
          .getBean<ScheduledAnnotationBeanPostProcessor>()
          .scheduledTasks;
      expect(
        tasks.map((t) => t.name),
        containsAll([endsWith('restockLowStock'), endsWith('dailyReport')]),
      );
      final report = tasks.firstWhere((t) => t.name.endsWith('dailyReport'));
      // neon.stock.report-cron=0 0 6 * * *
      expect(report.nextExecution!.hour, 6);
      expect(report.nextExecution!.minute, 0);
    });

    test('the TaskScheduler ships an order after the delay', () async {
      final orders = app.getBean<OrderService>();
      final placed = await withMockUser(
        () => orders.place('ada', {dune: 1}),
        username: 'ada',
      );
      expect(placed.status, OrderStatus.placed);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final later = await withMockUser(
        () => orders.find(placed.id),
        username: 'ada',
      );
      expect(later.status, OrderStatus.shipped);
    });
  });
}
