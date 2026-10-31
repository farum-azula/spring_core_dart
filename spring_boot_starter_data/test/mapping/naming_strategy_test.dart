import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

void main() {
  const naming = NamingStrategy();

  group('snakeCase', () {
    final cases = {
      'OrderLine': 'order_line',
      'Book': 'book',
      'createdAt': 'created_at',
      'authorId': 'author_id',
      'HTTPRequest': 'http_request',
      'parseHTTPResponse': 'parse_http_response',
      'orderID': 'order_id',
      'line2': 'line2',
      'line2Item': 'line2_item',
      'v2API': 'v2_api',
      'already_snake': 'already_snake',
      'ID': 'id',
      'x': 'x',
      '': '',
    };
    for (final MapEntry(key: input, value: expected) in cases.entries) {
      test('"$input" -> "$expected"', () {
        expect(naming.snakeCase(input), expected);
      });
    }
  });

  test('table: annotation value wins, else snake-case class name', () {
    expect(naming.tableName('OrderLine', null), 'order_line');
    expect(naming.tableName('OrderLine', const Table()), 'order_line');
    expect(naming.tableName('OrderLine', const Table('lines')), 'lines');
  });

  test('column: annotation value wins, else snake-case property name', () {
    expect(naming.columnName('createdAt', null), 'created_at');
    expect(naming.columnName('createdAt', const Column('made')), 'made');
  });

  test('reverse and key columns of a mapped collection', () {
    expect(naming.reverseColumnName('orders', null), 'orders_id');
    expect(naming.keyColumnName('orders', null), 'orders_key');
    const mapped = MappedCollection(idColumn: 'ref', keyColumn: 'pos');
    expect(naming.reverseColumnName('orders', mapped), 'ref');
    expect(naming.keyColumnName('orders', mapped), 'pos');
    expect(
      naming.reverseColumnName('orders', const MappedCollection()),
      'orders_id',
    );
  });

  test('a subclass can change a rule', () {
    expect(_Upper().columnName('createdAt', null), 'CREATEDAT');
    expect(_Upper().columnName('createdAt', const Column('x')), 'x');
  });
}

class _Upper extends NamingStrategy {
  @override
  String snakeCase(String name) => name.toUpperCase();
}
