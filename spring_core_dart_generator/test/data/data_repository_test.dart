// spring_boot_starter_data's repositories: an interface extending its
// DataRepository gets a generated class extending SimpleRepository, written
// by the generator itself (not through the @InterfaceProxy machinery) and
// registered as a bean. The sources use the real starter; what the class
// holds method by method is in compiled_repository_test.dart.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _repositories = '''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

class Book {
  Book({this.id, required this.title});
  int? id;
  String title;
}

class Author {
  Author(this.name);
  String name;
}

class Rules {
  const Rules(this.types);
  final List<Type> types;
}

class OutOfStock implements Exception {}

class NotFound implements Exception {}

@Service()
class Checkout {
  @Rules([OutOfStock])
  void place() {}
}

// No annotation: a repository all the same.
abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {
  @Rules([NotFound, OutOfStock])
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

  test('an interface extending DataRepository gets a class of its own', () {
    expect(
      output,
      _has(r'''
class _$BookRepositoryImpl extends SimpleRepository<Book, int>
    implements BookRepository'''),
    );
    expect(
      output,
      _has(r'''
class _$AuthorRepositoryImpl extends SimpleRepository<Author, String>
    implements AuthorRepository'''),
    );
    expect(output, _has(r'_$BookRepositoryImpl(super.operations)'));
  });

  test(
    'only the declared methods are written, the CRUD ones are inherited',
    () {
      expect(
        output,
        _has(
          'Future<List<Book>> findByTitle(String title) => '
          'this.operations.list(',
        ),
      );
      expect(
        output,
        _has('Future<Author?> findByName(String name) => this.operations.one('),
      );
      for (final inherited in ['findById', 'findAll', 'save']) {
        expect(output, isNot(contains(' $inherited(')));
      }
    },
  );

  test('it is not an interface proxy: no handler, no metadata, no call', () {
    expect(output, isNot(contains('InterfaceMetadata')));
    expect(output, isNot(contains('InvocationHandler')));
    expect(output, isNot(contains('supertypeArguments')));
    expect(output, isNot(contains('call:')));
    expect(output, isNot(contains('ProxyMethod')));
  });

  test('the types of repository signatures are not introspected', () {
    // Book has no @Table here: being returned by a repository describes
    // nothing (only a Feign client's bodies are described that way).
    expect(output, isNot(contains('BeanIntrospection<Book>')));
  });

  test('the starter makes the operations, with the entity and id types', () {
    expect(
      output,
      _has(
        'r.dependency<RepositoryFactory>()'
        ".operations<Book, int>(r'BookRepository')",
      ),
    );
    expect(
      output,
      _has(
        'r.dependency<RepositoryFactory>()'
        ".operations<Author, String>(r'AuthorRepository', "
        "annotations: const [Repository(r'authors')])",
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

  test('a value-is test for each type written in an annotation', () {
    expect(output, _has('typeTests: {'));
    expect(output, _has('OutOfStock: (value) => value is OutOfStock'));
    expect(output, _has('NotFound: (value) => value is NotFound'));
    // Once per type.
    expect(
      'OutOfStock: (value)'.allMatches(raw.replaceAll(RegExp(r'\s'), ' ')),
      hasLength(1),
    );
  });

  test('the generated code compiles', () async {
    final errors = await resolveSources<List<String>>(
      {
        for (final MapEntry(:key, :value) in _sources.entries)
          key: value as String,
        'pkg|lib/spring_gen/src/beans.spring.dart': raw,
      },
      (resolver) async {
        final library = await resolver.libraryFor(
          AssetId('pkg', 'lib/spring_gen/src/beans.spring.dart'),
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
      resolverFor: 'pkg|lib/spring_gen/src/beans.spring.dart',
      readAllSourcesFromFilesystem: true,
    );
    expect(errors, isEmpty);
  });
}
