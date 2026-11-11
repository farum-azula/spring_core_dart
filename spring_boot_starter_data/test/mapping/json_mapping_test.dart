// @Json in the mapping: the property's description, the combinations the
// mapping context refuses, the dialects' one extension point (JsonStorage)
// and the inserts and updates the SQL generator writes with it. The entity
// is described by hand, as the generator writes it.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../jdbc/support/fake_jdbc.dart';
import 'support.dart';

@Table('docs')
class Doc {
  Doc({this.id, this.data = const {}, this.items, this.version, this.author});

  @Id()
  int? id;

  @Json()
  Map<String, Object?> data;

  @Json(binary: false)
  List<Object?>? items;

  int? version;

  AggregateReference<Author, int>? author;
}

const _map = MapType<String, Object?>(
  ClassType<String>(),
  ClassType<Object>(nullable: true),
);
const _list = ListType<Object?>(
  ClassType<Object>(nullable: true),
  nullable: true,
);
const _intN = ClassType<int>(nullable: true);
const _authorRef = GenericType<AggregateReference<Author, int>>([
  ClassType<Author>(),
  ClassType<int>(),
], nullable: true);

/// The description of [Doc], with the annotations given for each property.
EntityIntrospection<Doc> docIntrospection({
  List<Object> id = const [Id()],
  List<Object> data = const [Json()],
  List<Object> items = const [Json(binary: false)],
  List<Object> version = const [],
  List<Object> author = const [],
}) => EntityIntrospection<Doc>(
  'Doc',
  [
    EntityProperty(
      'id',
      _intN,
      annotations: id,
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'data',
      _map,
      annotations: data,
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'items',
      _list,
      annotations: items,
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'version',
      _intN,
      annotations: version,
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'author',
      _authorRef,
      annotations: author,
      parameter: true,
      writable: true,
    ),
  ],
  annotations: const [Table('docs')],
  get: (d, i) => switch (i) {
    0 => d.id,
    1 => d.data,
    2 => d.items,
    3 => d.version,
    _ => d.author,
  },
  create: (v) => Doc(
    id: v[0] as int?,
    data: v[1]! as Map<String, Object?>,
    items: v[2] as List<Object?>?,
    version: v[3] as int?,
    author: v[4] as AggregateReference<Author, int>?,
  ),
  write: (d, i, v) => switch (i) {
    0 => d.id = v as int?,
    1 => d.data = v! as Map<String, Object?>,
    2 => d.items = v as List<Object?>?,
    3 => d.version = v as int?,
    4 => d.author = v as AggregateReference<Author, int>?,
    _ => null,
  },
);

PersistentEntity<Doc> _doc(EntityIntrospection<Doc> introspection) =>
    RelationalMappingContext(
      introspections: [introspection, authorIntrospection()],
    ).getRequiredPersistentEntity<Doc>();

class _Tagged {
  List<Tag> tags = [];
}

