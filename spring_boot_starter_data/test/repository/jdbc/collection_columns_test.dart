// A Map, List or Set property without @Json on the SQL store: a problem of
// the repository when it is created, and of the schema validation and
// creation, naming the entity, the property and the fix, before any
// statement runs (not an error of the driver at the first insert). Bytes,
// @Json, @MappedCollection and, on PostgreSQL, a list of simple values in
// an array column are kept; the memory store keeps everything.
import 'dart:typed_data';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../../postgres/support.dart';
import '../../schema/support.dart' show failure, memorySource;

@Table('lines')
class Line {
  Line({required this.sku, this.options = const {}});

  String sku;
  Map<String, String> options;
}

@Table('parcels')
class Parcel {
  Parcel({
    this.id,
    this.meta = const {},
    this.labels = const {},
    this.tags = const [],
    this.bytes = const [],
    this.raw,
    this.kept = const {},
    this.lines = const [],
  });

  @Id()
  int? id;
  Map<String, Object?> meta;
  Set<String> labels;
  List<String> tags;
  List<int> bytes;
  Uint8List? raw;
  @Json()
  Map<String, Object?> kept;
  @MappedCollection()
  List<Line> lines;
}

/// What PostgreSQL keeps in array columns.
@Table('tagged')
class Tagged {
  Tagged({this.id, this.tags = const [], this.weights = const []});

  @Id()
  int? id;
  List<String> tags;
  List<double> weights;
}

const _id = EntityProperty(
  'id',
  ClassType<int>(nullable: true),
  annotations: [Id()],
  parameter: true,
  writable: true,
);
const _tags = EntityProperty(
  'tags',
  ListType<String>(ClassType<String>()),
  parameter: true,
  writable: true,
);

EntityIntrospection<Line> _line() => EntityIntrospection<Line>(
  'Line',
  const [
    EntityProperty('sku', ClassType<String>(), parameter: true, writable: true),
    EntityProperty(
      'options',
      MapType<String, String>(ClassType<String>(), ClassType<String>()),
      parameter: true,
      writable: true,
    ),
  ],
  annotations: const [Table('lines')],
  get: (line, i) => i == 0 ? line.sku : line.options,
  create: (v) => Line(
    sku: v[0]! as String,
    options: (v[1]! as Map<Object?, Object?>).cast(),
  ),
  write: (line, i, v) => switch (i) {
    0 => line.sku = v! as String,
    _ => line.options = (v! as Map<Object?, Object?>).cast(),
  },
);

EntityIntrospection<Parcel> _parcel() => EntityIntrospection<Parcel>(
  'Parcel',
  const [
    _id,
    EntityProperty(
      'meta',
      MapType<String, Object?>(ClassType<String>(), DynamicType()),
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'labels',
      SetType<String>(ClassType<String>()),
      parameter: true,
      writable: true,
    ),
    _tags,
    EntityProperty(
      'bytes',
      ListType<int>(ClassType<int>()),
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'raw',
      ClassType<Uint8List>(nullable: true),
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'kept',
      MapType<String, Object?>(ClassType<String>(), DynamicType()),
      annotations: [Json()],
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'lines',
      ListType<Line>(ClassType<Line>()),
      annotations: [MappedCollection()],
      parameter: true,
      writable: true,
    ),
  ],
  annotations: const [Table('parcels')],
  get: (p, i) => [
    p.id,
    p.meta,
    p.labels,
    p.tags,
    p.bytes,
    p.raw,
    p.kept,
    p.lines,
  ][i],
  create: (v) => Parcel(
    id: v[0] as int?,
    meta: (v[1]! as Map<Object?, Object?>).cast(),
    labels: (v[2]! as Set<Object?>).cast(),
    tags: (v[3]! as List<Object?>).cast(),
    bytes: (v[4]! as List<Object?>).cast(),
    raw: v[5] as Uint8List?,
    kept: (v[6]! as Map<Object?, Object?>).cast(),
    lines: (v[7]! as List<Object?>).cast(),
  ),
  write: (p, i, v) => i == 0 ? p.id = v as int? : null,
);

EntityIntrospection<Tagged> _tagged() => EntityIntrospection<Tagged>(
  'Tagged',
  const [
    _id,
    _tags,
    EntityProperty(
      'weights',
      ListType<double>(ClassType<double>()),
      parameter: true,
      writable: true,
    ),
  ],
  annotations: const [Table('tagged')],
  get: (t, i) => [t.id, t.tags, t.weights][i],
  create: (v) => Tagged(
    id: v[0] as int?,
    tags: (v[1]! as List<Object?>).cast(),
    weights: (v[2]! as List<Object?>).cast(),
  ),
  write: (t, i, v) => i == 0 ? t.id = v as int? : null,
);

RelationalMappingContext _context() => RelationalMappingContext(
  introspections: [_parcel(), _line(), _tagged()],
);

String _refused(String where, String type) =>
    '$where: a $type property without @Json has no column on a SQL store: '
    'add @Json() to keep it as JSON, or @MappedCollection for rows of a '
    'child table';

