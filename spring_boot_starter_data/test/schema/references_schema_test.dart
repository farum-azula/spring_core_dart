// Foreign keys, indexes and unique constraints in the schemas the starter
// writes and checks: the DDL, the order of the tables (also with a cycle),
// create-drop, and the validation against a real SQLite database.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/references_mapping_test.dart' hide main;
import 'support.dart';

class Post extends Row {}

class Ca extends Row {}

class Cb extends Row {}

class Tree extends Row {}

BeanIntrospection<Post> post() => describe<Post>(
  'Post',
  [
    col<Post>('id', int, intN, annotations: const [Id()]),
    col<Post>(
      'writer',
      AggregateReference<Writer, int>,
      ref<Writer, int>(),
      annotations: const [OnDelete(OnDeleteAction.cascade)],
    ),
    col<Post>(
      'editorId',
      int,
      intN,
      annotations: const [Reference(Writer)],
    ),
    col<Post>('title', String, string, annotations: const [Unique()]),
    col<Post>('slug', String, string),
  ],
  annotations: const [
    Table('posts'),
    UniqueConstraint(['writer', 'slug'], name: 'uq_posts_writer_slug'),
  ],
);

// Two tables that reference each other.
BeanIntrospection<Ca> ca() => describe<Ca>(
  'Ca',
  [
    col<Ca>('id', int, intN, annotations: const [Id()]),
    col<Ca>('bId', int, intN, annotations: const [Reference(Cb)]),
  ],
  annotations: const [Table('cas')],
);

BeanIntrospection<Cb> cb() => describe<Cb>(
  'Cb',
  [
    col<Cb>('id', int, intN, annotations: const [Id()]),
    col<Cb>('aId', int, intN, annotations: const [Reference(Ca)]),
  ],
  annotations: const [Table('cbs')],
);

BeanIntrospection<Tree> tree(OnDeleteAction action) => describe<Tree>(
  'Tree',
  [
    col<Tree>('id', int, intN, annotations: const [Id()]),
    col<Tree>(
      'parentId',
      int,
      intN,
      annotations: [const Reference(Tree), OnDelete(action)],
      // setDefault needs a default value.
      hasInitialValue: action == OnDeleteAction.setDefault,
    ),
  ],
  annotations: const [Table('trees')],
);

const intN = ClassType<int>(nullable: true);
const string = ClassType<String>();

/// A data source of another one's database, with SQL of its own.
class DialectDataSource extends DriverDataSource {
  DialectDataSource(DataSource real, this.custom)
    : _real = real,
      super(name: 'custom', driver: real.driver, settings: real.settings);

  final DataSource _real;
  final SqlDialect custom;

  @override
  SqlDialect get dialect => custom;

  @override
  Future<JdbcConnection> getConnection() => _real.getConnection();

  @override
  Future<void> releaseConnection(JdbcConnection connection) =>
      _real.releaseConnection(connection);
}

/// SQLite's SQL, which the dialects below change a little.
base class LiteDialect extends SqlDialect {
  const LiteDialect();

  static const _sqlite = SqliteDialect();

  @override
  String get name => 'lite';

  @override
  String lower(String expression) => _sqlite.lower(expression);

  @override
  bool get likeIgnoresCase => true;

  @override
  LockStrategy get lockStrategy => _sqlite.lockStrategy;

  @override
  String lockClause(
    LockMode mode, {
    Duration? timeout,
    bool skipLocked = false,
  }) => '';

  @override
  String identityColumn(TypeInfo<Object?> type) => _sqlite.identityColumn(type);

  @override
  String? columnType(TypeInfo<Object?> type) => _sqlite.columnType(type);

  @override
  bool columnFits(String declared, TypeInfo<Object?> type) =>
      _sqlite.columnFits(declared, type);

  @override
  Set<Isolation> get isolationLevels => _sqlite.isolationLevels;

  @override
  List<String> get beforeDropStatements => _sqlite.beforeDropStatements;

  @override
  Future<List<ColumnInfo>?> describeTable(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) => _sqlite.describeTable(connection, table, schema);

  @override
  Future<List<ForeignKeyInfo>?> describeForeignKeys(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) => _sqlite.describeForeignKeys(connection, table, schema);

  @override
  Future<List<UniqueInfo>?> describeUniqueKeys(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) => _sqlite.describeUniqueKeys(connection, table, schema);

  @override
  DataAccessException translate(SqlError error, {String? sql}) =>
      _sqlite.translate(error, sql: sql);
}

