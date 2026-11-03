// A class is described for what the application does with it, as far as
// the build can see (`IntrospectionNeed`): getters for what is written out,
// constructor and setters for what is read in, methods where an expression
// may call them. A class reached by several routes gets the union.
import 'dart:isolate';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart'
    show mayCallMapper;
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

import 'support/real_sources.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

// The annotations of the starters, as far as the generator looks at them
// (it matches them by URL).
const _fakes = {
  'spring_web_dart|lib/src/annotations.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class Mapping {}

@BeanMethodAnnotation()
class GetMapping implements Mapping {
  const GetMapping(this.path);
  final String path;
}

@BeanMethodAnnotation()
class PostMapping implements Mapping {
  const PostMapping(this.path);
  final String path;
}

class RequestBody {
  const RequestBody();
}

class RequestPart {
  const RequestPart();
}

class PathVariable {
  const PathVariable();
}
''',
  'spring_web_dart|lib/src/controller_annotations.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';

@BeanMethodAnnotation()
class ExceptionHandler {
  const ExceptionHandler([this.types = const []]);
  final List<Type> types;
}
''',
  'spring_boot_starter_websocket|lib/src/web_socket_client.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';

@BeanMethodAnnotation()
class OnMessage {
  const OnMessage();
}
''',
  'spring_boot_starter_websocket|lib/src/server/web_socket_handler.dart': '''
abstract class WebSocketSession {
  void sendJson(Object? value);
}

class WebSocketSessionRegistry {
  void broadcast(String? pattern, Object message) {}
}
''',
  'spring_boot_starter_websocket|lib/src/server/web_socket_endpoint.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';

@BeanMethodAnnotation()
class OnOpen {
  const OnOpen();
}
''',
  'spring_boot_starter_scheduling|lib/src/scheduled.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';

@BeanMethodAnnotation()
class Scheduled {
  const Scheduled({this.fixedRate = 1000});
  final int fixedRate;
}
''',
  'spring_security_core|lib/src/method/annotations.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';

@BeanMethodAnnotation()
class PreAuthorize {
  const PreAuthorize(this.value);
  final String value;
}

@BeanMethodAnnotation()
class PostAuthorize {
  const PostAuthorize(this.value);
  final String value;
}

@BeanMethodAnnotation()
class Secured {
  const Secured(this.value);
  final List<String> value;
}
''',
  'spring_boot_starter_cache|lib/src/annotations.dart': '''
class Cacheable {
  const Cacheable(this.value, {this.key, this.condition, this.unless});
  final String value;
  final String? key;
  final String? condition;
  final String? unless;
}

class CachePut {
  const CachePut(this.value, {this.key, this.condition, this.unless});
  final String value;
  final String? key;
  final String? condition;
  final String? unless;
}

class CacheEvict {
  const CacheEvict(this.value, {this.key, this.condition});
  final String value;
  final String? key;
  final String? condition;
}

class Caching {
  const Caching({
    this.cacheable = const [],
    this.put = const [],
    this.evict = const [],
  });
  final List<Cacheable> cacheable;
  final List<CachePut> put;
  final List<CacheEvict> evict;
}
''',
};

const _imports = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/annotations.dart';
import 'package:spring_boot_starter_scheduling/src/scheduled.dart';
import 'package:spring_boot_starter_websocket/src/server/web_socket_endpoint.dart';
import 'package:spring_boot_starter_websocket/src/server/web_socket_handler.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client.dart';
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_security_core/src/method/annotations.dart';
import 'package:spring_web_dart/src/annotations.dart';
import 'package:spring_web_dart/src/controller_annotations.dart';
''';

const _models = r'''
// --- web ---

class Page<T> {
  Page(this.items, {this.total = 0});
  final List<T> items;
  final int total;
  int size() => items.length;
}

class PageItem {
  PageItem(this.title);
  final String title;
  void touch() {}
}

class Public {}

class BookView {
  BookView();
  @JsonView([Public])
  String title = '';
  Author? author;
  void rename(String to) {}
}

class Author {
  Author();
  String name = '';
}

class NewBook {
  NewBook();
  String title = '';
  Author? author;
  void validate() {}
}

class CheckedBook {
  CheckedBook();
  @NotBlank()
  String title = '';
  String note = '';
}

class Echo {
  Echo();
  String text = '';
  void shout() {}
}

class Problem {
  Problem(this.message);
  final String message;
}

class Tick {
  Tick();
  int count = 0;
}

@JsonInclude(JsonInclusion.nonDefault)
class Counter {
  Counter();
  int count = 0;
}

class Tag {
  Tag(this.label);
  final String label;
  @JsonValue()
  String asText() => 'tag:$label';
  String other() => label;
}

class Bag {
  Bag();
  @JsonAnySetter()
  void put(String key, Object? value) {}
  void other() {}
}

