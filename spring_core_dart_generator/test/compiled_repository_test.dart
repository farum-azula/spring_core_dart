// What the generator writes for a data repository of
// spring_boot_starter_data, an interface extending `DataRepository`: a class
// extending `SimpleRepository` (the CRUD methods) with one line for each
// other method, and no description of the methods for the starter to read at
// start up. A derived query (`findByTitleAndYear`) is parsed and checked by
// the build, which writes it as a constant `PartTree`: a wrong name is a
// build error, listed with every other problem of the interface.
//
// The sources use the real starter, so the generated code is checked
// against the real runtime API.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/part_tree_parser.dart';
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

// The entities of the tests: properties named like the keywords of method
// names (`Or`, `And`, `In`, `Is`), every kind of property, a child.
const _entities = '''
enum Status { draft, published }

@Table('authors')
class Author {
  Author({this.id, required this.name});

  @Id()
  int? id;

  String name;
}

@Table('chapters')
class Chapter {
  Chapter({required this.number});

  int number;
}

@Table('books')
class Book {
  Book({this.id, required this.title, this.year = 0});

  @Id()
  int? id;

  String title;
  int year;
  double price = 0;
  bool inStock = true;
  int orderNumber = 0;
  String origin = '';
  String android = '';
  String isbn = '';
  String? notes;
  int? between;
  String URL = '';
  String address = '';
  DateTime? published;
  Status status = Status.draft;
  AggregateReference<Author, int>? author;

  @Reference(Author)
  int? writerId;

  @MappedCollection()
  List<Chapter> chapters = [];

  @Transient()
  String cache = '';
}

class BookCard {
  const BookCard({required this.title});

  final String title;
}
''';

Future<TestBuilderResult> _build(
  String model, {
  ProxyMode proxyMode = ProxyMode.none,
  String header = _header,
  String entities = _entities,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(proxyMode: proxyMode),
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/model.dart': '$header$entities$model',
    },
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

/// The generated module for [model] (declarations after the entities).
Future<String> _generate(
  String model, {
  ProxyMode proxyMode = ProxyMode.none,
  String header = _header,
  String entities = _entities,
}) async {
  final result = await _build(
    model,
    proxyMode: proxyMode,
    header: header,
    entities: entities,
  );
  expect(result.errors, isEmpty);
  return result.readerWriter.testing.readString(
    AssetId('pkg', 'lib/src/beans.spring.dart'),
  );
}

/// The build errors for [model].
Future<String> _errors(String model) async =>
    (await _build(model)).errors.join('\n');

/// An interface `BookRepository` with [methods] as its body.
String _bookRepository(String methods) =>
    '''
abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {
$methods
}
''';

// A method of the catalogue of valid names, written as
// `declaration :: expectation`, and the `PartTree` the build writes for it.
//
// The declaration is Dart without a return type (a `Future<List<Book>>`) or
// with one. The expectation is the predicate and, after `;`, the options:
//
//  * predicate: `-` for none, else parts joined by `&` (And), the
//    alternatives by `|` (Or); a part is `property`, `property:type` or
//    `property:type:i` for a part that ignores case (`title::i` for the
//    default type);
//  * options: `count`, `exists` or `delete`, `max=3`, `distinct`, and
//    `sort=+title,-year`.
//
// `findByTitle(String t) :: title` is the tree
// `PartTree(r'findByTitle', [OrPart([Part(r'title')])])`.
class _Case {
  _Case(String row) {
    final [source, expectation] = row.split(' :: ');
    declaration = RegExp(r'^\w+\(').hasMatch(source)
        ? 'Future<List<Book>> $source;'
        : '$source;';
    name = RegExp(r'(\w+)\(').firstMatch(source)!.group(1)!;
    expected = _expected(name, expectation);
  }

  late final String declaration;
  late final String name;
  late final String expected;

  static String _expected(String name, String expectation) {
    final [predicate, ...options] = [
      for (final part in expectation.split(';')) part.trim(),
    ];
    var kind = 'find';
    int? max;
    var distinct = false;
    var sort = <String>[];
    for (final option in options.expand((o) => o.split(' '))) {
      if (option.startsWith('max=')) {
        max = int.parse(option.substring(4));
      } else if (option == 'distinct') {
        distinct = true;
      } else if (option.startsWith('sort=')) {
        sort = [
          for (final order in option.substring(5).split(',')) _order(order),
        ];
      } else if (option.isNotEmpty) {
        kind = option;
      }
    }
    final alternatives = predicate == '-'
        ? <String>[]
        : [
            for (final and in predicate.split(' | '))
              'OrPart([${[
                for (final part in and.split(' & ')) _part(part),
              ].join(', ')}])',
          ];
    final subject = kind == 'find' && max == null && !distinct
        ? ''
        : ', subject: Subject(SubjectKind.$kind'
              "${max == null ? '' : ', maxResults: $max'}"
              "${distinct ? ', distinct: true' : ''})";
    final order = sort.isEmpty ? '' : ', sort: Sort([${sort.join(', ')}])';
    return "static const _$name = PartTree(r'$name', "
        '[${alternatives.join(', ')}]$subject$order);';
  }

  // `-year` is `SortOrder.desc(r'year')`.
  static String _order(String order) {
    final direction = order.startsWith('-') ? 'desc' : 'asc';
    return "SortOrder.$direction(r'${order.substring(1)}')";
  }

  static String _part(String text) {
    final [property, ...rest] = text.split(':');
    final type = rest.isEmpty || rest[0].isEmpty ? 'simpleProperty' : rest[0];
    final ignoreCase = rest.length > 1 && rest[1] == 'i';
    // `ignoreCase` is the third positional parameter of `Part`.
    return "Part(r'$property'"
        "${type == 'simpleProperty' && !ignoreCase ? '' : ', PartType.$type'}"
        "${ignoreCase ? ', true' : ''})";
  }
}

const _books = 'Future<List<Book>>';

const _chapterReference = 'AggregateReference<Chapter, int>';

