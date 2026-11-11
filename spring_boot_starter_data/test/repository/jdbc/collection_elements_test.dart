// The elements of a collection are converted as single values are: an enum
// to its name, a BigInt to what the database takes for one, a DateTime as
// one, on the way in (an array column of PostgreSQL, the list of an `In`)
// and on the way out (a text[] into a List of enums), with a
// MappingException naming the property for an element that cannot be
// read. A list the driver has no array of (bytes) gets a marker per value
// in an `In`, and is refused as a column before any statement runs.
import 'dart:typed_data';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../../postgres/support.dart';
import '../../schema/support.dart' show memorySource;

enum Role { admin, editor, reader }

/// Lists in array columns (PostgreSQL), or as they are (the memory store).
@Table('members')
class Member {
  Member({
    this.id,
    this.roles = const [],
    this.amounts = const [],
    this.seen = const [],
    this.names = const [],
    this.counts = const [],
    this.bytes = const [],
  });

  @Id()
  int? id;
  List<Role> roles;
  List<BigInt> amounts;
  List<DateTime> seen;
  List<String?> names;
  List<int?> counts;

  /// Bytes: one `bytea` column, not an array.
  List<int> bytes;
}

/// Single values, for the lists of an `In`: on every store.
@Table('tokens')
class Token {
  Token({this.id, this.role, this.amount, this.key});

  @Id()
  int? id;
  Role? role;
  BigInt? amount;
  Uint8List? key;
}

/// A list no SQL database has a column for.
@Table('blobs')
class Blobs {
  Blobs({this.id, this.parts = const []});

  @Id()
  int? id;
  List<Uint8List> parts;
}

const _role = EnumType<Role>(Role.values);
const _id = EntityProperty(
  'id',
  ClassType<int>(nullable: true),
  annotations: [Id()],
  parameter: true,
  writable: true,
);
const _roles = ListType<Role>(_role);
const _amounts = ListType<BigInt>(ClassType<BigInt>());

EntityProperty _property(String name, TypeInfo<Object?> type) =>
    EntityProperty(name, type, parameter: true, writable: true);

EntityIntrospection<Member> _member() => EntityIntrospection<Member>(
  'Member',
  [
    _id,
    _property('roles', _roles),
    _property('amounts', _amounts),
    _property('seen', const ListType<DateTime>(ClassType<DateTime>())),
    _property(
      'names',
      const ListType<String?>(ClassType<String>(nullable: true)),
    ),
    _property('counts', const ListType<int?>(ClassType<int>(nullable: true))),
    _property('bytes', const ListType<int>(ClassType<int>())),
  ],
  annotations: const [Table('members')],
  get: (m, i) => [
    m.id,
    m.roles,
    m.amounts,
    m.seen,
    m.names,
    m.counts,
    m.bytes,
  ][i],
  create: (v) => Member(
    id: v[0] as int?,
    roles: v[1]! as List<Role>,
    amounts: v[2]! as List<BigInt>,
    seen: v[3]! as List<DateTime>,
    names: v[4]! as List<String?>,
    counts: v[5]! as List<int?>,
    bytes: v[6]! as List<int>,
  ),
  write: (m, i, v) => i == 0 ? m.id = v as int? : null,
);

EntityIntrospection<Token> _token() => EntityIntrospection<Token>(
  'Token',
  [
    _id,
    _property('role', const EnumType<Role>(Role.values, nullable: true)),
    _property('amount', const ClassType<BigInt>(nullable: true)),
    _property('key', const ClassType<Uint8List>(nullable: true)),
  ],
  annotations: const [Table('tokens')],
  get: (t, i) => [t.id, t.role, t.amount, t.key][i],
  create: (v) => Token(
    id: v[0] as int?,
    role: v[1] as Role?,
    amount: v[2] as BigInt?,
    key: v[3] as Uint8List?,
  ),
  write: (t, i, v) => i == 0 ? t.id = v as int? : null,
);

