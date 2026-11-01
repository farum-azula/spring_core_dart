// Default values: a field's constant initializer or a constructor default
// becomes the column's DEFAULT in a generated schema, and
// @OnDelete(setDefault) sets it, in memory as in SQLite.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

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

EntityProperty col(
  String name,
  TypeInfo<Object?> info, {
  List<Object> annotations = const [],
  bool hasDefaultValue = false,
  Object? defaultValue,
  bool parameter = false,
}) => EntityProperty(
  name,
  info,
  annotations: annotations,
  parameter: parameter,
  writable: true,
  hasDefaultValue: hasDefaultValue,
  defaultValue: defaultValue,
);

EntityIntrospection<T> describe<T extends Row>(
  String name,
  T Function() create,
  List<EntityProperty> properties, {
  List<Object> annotations = const [Table()],
}) => EntityIntrospection<T>(
  name,
  properties,
  annotations: annotations,
  get: (r, i) => r.values[properties[i].name],
  create: (v) => create(),
  write: (r, i, v) => r.values[properties[i].name] = v,
);

final EntityIntrospection<Gadget> gadget = describe<Gadget>(
  'Gadget',
  Gadget.new,
  [
    col('id', _intN, annotations: const [Id()]),
    col(
      'inStock',
      const ClassType<bool>(),
      hasDefaultValue: true,
      defaultValue: true,
    ),
    col('stock', _int, hasDefaultValue: true, defaultValue: 0),
    col(
      'label',
      const ClassType<String>(),
      hasDefaultValue: true,
      defaultValue: "it's new",
    ),
    col(
      'status',
      const EnumType<Status>(Status.values),
      hasDefaultValue: true,
      defaultValue: Status.draft,
    ),
    col(
      'rate',
      const ClassType<double>(),
      hasDefaultValue: true,
      defaultValue: 1.5,
    ),
    col('note', const ClassType<String>(nullable: true)),
  ],
  annotations: const [Table('gadgets')],
);

final EntityIntrospection<Publisher> publisher = describe<Publisher>(
  'Publisher',
  Publisher.new,
  [
    col('id', _int, annotations: const [Id()]),
    col('version', _int, annotations: const [Version()]),
  ],
  annotations: const [Table('publishers')],
);

EntityIntrospection<Item> item({bool withDefault = true}) => describe<Item>(
  'Item',
  Item.new,
  [
    col('id', _intN, annotations: const [Id()]),
    col(
      'publisherId',
      _intN,
      annotations: const [
        Reference(Publisher),
        OnDelete(OnDeleteAction.setDefault),
      ],
      hasDefaultValue: withDefault,
      defaultValue: withDefault ? 1 : null,
    ),
  ],
  annotations: const [Table('items')],
);

RelationalMappingContext contextOf(
  List<EntityIntrospection<Object>> introspections,
) => RelationalMappingContext(introspections: introspections);

void main() {
  group('the mapping', () {
    test('a field initializer is the default value', () {
      final entity = contextOf([gadget]).getRequiredPersistentEntity<Gadget>();
      expect(entity.property('inStock')!.hasDefaultValue, isTrue);
      expect(entity.property('inStock')!.defaultValue, true);
      expect(entity.property('note')!.hasDefaultValue, isFalse);
    });

    test('a constructor default counts as the default value', () {
      // The build gives the property the constant default of the constructor
      // parameter `this.stock = 7` when the field has no initializer.
      final withParameter = describe<Gadget>(
        'Gadget',
        Gadget.new,
        [
          col('id', _intN, annotations: const [Id()]),
          col(
            'stock',
            _int,
            parameter: true,
            hasDefaultValue: true,
            defaultValue: 7,
          ),
        ],
      );
      final entity = contextOf([
        withParameter,
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
      final converter = EntityConverter();
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
