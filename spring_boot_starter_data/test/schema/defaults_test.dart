// Default values: a field's constant initializer or a constructor default
// becomes the column's DEFAULT in a generated schema, and
// @OnDelete(setDefault) sets it, in memory as in SQLite.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/support.dart' show prop;
import 'support.dart';

class Row {
  final values = <String, Object?>{};
}

class Gadget extends Row {}

class Publisher extends Row {}

class Item extends Row {}

enum Status { draft, published }

const _int = ClassType<int>();
const _intN = ClassType<int>(nullable: true);

BeanProperty<T> col<T extends Row>(
  String name,
  Type type,
  TypeInfo<Object?> info, {
  List<Object> annotations = const [],
  bool hasInitialValue = false,
  Object? initialValue,
}) => prop<T>(
  name,
  type,
  info,
  (r) => r.values[name],
  set: (r, v) => r.values[name] = v,
  annotations: annotations,
  hasInitialValue: hasInitialValue,
  initialValue: initialValue,
);

BeanIntrospection<T> describe<T extends Row>(
  String name,
  T Function() create,
  List<BeanProperty<T>> properties, {
  List<Object> annotations = const [Table()],
  BeanConstructor<T>? constructor,
}) => BeanIntrospection<T>(
  className: name,
  annotations: annotations,
  properties: properties,
  instantiate: create,
  constructor: constructor,
);

final BeanIntrospection<Gadget> gadget = describe<Gadget>(
  'Gadget',
  Gadget.new,
  [
    col<Gadget>('id', int, _intN, annotations: const [Id()]),
    col<Gadget>(
      'inStock',
      bool,
      const ClassType<bool>(),
      hasInitialValue: true,
      initialValue: true,
    ),
    col<Gadget>('stock', int, _int, hasInitialValue: true, initialValue: 0),
    col<Gadget>(
      'label',
      String,
      const ClassType<String>(),
      hasInitialValue: true,
      initialValue: "it's new",
    ),
    col<Gadget>(
      'status',
      Status,
      const EnumType<Status>(Status.values),
      hasInitialValue: true,
      initialValue: Status.draft,
    ),
    col<Gadget>(
      'rate',
      double,
      const ClassType<double>(),
      hasInitialValue: true,
      initialValue: 1.5,
    ),
    col<Gadget>('note', String, const ClassType<String>(nullable: true)),
  ],
  annotations: const [Table('gadgets')],
);

final BeanIntrospection<Publisher> publisher = describe<Publisher>(
  'Publisher',
  Publisher.new,
  [
    col<Publisher>('id', int, _int, annotations: const [Id()]),
    col<Publisher>('version', int, _int, annotations: const [Version()]),
  ],
  annotations: const [Table('publishers')],
);

BeanIntrospection<Item> item({bool withDefault = true}) => describe<Item>(
  'Item',
  Item.new,
  [
    col<Item>('id', int, _intN, annotations: const [Id()]),
    col<Item>(
      'publisherId',
      int,
      _intN,
      annotations: const [
        Reference(Publisher),
        OnDelete(OnDeleteAction.setDefault),
      ],
      hasInitialValue: withDefault,
      initialValue: withDefault ? 1 : null,
    ),
  ],
  annotations: const [Table('items')],
);

RelationalMappingContext contextOf(
  List<BeanIntrospection<Object>> introspections,
) => RelationalMappingContext(
  introspector: BeanIntrospector(introspections: introspections),
);