const _meta = ('Parcel.meta', 'Map<String, Object?>');
const _labels = ('Parcel.labels', 'Set<String>');
const _parcelTags = ('Parcel.tags', 'List<String>');
const _options = ('Line.options', 'Map<String, String>');

RepositoryOperations<T, int> _repository<T extends Object>(
  String name,
  DataStore store,
  EntityConverter converter,
) =>
    RepositoryFactory(
      mappingContext: _context(),
      converter: converter,
      stores: [store],
    ).operations<T, int>(
      name,
      annotations: [UseStore(store.name)],
    );

// The repository, the validation and the creation of the schema refuse
// [refused] (and nothing else of Parcel) on [dataSource], whose database
// has no table at all: nothing was sent to it.
Future<void> _refuses(
  DataSource dataSource,
  List<(String, String)> refused,
) async {
  final converter = EntityConverter();
  final store = JdbcDataStore(dataSource: dataSource, converter: converter);
  final expected = [for (final (where, type) in refused) _refused(where, type)];
  final parcel = _context().getRequiredPersistentEntityOfType(Parcel);

  expect(store.mappingProblems(parcel), expected);
  expect(
    () => _repository<Parcel>('Parcels', store, converter),
    throwsA(
      isA<StateError>().having(
        (e) => e.message,
        'message',
        'Invalid repository Parcels:\n'
            '${expected.map((p) => '  - $p').join('\n')}',
      ),
    ),
  );

  final report = await SchemaValidator(dataSource).validate([parcel]);
  expect(report.problems, containsAll(expected));

  final creation = await failure<SchemaException>(
    () async => SchemaCreator(dataSource).createStatements([parcel]),
  );
  for (final problem in expected) {
    expect(creation.message, contains('  - $problem'));
  }
  for (final (where, _) in refused) {
    expect(
      creation.message,
      isNot(contains('$where: ${dataSource.dialect.name} has')),
    );
  }
}

void main() {
  setUpAll(() => SpringLog.handler = (_) {});

  test('the memory store keeps a Map, a Set and a List as they are', () async {
    final converter = EntityConverter();
    final parcels = _repository<Parcel>(
      'Parcels',
      InMemoryDataStore(converter: converter),
      converter,
    );
    final saved = await parcels.save(
      Parcel(
        meta: {'fragile': true},
        labels: {'a', 'b'},
        tags: ['x'],
        bytes: [1, 2],
        kept: {'n': 1},
        lines: [
          Line(sku: 's', options: {'gift': 'yes'}),
        ],
      ),
    );
    final read = (await parcels.findById(saved.id!))!;
    expect(read.meta, {'fragile': true});
    expect(read.labels, {'a', 'b'});
    expect(read.tags, ['x']);
    expect(read.lines.single.options, {'gift': 'yes'});
  });

  group('SQLite', () {
    test('a Map, a Set and a List without @Json are problems of the '
        'repository and of the schema, with the fix; bytes, @Json and '
        '@MappedCollection are not', () async {
      await _refuses(await memorySource(), [
        _meta,
        _labels,
        _parcelTags,
        _options,
      ]);
    });

    test('a list of simple values is refused too: SQLite has no '
        'arrays', () async {
      final dataSource = await memorySource();
      final converter = EntityConverter();
      expect(
        () => _repository<Tagged>(
          'Tags',
          JdbcDataStore(dataSource: dataSource, converter: converter),
          converter,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains(_refused('Tagged.tags', 'List<String>')),
              contains(_refused('Tagged.weights', 'List<double>')),
            ),
          ),
        ),
      );
    });
  });

  group(
    'PostgreSQL',
    () {
      usePostgresServer();

      test('a Map and a Set without @Json are problems of the repository '
          'and of the schema, with the fix; a list of simple values is '
          'not', () async {
        await _refuses(await newPostgresSource(), [_meta, _labels, _options]);
      });

      test('lists of simple values in array columns are stored and read, '
          'and the schema validates', () async {
        final dataSource = await newPostgresSource();
        final converter = EntityConverter();
        final store = JdbcDataStore(
          dataSource: dataSource,
          converter: converter,
        );
        await store.jdbc.execute(
          'create table tagged (id bigint generated by default as identity '
          'primary key, tags text[] not null, '
          'weights double precision[] not null)',
        );
        final tagged = _repository<Tagged>('Tags', store, converter);
        final saved = await tagged.save(
          Tagged(tags: ['a', 'b'], weights: [1.5, 2]),
        );
        final read = (await tagged.findById(saved.id!))!;
        expect(read.tags, ['a', 'b']);
        expect(read.weights, [1.5, 2.0]);
        final report = await SchemaValidator(dataSource).validate([
          _context().getRequiredPersistentEntityOfType(Tagged),
        ]);
        expect(report.problems, isEmpty);
      });
    },
    skip: postgresServerSkip,
    tags: 'postgres',
  );
}
