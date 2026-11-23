// The build the introspection-need tests share (test/core/, and the parts
// whose annotations decide a need: test/web/, test/websocket/,
// test/scheduling/, test/security/, test/cache/).
//
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
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

import 'module_files.dart';
import 'real_sources.dart';

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

class RestController extends Controller {
  const RestController();
}

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

class WebSocketEndpoint extends Component {
  const WebSocketEndpoint(this.path);
  final String path;
}

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

/// The application whose classes the tests look at: controllers, WebSocket
/// handlers, a client interface, expressions of the cache and security
/// annotations, direct calls of the `ObjectMapper`, explicit introspection.
const needsModels = r'''
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

@RestController()
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

@WebSocketEndpoint('/chat')
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

/// Builds [models] with the starters' annotations (as far as the generator
/// looks at them); returns the output without whitespace and the analyzer
/// errors of the generated library.
Future<(String, List<String>)> generateNeeds(String models) async {
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
    SpringBuilder(generations: packageGenerations),
    own,
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: packageConfig,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final output = moduleText(result);
  final errors = await resolveSources<List<String>>(
    {
      ...sources,
      ...moduleSources(output),
    },
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('pkg', 'lib/spring_gen/src/beans.spring.dart'),
      );
      final result = await moduleErrors(library);
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
  return (_normalize(moduleText(result)), errors);
}

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

/// The `Introspection<name>(...)` of the output, `null` without one.
String? introspectionOf(String output, String name) {
  final start = output.indexOf('Introspection<$name>(');
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
String shapeOf(String output, String name) {
  final block =
      introspectionOf(output, name) ??
      (throw StateError('$name is not introspected'));
  List<String> names(String pattern) => [
    for (final match in RegExp(pattern).allMatches(block)) match[1]!,
  ];
  // A constant description refers to top-level functions
  // (`get:_$get3`, `Object? _$get3(Book object) => object.title;`) of the
  // generated file it is in (each file of the module numbers its own).
  final file = _fileOf(output, output.indexOf(block));
  final functions = {
    for (final match in RegExp(
      r'_\$((?:get|set)\d+)\([\w<>,.?]+object(?:,Object\?value)?\)=>'
      r'object\.(\w+)',
    ).allMatches(file))
      match[1]!: match[2]!,
  };
  List<String> accessors(String kind, String closure) => [
    for (final match in RegExp(
      '$kind:(?:$closure|_\\\$($kind\\d+))',
    ).allMatches(block))
      match[1] ?? functions[match[2]]!,
  ];
  final getters = accessors('get', r'\(object\)=>object\.(\w+)');
  final setters = accessors('set', r'\(object,value\)=>object\.(\w+)=');
  final methods = names(r"IntrospectedMethod<[\w<>,.?]+>\(r'(\w+)'");
  final parts = RegExp(
    r'parts:(?:const)?\{([^}]*)\}',
  ).firstMatch(block)?[1];
  return [
    if (getters.isNotEmpty) 'get ${getters.join(',')}',
    if (setters.isNotEmpty) 'set ${setters.join(',')}',
    if (block.contains('instantiate:')) 'instantiate',
    if (block.contains('constructor:IntrospectedConstructor')) 'constructor',
    if (methods.isNotEmpty) 'methods ${methods.join(',')}',
    if (parts != null)
      'parts ${parts.replaceAll('IntrospectionPart.', '')}'.trim(),
  ].join('; ');
}

// The generated file of the module's text [output] (its files one after
// the other, each starting with the generated header) that holds [at].
String _fileOf(String output, int at) {
  const header = '//GENERATEDCODE';
  final start = output.lastIndexOf(header, at);
  final end = output.indexOf(header, at);
  return output.substring(
    start < 0 ? 0 : start,
    end < 0 ? output.length : end,
  );
}