void main() {
  group('the mapping', () {
    test('a field initializer is the default value', () {
      final entity = contextOf([gadget]).getRequiredPersistentEntity<Gadget>();
      expect(entity.property('inStock')!.hasDefaultValue, isTrue);
      expect(entity.property('inStock')!.defaultValue, true);
      expect(entity.property('note')!.hasDefaultValue, isFalse);
    });

    test('a constructor default counts when the field has none', () {
      final withConstructor = describe<Gadget>(
        'Gadget',
        Gadget.new,
        [
          col<Gadget>('id', int, _intN, annotations: const [Id()]),
          col<Gadget>('stock', int, _int),
        ],
        constructor: BeanConstructor<Gadget>(
          parameters: const [
            BeanParameter(
              'stock',
              type: ClassType<int>(),
              symbol: #stock,
              hasDefaultValue: true,
              defaultValue: 7,
            ),
          ],
          create: (positional, named) =>
              Gadget()..values['stock'] = named[#stock] ?? 7,
        ),
      );
      final entity = contextOf([
        withConstructor,
      ]).getRequiredPersistentEntity<Gadget>();
      expect(entity.property('stock')!.defaultValue, 7);
    });

    test('setDefault without a default value stops the start', () {
      expect(
        () => contextOf([
          publisher,
          item(withDefault: false),
        ]).getRequiredPersistentEntity<Item>(),
        throwsA(
          isA<MappingException>().having(
            (e) => e.message,
            'message',
            contains('needs a default value'),
          ),
        ),
      );
    });
  });

  test('a generated schema writes the defaults', () async {
    final db = await memorySource();
    final entity = contextOf([gadget]).getRequiredPersistentEntity<Gadget>();
    final sql = SchemaCreator(db).createStatements([entity]).first;
    expect(sql, contains('"in_stock" INTEGER NOT NULL DEFAULT 1'));
    expect(sql, contains('"stock" INTEGER NOT NULL DEFAULT 0'));
    expect(sql, contains('''"label" TEXT NOT NULL DEFAULT 'it''s new\''''));
    expect(sql, contains('''"status" TEXT NOT NULL DEFAULT 'draft\''''));
    expect(sql, contains('"rate" REAL NOT NULL DEFAULT 1.5'));
    expect(sql, isNot(contains('"note" TEXT DEFAULT')));
    // The database takes them: a row inserted without the columns.
    await SchemaCreator(db).create([entity]);
    final jdbc = JdbcTemplate(db);
    await jdbc.update('insert into gadgets (id) values (1)');
    final row = await jdbc.queryForMap('select * from gadgets where id = 1');
    expect(row['in_stock'], 1);
    expect(row['stock'], 0);
    expect(row['label'], "it's new");
    expect(row['status'], 'draft');
    expect(row['rate'], 1.5);
  });

  group('setDefault, the same in memory and in SQLite', () {
    late RelationalMappingContext mapping;
    late PersistentEntity<Publisher> publishers;
    late PersistentEntity<Item> items;

    setUp(() {
      mapping = contextOf([publisher, item()]);
      publishers = mapping.getRequiredPersistentEntity<Publisher>();
      items = mapping.getRequiredPersistentEntity<Item>();
    });

    Future<Map<String, DataStore>> stores() async {
      final converter = EntityConverter(introspector: mapping.introspector);
      final db = await memorySource();
      await SchemaCreator(db).create([publishers, items]);
      return {
        'memory': InMemoryDataStore(converter: converter),
        'sqlite': JdbcDataStore(dataSource: db, converter: converter),
      };
    }

    Publisher pub(int id) => Publisher()
      ..values['id'] = id
      ..values['version'] = 0;

    Item it(int publisherId) => Item()..values['publisherId'] = publisherId;

    for (final name in ['memory', 'sqlite']) {
      test(
        '$name: deleting a publisher moves its items to the default',
        () async {
          final store = (await stores())[name]!;
          await store.insert(publishers, pub(1));
          await store.insert(publishers, pub(2));
          final saved = await store.insert(items, it(2));
          await store.deleteById(publishers, 2);
          final moved = await store.findById(items, saved.values['id']!);
          expect(moved!.values['publisherId'], 1);
        },
      );

      test(
        '$name: the default must still exist: deleting it fails',
        () async {
          final store = (await stores())[name]!;
          await store.insert(publishers, pub(1));
          await store.insert(items, it(1));
          await expectLater(
            store.deleteById(publishers, 1),
            throwsA(isA<DataIntegrityViolationException>()),
          );
          expect(await store.findById(publishers, 1), isNotNull);
        },
      );
    }
  });
}
