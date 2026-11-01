// The glue the generator writes for a database driver package: a module of
// an application that depends on `sqlite3` and on spring_boot_starter_data
// gets the starter's template (resolved with the library's import
// prefixes) and a `JdbcDriver` bean definition; without either dependency,
// or without the starter's template, nothing is added.
//
// The starter and `sqlite3` are replaced by small fakes: the generated code
// must compile against the signatures the real template uses.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _template =
    'spring_boot_starter_data|'
    'lib/src/jdbc/drivers/sqlite3.dart.tmpl';

const _starterFake = '''
import 'package:spring_core_dart/spring_core_dart.dart';

export 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class JdbcDriver {}

final class SqlError implements Exception {
  const SqlError(this.message, {this.vendorCode, this.extendedCode});
  final String message;
  final int? vendorCode;
  final int? extendedCode;
}

enum SqliteOpenMode { readOnly, readWrite, readWriteCreate }

abstract interface class SqliteBinding {
  SqliteDatabase open(
    String filename, {
    SqliteOpenMode mode = SqliteOpenMode.readWriteCreate,
    bool uri = false,
  });
}

abstract interface class SqliteDatabase {
  void execute(String sql, [List<Object?> parameters = const []]);
  ({List<String> columns, List<List<Object?>> rows}) select(
    String sql, [
    List<Object?> parameters = const [],
  ]);
  SqliteCursor cursor(String sql, [List<Object?> parameters = const []]);
  int get updatedRows;
  int get lastInsertRowId;
  bool get autocommit;
  void close();
}

abstract interface class SqliteCursor {
  List<String> get columns;
  List<Object?>? next();
  void close();
}

final class SqliteJdbcDriver implements JdbcDriver {
  SqliteJdbcDriver(this.binding);
  final SqliteBinding binding;
}

class ConditionalOnMissingBean implements Condition {
  const ConditionalOnMissingBean.named(this.name);
  final String name;

  @override
  bool matches(ConditionContext context) => true;
}
''';

const _sqlite3Fake = '''
class SqliteException implements Exception {
  SqliteException({required this.extendedResultCode, required this.message});
  final String message;
  final int extendedResultCode;
  int get resultCode => extendedResultCode & 0xFF;
}

enum OpenMode { readOnly, readWrite, readWriteCreate }

class Row {
  dynamic columnAt(int i) => null;
}

class ResultSet {
  List<String> get columnNames => [];
  List<List<Object?>> get rows => [];
}

abstract class IteratingCursor implements Iterator<Row> {
  List<String> get columnNames;
}

abstract class PreparedStatement {
  IteratingCursor selectCursor([List<Object?> parameters = const []]);
  void close();
}

final class AllowedArgumentCount {
  const AllowedArgumentCount(this.allowedArgs);
  const AllowedArgumentCount.any() : allowedArgs = -1;
  final int allowedArgs;
}

abstract class SqliteArguments implements List<Object?> {}

abstract class Database {
  void execute(String sql, [List<Object?> parameters = const []]);
  ResultSet select(String sql, [List<Object?> parameters = const []]);
  PreparedStatement prepare(String sql);
  void createFunction({
    required String functionName,
    required Object? Function(SqliteArguments arguments) function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
    bool subtype = false,
  });
  int get updatedRows;
  int get lastInsertRowId;
  bool get autocommit;
  void close();
}

abstract class Sqlite3 {
  Database open(
    String filename, {
    String? vfs,
    OpenMode mode = OpenMode.readWriteCreate,
    bool uri = false,
    bool? mutex,
  });
}

const Sqlite3 sqlite3 = _Sqlite3();

class _Sqlite3 implements Sqlite3 {
  const _Sqlite3();

  @override
  Database open(
    String filename, {
    String? vfs,
    OpenMode mode = OpenMode.readWriteCreate,
    bool uri = false,
    bool? mutex,
  }) => throw UnimplementedError();
}
''';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _service = '''
import 'package:spring_core_dart/spring_core_dart.dart';

@Service()
class Greeter {}
''';

String _pubspec({
  bool sqlite = true,
  bool starter = true,
  bool dev = false,
}) {
  final dependencies = [
    if (starter) '  spring_boot_starter_data: any',
    if (sqlite && !dev) '  sqlite3: any',
  ];
  return [
    'name: pkg',
    'dependencies:',
    ...dependencies,
    if (sqlite && dev) ...['dev_dependencies:', '  sqlite3: any'],
  ].join('\n');
}

Map<String, Object> _sources({
  String? pubspec,
}) => {
  'pkg|pubspec.yaml': pubspec ?? _pubspec(),
  'spring_boot_starter_data|lib/spring_boot_starter_data.dart': _starterFake,
  'sqlite3|lib/sqlite3.dart': _sqlite3Fake,
  'pkg|lib/src/beans.dart': _scan,
  'pkg|lib/src/service.dart': _service,
};