/// A database that cannot have a key to a table that does not exist yet,
/// and drops with CASCADE what others reference.
final class StrictDialect extends LiteDialect {
  const StrictDialect();

  @override
  bool get supportsForwardForeignKeys => false;

  @override
  List<String> get beforeDropStatements => const [];

  @override
  String dropTableStatement(
    String table, {
    String? schema,
    bool referenced = false,
  }) =>
      'DROP TABLE IF EXISTS ${this.table(table, schema)}'
      '${referenced ? ' CASCADE' : ''}';
}

/// A dialect that cannot describe keys.
final class BlindDialect extends LiteDialect {
  const BlindDialect();

  @override
  Future<List<ForeignKeyInfo>?> describeForeignKeys(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) async => null;

  @override
  Future<List<UniqueInfo>?> describeUniqueKeys(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) async => null;
}

void main() {
  late RelationalMappingContext context;
  late PersistentEntity<Post> posts;

  setUp(() {
    context = contextOf([
      post(),
      writer(),
      ca(),
      cb(),
      tree(OnDeleteAction.noAction),
    ]);
    posts = context.getRequiredPersistentEntity<Post>();
  });

  PersistentEntity<Object> entityOf(Type type) =>
      context.getRequiredPersistentEntityOfType(type);

  group('the statements', () {
    test(
      'a reference is a foreign key with its action, an index and a key',
      () async {
        final statements = SchemaCreator(
          await memorySource(),
        ).createStatements([posts]);
        final tables = statements.where((s) => s.startsWith('CREATE TABLE'));
        // The table referenced comes first, though only the post is given.
        expect(tables.first, contains('"writers"'));
        final sql = tables.last;
        expect(
          sql,
          contains(
            '"writer" INTEGER NOT NULL REFERENCES "writers" ("id") ON '
            'DELETE CASCADE',
          ),
        );
        // No action, no clause.
        expect(
          sql,
          contains('"editor_id" INTEGER REFERENCES "writers" ("id"),'),
        );
        expect(sql, contains('CONSTRAINT "uq_posts_title" UNIQUE ("title")'));
        expect(
          sql,
          contains(
            'CONSTRAINT "uq_posts_writer_slug" UNIQUE ("writer", "slug")',
          ),
        );
        final indexes = statements.where((s) => s.startsWith('CREATE INDEX'));
        expect(indexes, hasLength(2));
        expect(
          indexes.first,
          'CREATE INDEX IF NOT EXISTS "idx_posts_writer" ON "posts" '
          '("writer")',
        );
        expect(
          indexes.last,
          'CREATE INDEX IF NOT EXISTS "idx_posts_editor_id" ON "posts" '
          '("editor_id")',
        );
      },
    );

    test('every action has its clause', () async {
      final db = await memorySource();
      for (final (action, clause) in [
        (OnDeleteAction.noAction, ''),
        (OnDeleteAction.restrict, ' ON DELETE RESTRICT'),
        (OnDeleteAction.cascade, ' ON DELETE CASCADE'),
        (OnDeleteAction.setNull, ' ON DELETE SET NULL'),
        (OnDeleteAction.setDefault, ' ON DELETE SET DEFAULT'),
      ]) {
        final type = action == OnDeleteAction.setDefault
            ? 'INTEGER DEFAULT NULL'
            : 'INTEGER';
        final trees = contextOf([
          tree(action),
        ]).getRequiredPersistentEntity<Tree>();
        final sql = SchemaCreator(db).createStatements([trees]).first;
        expect(
          sql,
          contains('"parent_id" $type REFERENCES "trees" ("id")$clause\n'),
          reason: action.name,
        );
      }
    });

    test(
      'a table comes after the tables it references, in any order',
      () async {
        final db = await memorySource();
        final order = SchemaCreator(db)
            .createStatements([posts, entityOf(Writer)])
            .where((s) => s.startsWith('CREATE TABLE'))
            .map((s) => RegExp(r'"(\w+)"').firstMatch(s)!.group(1))
            .toList();
        expect(order, ['writers', 'posts']);
      },
    );

    test('a self-reference needs no other table and no index of its own '
        'primary key', () async {
      final db = await memorySource();
      final statements = SchemaCreator(db).createStatements([
        entityOf(Tree),
      ]);
      expect(
        statements.where((s) => s.startsWith('CREATE TABLE')),
        hasLength(1),
      );
      expect(statements.last, contains('"idx_trees_parent_id"'));
    });

    test(
      'a unique reference gets no second index (the unique key serves)',
      () async {
        final unique = describe<Post>(
          'Post',
          [
            col<Post>('id', int, intN, annotations: const [Id()]),
            col<Post>(
              'writerId',
              int,
              intN,
              annotations: const [Reference(Writer), Unique()],
            ),
          ],
          annotations: const [Table('posts')],
        );
        final e = contextOf([unique, writer()])
            .getRequiredPersistentEntity<Post>();
        final statements = SchemaCreator(
          await memorySource(),
        ).createStatements([e]);
        expect(statements.where((s) => s.startsWith('CREATE INDEX')), isEmpty);
      },
    );
  });

  group('a cycle of references', () {
    test('SQLite takes the keys in CREATE TABLE, forward ones too', () async {
      final db = await memorySource();
      final statements = SchemaCreator(
        db,
      ).createStatements([entityOf(Ca), entityOf(Cb)]);
      expect(statements.where((s) => s.startsWith('ALTER')), isEmpty);
      expect(statements.join('\n'), contains('REFERENCES "cbs" ("id")'));
      expect(statements.join('\n'), contains('REFERENCES "cas" ("id")'));
    });

    test(
      'create and create-drop work, with rows that reference each other',
      () async {
        final db = await memorySource();
        final creator = SchemaCreator(db);
        final entities = [entityOf(Ca), entityOf(Cb)];
        await creator.create(entities);
        await run(db, 'INSERT INTO cas (id) VALUES (1)');
        await run(db, 'INSERT INTO cbs (id, a_id) VALUES (1, 1)');
        await run(db, 'UPDATE cas SET b_id = 1');
        // A row cannot reference what is not there, whichever table.
        await expectLater(
          run(db, 'INSERT INTO cbs (id, a_id) VALUES (2, 9)'),
          throwsA(isA<Object>()),
        );
        expect(await tablesOf(db), ['cas', 'cbs']);
        // The tables hold rows that reference each other: they still go.
        await creator.drop(entities);
        expect(await tablesOf(db), isEmpty);
      },
    );

    test(
      'a database that cannot have forward keys gets them with ALTER TABLE',
      () async {
        final db = DialectDataSource(
          await memorySource(),
          const StrictDialect(),
        );
        final creator = SchemaCreator(db);
        final entities = [entityOf(Ca), entityOf(Cb)];
        final statements = creator.createStatements(entities);
        final tables = statements.where((s) => s.startsWith('CREATE TABLE'));
        // The first table cannot reference the second yet: no key inline.
        expect(tables.first, contains('"cbs"'));
        expect(tables.first, isNot(contains('REFERENCES')));
        // The second can reference the first.
        expect(tables.last, contains('REFERENCES "cbs" ("id")'));
        expect(
          statements.singleWhere((s) => s.startsWith('ALTER TABLE')),
          'ALTER TABLE "cbs" ADD CONSTRAINT "fk_cbs_a_id" FOREIGN KEY '
          '("a_id") REFERENCES "cas" ("id")',
        );
        // The ALTER TABLE comes after every CREATE TABLE.
        expect(
          statements.indexWhere((s) => s.startsWith('ALTER')),
          greaterThan(
            statements.lastIndexWhere((s) => s.startsWith('CREATE TABLE')),
          ),
        );
        // The dialect's own drop, and no pragma of SQLite's.
        expect(creator.dropStatements(entities), [
          'DROP TABLE IF EXISTS "cas" CASCADE',
          'DROP TABLE IF EXISTS "cbs" CASCADE',
        ]);
      },
    );

    test(
      'the drop statements of SQLite defer the keys only for a cycle',
      () async {
        final creator = SchemaCreator(await memorySource());
        expect(
          creator.dropStatements([entityOf(Ca), entityOf(Cb)]).first,
          'PRAGMA defer_foreign_keys = ON',
        );
        expect(creator.dropStatements([posts]), [
          'DROP TABLE IF EXISTS "posts"',
          'DROP TABLE IF EXISTS "writers"',
        ]);
        expect(creator.dropStatements([entityOf(Tree)]), [
          'DROP TABLE IF EXISTS "trees"',
        ]);
      },
    );
  });

  group('create-drop with references', () {
    test('the tables are created, enforce the keys and are dropped', () async {
      final db = await memorySource();
      final creator = SchemaCreator(db);
      await creator.create([posts]);
      expect(await tablesOf(db), ['posts', 'writers']);
      await run(db, "INSERT INTO writers (id, name) VALUES (1, 'w')");
      await run(
        db,
        "INSERT INTO posts (writer, title, slug) VALUES (1, 't', 's')",
      );
      await expectLater(
        run(
          db,
          "INSERT INTO posts (writer, title, slug) VALUES (2, 'u', 'v')",
        ),
        throwsA(isA<SqlError>()),
      );
      await expectLater(
        run(
          db,
          "INSERT INTO posts (writer, title, slug) VALUES (1, 't', 'x')",
        ),
        throwsA(isA<SqlError>()),
      );
      // The writer's delete cascades to the post.
      await run(db, 'DELETE FROM writers WHERE id = 1');
      expect(await value(db, 'SELECT count(*) FROM posts'), 0);
      await creator.drop([posts]);
      expect(await tablesOf(db), isEmpty);
    });
  });

  group('validation', () {
    const writersTable =
        'CREATE TABLE writers (id INTEGER PRIMARY KEY, name TEXT NOT NULL)';

    // posts, with what each test changes in its definition.
    String postsTable({
      String writer = 'REFERENCES writers (id) ON DELETE CASCADE',
      String editor = 'REFERENCES writers (id)',
      String uniques =
          ', CONSTRAINT uq_posts_title UNIQUE (title), '
          'CONSTRAINT uq_posts_writer_slug UNIQUE (writer, slug)',
    }) =>
        'CREATE TABLE posts (id INTEGER PRIMARY KEY, '
        'writer INTEGER NOT NULL $writer, editor_id INTEGER $editor, '
        'title TEXT NOT NULL, slug TEXT NOT NULL$uniques)';

    Future<DataSource> database([String? table]) async {
      final db = await memorySource();
      await run(db, writersTable);
      await run(db, table ?? postsTable());
      return db;
    }

    Future<SchemaValidationReport> validate(
      DataSource db, [
      List<PersistentEntity<Object>>? entities,
    ]) => SchemaValidator(db).validate(entities ?? [posts]);

    test('a schema the creator wrote is valid, without warnings', () async {
      final db = await memorySource();
      await SchemaCreator(db).create([posts]);
      final report = await validate(db);
      expect(report.problems, isEmpty);
      expect(report.warnings, isEmpty);
    });

    test(
      'UNIQUE constraints (sqlite_autoindex) and unique indexes count',
      () async {
        final db = await database(
          postsTable(uniques: '').replaceFirst(
            'title TEXT NOT NULL',
            'title TEXT NOT NULL UNIQUE',
          ),
        );
        // The inline UNIQUE is an `sqlite_autoindex_posts_1`.
        expect(
          await value(
            db,
            'SELECT count(*) FROM sqlite_master WHERE name LIKE '
            "'sqlite_autoindex_posts%'",
          ),
          1,
        );
        await run(
          db,
          'CREATE UNIQUE INDEX posts_writer_slug ON posts (slug, writer)',
        );
        // The order of the columns of a unique index does not matter.
        final report = await validate(db);
        expect(report.problems, isEmpty);
      },
    );

    test('a missing foreign key is a warning for a plain reference', () async {
      final db = await database(postsTable(editor: ''));
      final report = await validate(db);
      expect(report.problems, isEmpty);
      expect(report.warnings, hasLength(1));
      expect(report.warnings.single, contains('"editor_id"'));
      expect(report.warnings.single, contains('has no foreign key'));
      expect(report.warnings.single, contains('Post.editorId'));
      expect(report.warnings.single, contains('not enforced'));
    });

    test(
      'a missing foreign key is an error with an explicit @OnDelete',
      () async {
        final db = await database(postsTable(writer: ''));
        final report = await validate(db);
        expect(report.warnings, isEmpty);
        expect(report.problems, hasLength(1));
        expect(report.problems.single, contains('Missing foreign key'));
        expect(report.problems.single, contains('"writer"'));
        expect(report.problems.single, contains('ON DELETE CASCADE'));
      },
    );

    test(
      'a wrong action is an error when explicit, a warning when not',
      () async {
        var db = await database(
          postsTable(writer: 'REFERENCES writers (id) ON DELETE SET NULL'),
        );
        var report = await validate(db);
        expect(report.problems, hasLength(1));
        expect(report.problems.single, contains('wrong action'));
        expect(report.problems.single, contains('expected ON DELETE CASCADE'));
        expect(report.problems.single, contains('found SET NULL'));
        // The plain reference expects no action: CASCADE would differ.
        db = await database(
          postsTable(editor: 'REFERENCES writers (id) ON DELETE CASCADE'),
        );
        report = await validate(db);
        expect(report.problems, isEmpty);
        expect(report.warnings.single, contains('found CASCADE'));
      },
    );

    test('RESTRICT and NO ACTION are the same for a plain reference', () async {
      final db = await database(
        postsTable(editor: 'REFERENCES writers (id) ON DELETE RESTRICT'),
      );
      final report = await validate(db);
      expect(report.problems, isEmpty);
      expect(report.warnings, isEmpty);
    });

    test('a key to another table is reported', () async {
      final db = await memorySource();
      await run(db, writersTable);
      await run(db, 'CREATE TABLE others (id INTEGER PRIMARY KEY)');
      await run(
        db,
        postsTable(writer: 'REFERENCES others (id) ON DELETE CASCADE'),
      );
      final report = await validate(db);
      expect(report.problems.single, contains('references "others"'));
      expect(report.problems.single, contains('"writers"'));
    });

    test('a missing unique constraint is an error naming it', () async {
      final db = await database(postsTable(uniques: ''));
      final report = await validate(db);
      expect(report.problems, hasLength(2));
      final title = report.problems.singleWhere(
        (p) => p.contains('uq_posts_title'),
      );
      expect(title, contains('Missing unique constraint'));
      expect(title, contains('Post.title (@Unique)'));
      expect(title, contains('"title"'));
      final composite = report.problems.singleWhere(
        (p) => p.contains('uq_posts_writer_slug'),
      );
      expect(composite, contains('@UniqueConstraint(writer, slug) of Post'));
      expect(composite, contains('"writer", "slug"'));
    });

    test('a unique constraint on other columns, or a partial index, '
        'does not do', () async {
      final db = await database(
        postsTable(
          uniques: ', UNIQUE (title, slug), UNIQUE (writer, slug, title)',
        ),
      );
      await run(db, "CREATE UNIQUE INDEX p ON posts (title) WHERE title > 'x'");
      final report = await validate(db);
      expect(report.problems, hasLength(2));
    });

    test('every problem is reported at once, and as one error', () async {
      final db = await database(postsTable(writer: '', uniques: ''));
      final error = await failure<SchemaValidationException>(
        () => SchemaValidator(db).validateOrThrow([posts]),
      );
      expect(error.problems, hasLength(3));
      expect(error.message, contains('3 problems'));
    });

    test(
      'a dialect that cannot describe keys is skipped, with a note',
      () async {
        final db = await database(postsTable(writer: '', uniques: ''));
        final blind = DialectDataSource(db, const BlindDialect());
        SpringLog.setLevel('spring.data.jdbc.schema', SpringLogLevel.debug);
        addTearDown(SpringLog.resetLevels);
        late SchemaValidationReport report;
        final lines = await logged(() async {
          report = await validate(blind);
        });
        expect(report.problems, isEmpty);
        expect(
          lines.where((l) => l.contains('cannot describe foreign keys')),
          isNotEmpty,
        );
        expect(
          lines.where((l) => l.contains('cannot describe unique constraints')),
          isNotEmpty,
        );
      },
    );

    test('the referenced table is checked too', () async {
      final db = await memorySource();
      await run(db, postsTable());
      final report = await validate(db);
      expect(
        report.problems.any((p) => p.contains('Missing table "writers"')),
        isTrue,
      );
    });
  });

  group('what SQLite reports of the keys', () {
    test(
      'foreign keys with their actions, unique keys of every origin',
      () async {
        final db = await memorySource();
        await run(db, 'CREATE TABLE p (id INTEGER PRIMARY KEY, code TEXT)');
        await run(
          db,
          'CREATE TABLE c (id INTEGER PRIMARY KEY, a INTEGER REFERENCES p '
          '(id) ON DELETE SET NULL, b INTEGER REFERENCES p ON DELETE '
          'RESTRICT, d INTEGER REFERENCES p (id) ON DELETE SET DEFAULT, '
          'e INTEGER REFERENCES p (id) ON DELETE CASCADE, f INTEGER '
          'REFERENCES p (id), x TEXT UNIQUE, y TEXT, z TEXT, '
          'UNIQUE (y, z))',
        );
        await run(db, 'CREATE UNIQUE INDEX i ON c (z, x)');
        await run(db, 'CREATE UNIQUE INDEX part ON c (a) WHERE a > 1');
        await run(db, 'CREATE INDEX plain ON c (b)');
        await using(db, (connection) async {
          final keys = {
            for (final k in (await db.dialect.describeForeignKeys(
              connection,
              'c',
            ))!)
              k.column: k,
          };
          expect(keys['a']!.onDelete, OnDeleteAction.setNull);
          expect(keys['b']!.onDelete, OnDeleteAction.restrict);
          expect(keys['b']!.parentColumn, isNull);
          expect(keys['d']!.onDelete, OnDeleteAction.setDefault);
          expect(keys['e']!.onDelete, OnDeleteAction.cascade);
          expect(keys['f']!.onDelete, OnDeleteAction.noAction);
          expect(keys['f']!.parentTable, 'p');
          expect(keys['f']!.parentColumn, 'id');
          expect(
            await db.dialect.describeForeignKeys(connection, 'p'),
            isEmpty,
          );

          final unique = [
            for (final u in (await db.dialect.describeUniqueKeys(
              connection,
              'c',
            ))!)
              u.columns.join(','),
          ];
          // The UNIQUE constraints (autoindex) and the unique index; neither
          // the partial one nor the plain one; the rowid alias is the key.
          expect(unique, unorderedEquals(['x', 'y,z', 'z,x', 'id']));
          expect(
            [
              for (final u in (await db.dialect.describeUniqueKeys(
                connection,
                'c',
              ))!)
                u.name,
            ],
            contains(startsWith('sqlite_autoindex_c_')),
          );
        });
      },
    );
  });
}
