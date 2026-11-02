// What the build checks in the `@Query` methods of a data repository of
// spring_boot_starter_data: the method against its annotation (the return
// type, the parameters, `@Modifying`, the row mapper), the text (the
// parameters, the `{Entity}` placeholders, the names of tables and columns
// against the entities and the migrations). Every problem of an interface is
// one build error. The text checks themselves are unit tested in
// query_text_checker_test.dart; here they run inside a build.
import 'dart:isolate';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _header =
    "import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';\n";

const _entities = '''
@Table('authors')
class Author {
  Author({this.id, required this.name});

  @Id()
  int? id;

  String name;
}

@Table('books')
class Book {
  Book({this.id, required this.title, this.year = 0});

  @Id()
  int? id;

  String title;
  int year;
  int? authorId;

  @Transient()
  String cache = '';

  @MappedCollection()
  List<Chapter> chapters = [];
}

@Table('chapters')
class Chapter {
  Chapter({required this.number});

  int number;
}

class BookCard {
  const BookCard({required this.title});

  final String title;
}

Object? mapper(JdbcRow row) => row.values.first;
Object? extractor(JdbcResult result) => result.rows.length;
int wrongMapper(int x) => x;
Object? _hidden(JdbcRow row) => row.values.first;
''';

// [packages] are other packages of the application: `{'shared': {'lib/a.dart':
// 'source'}}` is `package:shared/a.dart`.
Future<TestBuilderResult> _build(
  String repositories, {
  Map<String, String> files = const {},
  String entities = _entities,
  Map<String, Map<String, String>> packages = const {},
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  PackageConfig? packageConfig;
  if (packages.isNotEmpty) {
    final isolateConfig = await loadPackageConfigUri(
      (await Isolate.packageConfig)!,
    );
    packageConfig = PackageConfig([
      ...isolateConfig.packages,
      for (final name in packages.keys)
        Package(
          name,
          Uri.parse('file:///$name/'),
          packageUriRoot: Uri.parse('file:///$name/lib/'),
        ),
    ]);
  }
  return await testBuilder(
    SpringBuilder(proxyMode: ProxyMode.none),
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/model.dart': '$_header$entities$repositories',
      for (final MapEntry(:key, :value) in files.entries) 'pkg|$key': value,
      for (final MapEntry(key: package, value: sources) in packages.entries)
        for (final MapEntry(:key, :value) in sources.entries)
          '$package|$key': value,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: packageConfig,
    flattenOutput: true,
  );
}

/// The build errors of [repositories], one string.
Future<String> _errors(
  String repositories, {
  Map<String, String> files = const {},
  String entities = _entities,
  Map<String, Map<String, String>> packages = const {},
}) async {
  final result = await _build(
    repositories,
    files: files,
    entities: entities,
    packages: packages,
  );
  expect(result.succeeded, isFalse, reason: 'the build should fail');
  return result.errors.join('\n');
}

/// The generated module of [repositories], which must build.
Future<String> _generate(
  String repositories, {
  Map<String, String> files = const {},
  String entities = _entities,
  Map<String, Map<String, String>> packages = const {},
}) async {
  final result = await _build(
    repositories,
    files: files,
    entities: entities,
    packages: packages,
  );
  expect(result.errors, isEmpty);
  return result.readerWriter.testing.readString(
    AssetId('pkg', 'lib/src/beans.spring.dart'),
  );
}

// A line of the build error, written over several lines of source.
String _l(String line) => line;

// A method of a repository and the line the build lists for it.
class _Case {
  const _Case(this.method, this.line);

  final String method;
  final String line;
}

String _repository(String methods, {String name = 'BookRepository'}) =>
    '''
abstract interface class $name implements ListCrudRepository<Book, int> {
$methods
}
''';

void main() {
  group('the method against its @Query', () {
    // Each row: the method and the reason the build gives for it.
    const problems = <_Case>[
      _Case(
        "@Query('', name: 'books.byYear') Future<List<Book>> named();",
        'BookRepository.named: named queries (@Query(name: ...)) are not '
            'supported yet; give the SQL as the value',
      ),
      _Case(
        "@Query('  ') Future<List<Book>> empty();",
        'BookRepository.empty: @Query has no SQL',
      ),
      _Case(
        "@Query('select 1', rowMapper: mapper, resultSetExtractor: extractor) "
            'Future<List<String>> both();',
        'BookRepository.both: @Query has both rowMapper and '
            'resultSetExtractor: use one',
      ),
      _Case(
        "@Query('select 1', rowMapper: wrongMapper) "
            'Future<List<int>> badMapper();',
        'BookRepository.badMapper: the rowMapper is a int Function(int): it '
            'must be a function that takes a JdbcRow (a static method or a '
            'top-level function)',
      ),
      _Case(
        "@Query('select 1', resultSetExtractor: mapper) "
            'Future<List<int>> badExtractor();',
        'BookRepository.badExtractor: the resultSetExtractor is a '
            'Object? Function(JdbcRow): it must be a function that takes a '
            'JdbcResult (a static method or a top-level function)',
      ),
      _Case(
        "@Query('select * from books') List<Book> blocking();",
        'BookRepository.blocking: a repository method is asynchronous: '
            'return a Future (Future<List<Book>>) or a Stream',
      ),
      _Case(
        "@Query('select * from books') Future<Stream<Book>> futureStream();",
        'BookRepository.futureStream: a Stream is already asynchronous: '
            'return Stream<Book>, not a Future of it',
      ),
      _Case(
        "@Lock(LockMode.pessimisticWrite) @Query('select * from books for "
            "update') Future<List<Book>> locked();",
        'BookRepository.locked: @Lock is for the derived find methods and '
            'findById; in a @Query write the lock in the SQL (select ... for '
            'update) and call it in a transaction',
      ),
      _Case(
        "@Query('select * from books') Future<Page<Book>> twoPages(Pageable "
            'a, PageRequest b);',
        'BookRepository.twoPages: more than one Pageable parameter',
      ),
      _Case(
        "@Query('select * from books') Future<List<Book>> twoSorts(Sort a, "
            'Sort b);',
        'BookRepository.twoSorts: more than one Sort parameter',
      ),
      _Case(
        "@Modifying() @Query('update books set year = 0') "
            'Future<String> modifyingText();',
        'BookRepository.modifyingText: @Modifying returns the rows changed '
            '(Future<int>), whether any changed (Future<bool>) or nothing '
            '(Future<void>), not String',
      ),
      _Case(
        "@Modifying() @Query('update books set year = 0', rowMapper: mapper) "
            'Future<int> modifyingMapped();',
        'BookRepository.modifyingMapped: @Modifying has no result to map: '
            'drop the rowMapper',
      ),
      _Case(
        "@Modifying() @Query('update books set year = 0') "
            'Future<int> modifyingPaged(Pageable page);',
        'BookRepository.modifyingPaged: @Modifying cannot take a Pageable',
      ),
      _Case(
        "@Query('select * from books') Future<void> voidRead();",
        'BookRepository.voidRead: the method returns nothing: a change '
            'needs @Modifying, a read a result type',
      ),
      _Case(
        "@Query('select * from books') Future<Page<Book>> pageAlone();",
        'BookRepository.pageAlone: a page needs a Pageable parameter (the '
            'window to read)',
      ),
      _Case(
        "@Query('select * from books') Future<Slice<Book>> sliceAlone();",
        'BookRepository.sliceAlone: a slice needs a Pageable parameter (the '
            'window to read)',
      ),
      _Case(
        "@Query('select 1', resultSetExtractor: extractor) "
            'Stream<Book> extractedStream();',
        'BookRepository.extractedStream: a resultSetExtractor gives the '
            'whole result: return what it returns, or a List or Set of it, '
            'not a stream',
      ),
      _Case(
        "@Query('select 1', resultSetExtractor: extractor) "
            'Future<List<Book>> extractedWindow(Pageable page);',
        'BookRepository.extractedWindow: a resultSetExtractor reads the '
            'whole result: it cannot be paged',
      ),
      _Case(
        "@Query('select * from books', countQuery: 'select count(*) from "
            "books') Future<List<Book>> strayCount();",
        'BookRepository.strayCount: countQuery is for a method that returns '
            'a Page',
      ),
      _Case(
        "@Query('select * from books') Future<dynamic> unknownResult();",
        'BookRepository.unknownResult: the result type is not known '
            '(dynamic): return the entity, a class of yours, a column type '
            'or a Map, or give a rowMapper',
      ),
      _Case(
        "@Query('select * from books') Future<List<Object>> objects();",
        'BookRepository.objects: Object cannot be built from rows: it is no '
            'column type, no Map<String, Object?> and no class of yours; '
            'return the entity, a class of yours, a column type or a Map, or '
            'give a rowMapper',
      ),
      _Case(
        "@Query('select * from books') Future<Map<String, int>> intMap();",
        'BookRepository.intMap: a row as a map is a Map<String, Object?>, '
            'not Map<String, int>',
      ),
      // A private function cannot be written into the generated code: it
      // must not turn the method into a derived query (`findByTitle`).
      _Case(
        "@Query('select * from books where title like :title', rowMapper: "
            '_hidden) Future<List<Book>> findByTitle(String title);',
        'BookRepository.findByTitle: the rowMapper of @Query must be public: '
            'the generated code refers to it',
      ),
      _Case(
        "@Query('select * from books', resultSetExtractor: _hidden) "
            'Future<List<Book>> hiddenExtractor();',
        'BookRepository.hiddenExtractor: the resultSetExtractor of @Query '
            'must be public: the generated code refers to it',
      ),
      _Case(
        "@Query('select * from books') Future<AggregateReference<Author, int>>"
            ' reference();',
        'BookRepository.reference: AggregateReference<Author, int> cannot '
            'be built from rows',
      ),
    ];

    late String message;

    setUpAll(() async {
      message = await _errors(
        _repository(
          [for (final problem in problems) problem.method].join('\n'),
        ),
      );
    });

    test('the interface has one error, with a line for each method', () {
      expect(message, contains('Invalid repository BookRepository:'));
      expect('Invalid repository'.allMatches(message), hasLength(1));
      for (final line in problems.map((p) => p.line)) {
        expect(message, contains('\n  - $line'));
      }
    });

    test('and only for these methods', () {
      expect('\n  - '.allMatches(message), hasLength(problems.length));
    });

    test('they come in the order of the methods', () {
      var from = 0;
      for (final line in problems.map((p) => p.line)) {
        final at = message.indexOf('\n  - $line', from);
        expect(at, greaterThanOrEqualTo(from), reason: line);
        from = at;
      }
    });
  });

  group('the text of a @Query', () {
    test('parameters, markers and expressions', () async {
      final message = await _errors(
        _repository('''
  @Query('select * from books where year = :yeer')
  Future<List<Book>> unknownName(int year);

  @Query('select * from books where year = :book.year')
  Future<List<Book>> aProperty(Book book);

  @Query('select * from books where year = ?')
  Future<List<Book>> plain(int year);

  @Query('select * from #{#tableName} where year = :year')
  Future<List<Book>> elsewhere(int year);

  @Query('select * from books where year = :#{#year')
  Future<List<Book>> unclosed(int year);

  @Query('select * from books where year = :page')
  Future<Page<Book>> pageIsNoParameter(Pageable page);

  @Query('select * from books where year = :year',
      countQuery: 'select count(*) from books where year = :yeer')
  Future<Page<Book>> countText(int year, Pageable page);
'''),
      );
      for (final line in [
        _l(
          'BookRepository.unknownName: :yeer matches no parameter of the '
          'method (it has year)',
        ),
        _l(
          'BookRepository.aProperty: :book.year matches no parameter of the '
          'method (it has book) (to read a property write :#{#book.year})',
        ),
        _l(
          'BookRepository.plain: the query has a plain ? marker: write :name '
          'and bind it by the name of a parameter of the method',
        ),
        _l(
          'BookRepository.elsewhere: #{#tableName} is not allowed in the SQL '
          'text: only #{#entityName} is; to bind a value write '
          ':#{#tableName}',
        ),
        _l('BookRepository.unclosed: an expression is not closed: :#{#year'),
        _l(
          'BookRepository.pageIsNoParameter: :page matches no parameter of '
          'the method (it has none)',
        ),
        _l(
          'BookRepository.countText (countQuery): :yeer matches no parameter '
          'of the method (it has year)',
        ),
      ]) {
        expect(message, contains('\n  - $line'));
      }
    });

    test('names a parameter, an expression and the entity are fine', () async {
      final output = await _generate(
        _repository('''
  @Query('select * from #{#entityName} where year = :year and id = :#{#year}')
  Future<List<Book>> ok(int year);

  @Query('select * from books where year = :year',
      countQuery: 'select count(*) from books where year = :year')
  Future<Page<Book>> paged(int year, Pageable page);
'''),
      );
      expect(output, contains('QueryMethod'));
    });

    test('entity placeholders: the class and the property', () async {
      final message = await _errors(
        _repository('''
  @Query('select * from {Bok}')
  Future<List<Book>> unknownEntity();

  @Query('select {Book.titel} from {Book}')
  Future<List<Book>> unknownProperty();

  @Query('select {Book.cache} from {Book}')
  Future<List<Book>> transient();

  @Query('select {Book.chapters} from {Book}')
  Future<List<Book>> collection();

  @Query('select {BookCard} from books')
  Future<List<Book>> notATable();
'''),
      );
      for (final line in [
        _l(
          'BookRepository.unknownEntity: {Bok}: no @Table class Bok in the '
          "application, did you mean 'Book'?",
        ),
        _l(
          'BookRepository.unknownProperty: {Book.titel}: Book has no property '
          "titel, did you mean 'title'? (stored properties: id, title, "
          'year, authorId)',
        ),
        _l(
          'BookRepository.transient: {Book.cache}: Book.cache is @Transient: '
          'it has no column',
        ),
        _l(
          'BookRepository.collection: {Book.chapters}: Book.chapters is a '
          '@MappedCollection: its rows are in the table of its children, '
          'not in a column of Book',
        ),
        _l(
          'BookRepository.notATable: {BookCard}: no @Table class BookCard in '
          'the application',
        ),
      ]) {
        expect(message, contains('\n  - $line'));
      }
    });

    test(
      'an entity of another package is not a problem, and is written',
      () async {
        final output = await _generate(
          _repository('''
  @Query('select * from {Genre} where year = :year')
  Future<List<Book>> ofGenre(int year);

  @Query('select * from {Ghost} where year = :year')
  Future<List<Book>> ofGhost(int year);

  @Query('select * from {Author}')
  Future<List<Book>> authors();
'''),
          entities: "import 'package:shared/shared.dart';\n$_entities",
          packages: {
            'shared': {
              'lib/shared.dart': '''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

@Table('genres')
class Genre {
  Genre({this.id});

  @Id()
  int? id;
}
''',
            },
          },
        );
        final ofGenre = RegExp(
          r"QueryMethod\(\s*r'ofGenre'(.*?)\n\s*\);",
          dotAll: true,
        ).firstMatch(output)![1]!;
        // Through the library of the package that has it.
        expect(ofGenre, contains("entities: {r'Genre': "));
        expect(output, contains('package:shared/shared.dart'));
        // What nothing in sight has is the run time's to resolve.
        final ofGhost = RegExp(
          r"QueryMethod\(\s*r'ofGhost'(.*?)\n\s*\);",
          dotAll: true,
        ).firstMatch(output)![1]!;
        expect(ofGhost, isNot(contains('entities:')));
        // A class of the module is as before.
        final authors = RegExp(
          r"QueryMethod\(\s*r'authors'(.*?)\n\s*\);",
          dotAll: true,
        ).firstMatch(output)![1]!;
        expect(authors, contains("entities: {r'Author': "));
      },
    );

    test('a class of another package that is no @Table is a problem', () async {
      final message = await _errors(
        _repository('''
  @Query('select * from {Plain}')
  Future<List<Book>> plain();
'''),
        entities: "import 'package:shared/shared.dart';\n$_entities",
        packages: {
          'shared': {'lib/shared.dart': 'class Plain {}'},
        },
      );
      expect(
        message,
        contains(
          '\n  - BookRepository.plain: {Plain}: no @Table class Plain in the '
          'application',
        ),
      );
    });

    test('a DTO of the name of an entity is not the entity', () async {
      final output = await _generate(
        _repository('''
  @Query('select title from {Book}')
  Future<List<dto.Book>> cards();
'''),
        entities: "import 'package:pkg/src/dto.dart' as dto;\n$_entities",
        files: {
          'lib/src/dto.dart': '''
class Book {
  const Book({required this.title});

  final String title;
}
''',
        },
      );
      final entities = RegExp(
        r"QueryMethod\(\s*r'cards'.*?entities: \{r'Book': (\w+)\.Book",
        dotAll: true,
      ).firstMatch(output)![1]!;
      expect(
        output,
        contains("import 'package:pkg/src/model.dart' as $entities;"),
        reason: 'the @Table class, not the DTO',
      );
    });

    test('problems of the method and of the text are one error', () async {
      final message = await _errors(
        _repository('''
  Future<List<Book>> findByTitel(String title);

  @Query('select * from books where year = :yeer')
  Future<List<Book>> unknownName(int year);

  @Query('select * from books') Future<void> voidRead();
'''),
      );
      expect('Invalid repository'.allMatches(message), hasLength(1));
      expect(message, contains('BookRepository.findByTitel: No property'));
      expect(message, contains('BookRepository.voidRead: the method returns'));
      expect(
        message,
        contains('BookRepository.unknownName: :yeer matches no parameter'),
      );
    });

    test('two repositories each have their error', () async {
      final message = await _errors(
        '${_repository("@Query('select * from books where year = :a') "
        'Future<List<Book>> one(int year);', name: 'FirstRepository')}'
        '${_repository("@Query('select * from books where year = :b') "
        'Future<List<Book>> two(int year);', name: 'SecondRepository')}',
      );
      expect(message, contains('Invalid repository FirstRepository:'));
      expect(message, contains('Invalid repository SecondRepository:'));
    });
  });

  group('the results a @Query can have', () {
    test('every kind builds', () async {
      final output = await _generate(
        _repository('''
  @Query('select * from books') Future<List<Book>> entities();
  @Query('select * from books') Future<Set<Book>> entitySet();
  @Query('select * from books') Future<Iterable<Book>> iterable();
  @Query('select * from books') Future<Book?> one();
  @Query('select * from books') Stream<Book> streamed();
  @Query('select * from books') Future<Page<Book>> paged(Pageable p);
  @Query('select * from books') Future<Slice<Book>> sliced(Pageable p);
  @Query('select title from books') Future<List<BookCard>> cards();
  @Query('select name from authors') Future<List<Author>> authors();
  @Query('select count(*) from books') Future<int> count();
  @Query('select title from books') Future<List<String>> titles();
  @Query('select year from books') Future<Set<num>> years();
  @Query('select 1') Future<bool> flag();
  @Query('select title from books') Future<DateTime?> time();
  @Query('select * from books') Future<Map<String, Object?>?> row();
  @Query('select * from books') Future<List<Map<String, dynamic>>> rows();
  @Query('select title from books', rowMapper: mapper)
  Future<List<Object?>> mapped();
  @Query('select 1', resultSetExtractor: extractor) Future<int> extracted();
  @Modifying() @Query('update books set year = 0') Future<int> a();
  @Modifying() @Query('update books set year = 0') Future<bool> b();
  @Modifying() @Query('update books set year = 0') Future<void> c();
'''),
      );
      expect(output, contains('QueryMethod'));
    });
  });

  group('misspelled tables and columns', () {
    const migrations = {
      'lib/resources/db/migration/V1__start.sql': '''
create table authors (id integer primary key, name text not null);
create table books (id integer primary key, title text, year integer);
create table accounts (iban text primary key, owner text not null);
''',
      'lib/resources/db/migration/V10__isbn.sql': '''
alter table books add column isbn text;
''',
      'lib/resources/db/migration/V2__renamed.sql': '''
alter table accounts rename column owner to owners;
''',
      'lib/resources/db/migration/R__counts.sql': '''
drop view if exists author_book_counts;
create view author_book_counts as
select a.id, a.name, count(b.id) as books
from authors a left join books b on b.author_id = a.id
group by a.id, a.name;
''',
    };

    const goodQueries = '''
  @Query('select b.title, a.name, v.books from books b '
      'join authors a on a.id = b.author_id '
      'join author_book_counts v on v.id = a.id where b.isbn = :isbn')
  Future<List<Map<String, Object?>>> joined(String isbn);

  @Query('select owners from accounts')
  Future<List<String>> holders();

  @Query('select {Book.title} from {Book} where {Book.year} > :year')
  Future<List<String>> placeholders(int year);

  @Query('select * from external_things where x = 1')
  Future<List<Map<String, Object?>>> external();
''';

    test('queries that are right pass, in all their forms', () async {
      final output = await _generate(
        _repository(goodQueries),
        files: migrations,
      );
      expect(output, contains('joined'));
    });

    test('a typo is an error when a known name is close', () async {
      final message = await _errors(
        _repository('''
  @Query('select b.titel from books b')
  Future<List<String>> column();

  @Query('select * from bokks')
  Future<List<Map<String, Object?>>> table();

  @Query('select owner from accounts')
  Future<List<String>> renamedAway();

  @Query('select isbm from books')
  Future<List<String>> laterColumn();

  @Query('select v.bokks from author_book_counts v')
  Future<List<String>> viewColumn();

  @Query('select {Book.title} from {Book} b where b.yeer = :year')
  Future<List<String>> viaPlaceholder(int year);

  @Query('select number from chapters where books_idd = :year')
  Future<List<int>> childColumn(int year);
'''),
        files: migrations,
      );
      for (final line in [
        _l(
          'BookRepository.column: b.titel: no column titel in books, did you '
          "mean 'title'?",
        ),
        _l(
          "BookRepository.table: bokks: no table bokks, did you mean 'books'?",
        ),
        _l(
          'BookRepository.renamedAway: owner: no column owner in accounts, did '
          "you mean 'owners'?",
        ),
        _l(
          'BookRepository.laterColumn: isbm: no column isbm in books, did you '
          "mean 'isbn'?",
        ),
        _l(
          'BookRepository.viewColumn: v.bokks: no column bokks in '
          "author_book_counts, did you mean 'books'?",
        ),
        _l(
          'BookRepository.viaPlaceholder: b.yeer: no column yeer in books, did '
          "you mean 'year'?",
        ),
        _l(
          'BookRepository.childColumn: books_idd: no column books_idd in '
          "chapters, did you mean 'books_id'?",
        ),
      ]) {
        expect(message, contains('\n  - $line'));
      }
    });

    test('without migrations the entities are the schema', () async {
      final message = await _errors(
        _repository('''
  @Query('select titel from books')
  Future<List<String>> column();

  @Query('select year, author_id from books')
  Future<List<Map<String, Object?>>> derived();
'''),
      );
      expect(message, contains('titel: no column titel in books, did you'));
      expect(message, isNot(contains('author_id')));
    });

    test(
      'init scripts count: schema.sql and the locations of the settings',
      () async {
        final files = {
          'lib/resources/schema.sql': 'create table notes (id int, body text);',
          'lib/resources/sql/extra.sql':
              'create table tags (id int, label text);',
          'lib/resources/application.properties':
              'spring.sql.init.schema-locations=resources:sql/extra.sql\n',
        };
        final message = await _errors(
          _repository('''
  @Query('select * from tags where lable = :a')
  Future<List<Map<String, Object?>>> inSettings(String a);

  @Query('select * from notes where bdy = :a')
  Future<List<Map<String, Object?>>> notRead(String a);
'''),
          files: files,
        );
        expect(
          message,
          contains("lable: no column lable in tags, did you mean 'label'?"),
        );
        // schema.sql is no longer a location: its table is unknown.
        expect(message, isNot(contains('bdy')));
      },
    );

    test('the migrations of several databases are alternatives', () async {
      const files = {
        'lib/resources/application.properties':
            'spring.sql.migration.locations=resources:db/{vendor}\n',
        'lib/resources/db/sqlite/V1__notes.sql':
            'create table notes (id int, body text);',
        'lib/resources/db/postgres/V1__notes.sql':
            'create table notes (id int, bodyx text);',
      };
      // A column of either is a column; only a typo is not.
      final message = await _errors(
        _repository('''
  @Query('select body from notes where id = :a')
  Future<List<Map<String, Object?>>> sqlite(int a);

  @Query('select bodyx from notes where id = :a')
  Future<List<Map<String, Object?>>> postgres(int a);

  @Query('select bodz from notes where id = :a')
  Future<List<Map<String, Object?>>> typo(int a);
'''),
        files: files,
      );
      expect(message, contains('bodz: no column bodz in notes, did you mean'));
      expect(message, isNot(contains('BookRepository.sqlite')));
      expect(message, isNot(contains('BookRepository.postgres')));
    });

    test(
      'settings in application.yml are read, profile files are not',
      () async {
        const query = '''
  @Query('select * from tags where lable = :a')
  Future<List<Map<String, Object?>>> inSettings(String a);
''';
        final yaml = {
          'lib/resources/application.yml': 'spring:\n  sql:\n    init:\n      schema-locations: resources:sql/extra.sql\n',
          'lib/resources/sql/extra.sql':
              'create table tags (id int, label text);',
        };
        expect(
          await _errors(_repository(query), files: yaml),
          contains("lable: no column lable in tags, did you mean 'label'?"),
        );
        // A profile file may set them differently: no typo check.
        await _generate(
          _repository(query),
          files: {
            ...yaml,
            'lib/resources/application-prod.yml':
                'spring.sql.init.schema-locations: resources:sql/prod.sql\n',
          },
        );
      },
    );

    test('a location the build cannot read turns the typo check off', () async {
      final output = await _generate(
        _repository('''
  @Query('select titel from bokks')
  Future<List<Map<String, Object?>>> broken();
'''),
        files: const {
          'lib/resources/application.properties':
              'spring.sql.migration.locations=file:/var/migrations\n',
        },
      );
      expect(output, contains('broken'));
    });

    test(
      'a NamingStrategy of the application hides the derived names',
      () async {
        const queries = '''
  @Query('select b.titel from books b')
  Future<List<String>> column();
''';
        // By default `title` is known, so `titel` is a typo of it.
        expect(
          await _errors(_repository(queries)),
          contains("did you mean 'title'?"),
        );
        // The application's own strategy may name the column differently.
        final output = await _generate(
          '''
@Component()
class ShoutingNames extends NamingStrategy {
  const ShoutingNames();

  @override
  String columnName(String propertyName, Column? column) =>
      column?.value ?? propertyName.toUpperCase();
}
${_repository(queries)}''',
        );
        expect(output, contains('column'));
      },
    );
  });

  group('the :#{...} expressions', () {
    // The code of the source without the import prefixes and the layout.
    String flat(String code) => code
        .replaceAll(RegExp(r'\b_i\d+\.'), '')
        .replaceAll(RegExp(r'\s'), '')
        .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

    const classes = '''
@Component()
class Cutoffs {
  int get year => 1990;
  int before(int year) => year - 1;
}
''';

    // Methods whose expressions all compile.
    const compiled = '''
  @Query('select * from books where title = :#{#book.title} or id = :#{#p1}')
  Future<List<Book>> properties(Book book, int more);

  @Query('select * from books where year = :#{#a0 + 1} and id = :#{[0]}')
  Future<List<Book>> arguments(int year);

  @Query('select * from {Book} where title = :#{#entityName + #methodName}')
  Future<List<Book>> context();

  @Query('select * from books where year >= :#{@cutoffs.year} '
      'and year < :#{@cutoffs.before(#year)}')
  Future<List<Book>> beans(int year);

  @Query(
    "select * from books "
    "where year > :#{@environment.getProperty('c', '0')}",
  )
  Future<List<Book>> environment();

  @Query('select * from books where title = :#{@mystery}')
  Future<List<Book>> unknownBean();
''';

    test('a typo in a property is a build error with a suggestion', () async {
      final message = await _errors(
        _repository('''
  @Query('select * from books where title = :#{#book.titel}')
  Future<List<Book>> sameTitle(Book book);
'''),
      );
      expect(
        message,
        contains(
          'BookRepository.sameTitle: the expression :#{#book.titel} is '
          "invalid: No property 'titel' on type 'Book'; did you mean "
          "'title'?",
        ),
      );
    });

    test('a syntax error, an unknown variable and a wrong call', () async {
      final message = await _errors(
        _repository('''
  @Query('select * from books where year = :#{1 +}')
  Future<List<Book>> syntax(int year);

  @Query('select * from books where year = :#{#yeer}')
  Future<List<Book>> variable(int year);

  @Query('select * from books where title = :#{#book.title.substring()}')
  Future<List<Book>> call(Book book);

  @Query('select * from books where title = :#{#book?.title.length}')
  Future<List<Book>> nullable(Book? book);
'''),
      );
      for (final (method, expression, reason) in [
        ('syntax', '1 +', 'Invalid expression: EL1042E'),
        (
          'variable',
          '#yeer',
          "Unknown variable '#yeer'; did you mean '#year'?",
        ),
        (
          'call',
          '#book.title.substring()',
          "Method 'String.substring' takes between 1 and 2 arguments, but 0 "
              'were given',
        ),
        (
          'nullable',
          '#book?.title.length',
          "Cannot read property 'length' on String?",
        ),
      ]) {
        expect(
          message,
          contains(
            '\n  - BookRepository.$method: the expression :#{$expression} is '
            'invalid: $reason',
          ),
        );
      }
    });

    test('the count query is checked too, and named', () async {
      final message = await _errors(
        _repository('''
  @Query('select * from books where year > :year',
      countQuery: 'select count(*) from books where year > :#{#yeer}')
  Future<Page<Book>> counted(int year, Pageable page);
'''),
      );
      expect(
        message,
        contains(
          'BookRepository.counted (countQuery): the expression :#{#yeer} is '
          "invalid: Unknown variable '#yeer'; did you mean '#year'?",
        ),
      );
    });

    test('the variables, the beans and the environment are compiled', () async {
      final raw = await _generate('$classes${_repository(compiled)}');
      final output = flat(raw);
      const arguments = '(arguments, context) =>';
      const bean = "(context.bean(r'cutoffs') as Cutoffs)";
      const concat = '$arguments SpelOperations.concat';
      for (final expression in [
        // arguments by name, by position, as the list
        '$arguments (arguments[0] as Book).title',
        '$arguments (arguments[1] as int)',
        '$arguments (arguments[0] as int) + 1',
        '$arguments SpelOperations.listElement(arguments, 0)',
        // what the context gives
        '$concat(context.entityName, context.methodName)',
        // a bean of the application, typed
        '$arguments $bean.year',
        '$arguments $bean.before((arguments[0] as int))',
        // the environment of the context
        "$arguments context.environment!.getProperty('c', defaultValue: '0')",
        // a bean the build does not know
        "$arguments context.bean(r'mystery')",
      ]) {
        expect(output, contains(flat(expression)), reason: expression);
      }
      // A compiled expression needs code: a final field, no constant.
      expect(output, contains('staticfinal_properties=QueryMethod('));
      // Every expression is a function.
      expect(output, isNot(contains('expressions:[null')));
      expect(output, isNot(contains(',null')));
      // Nothing is introspected for them.
      expect(output, isNot(contains('BeanIntrospection')));
    });

    test('what the compiler leaves stays null, and is introspected', () async {
      final raw = await _generate(
        _repository(r'''
  @Query('select * from books where year = :#{#book.year} '
      'and title = :#{T(String).valueOf(#other.title)}')
  Future<List<Book>> mixed(Book book, BookCard other);

  @Query('select * from books where year = :#{#book.year} and id = :#{#year}',
      countQuery: 'select count(*) from books where year = :#{#book.year}')
  Future<Page<Book>> counted(Book book, int year, Pageable page);

  @Query(r"select * from books where id = :#{#year + '${x}'.length} limit 1")
  Future<List<Book>> placeholder(int year);
'''),
      );
      final output = flat(raw);
      // The first is compiled, the second is for the interpreter.
      expect(
        output,
        contains(
          flat(
            'expressions: [(arguments, context) => '
            '(arguments[0] as Book).year, null]',
          ),
        ),
      );
      // Every expression of the SQL, then of the count query; a text that
      // has a ${property} placeholder is not compiled.
      expect(
        output,
        contains(
          flat(
            'expressions: [(arguments, context) => '
            '(arguments[0] as Book).year, '
            '(arguments, context) => (arguments[1] as int), '
            '(arguments, context) => (arguments[0] as Book).year]',
          ),
        ),
      );
      expect(output, contains(flat('expressions: [null]')));
      // `Book` is an entity, never introspected; `BookCard` is read by the
      // interpreter at run time.
      expect(output, contains('BeanIntrospection<BookCard>('));
    });

    test('a bean an interpreted expression names is introspected', () async {
      const classes = '''
@Component()
class Catalog {
  String lookup(String key) => key;
}

@Component()
class Clock {
  String now() => 'now';
}
''';
      final raw = await _generate(
        '$classes${_repository('''
  @Query('select * from books where title = '
      ':#{@catalog.lookup(T(String).valueOf(#year))}')
  Future<List<Book>> interpreted(int year);

  @Query("select * from books where title = :#{@clock.now()}")
  Future<List<Book>> compiled(int year);
''')}',
      );
      final output = flat(raw);
      // The interpreter finds `lookup` through the bean's introspection.
      expect(output, contains('BeanIntrospection<Catalog>('));
      expect(output, contains("BeanMethod<Catalog>(r'lookup'"));
      // A compiled expression calls the method itself.
      expect(output, isNot(contains('BeanIntrospection<Clock>(')));
    });

    test('the generated code compiles against the starter', () async {
      final repositories =
          '$classes${_repository('''
$compiled
  @Query(
    'select * from books where year > :#{#sort == null ? 1 : 2} '
    'and id = :#{#page.pageNumber}',
  )
  Future<List<Book>> others(Sort sort, Pageable page);
''')}';
      final raw = await _generate(repositories);
      final errors = await resolveSources<List<String>>(
        {
          'pkg|lib/src/beans.dart': _scan,
          'pkg|lib/src/model.dart': '$_header$_entities$repositories',
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
  });
}