Future<String> _build(
  Map<String, Object> sources, {
  bool template = true,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  // The isolate's sources include the real starter: its real template is
  // the one under test.
  await readerWriter.testing.loadIsolateSources();
  if (!template) {
    readerWriter.testing.delete(AssetId.parse(_template));
  }
  final result = await testBuilder(
    SpringBuilder(),
    sources,
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  return result.readerWriter.testing.readString(result.outputs.single);
}

String _normalize(String code) => code.replaceAll(RegExp(r'\s'), '');

void main() {
  group('with sqlite3 and the starter among the dependencies', () {
    late String output;

    setUpAll(() async => output = await _build(_sources()));

    test('the glue classes are written into the module', () {
      for (final name in [
        r'class _$Sqlite3Binding',
        r'class _$Sqlite3Database',
        r'class _$Sqlite3Cursor',
        r'_$sqlite3Guard<T>',
      ]) {
        expect(output, contains(name));
      }
    });

    test('the symbols get the library import prefixes', () {
      expect(output, isNot(contains('{{')));
      expect(output, isNot(contains('}}')));
      final sqlite = RegExp(
        r"import 'package:sqlite3/sqlite3.dart' as (_i\d+);",
      ).firstMatch(output);
      expect(sqlite, isNotNull);
      final starter = RegExp(
        "import 'package:spring_boot_starter_data/"
        r"spring_boot_starter_data.dart'\s+as (_i\d+);",
      ).firstMatch(output);
      expect(starter, isNotNull);
      final s = sqlite![1];
      final d = starter![1];
      expect(output, contains('$s.sqlite3.open('));
      expect(output, contains('$s.OpenMode.values.byName(mode.name)'));
      expect(output, contains('on $s.SqliteException catch'));
      expect(output, contains('implements $d.SqliteBinding'));
      expect(output, contains('$d.SqlError('));
      expect(output, contains('$d.SqliteJdbcDriver('));
    });

    test('the documentation of the template is not copied', () {
      expect(output, isNot(contains('Placeholder syntax')));
      expect(output, isNot(contains('NOT a Dart library')));
    });

    test('a JdbcDriver bean definition, once per bean name', () {
      final code = _normalize(output);
      expect(code, contains("name:r'sqlite3JdbcDriver'"));
      expect(code, contains('BeanDefinition<'));
      expect(code, contains(r'create:(r)=>_$sqlite3JdbcDriver()'));
      expect(code, contains(".named(r'sqlite3JdbcDriver')"));
      expect(code, contains('JdbcDriver],'));
      expect(RegExp(r'JdbcDriver>\(').allMatches(output), hasLength(1));
    });

    test('the generated code compiles against the fakes', () async {
      final errors = await resolveSources<List<String>>(
        {
          for (final MapEntry(:key, :value) in _sources().entries)
            key: value as String,
          'pkg|lib/src/beans.spring.dart': output,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId('pkg', 'lib/src/beans.spring.dart'),
          );
          final result = await library.session.getErrors(
            library.firstFragment.source.fullName,
          );
          return [
            if (result case ErrorsResult(:final diagnostics))
              for (final diagnostic in diagnostics)
                if (diagnostic.severity == Severity.error) diagnostic.message,
          ];
        },
        rootPackage: 'pkg',
        resolverFor: 'pkg|lib/src/beans.spring.dart',
        readAllSourcesFromFilesystem: true,
      );
      expect(errors, isEmpty);
    });
  });

  group('nothing is written', () {
    Future<void> expectNoGlue(
      Map<String, Object> sources, {
      bool template = true,
    }) async {
      final output = await _build(sources, template: template);
      expect(output, isNot(contains('sqlite3')));
      expect(output, isNot(contains('Sqlite3')));
      expect(output, isNot(contains('JdbcDriver')));
    }

    test('without sqlite3 among the dependencies', () async {
      await expectNoGlue(_sources(pubspec: _pubspec(sqlite: false)));
    });

    test('with sqlite3 only as a dev dependency of a lib/ module', () async {
      await expectNoGlue(_sources(pubspec: _pubspec(dev: true)));
    });

    test('without the starter among the dependencies', () async {
      await expectNoGlue(_sources(pubspec: _pubspec(starter: false)));
    });

    test('without the starter template', () async {
      await expectNoGlue(_sources(), template: false);
    });

    test('without a readable pubspec', () async {
      await expectNoGlue(_sources()..remove('pkg|pubspec.yaml'));
    });
  });
  // The PostgreSQL glue is the starter's real template; the packages are
  // empty libraries: only what the generator writes is checked here (the
  // starter's own tests compile it against the real `postgres` package).
  group('with postgres and the starter among the dependencies', () {
    late String output;

    setUpAll(
      () async => output = await _build({
        ..._sources(
          pubspec: [
            'name: pkg',
            'dependencies:',
            '  spring_boot_starter_data: any',
            '  postgres: any',
          ].join('\n'),
        ),
        'postgres|lib/postgres.dart': '',
      }),
    );

    test('the glue and a JdbcDriver bean are written', () {
      expect(output, contains(r'class _$PostgresBinding'));
      expect(output, contains(r'class _$PostgresSession'));
      final code = _normalize(output);
      expect(code, contains("name:r'postgresJdbcDriver'"));
      expect(code, contains(r'create:(r)=>_$postgresJdbcDriver()'));
      expect(code, contains(".named(r'postgresJdbcDriver')"));
      // No SQLite glue: sqlite3 is not a dependency.
      expect(output, isNot(contains('Sqlite3')));
    });

    test('the symbols of the package, of the starter and of dart:io get '
        'the library import prefixes', () {
      expect(output, isNot(contains('{{')));
      final postgres = RegExp(
        r"import 'package:postgres/postgres.dart' as (_i\d+);",
      ).firstMatch(output);
      final io = RegExp(r"import 'dart:io' as (_i\d+);").firstMatch(output);
      final async = RegExp(
        r"import 'dart:async' as (_i\d+);",
      ).firstMatch(output);
      expect(postgres, isNotNull);
      expect(io, isNotNull);
      expect(async, isNotNull);
      expect(output, contains('${postgres![1]}.Connection.open('));
      expect(output, contains('error is ${postgres[1]}.ServerException'));
      expect(output, contains('${io![1]}.SecurityContext('));
      expect(output, contains('${async![1]}.TimeoutException'));
    });
  });
}