@JsonTypeInfo(property: 'kind')
@JsonSubTypes([JsonSubType(Dog, name: 'dog')])
abstract class Animal {
  Animal(this.name);
  final String name;
}

class Dog extends Animal {
  Dog(super.name);
  void bark() {}
}

@Component()
class BookController {
  @GetMapping('/book')
  Future<BookView> book() async => BookView();

  @GetMapping('/page')
  Page<PageItem> page() => Page([]);

  @PostMapping('/create')
  void create(@RequestBody() NewBook body) {}

  @PostMapping('/check')
  void check(@RequestBody() @Valid() CheckedBook body) {}

  @PostMapping('/echo')
  Echo echo(@RequestBody() Echo body) => body;

  @PostMapping('/order')
  void order(@RequestBody() Order body) {}

  @GetMapping('/counter')
  Counter counter() => Counter();

  @GetMapping('/tag')
  Tag tag() => Tag('a');

  @PostMapping('/bag')
  void bag(@RequestBody() Bag bag) {}

  @GetMapping('/animal')
  Animal animal() => Dog('rex');

  @ExceptionHandler([StateError])
  Problem handle(StateError error) => Problem('x');

  @Scheduled()
  Tick tick() => Tick();
}

// --- messages ---

class ChatMessage {
  ChatMessage();
  String text = '';
}

class ChatReply {
  ChatReply();
  String text = '';
}

@Component()
class ChatEndpoint {
  @OnOpen()
  void open(Untouched untouched) {}

  @OnMessage()
  ChatReply message(ChatMessage message) => ChatReply();
}

class Untouched {
  Untouched();
  String name = '';
}

// --- clients ---

@InterfaceProxy()
class RemoteApi {
  const RemoteApi();
}

class CatalogItem {
  CatalogItem();
  String name = '';
  Author? owner;
}

class CatalogRequest {
  CatalogRequest();
  String filter = '';
}

@RemoteApi()
abstract interface class CatalogClient {
  Future<CatalogItem> find(String id);
  Future<void> submit(CatalogRequest request);
}

// --- expressions ---

class Order {
  Order();
  String owner = '';
  void cancel() {}
}

class Invoice {
  Invoice();
  String owner = '';
}

class SearchQuery {
  SearchQuery();
  String text = '';
}

class Hit {
  Hit();
  String text = '';
}

class Stored {
  Stored();
  int id = 0;
}

@Component()
class Orders {
  @PreAuthorize('#order.owner == principal')
  void cancel(Order order) {}

  @PostAuthorize("returnObject.owner == 'me'")
  Invoice invoice() => Invoice();

  @PreAuthorize("hasRole('ADMIN')")
  void admin(Untouched untouched) {}

  @Secured(['ROLE_X'])
  void secured(Untouched untouched) {}

  @Cacheable('hits', key: '#query.text')
  Future<List<Hit>> search(SearchQuery query) async => [];

  @CachePut('stored', key: '#book.id', unless: '#result == null')
  Stored put(Stored book) => book;

  @Caching(cacheable: [Cacheable('nested', key: '#nested.id')])
  void caching(NestedKey nested) {}

  @CacheEvict('named', key: 'target.prefix')
  void evict(String id) {}

  String prefix = 'p';
}

class NestedKey {
  NestedKey();
  int id = 0;
}

// --- the mapper ---

class Loaded {
  Loaded();
  String x = '';
  void act() {}
}

class Saved {
  Saved();
  String y = '';
}

class Source {
  Source();
  String z = '';
}

class Copy {
  Copy();
  String w = '';
}

class Unseen {
  Unseen();
  String v = '';
}

class Pushed {
  Pushed();
  String p = '';
}

class Broadcast {
  Broadcast();
  String b = '';
}

@Component()
class Library {
  Library(this.mapper);
  final ObjectMapper mapper;

  Loaded load(String json) => mapper.readValue<Loaded>(json);
  String save(Saved saved) => mapper.writeValueAsString(saved);
  Copy copy(Source source) => mapper.convertValue<Copy>(source);
  String anything(Object value) => mapper.writeValueAsString(value);
  void push(WebSocketSession session, Pushed pushed) =>
      session.sendJson(pushed);
  void all(WebSocketSessionRegistry sessions, Broadcast message) =>
      sessions.broadcast('/rooms/{room}', message);
  Unseen? maybe(Map<String, Object?> tree) => null;
}

// --- explicit ---

@Introspected()
class Everything {
  Inner inner = Inner();
  void work() {}
}

class Inner {
  String name = '';
  void touch() {}
}

@Introspected(classes: [Listed])
class Holder {}

class Listed {
  String x = '';
  void act() {}
}

@ConfigurationProperties('app')
class AppProperties {
  String name = '';
  Limits limits = Limits();
  void helper() {}
}

