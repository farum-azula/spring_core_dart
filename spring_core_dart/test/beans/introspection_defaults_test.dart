import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

enum Status { draft, live }

class Item {
  Item({this.stock = 0, this.status = Status.draft});
  int stock;
  Status status;
  bool inStock = true;
  DateTime added = DateTime.now();
}

void main() {
  group('default values in the description', () {
    test('a parameter has no default unless it is described with one', () {
      const plain = BeanParameter('a', type: ClassType<int>());
      expect(plain.hasDefaultValue, isFalse);
      expect(plain.defaultValue, isNull);
    });

    test('a parameter carries a default, also an explicit null', () {
      const stock = BeanParameter(
        'stock',
        type: ClassType<int>(),
        symbol: #stock,
        hasDefaultValue: true,
        defaultValue: 0,
      );
      const status = BeanParameter(
        'status',
        type: ClassType<Status?>(),
        symbol: #status,
        hasDefaultValue: true,
        defaultValue: Status.draft,
      );
      const none = BeanParameter(
        'note',
        type: ClassType<String?>(),
        hasDefaultValue: true,
      );
      expect(stock.hasDefaultValue, isTrue);
      expect(stock.defaultValue, 0);
      expect(status.defaultValue, Status.draft);
      expect(none.hasDefaultValue, isTrue);
      expect(none.defaultValue, isNull);
    });

    test('a property carries the initial value of its field', () {
      final inStock = BeanProperty<Item>(
        'inStock',
        type: bool,
        get: (b) => b.inStock,
        hasInitialValue: true,
        initialValue: true,
      );
      final added = BeanProperty<Item>(
        'added',
        type: DateTime,
        get: (b) => b.added,
      );
      expect(inStock.hasInitialValue, isTrue);
      expect(inStock.initialValue, true);
      expect(added.hasInitialValue, isFalse);
      expect(added.initialValue, isNull);
    });
  });
}
