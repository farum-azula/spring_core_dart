// spring_boot_starter_data's repositories: an interface extending its
// DataRepository gets a generated implementation (the @InterfaceProxy
// machinery), with the type arguments of its supertypes in the metadata.
// The starter is matched by URL; a small copy of its marker stands in.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _dataLibrary =
    'spring_boot_starter_data|lib/src/repository/repository.dart';

const _data = '''
abstract interface class DataRepository<T, ID> {}

abstract interface class CrudRepository<T, ID>
    implements DataRepository<T, ID> {
  Future<T> save(T entity);
  Future<T?> findById(ID id);
  Future<Iterable<T>> findAll();
}

abstract interface class ListCrudRepository<T, ID>
    implements CrudRepository<T, ID> {
  @override
  Future<List<T>> findAll();
}
''';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _repositories = '''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_boot_starter_data/src/repository/repository.dart';

class Book {
  Book({this.id, required this.title});
  int? id;
  String title;
}

class Author {
  Author(this.name);
  String name;
}

// No annotation: a repository all the same.
abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {
  Future<List<Book>> findByTitle(String title);
}

// Only the declared methods.
@Repository('authors')
abstract interface class AuthorRepository
    implements DataRepository<Author, String> {
  Future<Author?> findByName(String name);
}

// A base for others, never a bean.
abstract interface class BaseRepository<T> implements CrudRepository<T, int> {}

// A concrete @Repository stays a plain component.
@Repository()
class AuditLog {
  final lines = <String>[];
}
''';

Map<String, Object> get _sources => {
  _dataLibrary: _data,
  'pkg|lib/src/beans.dart': _scan,
  'pkg|lib/src/repositories.dart': _repositories,
};

Future<TestBuilderResult> _build() async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(),
    _sources,
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

Matcher _has(String code) => contains(_normalize(code));

void main() {
  late String output;
  late String raw;

  setUpAll(() async {
    final result = await _build();
    expect(result.errors, isEmpty);
    raw = result.readerWriter.testing.readString(
      result.outputs.single,
    );
    output = _normalize(raw);
  });

  test('an interface extending DataRepository gets an implementation', () {
    expect(
      output,
      _has(r'class _$BookRepositoryImpl implements BookRepository'),
    );
    expect(
      output,
      _has(r'class _$AuthorRepositoryImpl implements AuthorRepository'),
    );
    // Inherited methods are implemented with the type arguments applied.
    expect(output, _has('Future<Book?> findById(int id)'));
    expect(output, _has('Future<List<Book>> findAll()'));
    expect(output, _has('Future<Book> save(Book entity)'));
    expect(output, _has('Future<List<Book>> findByTitle(String title)'));
  });

  test('the metadata carries the type arguments of the supertypes', () {
    expect(
      output,
      _has(
        "r'DataRepository': [const ClassType<Book>(), const ClassType<int>()]",
      ),
    );
    expect(
      output,
      _has(
        "r'ListCrudRepository': [const ClassType<Book>(), "
        'const ClassType<int>()]',
      ),
    );
    expect(
      output,
      _has(
        "r'DataRepository': [const ClassType<Author>(), "
        'const ClassType<String>()]',
      ),
    );
  });

  test('bean names: the decapitalized name, or the @Repository name', () {
    expect(output, _has("name: r'bookRepository'"));
    expect(output, _has("name: r'authors'"));
  });

  test('a generic base interface is no bean', () {
    expect(output, isNot(contains('BaseRepository')));
  });

  test('a concrete @Repository class stays a component', () {
    expect(output, _has("name: r'auditLog'"));
    expect(output, isNot(contains(r'_$AuditLogImpl')));
  });

  test('the generated code compiles', () async {
    final errors = await resolveSources<List<String>>(
      {
        for (final MapEntry(:key, :value) in _sources.entries)
          key: value as String,
        'pkg|lib/src/beans.spring.dart': raw,
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
}