class Limits {
  int max = 1;
  void check() {}
}
''';

Future<(String, List<String>)> _generate(String models) async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  final fakes = {for (final key in _fakes.keys) key.split('|').first};
  final packageConfig = PackageConfig([
    for (final package in isolateConfig.packages)
      if (!fakes.contains(package.name)) package,
    for (final name in fakes)
      Package(
        name,
        Uri.parse('file:///$name/'),
        packageUriRoot: Uri.parse('file:///$name/lib/'),
      ),
  ]);
  final sources = {
    'pkg|lib/src/beans.dart': _scan,
    'pkg|lib/src/models.dart': '$_imports\n$models',
    ..._fakes,
  };
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  final own = await loadRealSources(readerWriter, sources);
  final result = await testBuilder(
    SpringBuilder(),
    own,
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: packageConfig,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final output = result.readerWriter.testing.readString(result.outputs.single);
  final errors = await resolveSources<List<String>>(
    {...sources, 'pkg|lib/spring_gen/src/beans.spring.dart': output},
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
  return (_normalize(output), errors);
}

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

/// The `BeanIntrospection<name>(...)` of the output, `null` without one.
String? _introspection(String output, String name) {
  final start = output.indexOf('BeanIntrospection<$name>(');
  if (start < 0) {
    return null;
  }
  var depth = 0;
  for (var i = output.indexOf('(', start); i < output.length; i++) {
    final char = output[i];
    if (char == '(') {
      depth++;
    } else if (char == ')' && --depth == 0) {
      return output.substring(start, i + 1);
    }
  }
  throw StateError('unbalanced introspection of $name');
}

/// What a description of the class holds, in a few words: its getters,
/// setters, `instantiate`, `constructor`, methods, and `parts`.
String _shape(String output, String name) {
  final block =
      _introspection(output, name) ??
      (throw StateError('$name is not introspected'));
  List<String> names(String pattern) => [
    for (final match in RegExp(pattern).allMatches(block)) match[1]!,
  ];
  final getters = names(r'get:\(bean\)=>bean\.(\w+)');
  final setters = names(r'set:\(bean,value\)=>bean\.(\w+)=');
  final methods = names(r"BeanMethod<[\w<>,.?]+>\(r'(\w+)'");
  final parts = RegExp(r'parts:const\{([^}]*)\}').firstMatch(block)?[1];
  return [
    if (getters.isNotEmpty) 'get ${getters.join(',')}',
    if (setters.isNotEmpty) 'set ${setters.join(',')}',
    if (block.contains('instantiate:')) 'instantiate',
    if (block.contains('constructor:BeanConstructor')) 'constructor',
    if (methods.isNotEmpty) 'methods ${methods.join(',')}',
    if (parts != null)
      'parts ${parts.replaceAll('IntrospectionPart.', '')}'.trim(),
  ].join('; ');
}

void main() {
  late final String output;
  late final List<String> errors;

  setUpAll(() async {
    (output, errors) = await _generate(_models);
  });

  String shape(String name) => _shape(output, name);

  test('the generated code compiles', () {
    expect(errors, isEmpty);
  });

  group('a controller', () {
    test('writes out what it returns, and a test reads it back', () {
      // `mapper.readValue<BookView>(res.body)` in test/, which is not
      // scanned: the getters and the constructor and setters.
      expect(
        shape('BookView'),
        'get title,author; set title,author; instantiate; constructor; '
        'parts read,write',
      );
    });

    test('a class its answer is made of is written out too', () {
      expect(shape('Author'), contains('get name'));
      expect(shape('Page<dynamic>'), contains('get items,total'));
      expect(shape('Page<dynamic>'), isNot(contains('methods')));
      expect(shape('PageItem'), 'get title; constructor; parts read,write');
    });

    test('an exception handler answer is written out and read back', () {
      expect(shape('Problem'), 'get message; constructor; parts read,write');
    });

    test('reads in a body: constructor and setters only', () {
      expect(
        shape('NewBook'),
        'set title,author; instantiate; constructor; parts write',
      );
    });

    test('a validated body also gets the getters of its constraints', () {
      expect(
        shape('CheckedBook'),
        'get title; set title,note; instantiate; constructor; parts write',
      );
    });

    test('a class reached by several routes gets the union', () {
      // Written out (BookView, Page) and read in (NewBook): both.
      expect(
        shape('Author'),
        'get name; set name; instantiate; constructor; parts read,write',
      );
      // An expression's argument that is also a body.
      expect(
        shape('Order'),
        'get owner; set owner; instantiate; constructor; '
        'methods cancel',
      );
    });

    test('a class that is read and written gets both, no methods', () {
      expect(
        shape('Echo'),
        'get text; set text; instantiate; constructor; parts read,write',
      );
    });

    test('a scheduled method describes nothing', () {
      expect(_introspection(output, 'Tick'), isNull);
    });

    test('a class that compares with a new instance also has one', () {
      expect(
        shape('Counter'),
        'get count; set count; instantiate; constructor; parts read,write',
      );
    });

    test('a JSON annotation keeps the method it marks', () {
      expect(
        shape('Tag'),
        'get label; constructor; methods asText; parts read,write',
      );
      expect(shape('Bag'), contains('methods put'));
      expect(shape('Bag'), isNot(contains('other')));
    });

    test('the subtypes of a base take its need, a view class none', () {
      expect(shape('Animal'), contains('parts read,write'));
      expect(shape('Dog'), 'get name; constructor; parts read,write');
      expect(shape('Public'), 'parts');
    });
  });

  group('messages', () {
    test('an endpoint reads in the message and writes out the reply', () {
      expect(
        shape('ChatMessage'),
        'set text; instantiate; constructor; parts write',
      );
      expect(shape('ChatReply'), 'get text; parts read');
    });

    test('the other handlers describe nothing', () {
      expect(_introspection(output, 'Untouched'), isNull);
    });
  });

  group('a client interface', () {
    test('reads in the answer', () {
      expect(
        shape('CatalogItem'),
        'set name,owner; instantiate; constructor; parts write',
      );
    });

    test('writes out the arguments', () {
      expect(shape('CatalogRequest'), 'get filter; parts read');
    });
  });

  group('expressions', () {
    test('the expressions of @Caching are read too', () {
      expect(shape('NestedKey'), contains('methods'));
    });

    test('the bean itself is described when an expression names target', () {
      expect(shape('Orders'), contains('get prefix'));
      expect(shape('Orders'), contains('methods cancel'));
    });

    test('an argument they name is read and its methods called', () {
      expect(shape('Order'), contains('get owner'));
      expect(shape('Order'), contains('methods cancel'));
      expect(shape('SearchQuery'), contains('methods'));
      expect(shape('SearchQuery'), isNot(contains('instantiate')));
      expect(shape('SearchQuery'), isNot(contains('set ')));
    });

    test('so is a result they look at', () {
      expect(shape('Invoice'), contains('methods'));
      expect(shape('Stored'), contains('methods'));
    });

    test('a result no expression looks at is not described', () {
      expect(_introspection(output, 'Hit'), isNull);
    });

    test('an expression that reads no value describes nothing', () {
      // `hasRole('ADMIN')` and `@Secured` name no argument.
      expect(_introspection(output, 'Untouched'), isNull);
    });
  });

  group('direct calls of the ObjectMapper', () {
    test('a type argument is read in, a value written out', () {
      expect(
        shape('Loaded'),
        'set x; instantiate; constructor; parts write',
      );
      expect(shape('Saved'), 'get y; parts read');
    });

    test('convertValue writes out its value and reads in its type', () {
      expect(shape('Source'), 'get z; parts read');
      expect(
        shape('Copy'),
        'set w; instantiate; constructor; parts write',
      );
    });

    test('so do the WebSocket methods that write a value as JSON', () {
      expect(shape('Pushed'), 'get p; parts read');
      expect(shape('Broadcast'), 'get b; parts read');
    });

    test('a value of type Object names no class', () {
      expect(_introspection(output, 'Unseen'), isNull);
    });

    test('broadcast and sendJson count only where the starter is imported', () {
      // `StreamController.broadcast` is everywhere: such a library is not
      // resolved, as one that names no mapper method.
      const source =
          'final stream = controller.stream.asBroadcastStream();\n'
          'final events = StreamController<int>.broadcast();\n'
          'void send(Object o) => session.sendJson(o);';
      expect(mayCallMapper(source, webSocket: false), isFalse);
      expect(mayCallMapper(source, webSocket: true), isTrue);
      expect(
        mayCallMapper('mapper.readValue<Book>(text);', webSocket: false),
        isTrue,
      );
      expect(mayCallMapper('final a = 1;', webSocket: true), isFalse);
    });
  });

  group('explicit', () {
    test('@Introspected describes everything, and so what it is made of', () {
      expect(shape('Everything'), contains('methods work'));
      expect(shape('Everything'), contains('instantiate'));
      expect(shape('Everything'), isNot(contains('parts')));
      expect(shape('Inner'), contains('methods touch'));
      expect(shape('Inner'), isNot(contains('parts')));
    });

    test('a class listed in @Introspected(classes:) is described entirely', () {
      expect(shape('Listed'), contains('methods act'));
      expect(shape('Listed'), isNot(contains('parts')));
    });

    test('@ConfigurationProperties binds: setters and getters, no methods', () {
      expect(
        shape('AppProperties'),
        'get name,limits; set name,limits; instantiate; constructor; '
        'parts read,write',
      );
      expect(
        shape('Limits'),
        'get max; set max; instantiate; constructor; parts read,write',
      );
    });
  });
}
