// The HTTP service interfaces of @ImportHttpServices: the class the build
// writes for each (RestClient calls written out, which compile against the
// real starter), its bean on the group's RestClient, the groups' beans, and
// the build errors for what Spring's HttpServiceProxyFactory would refuse.
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

import '../support/introspection_needs.dart';
import '../support/spring_builder.dart';

const _imports = '''
import 'dart:typed_data';
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';
''';

const _book = '''
@Introspected()
class Book {
  Book(this.isbn, this.title);
  final String isbn;
  final String title;
}

enum Shelf { fiction, science }

class Tenant extends HttpRequestAttribute {
  const Tenant(String id) : super('tenant', id);
}
''';

const _services = r'''
@HttpExchange('/books')
@Tenant('neon')
abstract interface class BookService {
  @GetExchange('/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  @GetExchange('?sort=title')
  @Tenant('shop')
  Future<List<Book>> search(
    @RequestParam() String q, {
    @RequestParam() int? year,
    @RequestHeader('X-Tag') List<Shelf> tags = const [],
    @CookieValue() String? session,
  });

  @PostExchange.of(
    headers: ['X-Source=app', r'X-Env=${app.env}'],
    accept: ['application/json'],
  )
  Future<ResponseEntity<Book>> create(
    @RequestBody() Book book,
    @RequestHeader('X-Request-Id') int requestId,
  );

  @PutExchange('/{isbn}')
  Future<ResponseEntity<void>> replace(
    @PathVariable() String isbn,
    @RequestBody() List<Book> books,
  );

  @DeleteExchange('/{isbn}')
  Future<void> remove(@PathVariable('isbn') String id);

  @HttpExchange.of(url: '/{isbn}', method: HttpMethod.head)
  Future<HttpHeaders> head(@PathVariable() String isbn);

  @PostExchange('/{isbn}/cover')
  Future<void> upload(
    @PathVariable() String isbn,
    @RequestPart() MultipartFile cover,
    @RequestPart() Book meta,
    @RequestPart() String? note,
    @RequestPart() Uint8List thumbnail,
    @RequestPart() List<MultipartFile> pages,
    @RequestPart() MultipartFile? back,
  );

  @GetExchange('/events')
  EventStream<Book> events();

  @GetExchange('/{isbn}/pdf')
  Stream<List<int>> pdf(@PathVariable() String isbn);

  @PostExchange.of(
    url: '/login',
    contentType: 'application/x-www-form-urlencoded',
  )
  Future<String> login(@RequestParam() String user, @RequestParam() Shelf? shelf);

  @HttpExchange()
  Future<Map<String, int>> counts(HttpMethod method, Uri url);
}

@Configuration()
@ImportHttpServices(group: 'catalog', types: [BookService])
class Clients {}
''';

// The parameters Spring's HTTP service clients take beyond one value per
// parameter, and API versions.
const _moreServices = '''
@HttpExchange.of(url: '/stock', version: '1.0')
abstract interface class StockService {
  @GetExchange('/{sku}')
  Future<String> level(@PathVariable() String sku);

  @GetExchange.of(url: '/{sku}/history', version: '2.0')
  Future<String> history(@PathVariable() String sku);

  @GetExchange.of(url: '/blank', version: ' ')
  Future<String> blank();

  @GetExchange('/filter')
  Future<List<Book>> filter(
    @RequestParam() Map<String, String> filters, {
    @RequestParam() Map<String, List<Shelf>>? shelves,
    @RequestHeader() Map<String, int> counts = const {},
    @RequestHeader() Map<String, List<String>>? tags,
    @RequestHeader() HttpHeaders? more,
    @CookieValue() Map<String, Shelf> cookies = const {},
    @RequestAttribute('trace.tag') String? tag,
    @RequestAttribute() Map<String, Object?> marks = const {},
  });

  @GetExchange('/{shelf}/{sku}')
  Future<String> at(
    @PathVariable() Map<String, String> location,
    @RequestHeader() HttpHeaders headers,
    @RequestAttribute() int attempt,
  );

  @GetExchange('/{sku}')
  Future<String> fromMirror(
    UriBuilderFactory mirror,
    @PathVariable() String sku,
  );

  @GetExchange('/search')
  Future<String> searchMirror(
    UriBuilderFactory? mirror,
    @RequestParam() String q,
  );

  @PostExchange.of(
    url: '/subscribe',
    contentType: 'application/x-www-form-urlencoded',
  )
  Future<String> subscribe(
    @RequestParam() String user,
    @RequestParam() Map<String, Shelf> topics,
  );

  @PostExchange('/scan')
  Stream<List<int>> scan(@RequestPart() MultipartFile file);
}

@Configuration()
@ImportHttpServices(group: 'stock', types: [StockService])
class StockClients {}
''';