EntityIntrospection<Blobs> _blobs() => EntityIntrospection<Blobs>(
  'Blobs',
  [
    _id,
    _property('parts', const ListType<Uint8List>(ClassType<Uint8List>())),
  ],
  annotations: const [Table('blobs')],
  get: (b, i) => [b.id, b.parts][i],
  create: (v) => Blobs(id: v[0] as int?, parts: v[1]! as List<Uint8List>),
  write: (b, i, v) => i == 0 ? b.id = v as int? : null,
);

RelationalMappingContext _context() => RelationalMappingContext(
  introspections: [_member(), _token(), _blobs()],
);

RepositoryOperations<T, int> _repository<T extends Object>(
  String name,
  DataStore store,
  EntityConverter converter,
) => RepositoryFactory(
  mappingContext: _context(),
  converter: converter,
  stores: [store],
).operations<T, int>(name, annotations: [UseStore(store.name)]);

PartTree _in(String property, {bool not = false}) => PartTree(
  'findBy${property[0].toUpperCase()}${property.substring(1)}'
  '${not ? 'NotIn' : 'In'}',
  [
    OrPart([Part(property, not ? PartType.notIn : PartType.in_)]),
  ],
  sort: Sort.by(['id']),
);

final BigInt _big = BigInt.parse('9007199254740993');
final BigInt _huge = BigInt.parse('123456789012345678901234567890');
final _first = DateTime.utc(2024, 2, 29, 12, 30, 15, 123);
final _second = DateTime.utc(1999, 12, 31, 23, 59, 59);

Member _full() => Member(
  roles: [Role.admin, Role.reader],
  amounts: [_big, BigInt.from(-7)],
  seen: [_first, _second],
  names: ['a b', null, 'quo"te', r'back\slash', '{x,y}', ''],
  counts: [1, null, -3],
  bytes: [0, 1, 255],
);

// A member with every list filled (a null element where the type takes
// one), and one with every list empty, come back as they were saved.
Future<void> _storesLists(RepositoryOperations<Member, int> members) async {
  final saved = await members.save(_full());
  final read = (await members.findById(saved.id!))!;
  expect(read.roles, [Role.admin, Role.reader]);
  expect(read.roles, isA<List<Role>>());
  expect(read.amounts, [_big, BigInt.from(-7)]);
  expect(read.amounts, isA<List<BigInt>>());
  expect(read.seen, [_first, _second]);
  expect(read.seen.every((moment) => moment.isUtc), isTrue);
  expect(read.names, ['a b', null, 'quo"te', r'back\slash', '{x,y}', '']);
  expect(read.counts, [1, null, -3]);
  expect(read.bytes, [0, 1, 255]);

  final empty = await members.save(Member());
  final none = (await members.findById(empty.id!))!;
  expect(none.roles, isEmpty);
  expect(none.amounts, isEmpty);
  expect(none.seen, isEmpty);
  expect(none.names, isEmpty);
  expect(none.counts, isEmpty);
  expect(none.bytes, isEmpty);

  // An update binds the lists as the insert does.
  read
    ..roles = [Role.editor]
    ..amounts = [_huge]
    ..names = [null];
  await members.save(read);
  final updated = (await members.findById(saved.id!))!;
  expect(updated.roles, [Role.editor]);
  expect(updated.amounts, [_huge]);
  expect(updated.names, [null]);
}

// `In` and `NotIn` over enums, BigInts and bytes find the same rows on
// every store; a null in the list takes no part in `In`.
Future<void> _findsIn(RepositoryOperations<Token, int> tokens) async {
  Uint8List bytes(List<int> values) => Uint8List.fromList(values);
  await tokens.saveAll([
    Token(role: Role.admin, amount: _big, key: bytes([1, 2])),
    Token(role: Role.editor, amount: BigInt.two, key: bytes([3])),
    Token(role: Role.reader, amount: _huge, key: bytes([])),
    Token(),
  ]);
  Future<List<int>> ids(PartTree tree, List<Object?> values) async => [
    for (final token in await tokens.list(tree, [values])) token.id!,
  ];

  expect(await ids(_in('role'), [Role.admin, Role.reader]), [1, 3]);
  expect(await ids(_in('role'), <Role?>[Role.editor, null]), [2]);
  expect(await ids(_in('role', not: true), [Role.admin]), [2, 3]);
  expect(await ids(_in('role'), <Role>[]), isEmpty);

  expect(await ids(_in('amount'), [_big, _huge]), [1, 3]);
  expect(await ids(_in('amount'), <BigInt?>[BigInt.two, null]), [2]);
  expect(await ids(_in('amount', not: true), [_big, BigInt.two]), [3]);

  expect(
    await ids(_in('key'), [
      bytes([1, 2]),
      bytes([]),
    ]),
    [1, 3],
  );
  expect(
    await ids(_in('key'), <Uint8List?>[
      bytes([3]),
      null,
    ]),
    [2],
  );
  expect(
    await ids(_in('key', not: true), [
      bytes([3]),
    ]),
    [1, 3],
  );
}

