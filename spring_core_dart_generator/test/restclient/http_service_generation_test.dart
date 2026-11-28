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

    test('multipart parts: a file, JSON, an optional field, bytes', () {
      expect(
        module,
        hasCode('''
Future<void> upload(
  String isbn,
  MultipartFile cover,
  Book meta,
  String? note,
  Uint8List thumbnail,
) async {
  await _rest
      .post()
      .uri(r'/books/{isbn}/cover', {r'isbn': isbn})
      .attribute(r'tenant', r'neon')
      .body(
        MultipartBody([
          MultipartBodyPart.file(
            r'cover',
            await cover.bytes,
            filename: cover.originalFilename,
            contentType: cover.contentType,
          ),
          MultipartBodyPart.json(r'meta', _mapper.writeValueAsString(meta)),
          if (note != null) MultipartBodyPart.field(r'note', note),
          MultipartBodyPart.file(r'thumbnail', thumbnail),
        ]),
      )
      .retrieve()
      .toBodilessEntity();
}
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
      'an API version': (
        "abstract interface class A { @GetExchange.of(url: '/b', version: "
            "'2') Future<Book> find(); }",
        ['A.find asks for the API version "2"'],
      ),
      'a nullable path variable': (
        "abstract interface class A { @GetExchange('/b/{id}') Future<Book> "
            'find(@PathVariable() String? id); }',
        ['A.find: parameter id is nullable with @PathVariable'],
      ),
      'a Map of query parameters': (
        "abstract interface class A { @GetExchange('/b') Future<Book> "
            'find(@RequestParam() Map<String, String> q); }',
        ['A.find: parameter q is a Map with @RequestParam'],
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
      'a multipart file in a stream': (
        "abstract interface class A { @PostExchange('/b') Stream<List<int>> "
            'send(@RequestPart() MultipartFile file); }',
        ['A.send returns a stream and sends a MultipartFile'],
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