Future<TestBuilderResult> _build(String source) => buildPackage({
  'lib/src/beans.dart': scanRoot,
  'lib/src/service.dart': '$_imports$_book$source',
}, proxyMode: ProxyMode.all);

// The build of [main] as an application's entry point (`bin/main.dart`),
// with [config] as its `application.yml`.
Future<TestBuilderResult> _application(String main, {String? config}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(generations: packageGenerations),
    {
      'pkg|bin/main.dart':
          "$_imports\nimport 'spring_gen/main.spring.dart';\n$_book$main",
      'pkg|lib/resources/application.yml': ?config,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

String _applicationText(TestBuilderResult result) => normalize(
  moduleText(result, AssetId('pkg', 'bin/spring_gen/main.spring.dart')),
);

void main() {
  group('the generated client', () {
    late String module;

    setUpAll(() async {
      final result = await _build(_services);
      expect(result.errors, isEmpty);
      module = normalize(moduleText(result));
    });

    test('compiles against the starter', () async {
      expect(
        await compileErrors({
          'lib/src/service.dart': '$_imports$_book$_services',
        }),
        isEmpty,
      );
    });

    test("a class of its own on the group's RestClient", () {
      expect(
        module,
        hasCode(r'''
class _$BookServiceHttpService implements BookService {
  _$BookServiceHttpService(
    this._rest, {
    required Environment environment,
    required ObjectMapper mapper,
  }) : _mapper = mapper,
       _createXEnvHeader = environment.resolveRequiredPlaceholders(
         r'${app.env}',
       );
  final RestClient _rest;
  final ObjectMapper _mapper;
  final String _createXEnvHeader;
'''),
      );
      expect(
        module,
        hasCode(r'''
create: (r) => _$BookServiceHttpService(
  r.dependency<HttpServiceGroups>().restClient(r'catalog'),
  environment: r.dependency<Environment>(),
  mapper: r.dependency<ObjectMapper>(),
),
'''),
      );
    });

    test("a path variable, the interface's URL and attribute", () {
      expect(
        module,
        hasCode('''
Future<Book> find(String isbn) => _rest
    .get()
    .uri(r'/books/{isbn}', {r'isbn': isbn})
    .attribute(r'tenant', r'neon')
    .retrieve()
    .body<Book>();
'''),
      );
    });

    test('query parameters through the UriBuilder, a null left out', () {
      expect(
        module,
        hasCode('''
final request = _rest
    .get()
    .uri(
      (UriBuilder uri) => uri
          .path(r'/books')
          .queryParam(r'sort', r'title')
          .queryParam(r'q', q)
          .queryParamIfPresent(r'year', year)
          .build(),
    )
    .attribute(r'tenant', r'shop');
for (final value in tags) {
  request.header(r'X-Tag', value.name);
}
if (session != null) {
  request.cookie(r'session', session);
}
return request.retrieve().body<List<Book>>(
  const ListType<Book>(ClassType<Book>()),
);
'''),
      );
    });

    test('headers of the annotation, Accept, a body and an entity', () {
      expect(
        module,
        hasCode('''
Future<ResponseEntity<Book>> create(Book book, int requestId) => _rest
    .post()
    .uri(r'/books')
    .header(r'X-Source', r'app')
    .header(r'X-Env', _createXEnvHeader)
    .accept(r'application/json')
    .attribute(r'tenant', r'neon')
    .body(book)
    .header(r'X-Request-Id', requestId.toString())
    .retrieve()
    .toEntity<Book>();
'''),
      );
      expect(
        module,
        hasCode('''
.body(books, const ListType<Book>(ClassType<Book>()))
.retrieve()
.toBodilessEntity();
'''),
      );
    });

    test('no body: the status, the headers', () {
      expect(
        module,
        hasCode('''
Future<void> remove(String id) => _rest
    .delete()
    .uri(r'/books/{isbn}', {r'isbn': id})
'''),
      );
      expect(
        module,
        hasCode('''
.head()
.uri(r'/books/{isbn}', {r'isbn': isbn})
.attribute(r'tenant', r'neon')
.retrieve()
.toBodilessEntity()
.then((response) => response.headers);
'''),
      );
    });

    test('multipart parts: files streamed, JSON, an optional field, bytes', () {
      expect(
        module,
        hasCode('''
Future<void> upload(
  String isbn,
  MultipartFile cover,
  Book meta,
  String? note,
  Uint8List thumbnail,
  List<MultipartFile> pages,
  MultipartFile? back,
) => _rest
    .post()
    .uri(r'/books/{isbn}/cover', {r'isbn': isbn})
    .attribute(r'tenant', r'neon')
    .body(
      MultipartBody([
        MultipartBodyPart.multipartFile(r'cover', cover),
        MultipartBodyPart.json(r'meta', _mapper.writeValueAsString(meta)),
        if (note != null) MultipartBodyPart.field(r'note', note),
        MultipartBodyPart.file(r'thumbnail', thumbnail),
        for (final file in pages)
          MultipartBodyPart.multipartFile(r'pages', file),
        if (back != null) MultipartBodyPart.multipartFile(r'back', back),
      ]),
    )
    .retrieve()
    .toBodilessEntity();
'''),
      );
    });

    test('streams: server-sent events and bytes', () {
      expect(module, hasCode('.retrieve().eventStream<Book>();'));
      expect(module, hasCode('.retrieve().bodyStream();'));
    });

    test('a form body of the request parameters', () {
      expect(
        module,
        hasCode('''
.contentType(r'application/x-www-form-urlencoded')
.attribute(r'tenant', r'neon')
.body({r'user': user, r'shelf': shelf?.name})
.retrieve()
.body<String>();
'''),
      );
    });

    test('the method and the URL as parameters', () {
      expect(
        module,
        hasCode('''
Future<Map<String, int>> counts(HttpMethod method, Uri url) => _rest
    .method(method)
    .uri(url)
'''),
      );
    });

    test('the bean of the group', () {
      expect(
        module,
        hasCode('''
BeanDefinition<HttpServiceGroup>(
  name: r'httpServiceGroup.catalog#pkgBeans.Clients',
  source: r'package:spring_boot_starter_restclient#HttpServiceGroup.catalog',
  types: const [HttpServiceGroup],
  create: (r) => const HttpServiceGroup(r'catalog', types: [BookService]),
)
'''),
      );
    });
  });

  group('API versions and the parameters of several values', () {
    late String module;

    setUpAll(() async {
      final result = await _build(_moreServices);
      expect(result.errors, isEmpty);
      module = normalize(moduleText(result));
    });

    test('compiles against the starter', () async {
      expect(
        await compileErrors({
          'lib/src/service.dart': '$_imports$_book$_moreServices',
        }),
        isEmpty,
      );
    });

    test("the interface's version, the method's, a blank one", () {
      expect(
        module,
        hasCode('''
Future<String> level(String sku) => _rest
    .get()
    .uri(r'/stock/{sku}', {r'sku': sku})
    .apiVersion(r'1.0')
    .retrieve()
    .body<String>();
'''),
      );
      expect(
        module,
        hasCode('''
.uri(r'/stock/{sku}/history', {r'sku': sku})
.apiVersion(r'2.0')
'''),
      );
      expect(
        module,
        hasCode('''
.uri(r'/stock/blank')
.apiVersion(r'1.0')
'''),
      );
    });

    test('maps of query parameters, headers, cookies; HttpHeaders; '
        'attributes', () {
      expect(
        module,
        hasCode('''
final request = _rest
    .get()
    .uri(
      (UriBuilder uri) => uri
          .path(r'/stock/filter')
          .queryParams(filters)
          .queryParams(shelves ?? const {})
          .build(),
    )
    .apiVersion(r'1.0');
for (final MapEntry(key: name, value: value) in counts.entries) {
  request.header(name, value.toString());
}
if (tags != null) {
  for (final MapEntry(key: name2, value: values) in tags.entries) {
    for (final value2 in values) {
      request.header(name2, value2);
    }
  }
}
if (more != null) {
  request.headers((all) => all.addHeaders(more));
}
for (final MapEntry(key: name3, value: value3) in cookies.entries) {
  request.cookie(name3, value3.name);
}
if (tag != null) {
  request.attribute(r'trace.tag', tag);
}
for (final MapEntry(key: name4, value: value4) in marks.entries) {
  if (value4 != null) {
    request.attribute(name4, value4);
  }
}
return request.retrieve().body<List<Book>>(
  const ListType<Book>(ClassType<Book>()),
);
'''),
      );
    });

    test('a map of path variables, HttpHeaders, an attribute in the chain', () {
      expect(
        module,
        hasCode('''
Future<String> at(
  Map<String, String> location,
  HttpHeaders headers,
  int attempt,
) => _rest
    .get()
    .uri(r'/stock/{shelf}/{sku}', location)
    .apiVersion(r'1.0')
    .headers((all) => all.addHeaders(headers))
    .attribute(r'attempt', attempt)
    .retrieve()
    .body<String>();
'''),
      );
    });

    test('a UriBuilderFactory expands the URL', () {
      expect(
        module,
        hasCode('''
Future<String> fromMirror(UriBuilderFactory mirror, String sku) => _rest
    .get()
    .uri(mirror.expand(r'/stock/{sku}', {r'sku': sku}))
'''),
      );
      expect(
        module,
        hasCode('''
.uri(
  (mirror ?? const UriBuilderFactory())
      .uriString(r'/stock/search')
      .queryParam(r'q', q)
      .build(),
)
'''),
      );
    });

    test('a MultipartFile part in a method returning a stream', () {
      expect(
        module,
        hasCode('''
Stream<List<int>> scan(MultipartFile file) => _rest
    .post()
    .uri(r'/stock/scan')
    .apiVersion(r'1.0')
    .body(MultipartBody([MultipartBodyPart.multipartFile(r'file', file)]))
    .retrieve()
    .bodyStream();
'''),
      );
    });

    test('a map of form fields, enums by name', () {
      expect(
        module,
        hasCode('''
.body({
  r'user': user,
  ...topics.map((name, value) => MapEntry(name, value.name)),
})
'''),
      );
    });
  });

  group('basePackages and basePackageClasses', () {
    const catalog = '''
abstract interface class BookApi {
  @GetExchange('/books')
  Future<String> all();
}

@HttpExchange('/authors')
abstract interface class AuthorApi {
  @GetExchange()
  Future<String> all();
}

class Helper {}
''';
    const deep = '''
abstract interface class ShelfApi {
  @GetExchange('/shelves')
  Future<String> all();
}
''';
    const other = '''
abstract interface class PaymentApi {
  @GetExchange('/payments')
  Future<String> all();
}
''';

    // The build of [importer] (in lib/src/clients.dart) with the libraries
    // of lib/src/catalog/, lib/src/catalog/deep/ and lib/src/other/.
    Future<TestBuilderResult> buildWith(String importer) => buildPackage({
      'lib/src/beans.dart': scanRoot,
      'lib/src/catalog/catalog.dart': '$_imports$catalog',
      'lib/src/catalog/deep/deep.dart': '$_imports$deep',
      'lib/src/other/other.dart': '$_imports$other',
      'lib/src/util/util.dart': 'class Util {}',
      'lib/src/clients.dart':
          "$_imports\nimport 'catalog/catalog.dart';\n"
          "import 'other/other.dart';\nimport 'util/util.dart';\n$importer",
    }, proxyMode: ProxyMode.all);

    String groupOf(String module, String name) {
      final start = module.indexOf(
        normalize("name: r'httpServiceGroup.$name#"),
      );
      expect(start, isNot(-1), reason: name);
      final end = module.indexOf('BeanDefinition', start);
      return module.substring(start, end < 0 ? module.length : end);
    }

    test('a library URI prefix: its interfaces and those below', () async {
      final result = await buildWith('''
@Configuration()
@ImportHttpServices(group: 'catalog', basePackages: ['package:pkg/src/catalog/'])
class Clients {}
''');
      expect(result.errors, isEmpty);
      final module = normalize(moduleText(result));
      expect(
        groupOf(module, 'catalog'),
        contains(normalize('types: [BookApi, AuthorApi, ShelfApi]')),
      );
      expect(module, isNot(contains(r'_$PaymentApiHttpService')));
      expect(module, contains(r'_$ShelfApiHttpService'));
    });

    test('the directory of a type, with types of the same group', () async {
      final result = await buildWith('''
@Configuration()
@ImportHttpServices(
  group: 'shop',
  types: [PaymentApi, BookApi],
  basePackageClasses: [BookApi],
)
class Clients {}
''');
      expect(result.errors, isEmpty);
      expect(
        groupOf(normalize(moduleText(result)), 'shop'),
        contains(
          normalize('types: [PaymentApi, BookApi, AuthorApi, ShelfApi]'),
        ),
      );
    });

    test('a prefix without its last slash is the same directory', () async {
      final result = await buildWith('''
@Configuration()
@ImportHttpServices(basePackages: ['package:pkg/src/other'])
class Clients {}
''');
      expect(result.errors, isEmpty);
      expect(
        groupOf(normalize(moduleText(result)), 'default'),
        contains(normalize('types: [PaymentApi]')),
      );
    });

    test("the found interfaces follow the importer's conditions", () async {
      final result = await buildWith('''
@Profile(['prod'])
@Configuration()
@ImportHttpServices(basePackages: ['package:pkg/src/other/'])
class Clients {}
''');
      expect(result.errors, isEmpty);
      final module = normalize(moduleText(result));
      final start = module.indexOf(normalize('BeanDefinition<PaymentApi>('));
      expect(
        module.substring(start, module.indexOf('BeanDefinition', start + 1)),
        contains(normalize("[const ProfileCondition([r'prod'])]")),
      );
    });

    final errors = <String, (String, List<String>)>{
      'a prefix that finds nothing': (
        "@ImportHttpServices(basePackages: ['package:pkg/src/catalgo/'])",
        [
          "basePackages 'package:pkg/src/catalgo/' finds no interface",
          '(lib/src/catalgo/ holds no Dart library)',
        ],
      ),
      'a directory of libraries without interfaces': (
        '@ImportHttpServices(basePackageClasses: [Util])',
        [
          'basePackageClasses Util finds no interface',
          '(lib/src/util/ holds 1 library, none with @HttpExchange',
        ],
      ),
      'a prefix of another package': (
        "@ImportHttpServices(basePackages: ['package:spring_web_dart/src/'])",
        [
          "basePackages 'package:spring_web_dart/src/' is in the package",
          "lists the libraries of the package it builds only ('pkg')",
          'List the interfaces of',
        ],
      ),
      'a Java package name': (
        "@ImportHttpServices(basePackages: ['com.shop.catalog'])",
        [
          "basePackages 'com.shop.catalog' is no library URI prefix",
          "'package:pkg/src/catalog/'",
        ],
      ),
      'a type of another package': (
        '@ImportHttpServices(basePackageClasses: [RestClient])',
        [
          'basePackageClasses RestClient is declared in the package',
          "'spring_web_dart', and the build lists",
        ],
      ),
      'a type of the SDK': (
        '@ImportHttpServices(basePackageClasses: [String])',
        ['basePackageClasses String is declared in dart:core'],
      ),
      'found in one group, listed in another': (
        "@ImportHttpServices(group: 'a', basePackages: "
            "['package:pkg/src/other/'])\n"
            "@ImportHttpServices(group: 'b', types: [PaymentApi])",
        ['PaymentApi is imported into the groups "a" and "b"'],
      ),
    };
    for (final MapEntry(key: name, value: (annotations, messages))
        in errors.entries) {
      test(name, () async {
        final result = await buildWith('''
@Configuration()
$annotations
class Clients {}
''');
        expect(result.succeeded, isFalse);
        final text = result.errors.join('\n');
        for (final message in messages) {
          expect(text, contains(message));
        }
      });
    }

    test('found by two importers under different conditions', () async {
      final result = await buildWith('''
@Profile(['prod'])
@Configuration()
@ImportHttpServices(basePackages: ['package:pkg/src/other/'])
class Prod {}

@Profile(['dev'])
@Configuration()
@ImportHttpServices(types: [PaymentApi])
class Dev {}
''');
      expect(
        result.errors.join('\n'),
        contains(
          'PaymentApi is imported by Prod and by Dev, which are registered '
          'under different conditions',
        ),
      );
    });

    test('on a class that is no bean', () async {
      final result = await buildWith('''
@ImportHttpServices(basePackages: ['package:pkg/src/other/'])
class NotABean {}
''');
      expect(
        result.errors.join('\n'),
        contains('@ImportHttpServices on NotABean, which is no bean'),
      );
    });

    test('on main, in bin/', () async {
      final result = await _application('''
@HttpExchange('/api')
abstract interface class Api {
  @GetExchange('/ping')
  Future<String> ping();
}

@SpringBootApplication()
@ImportHttpServices(basePackageClasses: [Api])
void main(List<String> args) => runApplication(args);
''');
      expect(result.errors, isEmpty);
      expect(
        _applicationText(result),
        hasCode("const HttpServiceGroup(r'default', types: [Api])"),
      );
    });
  });

  group('on the application', () {
    const api = '''
@HttpExchange('/api')
abstract interface class Api {
  @GetExchange('/ping')
  Future<String> ping();
}
''';

    test('@ImportHttpServices on main: the default group', () async {
      final result = await _application('''
$api
@SpringBootApplication()
@ImportHttpServices(types: [Api])
void main(List<String> args) => runApplication(args);
''');
      expect(result.errors, isEmpty);
      final module = _applicationText(result);
      expect(
        module,
        hasCode(r'''
create: (r) => _$ApiHttpService(
  r.dependency<HttpServiceGroups>().restClient(r'default'),
),
'''),
      );
      expect(
        module,
        hasCode("const HttpServiceGroup(r'default', types: [Api])"),
      );
    });

    test(
      'an interface no @ImportHttpServices imports fails the build',
      () async {
        final result = await _application('''
$api
@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''');
        expect(result.succeeded, isFalse);
        expect(
          result.errors.join('\n'),
          allOf(
            contains(
              'Api declares HTTP calls (exchange annotations), and no '
              '@ImportHttpServices imports it, so it is no bean',
            ),
            contains('@ImportHttpServices(types: [Api])'),
          ),
        );
      },
    );

    test(
      'a library module leaves its interfaces to the applications',
      () async {
        final result = await _build(api);
        expect(result.errors, isEmpty);
      },
    );

    test('a plain body class is written out, a plain answer read in', () async {
      final result = await _build('''
class Order {
  const Order(this.isbn, this.copies);
  final String isbn;
  final int copies;
}

class Receipt {
  const Receipt(this.reference);
  final String reference;
}

@HttpExchange('/orders')
abstract interface class OrderService {
  @PostExchange()
  Future<Receipt> place(@RequestBody() Order order);
}

@Configuration()
@ImportHttpServices(types: [OrderService])
class Clients {}
''');
      expect(result.errors, isEmpty);
      final output = normalize(moduleText(result));
      expect(shapeOf(output, 'Order'), 'get isbn,copies; parts read');
      expect(shapeOf(output, 'Receipt'), 'constructor; parts write');
    });

    test('@Retryable on a method: the proxy retries the call', () async {
      final result = await _application(
        '''
@HttpExchange('/api')
abstract interface class Api {
  @GetExchange('/ping')
  @Retryable(includes: [ResourceAccessException])
  Future<String> ping();
}

@SpringBootApplication()
@ImportHttpServices(types: [Api])
void main(List<String> args) => runApplication(args);
''',
        config: 'spring:\n  resilience:\n    enabled: true\n',
      );
      expect(result.errors, isEmpty);
      final module = _applicationText(result);
      expect(module, contains(normalize(r'class _$ApiProxy')));
      expect(
        module,
        hasCode("annotationTypes: [r'GetExchange', r'Retryable']"),
      );
    });
  });

  group("the importer's conditions", () {
    const api = '''
@HttpExchange('/api')
abstract interface class Api {
  @GetExchange('/ping')
  Future<String> ping();
}
''';
    const prod =
        "ConditionGroup(r'package:pkg/src/service.dart#Prod', "
        "[const ProfileCondition([r'prod'])])";

    // The bean definition of [type] in [module], up to the next one.
    String definitionOf(String module, String type) {
      final start = module.indexOf(normalize('BeanDefinition<$type>('));
      expect(start, isNot(-1), reason: type);
      final end = module.indexOf(normalize('BeanDefinition<'), start + 1);
      return module.substring(start, end == -1 ? module.length : end);
    }

    test(
      'a @Profile configuration: its services and group follow it',
      () async {
        final result = await _build('''
$api
@Profile(['prod'])
@Configuration()
@ImportHttpServices(group: 'api', types: [Api])
class Prod {}

abstract interface class Status {
  @GetExchange('/status')
  Future<String> status();
}

@Configuration()
@ImportHttpServices(group: 'status', types: [Status])
class Open {}
''');
        expect(result.errors, isEmpty);
        final module = normalize(moduleText(result));
        expect(definitionOf(module, 'Api'), contains(normalize(prod)));
        final groups = module
            .split(normalize('BeanDefinition<HttpServiceGroup>('))
            .skip(1);
        expect(
          groups.firstWhere((g) => g.contains('httpServiceGroup.api#')),
          allOf(contains("pkgBeans.Prod'"), contains(normalize(prod))),
        );
        // The unconditional configuration's service and group stay so.
        expect(definitionOf(module, 'Status'), isNot(contains('conditions')));
        expect(
          groups.firstWhere((g) => g.contains('httpServiceGroup.status#')),
          isNot(contains('conditions')),
        );
      },
    );

    test('a class imported by a conditional configuration', () async {
      final result = await _build('''
$api
@ImportHttpServices(group: 'api', types: [Api])
class ApiClients {}

@Profile(['prod'])
@Configuration()
@Import([ApiClients])
class Prod {}
''');
      expect(result.errors, isEmpty);
      final module = normalize(moduleText(result));
      expect(definitionOf(module, 'Api'), contains(normalize(prod)));
    });

    test('@ConditionalOnProperty on the configuration', () async {
      final result = await _build('''
$api
@ConditionalOnProperty('shop.api.enabled', havingValue: 'true')
@Configuration()
@ImportHttpServices(group: 'api', types: [Api])
class Prod {}
''');
      expect(result.errors, isEmpty);
      final module = normalize(moduleText(result));
      expect(
        definitionOf(module, 'Api'),
        allOf(
          contains(
            normalize("ConditionGroup(r'package:pkg/src/service.dart#Prod'"),
          ),
          contains('ConditionalOnProperty'),
        ),
      );
    });

    test('a class that is no bean fails the build', () async {
      final result = await _build('''
$api
@ImportHttpServices(group: 'api', types: [Api])
class NotABean {}
''');
      expect(
        result.errors.join('\n'),
        contains('@ImportHttpServices on NotABean, which is no bean'),
      );
    });

    test('one interface imported under two sets of conditions', () async {
      final result = await _build('''
$api
@Profile(['prod'])
@Configuration()
@ImportHttpServices(group: 'api', types: [Api])
class Prod {}

@Profile(['dev'])
@Configuration()
@ImportHttpServices(group: 'api', types: [Api])
class Dev {}
''');
      expect(
        result.errors.join('\n'),
        contains(
          'Api is imported by Prod and by Dev, which are registered '
          'under different conditions',
        ),
      );
    });

    test('one interface imported twice without conditions', () async {
      final result = await _build('''
$api
@Configuration()
@ImportHttpServices(group: 'api', types: [Api])
class One {}

@Configuration()
@ImportHttpServices(group: 'api', types: [Api])
class Two {}
''');
      expect(result.errors, isEmpty);
    });
  });

  group('build errors', () {
    final cases = <String, (String, List<String>)>{
      'a URL variable no parameter fills': (
        "abstract interface class A { @GetExchange('/books/{isbn}') "
            'Future<Book> find(@PathVariable() String isnb); }',
        [
          '''A.find: the URL "/books/{isbn}" has {isbn}, and no parameter is @PathVariable('isbn')''',
          '(did you mean isnb?)',
          '''A.find: parameter isnb is @PathVariable('isnb'), and the URL "/books/{isbn}" has no {isnb}''',
        ],
      ),
      'a body on a GET': (
        "abstract interface class A { @GetExchange('/books') Future<Book> "
            'find(@RequestBody() Book book); }',
        ['A.find is a GET request and sends @RequestBody book'],
      ),
      'two bodies': (
        "abstract interface class A { @PostExchange('/books') Future<Book> "
            'add(@RequestBody() Book a, @RequestBody() Book b); }',
        ['A.add has 2 @RequestBody parameters (a, b)'],
      ),
      'a part with a body': (
        "abstract interface class A { @PostExchange('/books') Future<void> "
            'add(@RequestBody() Book a, @RequestPart() String b); }',
        ['A.add has @RequestBody a and @RequestPart b'],
      ),
      'a part without multipart': (
        "abstract interface class A { @PostExchange.of(url: '/books', "
            "contentType: 'application/json') Future<void> add( "
            '@RequestPart() String b); }',
        ['A.add has @RequestPart parameters and the content type'],
      ),
      'a parameter without a role': (
        "abstract interface class A { @GetExchange('/books') Future<Book> "
            'find(String isbn); }',
        ['A.find: parameter isbn has no annotation'],
      ),
      'a method without an exchange annotation': (
        'abstract interface class A { Future<Book> find(); }',
        ['A.find has no exchange annotation'],
      ),
      'a return type no call gives': (
        "abstract interface class A { @GetExchange('/books') Book find(); }",
        ['A.find returns Book, which a call cannot give'],
      ),
      'a listed class that is no interface': (
        "class A { @GetExchange('/books') Future<Book> find() async => "
            "Book('', ''); }",
        [
          'lists A, which is no abstract interface class',
          '@GetExchange on A.find: a method with a body is not a call',
        ],
      ),
      'a server mapping': (
        "abstract interface class A { @GetMapping('/books') Future<Book> "
            'find(); }',
        ['@GetMapping on A.find', 'Write @GetExchange instead'],
      ),
      'an API version with a placeholder': (
        "abstract interface class A { @GetExchange.of(url: '/b', version: "
            r"r'${api.version}') Future<Book> find(); }",
        [
          r'A.find asks for the API version "${api.version}", a placeholder',
          'spring.http.serviceclient.default.apiversion.default',
        ],
      ),
      'an API version with a line break': (
        "abstract interface class A { @GetExchange.of(url: '/b', version: "
            r"'1\n2') Future<Book> find(); }",
        ['A.find asks for an API version with a control character'],
      ),
      'a version on a method without an exchange annotation': (
        "@HttpExchange.of(url: '/b', version: '2') abstract interface class "
            'A { Future<Book> find(); }',
        ['A.find has no exchange annotation'],
      ),
      'a nullable path variable': (
        "abstract interface class A { @GetExchange('/b/{id}') Future<Book> "
            'find(@PathVariable() String? id); }',
        ['A.find: parameter id is nullable with @PathVariable'],
      ),
      'a Map of values that are no text': (
        "abstract interface class A { @GetExchange('/b') Future<Book> "
            'find(@RequestParam() Map<String, Book> q); }',
        [
          'A.find: parameter q is a Map<String, Book> with @RequestParam',
          'its values are Book, and a query parameter is text',
        ],
      ),
      'a Map of nullable header values': (
        "abstract interface class A { @GetExchange('/b') Future<Book> "
            'find(@RequestHeader() Map<String, String?> h); }',
        ['its values may be null, and a null has no text to send'],
      ),
      'a Map of dynamic cookie values': (
        "abstract interface class A { @GetExchange('/b') Future<Book> "
            'find(@CookieValue() Map<String, dynamic> c); }',
        ['A.find: parameter c is a Map<String, dynamic> with @CookieValue'],
      ),
      'a Map whose keys are no Strings': (
        "abstract interface class A { @GetExchange('/b') Future<Book> "
            'find(@RequestParam() Map<int, String> q); }',
        ['the keys of the map are the names of the query parameters'],
      ),
      'a Map of lists of path variables': (
        "abstract interface class A { @GetExchange('/b/{id}') Future<Book> "
            'find(@PathVariable() Map<String, List<String>> p); }',
        ['A path variable is one value, so a map of them holds no lists.'],
      ),
      'an HttpHeaders without @RequestHeader': (
        "abstract interface class A { @GetExchange('/b') Future<Book> "
            'find(HttpHeaders headers); }',
        ['A.find: parameter headers is an HttpHeaders without an annotation'],
      ),
      'a wildcard parameter': (
        "abstract interface class A { @GetExchange('/b') Future<Book> "
            'find(@RequestAttribute() String _); }',
        ['A.find: a parameter is the wildcard _'],
      ),
      'a UriBuilderFactory and a whole URL': (
        "abstract interface class A { @GetExchange('https://x.neon.books/b') "
            'Future<Book> find(UriBuilderFactory f); }',
        ['A.find: the URL "https://x.neon.books/b" is whole'],
      ),
      'a UriBuilderFactory and a Uri': (
        "abstract interface class A { @GetExchange('/b') Future<Book> "
            'find(Uri url, UriBuilderFactory f); }',
        ['the Uri parameter url is the whole URL of the call, and f'],
      ),
      'a header that is no text': (
        "abstract interface class A { @GetExchange('/b') Future<Book> "
            "find(@RequestHeader('X-Book') Book book); }",
        ['A.find: parameter book is a Book with @RequestHeader'],
      ),
      'a method with a body': (
        "abstract interface class A { @GetExchange('/b') Future<Book> find() "
            "async => Book('', ''); }",
        ['A.find has a body'],
      ),
      'a getter': (
        'abstract interface class A { String get name; }',
        ['A.name: an HTTP service interface declares methods only'],
      ),
      'a Uri with a path variable': (
        "abstract interface class A { @GetExchange('/b/{id}') Future<Book> "
            'find(Uri url, @PathVariable() String id); }',
        ['A.find: the Uri parameter url is the whole URL of the call'],
      ),
      'a header not written Name=value': (
        "abstract interface class A { @GetExchange.of(url: '/b', headers: "
            "['X-Flag']) Future<Book> find(); }",
        ['A.find: the header "X-Flag" is not written "Name=value"'],
      ),
    };
    for (final MapEntry(key: name, value: (source, messages))
        in cases.entries) {
      test(name, () async {
        final result = await _build('''
$source
@Configuration()
@ImportHttpServices(types: [A])
class Clients {}
''');
        expect(result.succeeded, isFalse, reason: source);
        final errors = result.errors.join('\n');
        for (final message in messages) {
          expect(errors, contains(message));
        }
      });
    }

    test('an interface in two groups', () async {
      final result = await _build('''
abstract interface class A { @GetExchange('/b') Future<Book> find(); }

@Configuration()
@ImportHttpServices(group: 'one', types: [A])
@ImportHttpServices(group: 'two', types: [A])
class Clients {}
''');
      expect(
        result.errors.join('\n'),
        contains('A is imported into the groups "one" and "two"'),
      );
    });

    test('@RequestAttribute on a controller handler', () async {
      final result = await buildPackage({
        'lib/src/beans.dart': scanRoot,
        'lib/src/service.dart':
            '''
$_imports
@RestController()
class Orders {
  @GetMapping('/orders')
  String all(@RequestAttribute('tag') String tag) => tag;
}
''',
      });
      expect(
        result.errors.join('\n'),
        contains(
          '@RequestAttribute on parameter tag of Orders.all: only a method '
          'of an HTTP service interface',
        ),
      );
    });

    test('an interface that another starter implements too', () async {
      final result = await buildPackage({
        'lib/src/beans.dart': scanRoot,
        'lib/src/service.dart':
            '''
$_imports
$_book
@InterfaceProxy()
class Remote {
  const Remote();
}

@Remote()
abstract interface class A { @GetExchange('/b') Future<Book> find(); }

@Configuration()
@ImportHttpServices(types: [A])
class Clients {}
''',
      }, proxyMode: ProxyMode.all);
      expect(
        result.errors.join('\n'),
        contains('A has @Remote and is imported by @ImportHttpServices'),
      );
    });
  });
}