void main() {
  setUpAll(() => SpringLog.handler = (_) {});

  group('EntityConverter', () {
    final converter = EntityConverter();

    test('the elements of a list and of a set are written as single values '
        'are; bytes and a collection with nothing to convert are '
        'untouched', () {
      expect(converter.toColumnValue([Role.admin, null, Role.reader]), [
        'admin',
        null,
        'reader',
      ]);
      expect(converter.toColumnValue({Role.editor}), {'editor'});
      expect(converter.toColumnValue(<Role>[]), isEmpty);
      final texts = ['a', 'b'];
      expect(converter.toColumnValue(texts), same(texts));
      final numbers = [BigInt.one];
      expect(converter.toColumnValue(numbers), same(numbers));
      final bytes = <int>[1, 2];
      expect(converter.toColumnValue(bytes), same(bytes));
      final raw = Uint8List.fromList([1, 2]);
      expect(converter.toColumnValue(raw), same(raw));
    });

    test('the elements of a list and of a set are read as single values '
        'are', () {
      expect(
        converter.fromColumnValue(['admin', 'reader'], _roles),
        allOf(isA<List<Role>>(), [Role.admin, Role.reader]),
      );
      expect(
        converter.fromColumnValue(
          ['reader', null],
          const ListType<Role?>(EnumType<Role>(Role.values, nullable: true)),
        ),
        allOf(isA<List<Role?>>(), [Role.reader, null]),
      );
      expect(
        converter.fromColumnValue(['12', 3], _amounts),
        allOf(isA<List<BigInt>>(), [BigInt.from(12), BigInt.from(3)]),
      );
      expect(
        converter.fromColumnValue([
          'editor',
          'editor',
        ], const SetType<Role>(_role)),
        allOf(isA<Set<Role>>(), {Role.editor}),
      );
      expect(
        converter.fromColumnValue(<Object?>[], _roles),
        allOf(isA<List<Role>>(), isEmpty),
      );
    });

    test('an element that cannot be read is a MappingException naming the '
        'property and the position', () {
      Matcher refuses(String message) => throwsA(
        isA<MappingException>().having((e) => e.message, 'message', message),
      );
      expect(
        () => converter.fromColumnValue(
          ['admin', 'owner'],
          _roles,
          where: 'Member.roles',
        ),
        refuses('Member.roles[1]: "owner" is not a constant of Role'),
      );
      expect(
        () => converter.fromColumnValue(
          ['admin', null],
          _roles,
          where: 'Member.roles',
        ),
        refuses('Member.roles[1] is null but its type Role is not'),
      );
      expect(
        () => converter.fromColumnValue(
          ['1', 'x'],
          _amounts,
          where: 'Member.amounts',
        ),
        refuses('Member.amounts[1]: "x" is not a number'),
      );
      expect(
        () => converter.fromColumnValue(
          [true],
          _amounts,
          where: 'Member.amounts',
        ),
        refuses('Member.amounts[0]: cannot use a bool as BigInt'),
      );
      // Bytes (an array the driver did not decode) are not elements.
      expect(
        () => converter.fromColumnValue(
          Uint8List(2),
          _amounts,
          where: 'Member.amounts',
        ),
        throwsA(
          isA<MappingException>().having(
            (e) => e.message,
            'message',
            allOf(
              startsWith('Member.amounts: cannot use a '),
              endsWith(
                ' as List<BigInt>',
              ),
            ),
          ),
        ),
      );
      expect(
        converter.fromColumnValue(
          Uint8List.fromList([1, 2]),
          const ListType<int>(ClassType<int>()),
        ),
        [1, 2],
      );
    });
  });

  group('the memory store', () {
    late EntityConverter converter;
    late InMemoryDataStore store;

    setUp(() {
      converter = EntityConverter();
      store = InMemoryDataStore(converter: converter);
    });

    test('lists of enums, BigInts, DateTimes, texts and numbers are stored '
        'and read', () async {
      await _storesLists(_repository<Member>('Members', store, converter));
    });

    test('In over enums, BigInts and bytes', () async {
      await _findsIn(_repository<Token>('Tokens', store, converter));
    });
  });

  group('SQLite', () {
    test('In over enums, BigInts and bytes: a marker per value', () async {
      final dataSource = await memorySource();
      final converter = EntityConverter();
      final store = JdbcDataStore(dataSource: dataSource, converter: converter);
      await store.jdbc.execute(
        'create table tokens (id integer primary key, role text, '
        'amount text, key blob)',
      );
      await _findsIn(_repository<Token>('Tokens', store, converter));
    });

    test('a list of bytes is refused as a column', () async {
      final dataSource = await memorySource();
      final converter = EntityConverter();
      expect(
        () => _repository<Blobs>(
          'Blobs',
          JdbcDataStore(dataSource: dataSource, converter: converter),
          converter,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(
              CollectionColumns.problem('Blobs.parts', 'List<Uint8List>'),
            ),
          ),
        ),
      );
    });
  });

  group('PostgresDialect', () {
    const dialect = PostgresDialect();

    test('the elements of a list go as single values do; a List<int> is '
        'bytes', () {
      expect(dialect.toDatabase(<Object?>[_big, null]), ['$_big', null]);
      expect(
        dialect.toDatabase([DateTime.parse('2024-02-29T12:00:00+02:00')]),
        [DateTime.utc(2024, 2, 29, 10)],
      );
      expect(dialect.toDatabase(<int?>[1, null]), [1, null]);
      expect(dialect.toDatabase(<int>[1, 2]), isA<Uint8List>());
      expect(dialect.toDatabase(<Object?>[]), isEmpty);
    });

    test('the elements of an array are read as single values are', () {
      expect(dialect.fromDatabase(['12', 3, '4.00'], _amounts), [
        BigInt.from(12),
        BigInt.from(3),
        BigInt.from(4),
      ]);
      expect(
        dialect.fromDatabase(
          [1, null],
          const ListType<int?>(ClassType<int>(nullable: true)),
        ),
        [1, null],
      );
      expect(
        dialect.fromDatabase([
          1,
          2,
        ], const ListType<int>(ClassType<int>())),
        isA<Uint8List>(),
      );
    });

    test('an array of one kind of simple values is one parameter; bytes '
        'and mixed kinds are not', () {
      expect(dialect.bindsAsArray(['a', null, 'b']), isTrue);
      expect(dialect.bindsAsArray([1, 2.5]), isTrue);
      expect(dialect.bindsAsArray([_big, 'x']), isTrue);
      expect(dialect.bindsAsArray([DateTime.utc(2024)]), isTrue);
      expect(dialect.bindsAsArray([true, false]), isTrue);
      expect(dialect.bindsAsArray(<Object?>[]), isTrue);
      expect(dialect.bindsAsArray([null]), isTrue);
      expect(dialect.bindsAsArray([Uint8List(1)]), isFalse);
      expect(dialect.bindsAsArray([1, 'a']), isFalse);
      expect(dialect.bindsAsArray([Object()]), isFalse);
    });

    test('a list of enums, BigInts or DateTimes is an array column; a list '
        'of bytes is not', () {
      expect(dialect.storesCollection(_roles), isTrue);
      expect(dialect.storesCollection(_amounts), isTrue);
      expect(
        dialect.storesCollection(
          const ListType<Uint8List>(ClassType<Uint8List>()),
        ),
        isFalse,
      );
      expect(
        dialect.storesCollection(
          const ListType<List<int>>(ListType<int>(ClassType<int>())),
        ),
        isFalse,
      );
    });
  });

  group(
    'PostgreSQL',
    () {
      usePostgresServer();

      late EntityConverter converter;
      late JdbcDataStore store;
      final statements = <String>[];

      setUp(() async {
        converter = EntityConverter();
        store = JdbcDataStore(
          dataSource: await newPostgresSource(),
          converter: converter,
        );
        statements.clear();
      });

      test('lists of enums, BigInts, DateTimes, texts and numbers are '
          'stored in array columns and read, a List<int> in a bytea', () async {
        await store.jdbc.execute(
          'create table members (id bigint generated by default as '
          'identity primary key, roles text[] not null, '
          'amounts text[] not null, seen timestamptz[] not null, '
          'names text[] not null, counts bigint[] not null, '
          'bytes bytea not null)',
        );
        final members = _repository<Member>('Members', store, converter);
        await _storesLists(members);
        // What the database holds: the names, the digits, one array.
        final row = (await store.jdbc.queryForMaps(
          'select roles::text, amounts::text, names[2] is null as hole, '
          'cardinality(seen) as moments from members where id = 1',
        )).single;
        expect(row['roles'], '{editor}');
        expect(row['amounts'], '{$_huge}');
        expect(row['moments'], 2);
        final report = await SchemaValidator(store.dataSource).validate([
          _context().getRequiredPersistentEntityOfType(Member),
        ]);
        expect(report.problems, isEmpty);
      });

      test('a List<BigInt> in a bigint[] column', () async {
        await store.jdbc.execute(
          'create table members (id bigint generated by default as '
          'identity primary key, roles text[] not null, '
          'amounts bigint[] not null, seen timestamptz[] not null, '
          'names text[] not null, counts bigint[] not null, '
          'bytes bytea not null)',
        );
        final members = _repository<Member>('Members', store, converter);
        final saved = await members.save(
          Member(amounts: [_big, BigInt.from(-7)]),
        );
        expect((await members.findById(saved.id!))!.amounts, [
          _big,
          BigInt.from(-7),
        ]);
      });

      test('an element of an array that is no constant of the enum is a '
          'MappingException naming the property', () async {
        await store.jdbc.execute(
          'create table members (id bigint primary key, roles text[], '
          'amounts text[], seen timestamptz[], names text[], '
          'counts bigint[], bytes bytea)',
        );
        await store.jdbc.execute(
          "insert into members values (1, '{admin,owner}', '{}', '{}', "
          "'{}', '{}', '')",
        );
        final members = _repository<Member>('Members', store, converter);
        await expectLater(
          members.findById(1),
          throwsA(
            isA<MappingException>().having(
              (e) => e.message,
              'message',
              'Member.roles[1]: "owner" is not a constant of Role',
            ),
          ),
        );
      });

      test('In over enums and BigInts is one array parameter, over bytes '
          'a marker per value', () async {
        await store.jdbc.execute(
          'create table tokens (id bigint generated by default as identity '
          'primary key, role text, amount numeric, key bytea)',
        );
        final tokens = _repository<Token>('Tokens', store, converter);
        await _findsIn(tokens);

        final sql = SqlGenerator(dialect: store.dialect, converter: converter);
        final entity = _context().getRequiredPersistentEntityOfType(Token);
        String where(String property, List<Object?> values) => sql
            .select(
              entity,
              criteria: Criteria(_in(property).predicate, [values]),
            )
            .sql;
        expect(where('role', [Role.admin, Role.reader]), contains('= any(?)'));
        expect(where('amount', [_big, _huge]), contains('= any(?)'));
        expect(
          where('key', [Uint8List(1), Uint8List(2)]),
          contains('in (?, ?)'),
        );
      });

      test('a list of bytes is refused as a column before any statement '
          'runs', () async {
        expect(
          () => _repository<Blobs>('Blobs', store, converter),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains(
                CollectionColumns.problem('Blobs.parts', 'List<Uint8List>'),
              ),
            ),
          ),
        );
      });
    },
    skip: postgresServerSkip,
    tags: 'postgres',
  );
}