void main() {
  group('the property', () {
    test('carries the @Json settings; the others have none', () {
      final doc = _doc(docIntrospection());
      expect(doc.property('data')!.isJson, isTrue);
      expect(doc.property('data')!.json!.binary, isTrue);
      expect(doc.property('items')!.json!.binary, isFalse);
      expect(doc.property('id')!.isJson, isFalse);
      expect(doc.property('author')!.json, isNull);
      expect(doc.columns.map((p) => p.columnName), [
        'id',
        'data',
        'items',
        'version',
        'author',
      ]);
    });

    Matcher refused(String what) => throwsA(
      isA<MappingException>().having(
        (e) => e.message,
        'message',
        allOf(contains('@Json cannot be on $what'), contains('remove @Json')),
      ),
    );

    test('@Json on the @Id is refused', () {
      expect(
        () => _doc(docIntrospection(id: const [Id(), Json()])),
        refused('the @Id'),
      );
    });

    test('@Json on the @Version is refused', () {
      expect(
        () => _doc(docIntrospection(version: const [Version(), Json()])),
        refused('the @Version'),
      );
    });

    test('@Json on an AggregateReference is refused', () {
      expect(
        () => _doc(docIntrospection(author: const [Json()])),
        refused('a reference to another aggregate'),
      );
    });

    test('@Json on a @MappedCollection is refused', () {
      expect(
        () => RelationalMappingContext(
          introspections: [
            EntityIntrospection<_Tagged>(
              '_Tagged',
              const [
                EntityProperty(
                  'tags',
                  ListType<Tag>(ClassType<Tag>()),
                  annotations: [MappedCollection(), Json()],
                  writable: true,
                ),
              ],
              annotations: const [Table('tagged')],
              get: (t, i) => t.tags,
              create: (v) => _Tagged(),
              write: (t, i, v) => t.tags = v! as List<Tag>,
            ),
            tagIntrospection(),
          ],
        ).getRequiredPersistentEntity<_Tagged>(),
        refused('a @MappedCollection'),
      );
    });
  });

  group('JsonStorage', () {
    const json = Json();
    const text = Json(binary: false);

    test('by default: JSON text in a TEXT column, for any database', () {
      // A dialect that overrides nothing.
      final storage = FakeDialect().jsonStorage(json);
      expect(storage.columnType, 'TEXT');
      expect(storage.marker, '?');
      expect(storage.check('"data"'), isNull);
      expect(
        storage.toDatabase({
          'a': [1, null, 'x'],
        }),
        '{"a":[1,null,"x"]}',
      );
      expect(storage.fromDatabase('{"a":[1,null,"x"]}'), {
        'a': [1, null, 'x'],
      });
      expect(storage.fromDatabase('"text"'), 'text');
      expect(() => storage.fromDatabase('no json'), throwsFormatException);
      expect(storage.fits('varchar(200)'), isTrue);
      expect(storage.fits('CLOB'), isTrue);
      expect(storage.fits('json'), isTrue);
      expect(storage.fits('integer'), isFalse);
    });

    test('SQLite: TEXT, checked with json_valid', () {
      final storage = const SqliteDialect().jsonStorage(json);
      expect(storage.columnType, 'TEXT');
      expect(const SqliteDialect().jsonStorage(text).columnType, 'TEXT');
      expect(storage.marker, '?');
      expect(storage.check('"data"'), 'json_valid("data")');
      expect(storage.toDatabase(const [1]), '[1]');
      expect(storage.fromDatabase('[1]'), [1]);
      expect(storage.fits('TEXT'), isTrue);
      expect(storage.fits('JSON'), isTrue);
      expect(storage.fits(''), isTrue);
      expect(storage.fits('INTEGER'), isFalse);
      expect(storage.fits('REAL'), isFalse);
    });

    test('PostgreSQL: jsonb or json, bound with a cast, read as the driver '
        'decoded it', () {
      const dialect = PostgresDialect();
      final binary = dialect.jsonStorage(json);
      final plain = dialect.jsonStorage(text);
      expect(binary.columnType, 'JSONB');
      expect(plain.columnType, 'JSON');
      expect(binary.marker, 'CAST(? AS JSONB)');
      expect(plain.marker, 'CAST(? AS JSON)');
      expect(binary.check('"data"'), isNull);
      expect(binary.toDatabase({'a': 1}), '{"a":1}');
      expect(binary.fromDatabase({'a': 1}), {'a': 1});
      // A JSON string, decoded by the driver, is not decoded again.
      expect(binary.fromDatabase('42'), '42');
      expect(binary.fits('jsonb'), isTrue);
      expect(binary.fits('json'), isFalse);
      expect(plain.fits('json'), isTrue);
      expect(plain.fits('jsonb'), isFalse);
      expect(plain.fits('text'), isFalse);
    });
  });

  group('a stored JSON string is the value, not a document', () {
    final converter = EntityConverter();

    test('a BigInt written as a string keeps every digit', () {
      const text = '123456789012345678901234567890';
      expect(
        converter.fromJsonTree(text, const ClassType<BigInt>()),
        BigInt.parse(text),
      );
    });

    test('the text of a document is still read as the document', () {
      expect(
        converter.fromJsonTree('[1,2]', const ListType<int>(ClassType<int>())),
        [1, 2],
      );
    });
  });

  group('SqlGenerator', () {
    final doc = _doc(docIntrospection());
    final converter = EntityConverter();
    final row = converter.write(
      doc,
      Doc(
        id: 1,
        data: {
          'theme': 'dark',
          'sizes': [1, 2],
        },
        items: ['a', 1],
        version: 3,
      ),
    );

    test('the row holds trees', () {
      expect(row['data'], {
        'theme': 'dark',
        'sizes': [1, 2],
      });
      expect(row['items'], ['a', 1]);
    });

    test(
      'PostgreSQL: the casts in an insert and an update, JSON text bound',
      () {
        final sql = SqlGenerator(
          dialect: const PostgresDialect(),
          converter: converter,
        );
        final insert = sql.insert(doc, row);
        expect(
          insert.sql,
          'insert into "docs" ("id", "data", "items", "version", "author") '
          'values (?, CAST(? AS JSONB), CAST(? AS JSON), ?, ?)',
        );
        expect(insert.parameters, [
          1,
          '{"theme":"dark","sizes":[1,2]}',
          '["a",1]',
          3,
          null,
        ]);
        final update = sql.update(doc, row, id: 1);
        expect(
          update.sql,
          'update "docs" set "data" = CAST(? AS JSONB), '
          '"items" = CAST(? AS JSON), "version" = ?, "author" = ? '
          'where "id" = ?',
        );
        expect(update.parameters, [
          '{"theme":"dark","sizes":[1,2]}',
          '["a",1]',
          3,
          null,
          1,
        ]);
      },
    );

    test('SQLite: plain markers, JSON text bound; a null stays null', () {
      final sql = SqlGenerator(
        dialect: const SqliteDialect(),
        converter: converter,
      );
      final insert = sql.insert(doc, {...row, 'items': null});
      expect(
        insert.sql,
        'insert into "docs" ("id", "data", "items", "version", "author") '
        'values (?, ?, ?, ?, ?)',
      );
      expect(insert.parameters, [
        1,
        '{"theme":"dark","sizes":[1,2]}',
        null,
        3,
        null,
      ]);
    });
  });

  group('SchemaModel', () {
    test('a JSON column: no DEFAULT, its settings kept', () {
      final model = SchemaModel.of([_doc(docIntrospection())]);
      final columns = {
        for (final c
            in model.tables.firstWhere((t) => t.name == 'docs').columns)
          c.name: c,
      };
      expect(columns['data']!.json!.binary, isTrue);
      expect(columns['items']!.json!.binary, isFalse);
      expect(columns['items']!.nullable, isTrue);
      expect(columns['id']!.json, isNull);
    });
  });
}
