// The object methods of the order classes (chapter 6): OrderLine's and
// CustomerOrder's ==, hashCode and toString() (IntrospectedObject, through
// their descriptions) and CustomerOrder's copyWith
// (lib/spring_gen/src/app.spring.introspection.dart). The descriptions are
// registered without a context.
@TestOn('vm')
library;

import 'package:neon_books_server/spring_gen/src/app.spring.introspection.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

OrderLine _line({int quantity = 2}) => OrderLine(
  isbn: '978-0441013593',
  title: 'Dune',
  price: 9.5,
  quantity: quantity,
  total: 9.5 * quantity,
);

CustomerOrder _order() => CustomerOrder(
  id: 1,
  customer: 'ada',
  lines: [_line()],
  total: 19,
  placedAt: DateTime.utc(2026, 10, 27),
  payment: 'sandbox-1',
);

void main() {
  setUpAll(() => Introspector.shared.registerAll($appBeansIntrospections));

  test('order lines with the same values are equal, also in a set', () {
    expect(_line(), _line());
    expect(_line().hashCode, _line().hashCode);
    expect({_line(), _line()}, hasLength(1));
    expect(_line(), isNot(_line(quantity: 3)));
  });

  test('orders compare their lines by content', () {
    expect(_order(), _order());
    expect({_order()}.contains(_order()), isTrue);
  });

  test('toString() shows the fields, the payment reference masked', () {
    expect(
      '${_line()}',
      'OrderLine(isbn: 978-0441013593, title: Dune, price: 9.5, '
          'quantity: 2, discount: 0, total: 19.0)',
    );
    expect('${_order()}', contains('customer: ada'));
    expect('${_order()}', endsWith('payment: ******)'));
    expect('${_order()}', isNot(contains('sandbox-1')));
  });

  test('copyWith changes what it is given, keeps the rest, clears with '
      'null', () {
    final order = _order();
    final shipped = order.copyWith(status: OrderStatus.shipped);

    expect(shipped.status, OrderStatus.shipped);
    expect(shipped.lines, [_line()]);
    expect(shipped.payment, 'sandbox-1');
    expect(order.copyWith(), order);
    // An explicit null clears; left out, the value is kept.
    expect(order.copyWith(payment: null).payment, isNull);
  });
}
