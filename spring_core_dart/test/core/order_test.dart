import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

class _O implements Ordered {
  const _O(this.order, this.id);
  @override
  final int order;
  final String id;
}

class _P implements PriorityOrdered {
  const _P(this.order, this.id);
  @override
  final int order;
  final String id;
}

String id(Object o) => switch (o) {
  _O(:final id) || _P(:final id) => id,
  _ => '$o',
};

void main() {
  test('PriorityOrdered first, then order, stable, fallback order', () {
    final items = <Object>[
      'plain1',
      const _O(5, 'o5'),
      const _P(10, 'p10'),
      const _O(-1, 'o-1'),
      'plain2',
      const _P(1, 'p1'),
      'annotated',
      const _O(5, 'o5b'),
    ];
    final sorted = OrderComparator.sort(
      items,
      (o) => o == 'annotated' ? 0 : null,
    );
    expect(sorted.map(id), [
      'p1',
      'p10',
      'o-1',
      'annotated',
      'o5',
      'o5b',
      'plain1',
      'plain2',
    ]);
  });

  test('orderOf and annotation', () {
    expect(OrderComparator.orderOf(const _O(3, 'x')), 3);
    expect(OrderComparator.orderOf('x'), Ordered.lowestPrecedence);
    expect(OrderComparator.orderOf('x', 7), 7);
    expect(const Order().value, Ordered.lowestPrecedence);
    expect(const Order(1).value, 1);
    expect(Ordered.highestPrecedence, lessThan(0));
  });
}