// The catalogue of valid names, one method each: a row per line; a line that
// starts with spaces goes on with the one before (with no space before a
// parenthesis), and `#` starts a comment.
Iterable<String> _rows(String table) sync* {
  var row = '';
  for (final line in table.split('\n')) {
    if (line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('  ')) {
      row += '${line.trim().startsWith('(') ? '' : ' '}${line.trim()}';
      continue;
    }
    if (row.isNotEmpty) {
      yield row;
    }
    row = line.trim();
  }
  if (row.isNotEmpty) {
    yield row;
  }
}

final List<_Case> _cases = [
  // The prefix is the subject.
  for (final prefix in ['find', 'read', 'get', 'query', 'search', 'stream'])
    '${prefix}ByTitle(String t) :: title',
  ..._rows('''
Future<int> countByTitle(String t) :: title ; count
Future<bool> existsByTitle(String t) :: title ; exists
Future<int> deleteByTitle(String t) :: title ; delete
Future<int> removeByTitle(String t) :: title ; delete
# First and Top, with and without a number; other words are ignored.
findFirstByTitle(String t) :: title ; max=1
findTopByTitle(String t) :: title ; max=1
findTop10ByTitle(String t) :: title ; max=10
findFirst3ByTitle(String t) :: title ; max=3
findBooksByTitle(String t) :: title
findFirstBooksByTitle(String t) :: title ; max=1
findAllByTitle(String t) :: title
getAllBooksByYear(int y) :: year
# Distinct anywhere in the subject.
findDistinctByTitle(String t) :: title ; distinct
findDistinctTop2ByTitle(String t) :: title ; max=2 distinct
findTop2DistinctByTitle(String t) :: title ; max=2 distinct
Future<int> countDistinctByTitle(String t) :: title ; count distinct
# An empty predicate matches everything.
findAllBy() :: -
findBy() :: -
Future<int> countBy() :: - ; count
findAllByOrderByTitleAsc() :: - ; sort=+title
# And binds tighter than Or.
findByTitleOrYearAndPrice(String t, int y, double p) :: title | year & price
findByTitleAndYearOrPrice(String t, int y, double p) :: title & year | price
findByYearBetweenAndTitleOrInStockTrue(int a, int b, String t)
  :: year:between & title | inStock:isTrue
# Properties that contain Or, And and keywords stay whole.
findByOrderNumber(int v) :: orderNumber
findByOrigin(String v) :: origin
findByAndroid(String v) :: android
findByIsbn(String v) :: isbn
findByInStock(bool v) :: inStock
findByNotes(String? v) :: notes
findByBetween(int? v) :: between
findByURL(String v) :: URL
findByAddress(String v) :: address
findByOrderNumberAndOriginOrAndroidAndIsbn
  (int a, String b, String c, String d)
  :: orderNumber & origin | android & isbn
findByOrderNumberOrderByOrigin(int n) :: orderNumber ; sort=+origin
# Keywords on properties named like keywords.
findByNotesNull() :: notes:isNull
findByNotesNotNull() :: notes:isNotNull
findByBetweenIn(List<int> v) :: between:in_
findByInStockNot(bool v) :: inStock:negatingSimpleProperty
findByURLContaining(String v) :: URL:containing
# Ignore case, on one part and on all.
findByTitleIgnoreCase(String t) :: title::i
findByAddressIgnoringCase(String t) :: address::i
findByTitleContainingIgnoreCase(String t) :: title:containing:i
findByTitleIgnoreCaseAndOrigin(String t, String o) :: title::i & origin
findByTitleAndYearAndOriginAllIgnoreCase(String t, int y, String o)
  :: title::i & year & origin::i
findByIsbnAndPriceAndAndroidAllIgnoringCase(String t, double y, String o)
  :: isbn::i & price & android::i
findByTitleAllIgnoreCaseOrderByYear(String t) :: title::i ; sort=+year
findByNotesNullAndOriginAllIgnoreCase(String t) :: notes:isNull & origin::i
# Order by.
findByYearOrderByYearDescTitleAscOriginAscAndroid(int y)
  :: year ; sort=-year,+title,+origin,+android
findAllByOrderByYear() :: - ; sort=+year
findAllByOrderByOrderNumberDesc() :: - ; sort=-orderNumber
# Every keyword and alias.
findByYearBetween(int a, int b) :: year:between
findByYearIsBetween(int a, int b) :: year:between
findByNotesIsNotNull() :: notes:isNotNull
findByNotesIsNull() :: notes:isNull
findByYearLessThan(int y) :: year:lessThan
findByYearIsLessThan(int y) :: year:lessThan
findByYearBefore(int y) :: year:lessThan
findByYearIsBefore(int y) :: year:lessThan
findByYearLessThanEqual(int y) :: year:lessThanEqual
findByYearIsLessThanEqual(int y) :: year:lessThanEqual
findByYearGreaterThan(int y) :: year:greaterThan
findByYearIsGreaterThan(int y) :: year:greaterThan
findByYearAfter(int y) :: year:greaterThan
findByYearIsAfter(int y) :: year:greaterThan
findByYearGreaterThanEqual(int y) :: year:greaterThanEqual
findByYearIsGreaterThanEqual(int y) :: year:greaterThanEqual
findByTitleNotLike(String t) :: title:notLike
findByTitleIsNotLike(String t) :: title:notLike
findByTitleLike(String t) :: title:like
findByTitleIsLike(String t) :: title:like
findByTitleStartingWith(String t) :: title:startingWith
findByTitleIsStartingWith(String t) :: title:startingWith
findByTitleStartsWith(String t) :: title:startingWith
findByTitleEndingWith(String t) :: title:endingWith
findByTitleIsEndingWith(String t) :: title:endingWith
findByTitleEndsWith(String t) :: title:endingWith
findByTitleNotContaining(String t) :: title:notContaining
findByTitleIsNotContaining(String t) :: title:notContaining
findByTitleNotContains(String t) :: title:notContaining
findByTitleContaining(String t) :: title:containing
findByTitleIsContaining(String t) :: title:containing
findByTitleContains(String t) :: title:containing
findByYearNotIn(List<int> y) :: year:notIn
findByYearIsNotIn(List<int> y) :: year:notIn
findByYearIn(List<int> y) :: year:in_
findByYearIsIn(List<int> y) :: year:in_
findByInStockTrue() :: inStock:isTrue
findByInStockIsTrue() :: inStock:isTrue
findByInStockFalse() :: inStock:isFalse
findByInStockIsFalse() :: inStock:isFalse
findByYearNot(int y) :: year:negatingSimpleProperty
findByYearIsNot(int y) :: year:negatingSimpleProperty
findByYearIs(int y) :: year
findByYearEquals(int y) :: year
findByYear(int y) :: year
# The example of the docs.
findTop5ByTitleContainingIgnoreCaseAndYearGreaterThanOrderByYearDesc
  (String title, int year)
  :: title:containing:i & year:greaterThan ; max=5 sort=-year
# Parameters that fit the property: nullable, num, dynamic, Object, ...
findByOrderNumberIs(int? v) :: orderNumber
findByOrderNumberEquals(num v) :: orderNumber
findByOrderNumberIsNot(dynamic v) :: orderNumber:negatingSimpleProperty
findByOrderNumberNot(Object v) :: orderNumber:negatingSimpleProperty
findByPrice(int v) :: price
findByPriceIs(double v) :: price
findByPublished(DateTime v) :: published
findByStatus(Status v) :: status
findByTitleIs(String? v) :: title
# ... a reference by the reference or by its id, an id marked @Reference.
findByAuthor(int v) :: author
findByAuthorIs(AggregateReference<Author, int> v) :: author
findByAuthorEquals(Object v) :: author
findByAuthorIn(List<int> v) :: author:in_
findByWriterId(int v) :: writerId
# In takes a collection of elements that fit.
findByOriginNotIn(Set<String> v) :: origin:notIn
findByAddressIn(Iterable<String> v) :: address:in_
findByIsbnIn(List<Object> v) :: isbn:in_
findByAndroidIn(dynamic v) :: android:in_
# Sort and Pageable are no part of the name, wherever they are.
findByTitleAndOrigin(String t, Sort s, String o) :: title & origin
findByIsbnAndAndroid(Pageable p, String a, String b) :: isbn & android
findByAddressAndURL(String a, String u, Pageable p) :: address & URL
findByYearBetweenAndPrice(int a, Pageable p, int b, double c)
  :: year:between & price
findTop3ByNotes(String? t, Pageable p) :: notes ; max=3
# Return types: the entity, nullable or not, collections, streams, pages.
Future<Book> findByTitleIsNot(String t) :: title:negatingSimpleProperty
Future<Book?> findFirstByIsbn(String t) :: isbn ; max=1
Future<Set<Book>> findByAddressNot(String t) :: address:negatingSimpleProperty
Future<Iterable<Book>> findByOriginIs(String t) :: origin
Stream<Book> streamByYear(int y) :: year
Future<Page<Book>> findByPriceAfter(double p, Pageable a) :: price:greaterThan
Future<Slice<Book>> findByPriceBefore(double p, Pageable a) :: price:lessThan
Future<List<Book>?> findByIsbnLike(String p) :: isbn:like
Future<void> deleteByYearIs(int y) :: year ; delete
Future<List<Book>> removeByYearIs(int y) :: year ; delete
Future<int?> countByYearIs(int y) :: year ; count
'''),
].map(_Case.new).toList();

void main() {
  group('the class of a repository', () {
    const model = '''
// CRUD only: nothing to write.
abstract interface class AuthorRepository
    implements ListCrudRepository<Author, int> {}

abstract interface class Searchable<T> {
  Future<List<T>> findByTitleContaining(String part);

  @Query('select count(*) from books')
  Future<int> total();
}

class Rules {
  const Rules(this.types);
  final List<Type> types;
}

class OutOfStock implements Exception {}

@Repository('library')
@UseStore('memory')
abstract interface class BookRepository
    implements
        ListCrudRepository<Book, int>,
        ListPagingAndSortingRepository<Book, int>,
        Searchable<Book> {
  // A CRUD method redeclared: SimpleRepository implements it.
  @override
  Future<List<Book>> findAll();

  Future<List<Book>> findByTitleAndYear(String title, int year);
  Future<Iterable<Book>> findByYearLessThanOrderByYear(int year);
  Future<Set<Book>> findByYear(int year);
  Future<Book?> findFirstByOrderByYearAsc();
  Future<Book> getByTitle(String title);
  Stream<Book> streamByInStock(bool inStock);
  Future<Page<Book>> findByYearAfter(int year, Pageable page);
  Future<Slice<Book>> findByInStockIsTrue(Pageable page);
  Future<List<Book>> findByInStock(bool inStock, Sort order);
  Stream<Book> streamByYear(int year, Pageable page);
  Future<int> countByInStock(bool inStock);
  Future<bool> existsByTitle(String title);
  Future<int> deleteByYearLessThan(int year);
  Future<void> removeByTitle(String title);
  Future<List<Book>> deleteByInStock(bool inStock);
  Future<List<Book>> findByNotesNull();
  Future<List<Book>> findByYearIn({required List<int> years});

  @Rules([OutOfStock])
  Future<List<Book>> findByOrigin(String origin);

  @Lock(LockMode.pessimisticWrite)
  Future<Book?> findById(int id);

  @Lock(LockMode.pessimisticRead, skipLocked: true)
  Future<Book?> findOneByYearAndTitle(int year, String title);

  @Lock(LockMode.pessimisticWrite)
  Future<Page<Book>> findByTitle(String title, Pageable page);

  @Query('select title from books where year = :year')
  Future<List<BookCard>> cards(int year);

  @Query('select title from books')
  Stream<BookCard> cardStream();

  // A name that would be derived: @Query wins, and is never parsed.
  @Query('select * from books')
  Future<List<Book>> findByEverything();

  @Modifying()
  @Query('delete from books where year = :year')
  Future<void> purge({required int year});

  @Modifying()
  @Query('update books set year = year + 1 where year > :year')
  Future<int> bump(int year);

  @Query('select * from books where year > :year')
  Future<Page<Book>> pageAfter(int year, Pageable pageable);

  @Query('select * from books where year > :year')
  Future<Slice<Book>> sliceAfter(int year, Pageable pageable);

  @Query('select * from books where year > :year',
      countQuery: 'select count(*) from books where year > :year')
  Future<Page<Book>> pageCounted(int year, Pageable pageable);

  @Query('select * from books where year > :year')
  Future<List<Book>> sorted(Sort sort, int year);

  @Query('select * from {Book} b where b.{Book.year} = :year')
  Future<Book?> viaPlaceholder(int year);

  @Query('select * from books where year = :#{#year + 1} or year = :#{[0]}')
  Future<Set<Book>> viaExpressions(int year);

  @Query('select title from books', rowMapper: firstColumn)
  Future<List<String>> titles();

  @Query('select title from books where id = :id')
  Future<String?> titleOf(int id);

  @Query('select status from books where id = :id')
  Future<Status> statusOf(int id);
}

Object? firstColumn(JdbcRow row) => row.values.first;
''';

    late String raw;
    late String output;
    late String authors;
    late String books;

    setUpAll(() async {
      raw = await _generate(model);
      output = _normalize(raw);
      final authorsStart = raw.indexOf(r'class _$AuthorRepositoryImpl');
      final booksStart = raw.indexOf(r'class _$BookRepositoryImpl');
      authors = raw.substring(authorsStart, booksStart);
      books = raw.substring(booksStart);
    });

    test('extends SimpleRepository with the type arguments of the entity', () {
      expect(
        _normalize(authors),
        _has(r'''
class _$AuthorRepositoryImpl extends SimpleRepository<Author, int>
    implements AuthorRepository {
  _$AuthorRepositoryImpl(super.operations);
  static _$AuthorRepositoryImpl $create(DependencyResolver r) =>
      _$AuthorRepositoryImpl(
        r.dependency<RepositoryFactory>()
            .operations<Author, int>(r'AuthorRepository'),
      );
}
'''),
      );
    });

    test('a repository with CRUD methods only has nothing else', () {
      expect(authors, isNot(contains('static const')));
      expect(authors, isNot(contains('@override')));
      expect(authors, isNot(contains('queries:')));
      expect(authors, isNot(contains('annotations:')));
    });

    test('the annotations of the interface and its queries are passed', () {
      expect(
        _normalize(books),
        _has('''
operations<Book, int>(
  r'BookRepository',
  annotations: const [Repository(r'library'), UseStore(r'memory')],
  queries: [
    _cards, _cardStream, _findByEverything, _purge, _bump, _pageAfter,
    _sliceAfter,
    _pageCounted, _sorted, _viaPlaceholder, _viaExpressions, _titles, _titleOf,
    _statusOf, _total,
  ],
)'''),
      );
    });

    test('the bean has the name, types and creation of the interface', () {
      expect(output, _has("name: r'library'"));
      expect(output, _has("name: r'authorRepository'"));
      expect(output, _has('BeanDefinition<BookRepository>('));
      expect(output, _has(r'create: (r) => _$BookRepositoryImpl.$create(r)'));
      expect(
        output,
        _has('''
types: const [
  BookRepository,
  ListCrudRepository<Book, int>,
  CrudRepository<Book, int>,
  DataRepository<Book, int>,'''),
      );
      expect(
        output,
        _has(
          "annotations: const [Repository(r'library'), UseStore(r'memory')]",
        ),
      );
    });

    test('a derived query is a constant tree and a one-line call', () {
      expect(
        output,
        _has('''
static const _findByTitleAndYear = PartTree(r'findByTitleAndYear', [
  OrPart([Part(r'title'), Part(r'year')]),
]);'''),
      );
      expect(
        output,
        _has('''
Future<List<Book>> findByTitleAndYear(String title, int year) =>
    this.operations.list(_findByTitleAndYear, [title, year]);'''),
      );
    });

    test('the operation follows the return type', () {
      for (final (call, signature) in [
        (
          'list(_findByYearLessThanOrderByYear, [year])',
          'Future<Iterable<Book>> findByYearLessThanOrderByYear(int year)',
        ),
        ('set(_findByYear, [year])', 'Future<Set<Book>> findByYear(int year)'),
        (
          'one(_findFirstByOrderByYearAsc, const [])',
          'Future<Book?> findFirstByOrderByYearAsc()',
        ),
        (
          'single(_getByTitle, [title])',
          'Future<Book> getByTitle(String title)',
        ),
        (
          'stream(_streamByInStock, [inStock])',
          'Stream<Book> streamByInStock(bool inStock)',
        ),
        (
          'page(_findByYearAfter, [year], page)',
          'Future<Page<Book>> findByYearAfter(int year, Pageable page)',
        ),
        (
          'slice(_findByInStockIsTrue, const [], page)',
          'Future<Slice<Book>> findByInStockIsTrue(Pageable page)',
        ),
        (
          'countBy(_countByInStock, [inStock])',
          'Future<int> countByInStock(bool inStock)',
        ),
        (
          'existsBy(_existsByTitle, [title])',
          'Future<bool> existsByTitle(String title)',
        ),
        (
          'deleteBy(_deleteByYearLessThan, [year])',
          'Future<int> deleteByYearLessThan(int year)',
        ),
        (
          'deleteBy(_removeByTitle, [title])',
          'Future<void> removeByTitle(String title)',
        ),
        (
          'deleteByReturning(_deleteByInStock, [inStock])',
          'Future<List<Book>> deleteByInStock(bool inStock)',
        ),
      ]) {
        expect(
          output,
          _has('$signature => this.operations.$call;'),
          reason: signature,
        );
      }
    });

    test('Sort and Pageable are passed by name, a page takes its own', () {
      expect(
        output,
        _has('''
Future<List<Book>> findByInStock(bool inStock, Sort order) =>
    this.operations.list(_findByInStock, [inStock], sort: order);'''),
      );
      expect(
        output,
        _has('''
Stream<Book> streamByYear(int year, Pageable page) =>
    this.operations.stream(_streamByYear, [year], pageable: page);'''),
      );
    });

    test('a named parameter is an argument like any other', () {
      expect(
        output,
        _has('''
Future<List<Book>> findByYearIn({required List<int> years}) =>
    this.operations.list(_findByYearIn, [years]);'''),
      );
    });

    test('@Lock is passed with the call', () {
      expect(
        output,
        _has('''
Future<Book?> findOneByYearAndTitle(int year, String title) =>
    this.operations.one(
      _findOneByYearAndTitle, [year, title],
      lock: const Lock(LockMode.pessimisticRead, skipLocked: true));'''),
      );
      expect(
        output,
        _has('''
Future<Page<Book>> findByTitle(String title, Pageable page) =>
    this.operations.page(
      _findByTitle, [title], page,
      lock: const Lock(LockMode.pessimisticWrite));'''),
      );
    });

    test('findById with @Lock overrides the CRUD method with the lock', () {
      expect(
        output,
        _has(
          '''
Future<Book?> findById(int id) =>
    this.operations.findById(id, lock: const Lock(LockMode.pessimisticWrite));''',
        ),
      );
    });

    test('a CRUD method redeclared is left to SimpleRepository', () {
      expect(output, isNot(_has('Future<List<Book>> findAll()')));
      expect(output, isNot(contains('_findAll')));
      expect(output, isNot(_has('operations.findAll')));
    });

    test('a CRUD method of a repository without CrudRepository too', () async {
      final source = await _generate('''
abstract interface class AuthorRepository
    implements DataRepository<Author, int> {
  @override
  Future<Author?> findById(int id);
  Future<int> count();
  @Lock(LockMode.pessimisticRead)
  Future<Author?> findByName(String name);
}
''');
      final output = _normalize(source);
      expect(output, _has('extends SimpleRepository<Author, int>'));
      expect(output, isNot(_has('operations.findById')));
      expect(output, isNot(contains('_count')));
      expect(output, _has('this.operations.one(_findByName'));
    });

    test(
      'the CRUD methods are found with nothing imported but the marker',
      () async {
        // Only `DataRepository` and `Lock` are imported: no library that
        // exports `ListCrudRepository`.
        final source = await _generate(
          '''
class Note {
  Note(this.text);
  String text;
}

abstract interface class NoteRepository
    implements DataRepository<Note, int> {
  @Lock(LockMode.pessimisticWrite)
  Future<Note?> findById(int id);
  Future<int> count();
  Future<List<Note>> findByText(String text);
}
''',
          header: '''
import 'package:spring_boot_starter_data/src/annotations.dart'
    show Lock, LockMode;
import 'package:spring_boot_starter_data/src/repository/repository.dart'
    show DataRepository;
''',
          entities: '',
        );
        final output = _normalize(source);
        expect(
          output,
          _has(
            '''
Future<Note?> findById(int id) =>
    this.operations.findById(id, lock: const Lock(LockMode.pessimisticWrite));''',
          ),
        );
        expect(output, isNot(contains('_count')));
        expect(output, _has('this.operations.list(_findByText'));
      },
    );

    test('a parameter called operations does not hide the call', () async {
      const model = '''
abstract interface class StockRepository
    implements ListCrudRepository<Book, int> {
  Future<List<Book>> findByYear(int operations);
  Future<Page<Book>> findByTitle(String title, Pageable operations);
  @Query('select * from books where year = :operations')
  Future<List<Book>> byOperations(int operations);
}
''';
      final raw = await _generate(model);
      final output = _normalize(raw);
      expect(
        output,
        _has('''
Future<List<Book>> findByYear(int operations) =>
    this.operations.list(_findByYear, [operations]);'''),
      );
      expect(
        output,
        _has('''
Future<Page<Book>> findByTitle(String title, Pageable operations) =>
    this.operations.page(_findByTitle, [title], operations);'''),
      );
      expect(
        output,
        _has(
          'this.operations.query<List<Book>>(_byOperations, [operations])',
        ),
      );
      final errors = await resolveSources<List<String>>(
        {
          'pkg|lib/src/beans.dart': _scan,
          'pkg|lib/src/model.dart': '$_header$_entities$model',
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

    test('a method named like a member of the generated class', () async {
      final message = await _errors(r'''
abstract interface class StockRepository
    implements ListCrudRepository<Book, int> {
  @Query('select * from books')
  Future<List<Book>> operations();
  @Query('select * from books')
  Future<List<Book>> $create();
}
''');
      for (final name in ['operations', r'$create']) {
        expect(
          message,
          contains(
            'StockRepository.$name: the generated class has a member of this '
            'name: rename the method.',
          ),
        );
      }
    });

    test(
      '@Query is a constant for the starter, listed in the factory call',
      () {
        expect(
          output,
          _has("""
static const _cards = QueryMethod(
  r'cards',
  Query(r'select title from books where year = :year'),
  parameters: [r'year'],
  element: ClassType<BookCard>(),
);"""),
        );
        expect(
          output,
          _has('''
Future<List<BookCard>> cards(int year) =>
    this.operations.query<List<BookCard>>(_cards, [year]);'''),
        );
      },
    );

    test('a @Query returning a Stream is a queryStream', () {
      expect(
        output,
        _has("""
static const _cardStream = QueryMethod(
  r'cardStream',
  Query(r'select title from books'),
  shape: QueryShape.stream,
  element: ClassType<BookCard>(),
);"""),
      );
      expect(
        output,
        _has('''
Stream<BookCard> cardStream() =>
    this.operations.queryStream<BookCard>(_cardStream, const []);'''),
      );
    });

    test('@Query wins over a name that would be derived', () {
      expect(output, isNot(contains('_findByEverything = PartTree')));
      expect(
        output,
        _has('this.operations.query<List<Book>>(_findByEverything, const [])'),
      );
    });

    test('a change says what it returns, and has no element', () {
      expect(
        output,
        _has("""
static const _purge = QueryMethod(
  r'purge',
  Query(r'delete from books where year = :year'),
  parameters: [r'year'],
  change: QueryChange.nothing,
);"""),
      );
      expect(
        output,
        _has('''
Future<void> purge({required int year}) =>
    this.operations.query<void>(_purge, [year]);'''),
      );
      expect(
        output,
        _has("""
static const _bump = QueryMethod(
  r'bump',
  Query(r'update books set year = year + 1 where year > :year'),
  parameters: [r'year'],
  change: QueryChange.rows,
);"""),
      );
    });

    test(
      'pages, slices and sorts: the shape and the index of the argument',
      () {
        expect(
          output,
          _has("""
static const _pageAfter = QueryMethod(
  r'pageAfter',
  Query(r'select * from books where year > :year'),
  parameters: [r'year', r'pageable'],
  pageable: 1,
  shape: QueryShape.page,
  element: ClassType<Book>(),
);"""),
        );
        expect(
          output,
          _has("""
static const _sliceAfter = QueryMethod(
  r'sliceAfter',
  Query(r'select * from books where year > :year'),
  parameters: [r'year', r'pageable'],
  pageable: 1,
  shape: QueryShape.slice,
  element: ClassType<Book>(),
);"""),
        );
        expect(
          output,
          _has("""
static const _pageCounted = QueryMethod(
  r'pageCounted',
  Query(
    r'select * from books where year > :year',
    countQuery: r'select count(*) from books where year > :year',
  ),
  parameters: [r'year', r'pageable'],
  pageable: 1,
  shape: QueryShape.page,
  element: ClassType<Book>(),
);"""),
        );
        expect(
          output,
          _has("""
static const _sorted = QueryMethod(
  r'sorted',
  Query(r'select * from books where year > :year'),
  parameters: [r'sort', r'year'],
  sort: 0,
  element: ClassType<Book>(),
);"""),
        );
      },
    );

    test('results: a single one, nullable or not, a scalar, an enum', () {
      expect(
        output,
        _has("""
static const _titleOf = QueryMethod(
  r'titleOf',
  Query(r'select title from books where id = :id'),
  parameters: [r'id'],
  shape: QueryShape.single,
  element: ClassType<String>(nullable: true),
);"""),
      );
      expect(
        output,
        _has("""
static const _statusOf = QueryMethod(
  r'statusOf',
  Query(r'select status from books where id = :id'),
  parameters: [r'id'],
  shape: QueryShape.single,
  element: EnumType<Status>(Status.values),
);"""),
      );
    });

    test('an entity placeholder names the entity class, once', () {
      expect(
        output,
        _has("""
static const _viaPlaceholder = QueryMethod(
  r'viaPlaceholder',
  Query(r'select * from {Book} b where b.{Book.year} = :year'),
  parameters: [r'year'],
  shape: QueryShape.single,
  element: ClassType<Book>(nullable: true),
  entities: {r'Book': Book},
);"""),
      );
    });

    test('an expression the build compiles is a function of the arguments', () {
      expect(
        output,
        _has("""
static final _viaExpressions = QueryMethod(
  r'viaExpressions',
  const Query(
    r'select * from books where year = :#{#year + 1} or year = :#{[0]}',
  ),
  parameters: const [r'year'],
  shape: QueryShape.set,
  element: const ClassType<Book>(),
  expressions: [
    (arguments, context) => (arguments[0] as int) + 1,
    (arguments, context) => SpelOperations.listElement(arguments, 0),
  ],
);"""),
      );
    });

    test('a row mapper stays in the annotation, as a function reference', () {
      expect(
        output,
        _has("""
static const _titles = QueryMethod(
  r'titles',
  Query(r'select title from books', rowMapper: firstColumn),
  element: ClassType<String>(),
);"""),
      );
    });

    test('a method inherited from another interface, with its types', () {
      expect(
        output,
        _has('''
static const _findByTitleContaining = PartTree(r'findByTitleContaining', [
  OrPart([Part(r'title', PartType.containing)]),
]);'''),
      );
      expect(
        output,
        _has('''
Future<List<Book>> findByTitleContaining(String part) =>
    this.operations.list(_findByTitleContaining, [part]);'''),
      );
      expect(
        output,
        _has(
          'Future<int> total() => '
          'this.operations.query<int>(_total, const []);',
        ),
      );
    });

    test('nothing is described for the starter to read at start up', () {
      expect(output, isNot(contains('InterfaceMetadata')));
      expect(output, isNot(contains('InvocationHandler')));
      expect(output, isNot(contains('supertypeArguments')));
      expect(output, isNot(contains('call:')));
      // The @Query methods have a QueryMethod, never a ProxyMethod.
      expect(output, isNot(contains('ProxyMethod')));
      expect('QueryMethod('.allMatches(output), hasLength(15));
      expect(output, isNot(_has("QueryMethod(r'findByTitleAndYear'")));
    });

    test('the types of repository signatures are not introspected', () {
      expect(output, isNot(contains('BeanIntrospection')));
    });

    test('the generated code compiles against the starter', () async {
      final errors = await resolveSources<List<String>>(
        {
          'pkg|lib/src/beans.dart': _scan,
          'pkg|lib/src/model.dart': '$_header$_entities$model',
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

  group('beans', () {
    test('a generic interface is a base, never a bean', () async {
      final output = _normalize(
        await _generate('''
abstract interface class BaseRepository<T> implements CrudRepository<T, int> {}

abstract interface class AuthorRepository
    implements BaseRepository<Author> {
  Future<Author?> findByName(String name);
}
'''),
      );
      expect(output, isNot(contains(r'_$BaseRepositoryImpl')));
      expect(output, isNot(_has("name: r'baseRepository'")));
      expect(output, _has('extends SimpleRepository<Author, int>'));
    });

    test('a concrete @Repository class stays a component', () async {
      final output = _normalize(
        await _generate('''
@Repository()
class AuditLog {
  final lines = <String>[];
}
'''),
      );
      expect(output, _has("name: r'auditLog'"));
      expect(output, isNot(contains(r'_$AuditLogImpl')));
    });

    test('an advised repository is wrapped in its proxy', () async {
      final output = _normalize(
        await _generate('''
abstract interface class AuthorRepository
    implements ListCrudRepository<Author, int> {
  @Transactional()
  Future<List<Author>> findByName(String name);
}
''', proxyMode: ProxyMode.all),
      );
      expect(output, _has(r'class _$AuthorRepositoryProxy'));
      expect(output, _has(r'create: (r) => _$AuthorRepositoryImpl.$create(r)'));
      expect(output, _has('aopProxy: AopProxyFactory('));
    });

    test(
      'CrudRepository alone is enough: SimpleRepository narrows it',
      () async {
        final output = _normalize(
          await _generate('''
abstract interface class AuthorRepository
    implements CrudRepository<Author, int> {
  Future<List<Author>> findAll();
}
'''),
        );
        expect(output, _has('extends SimpleRepository<Author, int>'));
        expect(output, isNot(contains('operations.findAll')));
      },
    );
  });

  group('derived query names', () {
    late String output;

    setUpAll(() async {
      output = _normalize(
        await _generate(
          _bookRepository([for (final c in _cases) c.declaration].join('\n')),
        ),
      );
    });

    test('are unique in the catalogue', () {
      expect(_cases.map((c) => c.name).toSet(), hasLength(_cases.length));
    });

    test('are written as constant trees (subjects, predicates, order)', () {
      for (final c in _cases) {
        expect(output, _has(c.expected), reason: c.name);
      }
    });

    test('are told from other names by their start', () {
      for (final name in [
        'findByTitle',
        'findAllBooksByTitle',
        'countBy',
        'removeByTitle',
      ]) {
        expect(PartTreeParser.isDerivedQuery(name), isTrue, reason: name);
      }
      for (final name in [
        'save',
        'findAll',
        'fetchByTitle',
        'findbyTitle',
        'titleBy',
      ]) {
        expect(PartTreeParser.isDerivedQuery(name), isFalse, reason: name);
      }
    });
  });

  group('build errors', () {
    // The problems of one interface, `BookRepository`: each row is a method
    // and the line the build lists for it.
    final problems = <(String, String)>[
      // Getters and setters come first: they are found before the methods.
      (
        'int get size;',
        'BookRepository.size: only methods are supported in a repository '
            '(no getters or setters).',
      ),
      // The name is not a query.
      (
        'Future<List<Book>> fetchByTitle(String t);',
        'BookRepository.fetchByTitle: not a CRUD method of the repository '
            'interfaces and not a derived query: a query method starts with '
            'find, read, get, query, search, stream, count, exists, delete or '
            'remove, then By and the conditions (findByTitle)',
      ),
      (
        'Future<List<Book>> findbyTitle(String t);',
        'BookRepository.findbyTitle: not a CRUD method',
      ),
      (
        'Future<List<Book>> doSomething();',
        'BookRepository.doSomething: not a CRUD method of the repository '
            'interfaces and not a derived query',
      ),
      // A CRUD name with another arity is not CRUD.
      (
        'Future<void> save(Book a, Book b);',
        'BookRepository.save: not a CRUD method of the repository '
            'interfaces and not a derived query',
      ),
      (
        'Future<void> deleteAll(int x);',
        'BookRepository.deleteAll: not a CRUD method',
      ),
      (
        'Future<void> count(int x, int y);',
        'BookRepository.count: not a CRUD method',
      ),
      // A CRUD name with a signature that does not fit it.
      (
        'Future<int> findById(int id);',
        'BookRepository.findById: has the name of a CRUD method of the '
            'repository interfaces, Future<Book?> findById(int id), but a '
            'signature that does not fit it',
      ),
      // Properties.
      (
        'Future<List<Book>> findByTitel(String title);',
        "BookRepository.findByTitel: No property 'titel' found for type "
            "'Book'; did you mean 'title'? Available properties: id, title, "
            'year, price, inStock, orderNumber, origin, android, isbn, notes, '
            'between, URL, address, published, status, author, writerId.',
      ),
      (
        'Future<List<Book>> findByZzzzzz(String t);',
        "BookRepository.findByZzzzzz: No property 'zzzzzz' found for type "
            "'Book' Available properties:",
      ),
      (
        'Future<List<Book>> findByChapters(List<Chapter> c);',
        "BookRepository.findByChapters: property 'chapters' cannot be used "
            'in a condition: it holds child entities, and derived queries '
            "stay within the columns of the root entity's own table",
      ),
      (
        'Future<List<Book>> findByCache(String c);',
        "BookRepository.findByCache: No property 'cache' found",
      ),
      (
        'Future<List<Book>> findByAddressCity(String c);',
        'BookRepository.findByAddressCity: nested property path '
            "'addressCity' (property 'address' and then 'city') is not "
            'supported yet',
      ),
      (
        'Future<List<Book>> findByAddress_City(String c);',
        'BookRepository.findByAddress_City: nested property path '
            "'address_City' is not supported yet",
      ),
      (
        'Future<List<Book>> findByAddressCityContaining(String c);',
        'BookRepository.findByAddressCityContaining: nested property path',
      ),
      (
        'Future<List<Book>> findByYearTitle(String c);',
        'BookRepository.findByYearTitle: nested property path',
      ),
      (
        'Future<List<Book>> findAllByOrderByTitel();',
        "BookRepository.findAllByOrderByTitel: No property 'titel'",
      ),
      (
        'Future<List<Book>> findAllByOrderByTitleOrderByYear();',
        'BookRepository.findAllByOrderByTitleOrderByYear: the name has more '
            'than one "OrderBy"',
      ),
      (
        'Future<List<Book>> findAllByOrderByChapters();',
        "BookRepository.findAllByOrderByChapters: property 'chapters' cannot "
            'be used in OrderBy',
      ),
      // Parameters.
      (
        'Future<List<Book>> getByTitle();',
        'BookRepository.getByTitle: the name needs 1 parameter(s) besides '
            'Sort and Pageable, but the method declares 0',
      ),
      (
        'Future<List<Book>> readByTitle(String a, String b);',
        'BookRepository.readByTitle: the name needs 1 parameter(s) besides '
            'Sort and Pageable, but the method declares 2',
      ),
      (
        'Future<List<Book>> findByYearBetween(int a);',
        'BookRepository.findByYearBetween: the name needs 2 parameter(s)',
      ),
      (
        'Future<List<Book>> queryByTitle(int t);',
        "BookRepository.queryByTitle: parameter 't' (int) does not fit "
            "'title' (String) with simpleProperty",
      ),
      (
        'Future<List<Book>> searchByYear(String year);',
        "BookRepository.searchByYear: parameter 'year' (String) does not fit "
            "'year' (int)",
      ),
      (
        'Future<List<Book>> findByTitleContaining(int t);',
        "BookRepository.findByTitleContaining: parameter 't' (int) must be a "
            'String for containing',
      ),
      (
        'Future<List<Book>> findByYearContaining(String t);',
        'BookRepository.findByYearContaining: containing needs a String '
            'property',
      ),
      (
        'Future<List<Book>> findByYearIgnoreCase(int y);',
        'BookRepository.findByYearIgnoreCase: IgnoreCase needs a String '
            "property, but 'year' is int",
      ),
      (
        'Future<List<Book>> findByTitleTrue();',
        'BookRepository.findByTitleTrue: True/False need a bool property, '
            "but 'title' is String",
      ),
      (
        'Future<List<Book>> findByYearFalse();',
        'BookRepository.findByYearFalse: True/False need a bool property',
      ),
      (
        'Future<List<Book>> findByOrderNumberIn(int y);',
        "BookRepository.findByOrderNumberIn: parameter 'y' (int) must be a "
            'List, Set or Iterable for in_',
      ),
      (
        'Future<List<Book>> findByIsbnIn(List<int> y);',
        "BookRepository.findByIsbnIn: the elements of parameter 'y' (int) do "
            'not fit',
      ),
      (
        'Future<List<Book>> findByAuthorIs($_chapterReference a);',
        "BookRepository.findByAuthorIs: parameter 'a' "
            '(AggregateReference<Chapter, int>) does not fit',
      ),
      (
        'Future<List<Book>> findByTitleAndOrigin(String t, Pageable p);',
        'BookRepository.findByTitleAndOrigin: the name needs 2 parameter(s) '
            'besides Sort and Pageable, but the method declares 1',
      ),
      (
        'Future<List<Book>> findByAndroid(String t, Sort s, Pageable p);',
        'BookRepository.findByAndroid: it has a Pageable and a Sort '
            'parameter; sort in the Pageable instead',
      ),
      (
        'Future<List<Book>> findByIsbn(String t, Sort s, Sort s2);',
        'BookRepository.findByIsbn: it has more than one Sort parameter',
      ),
      (
        'Future<List<Book>> findByAddress(String t, Pageable a, Pageable b);',
        'BookRepository.findByAddress: it has more than one Pageable '
            'parameter',
      ),
      (
        'Future<int> countByTitle(String t, Sort s);',
        'BookRepository.countByTitle: a Sort or Pageable parameter is only '
            'allowed on a find method, not on count',
      ),
      (
        '$_books findByYearBetweenAndTitle(int a, String b, String t);',
        "BookRepository.findByYearBetweenAndTitle: parameter 'b' (String) "
            'does not fit',
      ),
      (
        'Future<List<Book>> findByTitleAndYearBetween(int a, int b, int c);',
        "BookRepository.findByTitleAndYearBetween: parameter 'a' (int) does "
            'not fit',
      ),
      // Return types.
      (
        'Future<Author> findByStatus(Status s);',
        'BookRepository.findByStatus: a find method must return Book, or a '
            'List, Set, Iterable, Stream, Page or Slice of Book (projections '
            'are not supported), not Author',
      ),
      (
        'Future<List<Author>> findByPrice(double p);',
        'BookRepository.findByPrice: a find method must return Book, or a '
            'List, Set, Iterable, Stream, Page or Slice of Book',
      ),
      (
        'Future<String> findByPublished(DateTime p);',
        'BookRepository.findByPublished: a find method must return Book, or '
            'a List',
      ),
      (
        'Future<Page<Author>> findByBetween(int p, Pageable a);',
        'BookRepository.findByBetween: a find method must return Book',
      ),
      (
        'Future<Page<Book>> findByOrigin(String o);',
        'BookRepository.findByOrigin: a method returning Page or Slice needs '
            'a Pageable parameter',
      ),
      (
        'Future<Slice<Book>> findByAndroidLike(String o);',
        'BookRepository.findByAndroidLike: a method returning Page or Slice '
            'needs a Pageable parameter',
      ),
      (
        'Future<Stream<Book>> findByIsbnLike(String o);',
        'BookRepository.findByIsbnLike: a Stream is already asynchronous: '
            'return Stream<Book>, not a Future of it',
      ),
      (
        'Future<String> countByIsbn(String s);',
        'BookRepository.countByIsbn: a count method must return int',
      ),
      (
        'Future<int> existsByOrigin(String o);',
        'BookRepository.existsByOrigin: an exists method must return bool',
      ),
      (
        'Future<String> deleteByAndroid(String a);',
        'BookRepository.deleteByAndroid: a delete method must return void, '
            'int (the number deleted) or List<Book>',
      ),
      (
        'Future<List<Author>> removeByAddress(String a);',
        'BookRepository.removeByAddress: a delete method must return void',
      ),
      // What the generated code could not say.
      (
        'Future<Book?> findFirstByYear(int y, Pageable p);',
        'BookRepository.findFirstByYear: a method that returns one Book? '
            'cannot take a Pageable: return a List, Page or Slice of it',
      ),
      (
        'Future<Page<Book>> findByStatusNot(Status s, Pageable? p);',
        "BookRepository.findByStatusNot: the Pageable parameter 'p' of a "
            'method returning a Page or Slice must not be nullable',
      ),
      // Every method is asynchronous.
      (
        'List<Book> findByURL(String u);',
        'BookRepository.findByURL: a repository method is asynchronous: '
            'return a Future (Future<List<Book>>) or a Stream',
      ),
      (
        "@Query('select 1') List<Book> rows();",
        'BookRepository.rows: a repository method is asynchronous',
      ),
      // @Lock reads rows.
      (
        '@Lock(LockMode.pessimisticWrite) Future<int> countByYearIs(int y);',
        'BookRepository.countByYearIs: @Lock is for the derived find methods '
            '(findByTitle) and findById: a lock is taken by reading rows, and '
            'this one counts',
      ),
      (
        '@Lock(LockMode.pessimisticWrite) Future<int> deleteByYearIs(int y);',
        'BookRepository.deleteByYearIs: @Lock is for the derived find '
            'methods (findByTitle) and findById: a lock is taken by reading '
            'rows, and this one deletes',
      ),
      (
        '@Lock(LockMode.pessimisticWrite) Future<bool> existsByYearIs(int y);',
        'BookRepository.existsByYearIs: @Lock is for the derived find '
            'methods',
      ),
      (
        '@Lock(LockMode.pessimisticWrite) @override '
            'Future<List<Book>> findAll();',
        'BookRepository.findAll: @Lock is for the derived find methods '
            '(findByTitle) and findById: a lock is taken by reading rows',
      ),
      // What the generated class cannot implement.
      (
        'Future<int> twice() async => 2;',
        'BookRepository.twice has a body: every method of the interface is '
            'implemented by the generated class.',
      ),
      (
        'Future<T?> findByTitleOfAny<T>(String t);',
        'BookRepository.findByTitleOfAny must not be generic.',
      ),
    ];

    late String message;

    setUpAll(() async {
      message = await _errors(
        _bookRepository(
          [for (final (source, _) in problems) source].join('\n'),
        ),
      );
    });

    test('are one error, naming the interface', () {
      expect(message, contains('Invalid repository BookRepository:\n  - '));
      expect('Invalid repository'.allMatches(message), hasLength(1));
      expect('\n  - '.allMatches(message), hasLength(problems.length));
    });

    for (final (source, line) in problems) {
      test(source, () {
        expect(message, contains('\n  - $line'));
      });
    }

    test('every problem is listed in the order of the methods', () {
      var from = 0;
      for (final (_, line) in problems) {
        final at = message.indexOf('\n  - $line', from);
        expect(at, greaterThanOrEqualTo(from), reason: line);
        from = at;
      }
    });

    test('a name with no property close enough has no suggestion', () {
      final line = message
          .split('\n')
          .firstWhere((l) => l.contains('BookRepository.findByZzzzzz'));
      expect(line, isNot(contains('did you')));
    });

    test('a method has one problem: the first one', () async {
      final one = await _errors(
        _bookRepository('Future<List<Book>> findByTitelAndYeer(String t);'),
      );
      expect(one, contains("No property 'titel' found"));
      expect(one, isNot(contains('yeer')));
    });
  });

  group('build errors of the repository itself', () {
    test('a repository that names no entity', () async {
      final message = await _errors('''
abstract interface class LooseRepository implements DataRepository {}
''');
      expect(message, contains('Invalid repository LooseRepository:'));
      expect(
        message,
        contains(
          'the entity type of DataRepository<T, ID> is dynamic: '
          'LooseRepository must name a class',
        ),
      );
    });

    test('a CRUD name with the wrong arity is not CRUD', () async {
      final message = await _errors(
        _bookRepository('Future<List<Book>> findAll(String x);'),
      );
      expect(
        message,
        contains(
          'BookRepository.findAll: not a CRUD method of the repository '
          'interfaces and not a derived query',
        ),
      );
    });

    test('a nullable entity', () async {
      final message = await _errors('''
abstract interface class NullRepository
    implements DataRepository<Book?, int> {}
''');
      expect(message, contains('the entity type of DataRepository<T, ID>'));
    });

    test('a private interface', () async {
      final message = await _errors('''
abstract interface class _Hidden implements DataRepository<Book, int> {}
''');
      expect(message, contains('Interface _Hidden must be public.'));
    });

    test('problems of two repositories are both reported', () async {
      final message = await _errors('''
abstract interface class FirstRepository
    implements DataRepository<Book, int> {
  Future<List<Book>> findByTitel(String t);
}

abstract interface class SecondRepository
    implements DataRepository<Author, int> {
  Future<List<Author>> findByNme(String t);
}
''');
      expect(message, contains('Invalid repository FirstRepository:'));
      expect(message, contains("did you mean 'title'?"));
      expect(message, contains('Invalid repository SecondRepository:'));
      expect(message, contains("did you mean 'name'?"));
    });

    test('a derived query on an entity without the property', () async {
      final message = await _errors('''
abstract interface class AuthorRepository
    implements DataRepository<Author, int> {
  Future<List<Author>> findByTitle(String t);
}
''');
      expect(
        message,
        contains(
          "AuthorRepository.findByTitle: No property 'title' found for type "
          "'Author' Available properties: id, name.",
        ),
      );
    });
  });
}
