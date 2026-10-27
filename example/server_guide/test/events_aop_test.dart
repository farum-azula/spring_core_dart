// Chapter 6, events and AOP: who reacts to an order and in which order,
// asynchronous listeners, and the aspects around the services.
@TestOn('vm')
library;

import 'package:neon_books_server/src/aop/handler_metrics.dart';
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/orders/order_service.dart';
import 'package:neon_books_server/src/stock/stock_changed.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_security_core/testing.dart';
import 'package:test/test.dart';

import 'support/app.dart';

const hobbit = '9780547928227'; // 10.99, 6 copies

/// Waits until [condition] holds (asynchronous listeners, scheduled
/// tasks), at most 5 seconds.
Future<void> eventually(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  final app = neonBooks();
  final logs = captureLogs(level: SpringLogLevel.debug);

  Future<int> stockOf() async => app.getBean<Catalog>().get(hobbit).available;

  Future<CustomerOrder> order(int copies) => withMockUser(
    () => app.getBean<OrderService>().place('ada', {hobbit: copies}),
    username: 'ada',
  );

  group('OrderPlaced', () {
    test('listeners run in @Order: the stock is taken first', () async {
      int? stockSeenLater;
      final registration = app.context.addListener<OrderPlaced>(
        (_) => stockSeenLater = app.getBean<Catalog>().get(hobbit).available,
      );
      final before = app.getBean<Catalog>().get(hobbit).available;
      await order(1);
      registration.remove();
      expect(stockSeenLater, before - 1);
    });

    test('the VIP desk only hears big orders (a condition)', () async {
      await order(1); // 10.99 EUR
      expect(logs.ofLogger('neon.vip'), isEmpty);
      await order(10); // 98.91 EUR after the bulk discount
      expect(logs.ofLogger('neon.vip'), isEmpty);
      app.getBean<Catalog>().changeStock(hobbit, 10);
      await order(11); // 108.80 EUR
      expect(logs.ofLogger('neon.vip').single.message, contains('VIP order'));
    });

    test('@Async: the mail is sent after place() returned', () async {
      final placed = await order(1);
      // Not yet: the listener runs on the TaskExecutor, in a later turn.
      expect(logs.ofLogger('neon.mail'), isEmpty);
      await eventually(() => logs.ofLogger('neon.mail').isNotEmpty);
      final mail = logs.ofLogger('neon.mail').single;
      expect(
        mail.message,
        'mail to ada: Your order ${placed.id} at NEON Books',
      );
      expect(mail.fields['body'], contains('one book for 10.99 EUR'));
      // Fields of the zone it was published in (SpringLog.withFields).
      expect(mail.fields['order'], placed.id);
    });

    test("a listener's result is published: LowStock", () async {
      final low = <LowStock>[];
      final registration = app.context.addListener<LowStock>(low.add);
      app.getBean<Catalog>().changeStock(hobbit, 2 - (await stockOf()));
      final placed = await order(1); // 2 → 1 copy: below the threshold
      registration.remove();
      expect(low.single.orderId, placed.id);
      expect(low.single.isbns, [hobbit]);
    });

    test('OrderShipped, an ApplicationEvent, after the delay', () async {
      final shipped = <CustomerOrder>[];
      final registration = app.context.addListener<OrderShipped>(
        (event) => shipped.add(event.order),
      );
      final placed = await order(1);
      // (Orders of the tests before may ship meanwhile.)
      await eventually(() => shipped.any((o) => o.id == placed.id));
      registration.remove();
      expect(
        shipped.singleWhere((o) => o.id == placed.id).status,
        OrderStatus.shipped,
      );
    });
  });

  group('aspects', () {
    test('@Around @Timed: the duration of the catalog search', () {
      app.getBean<Catalog>().search('dune', 0);
      expect(logs.ofLogger('neon.timing').map((r) => r.message), [
        startsWith('search took'),
      ]);
    });

    test('@Before and @Around in aspect order: audit outside', () async {
      await withMockUser(
        () => app.getBean<Catalog>().remove('9780345391803'),
        username: 'root',
        roles: ['ADMIN'],
      );
      final lines = logs.records
          .where(
            (r) =>
                r.loggerName == 'neon.audit' || r.loggerName == 'neon.timing',
          )
          .map((r) => '${r.loggerName}: ${r.message}')
          .toList();
      expect(lines, [
        'neon.audit: removing book 9780345391803', // @Order(1): first
        startsWith('neon.timing: remove took'),
      ]);
    });

    test('an advisor bean counts the handler calls', () async {
      await app.mockMvc.get('/api/books');
      expect(
        app.getBean<HandlerMetrics>().calls['BookController.search'],
        greaterThan(0),
      );
    });

    test('@AfterReturning and @AfterThrowing', () async {
      final placed = await order(1);
      expect(
        logs.ofLogger('neon.audit').map((r) => r.message),
        contains('order ${placed.id} placed by ada'),
      );
      expect(
        () => app.getBean<Catalog>().get('9780000000000'),
        throwsA(anything),
      );
      expect(
        logs.ofLogger('neon.audit').last.message,
        'execution(Catalog.get(..)) failed: '
        'BookNotFoundException: no book 9780000000000',
      );
    });
  });
}
