// What the generator writes for the classes of spring_boot_starter_data's
// data layer: an `EntityIntrospection` for each `@Table` class and each
// DTO a `@Query` returns (properties, and the closures that read, create
// and set an instance), registered as one `EntityIntrospections` bean per
// module, and no `BeanIntrospection` unless something else asks for one.
//
// The sources use the real starter, so the generated code is checked
// against the real runtime API.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _header =
    "import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';\n";

Future<TestBuilderResult> _build(Map<String, Object> sources) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(proxyMode: ProxyMode.none),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
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

/// The generated source for [model], a library of the scanned package.
Future<String> _generate(String model) async {
  final result = await _build({
    'lib/src/beans.dart': _scan,
    'lib/src/model.dart': '$_header$model',
  });
  expect(result.errors, isEmpty);
  return result.readerWriter.testing.readString(
    AssetId('pkg', 'lib/spring_gen/src/beans.spring.dart'),
  );
}

/// The compile errors of [generated], the output for [model].
Future<List<String>> _compileErrors(String model, String generated) =>
    resolveSources<List<String>>(
      {
        'pkg|lib/src/beans.dart': _scan,
        'pkg|lib/src/model.dart': '$_header$model',
        'pkg|lib/spring_gen/src/beans.spring.dart': generated,
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

/// The build errors for [model].
Future<String> _errors(String model) async {
  final result = await _build({
    'lib/src/beans.dart': _scan,
    'lib/src/model.dart': '$_header$model',
  });
  return result.errors.join('\n');
}

const _model = '''
enum Status { draft, published }

@Table('authors')
class Author {
  Author({required this.name, this.id, this.isni});

  @Id()
  int? id;

  String name;

  @Unique()
  String? isni;
}

// Immutable: final fields, positional and named parameters, a default.
@Table('accounts')
class Account {
  const Account(this.iban, this.owner, {this.version = 0});

  @Id()
  final String iban;

  final String owner;

  @Version()
  final int version;
}

// No arguments: every property is set after the instance exists, and the
// defaults come from the fields.
@Table('counters')
class Counter {
  String label = 'none';
  int hits = 0;
  List<String> tags = const [];
  DateTime? at;
}

// A default from the constructor, an enum.
@Table('products')
class Product {
  Product({required this.name, this.inStock = true, this.status = Status.draft});

  String name;
  bool inStock;
  Status status;
}

@Table('books')
class Book {
  Book({required this.title, this.author});

  String title;
  AggregateReference<Author, int>? author;
}

@Table('orders')
class PurchaseOrder {
  PurchaseOrder({required this.customer, this.id, this.lines = const []});

  @Id()
  int? id;

  String customer;

  @MappedCollection()
  List<OrderLine> lines;
}

@Table('order_lines')
class OrderLine {
  OrderLine({required this.sku, required this.quantity});

  String sku;
  int quantity;
}

class Audited {
  Audited({this.id});

  @Id()
  int? id;

  DateTime? createdAt;
}

@Table('invoices')
class Invoice extends Audited {
  Invoice({required this.number, super.id});

  String number;
}

class Base<T> {
  T? id;
}

@Table('tags')
class Tag extends Base<int> {
  Tag({required this.label});

  String label;
}

@Table('sessions')
class Session {
  Session({this.user});

  String? user;

  @Transient()
  String cache = '';
}

// A DTO.
class BookCard {
  const BookCard({required this.title, required this.year});

  final String title;
  final int year;
}

class AuthorStats {
  AuthorStats({required this.name});

  final String name;
}

class Raw {
  static Raw fromRow(Object row) => Raw();
}

abstract interface class BookReportRepository
    implements DataRepository<Book, int> {
  @Query('select title, year from books')
  Future<List<BookCard>> cards();

  @Query('select title, year from books where year = :year')
  Future<BookCard?> one(int year);

  @Query('select title, year from books', countQuery: 'select count(*) from books')
  Future<Page<BookCard>> page(Pageable pageable);

  @Query('select title, year from books')
  Stream<BookCard> stream();

  @Query('select name from authors')
  Future<Set<AuthorStats>> stats();

  @Query('select count(*) from books')
  Future<int> count();

  @Query('select title from books')
  Future<List<String>> titles();

  @Query('select * from books')
  Future<List<Book>> all();

  @Query('select * from books', rowMapper: Raw.fromRow)
  Future<List<Raw>> raw();
}

// The DTO of another repository, once.
abstract interface class OtherRepository
    implements DataRepository<Author, int> {
  @Query('select title, year from books')
  Future<List<BookCard>> cards();
}
''';

void main() {
  late String raw;
  late String output;

  setUpAll(() async {
    raw = await _generate(_model);
    output = _normalize(raw);
  });

  test('a mutable entity: properties, get, create, write', () {
    expect(
      output,
      _has('''
EntityIntrospection<Author>(
  r'Author',
  const [
    EntityProperty(r'id', ClassType<int>(nullable: true),
        annotations: [Id()], parameter: true, writable: true),
    EntityProperty(r'name', ClassType<String>(),
        parameter: true, writable: true),
    EntityProperty(r'isni', ClassType<String>(nullable: true),
        annotations: [Unique()], parameter: true, writable: true),
  ],
  annotations: const [Table(r'authors')],
  get: (e, i) => switch (i) {
    0 => e.id,
    1 => e.name,
    _ => e.isni,
  },
  create: (v) => Author(
      name: v[1] as String, id: v[0] as int?, isni: v[2] as String?),
  write: (e, i, v) => switch (i) {
    0 => e.id = v as int?,
    1 => e.name = v as String,
    2 => e.isni = v as String?,
    _ => null,
  },
)'''),
    );
  });

  test('an immutable entity: no write; positional and named parameters', () {
    expect(
      output,
      _has('''
EntityIntrospection<Account>(
  r'Account',
  const [
    EntityProperty(r'iban', ClassType<String>(),
        annotations: [Id()], parameter: true),
    EntityProperty(r'owner', ClassType<String>(), parameter: true),
    EntityProperty(r'version', ClassType<int>(),
        annotations: [Version()], parameter: true,
        hasDefaultValue: true, defaultValue: 0),
  ],
  annotations: const [Table(r'accounts')],
  get: (e, i) => switch (i) {
    0 => e.iban,
    1 => e.owner,
    _ => e.version,
  },
  create: (v) => Account(v[0] as String, v[1] as String, version: v[2] as int),
)'''),
    );
  });

  test('no arguments: nothing is a parameter, all are written', () {
    expect(
      output,
      _has('''
EntityIntrospection<Counter>(
  r'Counter',
  const [
    EntityProperty(r'label', ClassType<String>(),
        writable: true, hasDefaultValue: true, defaultValue: r'none'),
    EntityProperty(r'hits', ClassType<int>(),
        writable: true, hasDefaultValue: true, defaultValue: 0),
    EntityProperty(r'tags', ListType<String>(ClassType<String>()),
        writable: true, hasDefaultValue: true, defaultValue: <String>[]),
    EntityProperty(r'at', ClassType<DateTime>(nullable: true), writable: true),
  ],
  annotations: const [Table(r'counters')],
  get: (e, i) => switch (i) {
    0 => e.label,
    1 => e.hits,
    2 => e.tags,
    _ => e.at,
  },
  create: (v) => Counter(),
  write: (e, i, v) => switch (i) {
    0 => e.label = v as String,
    1 => e.hits = v as int,
    2 => e.tags = v as List<String>,
    3 => e.at = v as DateTime?,
    _ => null,
  },
)'''),
    );
  });

  test('a default of the constructor, an enum property', () {
    expect(
      output,
      _has('''
    EntityProperty(r'name', ClassType<String>(), parameter: true, writable: true),
    EntityProperty(r'inStock', ClassType<bool>(),
        parameter: true, writable: true,
        hasDefaultValue: true, defaultValue: true),
    EntityProperty(r'status', EnumType<Status>(Status.values),
        parameter: true, writable: true,
        hasDefaultValue: true, defaultValue: Status.draft),
  ],
  annotations: const [Table(r'products')],
  get: (e, i) => switch (i) {
    0 => e.name,
    1 => e.inStock,
    _ => e.status,
  },
  create: (v) => Product(
      name: v[0] as String,
      inStock: v[1] as bool,
      status: v[2] as Status),'''),
    );
  });

  test('an AggregateReference property keeps its type arguments', () {
    expect(
      output,
      _has('''
    EntityProperty(r'author',
        GenericType<AggregateReference<Author, int>>(
            [ClassType<Author>(), ClassType<int>()], nullable: true),
        parameter: true, writable: true)'''),
    );
    expect(
      output,
      _has(
        'author: v[1] as AggregateReference<Author, int>?',
      ),
    );
    expect(
      output,
      _has('1 => e.author = v as AggregateReference<Author, int>?'),
    );
  });

  test('a @MappedCollection and its children are both described', () {
    expect(
      output,
      _has(
        '''
    EntityProperty(r'lines', ListType<OrderLine>(ClassType<OrderLine>()),
        annotations: [MappedCollection()], parameter: true, writable: true,
        hasDefaultValue: true, defaultValue: <OrderLine>[]),
  ],
  annotations: const [Table(r'orders')],
  get: (e, i) => switch (i) {
    0 => e.id,
    1 => e.customer,
    _ => e.lines,
  },
  create: (v) => PurchaseOrder(
      customer: v[1] as String, id: v[0] as int?, lines: v[2] as List<OrderLine>),''',
      ),
    );
    expect(output, _has('EntityIntrospection<OrderLine>(r'));
    expect(
      output,
      _has(
        'create: (v) => OrderLine(sku: v[0] as String, quantity: v[1] as int)',
      ),
    );
  });

  test('a superclass field comes after the class own fields', () {
    expect(
      output,
      _has('''
EntityIntrospection<Invoice>(
  r'Invoice',
  const [
    EntityProperty(r'number', ClassType<String>(), parameter: true, writable: true),
    EntityProperty(r'id', ClassType<int>(nullable: true),
        annotations: [Id()], parameter: true, writable: true),
    EntityProperty(r'createdAt', ClassType<DateTime>(nullable: true), writable: true),
  ],
  annotations: const [Table(r'invoices')],
  get: (e, i) => switch (i) {
    0 => e.number,
    1 => e.id,
    _ => e.createdAt,
  },
  create: (v) => Invoice(number: v[0] as String, id: v[1] as int?),'''),
    );
  });

  test('a field of a generic superclass has the type argument', () {
    expect(
      output,
      _has('''
EntityIntrospection<Tag>(
  r'Tag',
  const [
    EntityProperty(r'label', ClassType<String>(), parameter: true, writable: true),
    EntityProperty(r'id', ClassType<int>(nullable: true), writable: true),
  ],'''),
    );
    expect(output, _has('1 => e.id = v as int?'));
  });

  test('a @Transient field is described, for the data layer to skip', () {
    expect(
      output,
      _has('''
EntityIntrospection<Session>(
  r'Session',
  const [
    EntityProperty(r'user', ClassType<String>(nullable: true),
        parameter: true, writable: true),
    EntityProperty(r'cache', ClassType<String>(),
        annotations: [Transient()], writable: true,
        hasDefaultValue: true, defaultValue: r''),
  ],'''),
    );
  });

  test('properties are read one at a time, by index', () {
    // The data layer asks only for the stored ones: a @Transient `late`
    // field that was never set is not touched by a save.
    expect(
      output,
      _has('get: (e, i) => switch (i) { 0 => e.user, _ => e.cache }'),
    );
    // A class of one property reads it without a switch.
    expect(
      output,
      _has('''
    EntityProperty(r'name', ClassType<String>(), parameter: true),
  ],
  get: (e, i) => e.name,'''),
    );
    expect(output, isNot(_has('read: (e)')));
  });

  test('a @Query DTO is described like an entity, without annotations', () {
    expect(
      output,
      _has('''
EntityIntrospection<BookCard>(
  r'BookCard',
  const [
    EntityProperty(r'title', ClassType<String>(), parameter: true),
    EntityProperty(r'year', ClassType<int>(), parameter: true),
  ],
  get: (e, i) => switch (i) {
    0 => e.title,
    _ => e.year,
  },
  create: (v) => BookCard(title: v[0] as String, year: v[1] as int),
)'''),
    );
  });

  test('a DTO is found under Future, Stream, Set, Page and nullable', () {
    // `cards`, `one`, `page` and `stream` return BookCard; `stats` an
    // AuthorStats in a Set.
    expect(output, _has('EntityIntrospection<AuthorStats>(r'));
    expect('EntityIntrospection<BookCard>('.allMatches(output), hasLength(1));
  });

  test('not described: columns, entities, and rows a mapper builds', () {
    expect(output, isNot(_has('EntityIntrospection<Raw>')));
    expect(output, isNot(_has('EntityIntrospection<int>')));
    expect(output, isNot(_has('EntityIntrospection<String>')));
    expect(output, isNot(_has('EntityIntrospection<List')));
    expect(output, isNot(_has('EntityIntrospection<Page')));
    // Book is described once, as the @Table class it is.
    expect('EntityIntrospection<Book>('.allMatches(output), hasLength(1));
  });

  test('one EntityIntrospections bean holds them all', () {
    expect(output, _has("name: r'entityIntrospections#pkgBeans'"));
    expect(output, _has('types: const [EntityIntrospections]'));
    expect(
      'EntityIntrospections('.allMatches(raw.replaceAll(RegExp(r'\s'), '')),
      hasLength(1),
    );
    expect(output, _has('create: (r) => EntityIntrospections(['));
    for (final name in [
      'Author',
      'Account',
      'Counter',
      'Product',
      'Book',
      'PurchaseOrder',
      'OrderLine',
      'Invoice',
      'Tag',
      'Session',
      'BookCard',
      'AuthorStats',
    ]) {
      expect(output, _has('EntityIntrospection<$name>(r'), reason: name);
    }
  });

  test('a @Table class gets no BeanIntrospection', () {
    expect(output, isNot(contains('BeanIntrospection')));
    expect(output, isNot(contains('introspections:')));
    // Not the generic one of AggregateReference either.
    expect(output, isNot(contains('AggregateReference<dynamic')));
  });

  test('the generated code compiles against the starter', () async {
    expect(await _compileErrors(_model, raw), isEmpty);
  });

  group('beside other introspection', () {
    test(
      'an explicit @Introspected still gets its BeanIntrospection',
      () async {
        final output = _normalize(
          await _generate('''
@Introspected()
@Table('books')
class Book {
  Book({required this.title});
  String title;
}
'''),
        );
        expect(output, _has('BeanIntrospection<Book>('));
        expect(output, _has('EntityIntrospection<Book>('));
      },
    );

    test('a module without entities has no EntityIntrospections', () async {
      final output = _normalize(
        await _generate('''
@Introspected()
class Plain {
  String name = '';
}
'''),
      );
      expect(output, _has('BeanIntrospection<Plain>('));
      expect(output, isNot(contains('Entity')));
    });
  });

  group('@Json properties', () {
    const model = '''
class Settings {
  Settings({required this.theme, this.layout});
  String theme;
  Layout? layout;
}

class Layout {
  int columns = 1;
}

class Address {
  Address(this.street);
  String street;
}

class Plain {
  String note = '';
}

@Table('profiles')
class Account {
  Account({required this.settings, this.raw = const {}, this.addresses,
      this.id});
  @Id()
  int? id;
  @Json()
  Settings settings;
  @Json(binary: false)
  Map<String, Object?> raw;
  @Json()
  List<Address>? addresses;
  @Transient()
  Plain? plain;
}
''';

    test('the classes of the type are described for the ObjectMapper, '
        'nested ones too, with no @Introspected', () async {
      final raw = await _generate(model);
      final output = _normalize(raw);
      expect(output, _has('BeanIntrospection<Settings>('));
      expect(output, _has('BeanIntrospection<Layout>('));
      expect(output, _has('BeanIntrospection<Address>('));
      // What no @Json property holds is not, and neither is the entity.
      expect(output, isNot(_has('BeanIntrospection<Plain>')));
      expect(output, isNot(_has('BeanIntrospection<Account>')));
      expect(
        output,
        _has('''
    EntityProperty(r'settings', ClassType<Settings>(),
        annotations: [Json()], parameter: true, writable: true),'''),
      );
      expect(output, _has('annotations: [Json(binary: false)]'));
      expect(await _compileErrors(model, raw), isEmpty);
    });

    test('without @Json nothing is described for the ObjectMapper', () async {
      final output = _normalize(
        await _generate(model.replaceAll(RegExp(r'@Json\([^)]*\)'), '')),
      );
      expect(output, isNot(contains('BeanIntrospection')));
    });
  });

  group('SpEL in @Query', () {
    const repository = '''
class Filter {
  String name = '';
}

class Picked {
  String name = '';
}

class Other {
  String name = '';
}

abstract interface class FilterRepository
    implements DataRepository<Filter, int> {
  @Query('select * from filters where name = :#{#filter.name}')
  Future<int> byFilter(Filter filter);

  @Query(
    'select * from filters where name = :#{T(String).valueOf(#picked.name)}',
  )
  Future<int> byPicked(Picked picked);

  @Query('select * from #{#entityName} where name = :other')
  Future<int> byName(Other other);
}
''';

    test(
      'a compiled expression needs no description of its arguments',
      () async {
        final output = _normalize(await _generate(repository));
        expect(output, isNot(_has('BeanIntrospection<Filter>')));
        expect(
          output,
          _has(
            'expressions: [(arguments, context) => '
            '(arguments[0] as Filter).name]',
          ),
        );
      },
    );

    test('an interpreted one describes the types of the arguments', () async {
      final output = _normalize(await _generate(repository));
      expect(output, _has('BeanIntrospection<Picked>('));
      // `#{#entityName}` reads no argument.
      expect(output, isNot(_has('BeanIntrospection<Other>')));
    });

    test('without an expression nothing is introspected', () async {
      final output = _normalize(
        await _generate(
          repository
              .replaceAll(':#{#filter.name}', ':filter')
              .replaceAll(':#{T(String).valueOf(#picked.name)}', ':picked'),
        ),
      );
      expect(output, isNot(contains('BeanIntrospection')));
    });
  });

  group('modules', () {
    test('of one application each register their own bean', () async {
      final result = await _build({
        'lib/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''',
        'lib/model.dart':
            '$_header\n'
            "@Table('books')\n"
            'class Book { Book({required this.title}); String title; }\n',
        'lib/library/scan.dart': _scan
            .replaceAll('src/beans.spring', 'library/scan.spring')
            .replaceAll('pkgBeans', 'libraryBeans'),
        'lib/library/author.dart':
            '$_header\n'
            "@Table('authors')\n"
            'class Author { Author({required this.name}); String name; }\n',
      });
      expect(result.errors, isEmpty);
      final application = result.readerWriter.testing.readString(
        AssetId('pkg', 'lib/spring_gen/main.spring.dart'),
      );
      final library = result.readerWriter.testing.readString(
        AssetId('pkg', 'lib/spring_gen/library/scan.spring.dart'),
      );
      expect(application, contains("r'entityIntrospections#application'"));
      expect(application, contains('EntityIntrospection<_i'));
      expect(application, isNot(contains('Author')));
      expect(library, contains("r'entityIntrospections#libraryBeans'"));
      expect(library, isNot(contains('Book')));
    });
  });

  group('shapes of a class', () {
    test('a computed getter is no property', () async {
      const model = '''
@Table('books')
class Book {
  Book({required this.title, this.id});

  @Id()
  int? id;
  String title;

  bool get isNew => id == null;

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(Object other) => other is Book && other.id == id;
}

abstract interface class BookRepository
    implements DataRepository<Book, int> {
  Future<List<Book>> findByTitle(String title);
}
''';
      final generated = await _generate(model);
      final output = _normalize(generated);
      expect(output, _has("EntityProperty(r'id'"));
      expect(output, _has("EntityProperty(r'title'"));
      expect(output, isNot(_has("EntityProperty(r'isNew'")));
      expect(output, isNot(_has("EntityProperty(r'hashCode'")));
      expect(output, isNot(_has('e.hashCode')));
      expect(await _compileErrors(model, generated), isEmpty);
    });

    test('a getter a constructor parameter takes is a property', () async {
      const model = '''
@Table('prices')
class Price {
  Price({required int cents}) : _cents = cents;

  final int _cents;

  int get cents => _cents;
}
''';
      final generated = await _generate(model);
      final output = _normalize(generated);
      expect(
        output,
        _has("EntityProperty(r'cents', ClassType<int>(), parameter: true)"),
      );
      expect(output, _has('create: (v) => Price(cents: v[0] as int)'));
      expect(await _compileErrors(model, generated), isEmpty);
    });

    test('a parameter of a wider type than its field gets the value', () async {
      const model = '''
@Table('amounts')
class Amount {
  Amount({required num value}) : value = value.toInt();

  int value;
}
''';
      final generated = await _generate(model);
      expect(
        _normalize(generated),
        _has('create: (v) => Amount(value: v[0] as num)'),
      );
      expect(await _compileErrors(model, generated), isEmpty);
    });

    test(
      'the fields of a generic superclass have the type arguments',
      () async {
        const model = '''
class Base<T> {
  T? id;
  List<T> tags = [];
  Map<String, T>? lookup;
}

@Table('tagged')
class Tagged extends Base<String> {
  Tagged({this.title = ''});

  String title;
}
''';
        final generated = await _generate(model);
        final output = _normalize(generated);
        expect(
          output,
          _has("EntityProperty(r'tags', ListType<String>(ClassType<String>())"),
        );
        expect(output, _has('2 => e.tags = v as List<String>'));
        expect(output, _has('3 => e.lookup = v as Map<String, String>?'));
        expect(await _compileErrors(model, generated), isEmpty);
      },
    );

    test(
      'a default of the field wins over one the build cannot write',
      () async {
        const model = '''
class _Secret {
  const _Secret();
}

@Table('holders')
class Holder {
  Holder({this.secret = const _Secret()});

  Object secret = 'public';
}
''';
        final output = _normalize(await _generate(model));
        expect(output, _has("hasDefaultValue: true, defaultValue: r'public'"));
      },
    );
  });

  group('build errors', () {
    test('a required constructor parameter that names no field', () async {
      final message = await _errors('''
@Table('books')
class Book {
  Book(String isbn);
  String title = '';
}
''');
      expect(message, contains('Book(isbn)'));
      expect(message, contains('names no field'));
      expect(message, contains('this.isbn'));
    });

    test('an optional parameter that names no field is left out', () async {
      final output = _normalize(
        await _generate('''
@Table('books')
class Book {
  Book({this.title = '', int? unused});
  String title;
}
'''),
      );
      expect(output, _has('create: (v) => Book(title: v[0] as String)'));
    });

    test('no public unnamed constructor', () async {
      final message = await _errors('''
@Table('books')
class Book {
  Book._();
  String title = '';
}
''');
      expect(message, contains('@Table class Book has no public unnamed'));
      expect(message, contains('Add one'));
    });

    test('a private class', () async {
      final message = await _errors('''
@Table('books')
class _Book {
  String title = '';
}
''');
      expect(message, contains('@Table class _Book must be public'));
    });

    test('an abstract class', () async {
      final message = await _errors('''
@Table('books')
abstract class Book {
  String title = '';
}
''');
      expect(message, contains('@Table class Book is abstract'));
      expect(message, contains('concrete'));
    });

    test('a generic class', () async {
      final message = await _errors('''
@Table('boxes')
class Box<T> {
  Box(this.content);
  T content;
}
''');
      expect(message, contains('@Table class Box is generic'));
    });

    test('a final field no parameter takes', () async {
      final message = await _errors('''
@Table('books')
class Book {
  Book({this.title = ''});
  String title;
  final String slug = 'x';
}
''');
      expect(message, contains('Book.slug is final'));
      expect(message, contains('nothing could set it'));
      expect(message, contains('constructor parameter'));
      expect(message, contains('setter'));
      expect(message, contains('@Transient'));
    });

    test('a final @Transient field is fine', () async {
      final output = _normalize(
        await _generate('''
@Table('books')
class Book {
  Book({this.title = ''});
  String title;
  @Transient()
  final String slug = 'x';
}
'''),
      );
      expect(output, _has("EntityProperty(r'slug', ClassType<String>(),"));
      expect(output, isNot(_has('e.slug =')));
    });

    test(
      'an optional positional parameter skipped before a used one',
      () async {
        final message = await _errors('''
@Table('books')
class Book {
  Book([int? unused, this.title = '']);
  String title;
}
''');
        expect(message, contains('Book(title)'));
        expect(message, contains('unused'));
      },
    );

    test('a DTO follows the same rules, and names the query', () async {
      final message = await _errors('''
class Card {
  Card({required this.title});
  final String title;
  final int year = 0;
}

abstract interface class CardRepository
    implements DataRepository<Card, int> {
  @Query('select title from cards')
  Future<List<Card>> cards();
}
''');
      expect(
        message,
        contains(
          'Class Card (read by the @Query method CardRepository.cards): '
          'Card.year is final',
        ),
      );
    });

    test('a parameter of a type the field does not fit', () async {
      final message = await _errors('''
@Table('links')
class Link {
  Link({required String url}) : url = Uri.parse(url);

  Uri url;
}
''');
      expect(message, contains('Link(url)'));
      expect(message, contains('the type String'));
      expect(message, contains('the type Uri'));
      expect(message, contains('this.url'));
    });

    test('a default of a parameter the build cannot write', () async {
      final message = await _errors('''
class _Secret {
  const _Secret();
}

@Table('holders')
class Holder {
  Holder({this.secret = const _Secret()});

  final Object secret;
}
''');
      expect(message, contains('Holder.secret'));
      expect(message, contains('cannot be written by the build'));
      expect(message, contains('Make the constant public'));
      expect(message, contains('give the field an initializer'));
    });
  });
}
