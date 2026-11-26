// The main builder's module: beans, injection points, conditions, the
// container's metadata, inherited members, registrars and listeners.
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/builder.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/spring_builder.dart';

void main() {
  test('builder factory', () {
    expect(springCoreDartBuilder(BuilderOptions.empty), isA<SpringBuilder>());
    // A module's library, and beside it its descriptions, the binding of
    // its @ConfigurationProperties classes, its proxies, an application's
    // debug part and the part of its --dart-define values.
    List<String> module(String root) => [
      '$root/spring_gen/{{}}.spring.dart',
      '$root/spring_gen/{{}}.spring.introspection.dart',
      '$root/spring_gen/{{}}.spring.properties.dart',
      '$root/spring_gen/{{}}.spring.proxies.dart',
      '$root/spring_gen/{{}}.spring.signals.dart',
      '$root/spring_gen/{{}}.spring.debug.dart',
      '$root/spring_gen/{{}}.spring.env.dart',
    ];
    expect(SpringBuilder().buildExtensions, {
      '^lib/{{}}.dart': module('lib'),
      '^bin/{{}}.dart': module('bin'),
      '^test/{{}}.dart': module('test'),
      '^example/{{}}.dart': module('example'),
    });
    expect(SpringPropertiesBuilder().buildExtensions, {
      '^lib/{{}}.dart': module('lib'),
    });
  });

  test('build.yaml declares the outputs the builders write', () {
    final builders =
        (loadYaml(
              File.fromUri(
                Isolate.resolvePackageUriSync(
                  Uri.parse('package:spring_core_dart_generator/'),
                )!.resolve('../build.yaml'),
              ).readAsStringSync(),
            ) as YamlMap)['builders']
            as YamlMap;
    Map<String, List<String>> declared(String builder) => {
      for (final MapEntry(:key, :value)
          in ((builders[builder] as YamlMap)['build_extensions'] as YamlMap)
              .entries)
        key as String: (value as YamlList).cast<String>(),
    };
    expect(declared('spring_core_dart'), SpringBuilder().buildExtensions);
    expect(
      declared('spring_properties'),
      SpringPropertiesBuilder().buildExtensions,
    );
  });

  test('primary constructors: the dependencies and a const bean', () async {
    final code = await generateModule(r'''
@Component()
class const Clock();

@Service()
class Greeter(this.clock, {@Value(r'${greeting:Hi}') this.greeting = 'Hi'}) {
  final Clock clock;
  final String greeting;
}
''');
    expect(code, hasCode('Clock()'));
    expect(code, hasCode("Dependency(Clock, name: r'clock')"));
    expect(code, hasCode('Greeter(r.dependency<Clock>('));
    expect(code, contains('greeting:'));
  });

  group('generated code compiles', () {
    test('SDK types as beans (internal dart:_http, dart:_internal)', () async {
      expect(
        await compileErrors({
          'lib/src/s.dart': '''
import 'dart:io';
import 'dart:typed_data';
@Configuration()
class C {
  @Bean() HttpClient client() => HttpClient();
  @Bean() Uint8List bytes() => Uint8List(4);
  @Bean() List<String> names() => ['a'];
}
''',
        }),
        isEmpty,
      );
    });

    // A supertype declared in dart:_http, which dart:io exports, used to
    // be left out: `ServerUser(HttpServer)` failed at start. It is written
    // through dart:io, also from a library that does not import dart:io
    // (found through the import of dart:_http itself).
    test('supertypes from dart:_http, written through dart:io', () async {
      final files = {
        'lib/src/base.dart': """
import 'dart:io';
abstract class BaseServer implements HttpServer {}
""",
        'lib/src/s.dart': """
import 'base.dart';
@Component()
class LoggingServer extends BaseServer {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
@Component()
class ServerUser {
  ServerUser(this.server);
  final BaseServer server;
}
abstract interface class Repo<T> {}
class _Draft {}
@Component()
class DraftRepo implements Repo<_Draft> {}
""",
      };
      expect(
        await compileErrors(files, proxyMode: ProxyMode.none),
        isEmpty,
      );
      final result = await buildPackage({
        'lib/src/beans.dart': scanRoot,
        for (final MapEntry(:key, :value) in files.entries)
          key: '$coreImport$value',
      });
      expect(result.errors, isEmpty);
      final source = moduleText(result);
      expect(source, contains("import 'dart:io' as"));
      expect(source, isNot(contains('dart:_')));
      final output = normalize(source);
      expect(output, contains('HttpServer,Stream<HttpRequest>'));
      expect(
        output,
        hasCode('types: const [LoggingServer, BaseServer, HttpServer,'),
      );
      // A supertype with a private type argument: its raw form only.
      expect(output, hasCode('types: const [DraftRepo, Repo<dynamic>]'));
    });

    test('Future<T>? members of proxied beans', () async {
      expect(
        await compileErrors({
          'lib/src/s.dart': '''
@Component()
class S {
  Future<int>? maybe() => null;
  Future<int> sure() async => 1;
}
''',
        }),
        isEmpty,
      );
    });

    test(
      'members named like Spring Advised (advisors, targetObject)',
      () async {
        expect(
          await compileErrors({
            'lib/src/s.dart': '''
@Component()
class Advisory {
  List<String> advisors() => ['ada'];
  Object get targetObject => 2;
}
''',
          }),
          isEmpty,
        );
      },
    );

    test('toString with parameters', () async {
      expect(
        await compileErrors({
          'lib/src/s.dart': r'''
@Component()
class S {
  @override
  String toString({bool full = false}) => full ? 'S(full)' : 'S';
}
abstract interface class Named { String name(); }
@Component()
class N implements Named {
  N(@Lazy() this.self);
  final Named self;
  @override
  String name() => 'n';
  @override
  String toString([String prefix = '']) => '${prefix}N';
}
''',
        }),
        isEmpty,
      );
    });

    test('classes with the same name in two directories', () async {
      expect(
        await compileErrors({
          'lib/src/a/service.dart':
              "@Component('a') class Service { int x() => 1; }",
          'lib/src/b/service.dart':
              "@Component('b') class Service { int y() => 2; }",
        }),
        isEmpty,
      );
    });

    test('covariant parameters', () async {
      expect(
        await compileErrors({
          'lib/src/s.dart': '''
class Animal {}
class Dog extends Animal {}
class Base { void feed(Animal a) {} }
@Component()
class Kennel extends Base {
  @override
  void feed(covariant Dog a) {}
}
''',
        }),
        isEmpty,
      );
    });
  });

  test(
    'optional fields and setters keep their value when nothing is found',
    () async {
      final output = await generateModule(r'''
abstract interface class Clock {}

class SystemClock implements Clock {
  const SystemClock();
}

@Component()
class Report {
  @Autowired()
  Clock? clock = const SystemClock();

  @Value(r'${report.title}')
  String? title = 'Untitled';

  @Autowired()
  set audit(Clock? value) => audited = value;
  Clock? audited;

  @Value(r'${report.size:10}')
  late final int size;
}
''');
      expect(
        output,
        hasCode(
          "if (r.optionalDependency<Clock>(name: r'clock') case final value?) "
          '{ bean.clock = value; }',
        ),
      );
      expect(
        output,
        hasCode(
          r"if (r.optionalValue<String>(r'${report.title}') case final value?) "
          '{ bean.title = value; }',
        ),
      );
      expect(
        output,
        hasCode(
          "if (r.optionalDependency<Clock>(name: r'audit') case final value?) "
          '{ bean.audit = value; }',
        ),
      );
      // Required points are assigned as before.
      expect(
        output,
        hasCode(r"bean.size = r.value<int>(r'${report.size:10}');"),
      );
    },
  );

  group('generates', () {
    test('module, names, types, constructor arguments', () async {
      final output = await generateModule('''
abstract interface class Api {}

@Service()
class ApiImpl implements Api {
  ApiImpl(this.dep, {@Qualifier('x') Other? other});
  final Other dep;
}

@Component('x')
@Scope('session')
@Lazy()
@Primary()
@Fallback()
@Order(3)
@DependsOn(['apiImpl'])
@Description('An other')
@Qualifier('q')
class Other {}
''');
      expect(
        output,
        hasCode(r"BeanModule get $pkgBeans => BeanModule(r'pkgBeans',"),
      );
      expect(output, hasCode("name: r'apiImpl'"));
      expect(
        output,
        hasCode("source: r'package:pkg/src/service.dart#ApiImpl'"),
      );
      expect(output, hasCode('types: const [ApiImpl, Api]'));
      expect(
        output,
        hasCode(
          "ApiImpl(r.dependency<Other>(name: r'dep'), "
          "other: r.optionalDependency<Other>(qualifier: r'x', name: "
          "r'other'),)",
        ),
      );
      expect(output, hasCode("Dependency(Other, name: r'dep')"));
      expect(
        output,
        hasCode(
          "Dependency(Other, qualifier: r'x', optional: true, name: r'other')",
        ),
      );
      for (final fragment in [
        "scope: r'session'",
        'lazy: true',
        'primary: true',
        'fallback: true',
        'order: 3',
        "description: r'An other'",
        "dependsOn: const [r'apiImpl']",
        "qualifiers: const {r'q'}",
      ]) {
        expect(output, hasCode(fragment));
      }
    });

    test('Spring bean names and @Named', () async {
      final output = await generateModule('''
@Component() class URLService {}
@Component() class AuthService {}
@Named() class Plain {}
@Named('custom') class Custom {}
@Component()
class UsesNamed {
  UsesNamed(@Named('custom') Custom c, @Named() Plain plain);
}
''');
      expect(output, hasCode("name: r'URLService'"));
      expect(output, hasCode("name: r'authService'"));
      expect(output, hasCode("name: r'plain'"));
      expect(output, hasCode("name: r'custom'"));
      expect(
        output,
        hasCode("r.dependency<Custom>(qualifier: r'custom', name: r'c')"),
      );
      expect(
        output,
        hasCode("r.dependency<Plain>(qualifier: r'plain', name: r'plain')"),
      );
    });

    test('collections, providers and values', () async {
      final output = await generateModule(r'''
abstract interface class Plugin {}

@Component()
class Host {
  Host(
    List<Plugin> list,
    Iterable<Plugin> iterable,
    Set<Plugin>? set,
    Map<String, Plugin> map,
    ObjectProvider<Plugin> provider,
    @Value(r'${port:80}') int port,
    @Value(r'${maybe}') Duration? maybe,
    List<Plugin>? optionalList,
    Map<String, Plugin>? optionalMap,
  );
}
''');
      // A single constructor gets an empty collection when nothing matches
      // (Spring's ConstructorResolver fallback).
      expect(
        output,
        hasCode('r.optionalDependencyList<Plugin>() ?? <Plugin>[]'),
      );
      // A Set keeps registration order, like Spring (only lists are sorted).
      expect(
        output,
        hasCode('r.optionalDependencyMap<Plugin>()?.values.toSet()'),
      );
      expect(
        output,
        hasCode('r.optionalDependencyMap<Plugin>() ?? <String, Plugin>{}'),
      );
      expect(output, hasCode('r.optionalDependencyMap<Plugin>()'));
      // The provider resolves for the injection point, named like it.
      expect(output, hasCode("r.provider<Plugin>(name: r'provider')"));
      expect(output, hasCode(r"r.value<int>(r'${port:80}')"));
      expect(output, hasCode(r"r.optionalValue<Duration>(r'${maybe}')"));
      expect(output, hasCode('Dependency.collection(Plugin, optional: true)'));
      expect(output, hasCode('Dependency.map(Plugin, optional: true)'));
      expect(output, hasCode("Dependency.provider(Plugin, name: r'provider')"));
      expect(output, hasCode(r"Dependency.value(r'${port:80}')"));
      expect(output, hasCode(r"Dependency.value(r'${maybe}', optional: true)"));
    });

    test('fields, setters, methods, inherited members', () async {
      final output = await generateModule(r'''
class Dep {}

@Component() class DepBean extends Dep {}

class Base {
  @Autowired()
  late final Dep inherited;

  @PostConstruct()
  void baseInit() {}

  @PreDestroy()
  void baseDestroy() {}
}

@Component()
class Child extends Base {
  @Value(r'${name}')
  late final String name;

  Dep? _dep;
  @Autowired()
  set dep(Dep? value) => _dep = value;

  @Autowired()
  void wire(Dep dep, {@Value(r'${x:1}') int x = 0}) {}

  @PostConstruct()
  void childInit() {}

  @PreDestroy()
  void childDestroy() {}
}
''');
      expect(output, hasCode(r"bean.name = r.value<String>(r'${name}');"));
      expect(
        output,
        hasCode(
          "if (r.optionalDependency<Dep>(name: r'dep') case final value?) { "
          'bean.dep = value; }',
        ),
      );
      expect(
        output,
        hasCode("bean.inherited = r.dependency<Dep>(name: r'inherited');"),
      );
      expect(
        output,
        hasCode(
          "bean.wire(r.dependency<Dep>(name: r'dep'), x: "
          r"r.optionalValue<int>(r'${x:1}') ?? 0,);",
        ),
      );
      expect(
        output,
        hasCode('postConstruct: (bean) {bean.baseInit(); bean.childInit();}'),
      );
      expect(
        output,
        hasCode(
          'preDestroy: (bean) {bean.childDestroy(); bean.baseDestroy();}',
        ),
      );
    });

    test(
      '@Bean methods: options, static, inferred and explicit lifecycle',
      () async {
        final output = await generateModule('''
class Closable { void close() {} void open() {} void stop() {} }
class Shut { void shutdown() {} }
class Disp { void dispose() {} }
class Plain {}

@Configuration()
@Lazy()
@Profile(['cloud'])
class Config {
  @Bean(name: 'main', aliases: ['primaryClosable'], initMethod: 'open')
  Closable closable() => Closable();

  @Bean(destroyMethod: 'stop', autowireCandidate: false)
  @Lazy(false)
  Closable other() => Closable();

  @Bean(destroyMethod: '')
  Closable noDestroy() => Closable();

  @Bean()
  static Shut shut() => Shut();

  @Bean()
  Disp disp() => Disp();

  @Bean()
  Plain plain() => Plain();
}
''');
        expect(output, hasCode("name: r'main'"));
        expect(output, hasCode("aliases: const [r'primaryClosable']"));
        expect(output, hasCode('initMethod: (bean) {bean.open();}'));
        expect(output, hasCode('destroyMethod: (bean) {bean.close();}'));
        expect(output, hasCode('destroyMethod: (bean) {bean.stop();}'));
        expect(output, hasCode('autowireCandidate: false'));
        expect(output, hasCode('destroyMethod: (bean) {bean.shutdown();}'));
        expect(output, hasCode('destroyMethod: (bean) {bean.dispose();}'));
        expect(output, hasCode('create: (r) => Config.shut()'));
        expect(
          output,
          hasCode(
            "(r.dependency<Config>(qualifier: r'config') "
            r'as _$ConfigConfiguration)._$closable(r)',
          ),
        );
        expect(output, hasCode("const ProfileCondition([r'cloud'])"));
        final noDestroy = output.substring(output.indexOf("name:r'noDestroy'"));
        expect(
          noDestroy.substring(0, noDestroy.indexOf('BeanDefinition')),
          allOf(
            isNot(contains('destroyMethod:(')),
            isNot(contains('destroyMethodName')),
          ),
        );
        final other = output.substring(output.indexOf("name:r'other'"));
        expect(
          other.substring(0, other.indexOf('create')),
          isNot(contains('lazy')),
        );
        expect(
          'lazy:true'.allMatches(output).length,
          6,
          reason: 'config + 5 beans',
        );
      },
    );

    test('factory beans and listeners', () async {
      final output = await generateModule('''
class Product {}
class Placed {}
class Shipped extends ApplicationEvent { Shipped(super.source); }

bool isImportant(Placed p) => true;

class Conditions {
  static bool always(Object o) => true;
}

@Component()
class ProductFactory extends FactoryBean<Product> {
  @override
  Product getObject() => Product();

  @EventListener()
  void onPlaced(Placed placed) {}
}

@Component()
@Order(5)
class Listener implements ApplicationListener<Shipped> {
  @override
  void onApplicationEvent(Shipped event) {}

  @EventListener(condition: isImportant)
  @Order(1)
  Shipped onPlaced(Placed placed) => Shipped(this);

  @EventListener(classes: [Placed, Shipped], condition: Conditions.always, id: 'custom')
  void onAny() {}

  @EventListener(classes: [Placed])
  Object onTyped(Object event) => event;

  @EventListener()
  Future<void> onAsync(Placed placed) async {}

  @EventListener()
  void onPayload(PayloadApplicationEvent<Placed> event) {}

  @EventListener()
  List<Placed?> onMany(Product product) => [];
}
''');
      expect(output, hasCode('factoryObjectTypes: const [Product]'));
      // A FactoryBean's listeners are registered (invoked on the factory).
      expect(
        output,
        hasCode(
          'EventListenerMethod.of<ProductFactory, '
          "Placed>(r'ProductFactory.onPlaced'",
        ),
      );
      // A PayloadApplicationEvent<P> listener matches on the payload type.
      expect(
        output,
        hasCode(
          'EventListenerMethod.forPayload<Listener, '
          "Placed>(r'Listener.onPayload'",
        ),
      );
      // The raw `FactoryBean` (instantiated to bounds) finds every factory.
      expect(
        output,
        hasCode(
          'types: const [ProductFactory, FactoryBean<Product>, '
          'FactoryBean<Object>]',
        ),
      );
      expect(
        output,
        hasCode(
          'EventListenerMethod.of<Listener, '
          "Shipped>(r'Listener.onApplicationEvent', "
          '(bean, event) {bean.onApplicationEvent(event); return null;}, '
          'order: 5,)',
        ),
      );
      expect(
        output,
        hasCode(
          "EventListenerMethod.of<Listener, Placed>(r'Listener.onPlaced', "
          '(bean, event) => bean.onPlaced(event), order: 1, '
          'resultType: const EventResultType<Shipped>(), '
          'condition: isImportant,)',
        ),
      );
      expect(
        output,
        hasCode("EventListenerMethod<Listener>.matching(id: r'custom',"),
      );
      expect(output, hasCode('candidate is Placed || candidate is Shipped'));
      expect(output, hasCode('condition: Conditions.always'));
      expect(
        output,
        hasCode(
          'return bean.onTyped((EventListenerMethod.match(event, (candidate) '
          '=> candidate is Placed) as Object));',
        ),
      );
      expect(output, hasCode('bean.onAsync(event); return null;'));
      // Results are published as their declared (element) type, so
      // PayloadApplicationEvent<Placed> listeners see them.
      expect(
        output,
        hasCode(
          "EventListenerMethod.of<Listener, Product>(r'Listener.onMany', "
          '(bean, event) => bean.onMany(event), '
          'resultType: const EventResultType<Placed>(),)',
        ),
      );
      expect(output, isNot(hasCode('EventResultType<Object>')));
    });

    test('conditions, imports, property sources, configurables', () async {
      final output = await generateModule(r'''
enum Mode { on, off }

class OnMode implements Condition {
  const OnMode(this.mode, {this.names = const ['a'], this.weights = const {'w': 1.5}, this.flags = const {true}, this.type = String, this.nested = const Nested(), this.check = OnMode.always, this.nothing});
  final Mode mode;
  final List<String> names;
  final Map<String, double> weights;
  final Set<bool> flags;
  final Type type;
  final Nested nested;
  final bool Function() check;
  final Object? nothing;
  static bool always() => true;
  @override
  bool matches(ConditionContext context) => true;
}

class Nested {
  const Nested();
}

const onConstant = OnMode(Mode.off);

class Custom implements Condition {
  @override
  bool matches(ConditionContext context) => true;
}

class YamlFactory implements PropertySourceFactory {
  @override
  AbstractPropertySource<Object> createPropertySource(String? name, EncodedResource resource) => throw UnimplementedError();
}

class Imported {
  @Bean()
  String text() => 'x';
}

@Configuration()
@Import([Imported])
@PropertySource(['file:a.properties'])
@PropertySource([r'${dir}/b.yml'], name: 'b', ignoreResourceNotFound: true, factory: YamlFactory, encoding: 'ISO-8859-1')
@OnMode(Mode.on, names: ['a'], weights: {'w': 1.5}, flags: {true}, type: String, nested: Nested(), check: OnMode.always, nothing: null)
@onConstant
@Conditional([Custom])
class Config {}

@Configurable()
class Screen {
  @Autowired()
  late final Config config;

  @Value(r'${title}')
  late final String title;

  @Autowired()
  void wire(Config config) {}
}
''');
      expect(
        output,
        hasCode(
          "const OnMode(Mode.on, names: [r'a'], weights: {r'w': 1.5}, "
          'flags: {true}, type: String, nested: Nested(), check: '
          'OnMode.always, nothing: null)',
        ),
      );
      expect(output, hasCode('const OnMode(Mode.off)'));
      expect(output, hasCode('Custom()'));
      expect(
        output,
        hasCode("source: r'package:pkg/src/service.dart#Imported'"),
      );
      expect(
        output,
        hasCode("r.dependency<Imported>(qualifier: r'imported').text()"),
      );
      expect(
        output,
        // The declaring class's conditions gate its property sources.
        hasCode(
          "PropertySourceDeclaration(const [r'file:a.properties'], "
          "conditions: [ConditionGroup(r'package:pkg/src/service.dart#Config', [const OnMode(",
        ),
      );
      expect(
        output,
        hasCode(
          r"PropertySourceDeclaration(const [r'${dir}/b.yml'], name: r'b', "
          "ignoreResourceNotFound: true, encoding: r'ISO-8859-1', "
          'factory: YamlFactory(), conditions: [',
        ),
      );
      expect(
        output,
        hasCode(
          'configurers: {Screen: (bean, r) {final target = (bean as Screen);',
        ),
      );
      expect(output, hasCode(r"target.title = r.value<String>(r'${title}');"));
      expect(
        output,
        hasCode("target.wire(r.dependency<Config>(name: r'config'));"),
      );
    });

    test('introspection metadata', () async {
      final output = await generateModule('''
class Marker {
  const Marker();
}

class Base {
  @NotBlank()
  String baseName = '';
  void baseMethod() {}
}

@Introspected()
@Marker()
class Form extends Base {
  @Size(max: 3)
  @Value('nick')
  String? nick;

  final int id = 1;

  late void Function() callback;

  int get computed => 2;

  @Marker()
  set computed(int value) {}

  String greet(String name, [int times = 1]) => name * times;
  void configure({required int x}) {}
  void typed(void Function() f) {}
  Future<void> later() async {}
  static void util() {}
  bool operator ==(Object other) => false;
}

@Introspected()
class NoCtor {
  NoCtor(this.x);
  final int x;
}
''');
      // A constant: `const Introspection<Form>(`, the closures are
      // top-level functions and each type comes from its typeInfo.
      expect(output, hasCode('const Introspection<Form>('));
      expect(
        output,
        matches(
          RegExp(
            r"IntrospectedProperty<Form>\(r'nick',nullable:true,"
            r'typeInfo:ClassType<String>\(nullable:true\),get:_\$get\d+,'
            r'set:_\$set\d+,annotations:\[Size\(max:3\)\]\)',
          ),
        ),
      );
      expect(output, hasCode('(Form object) => object.nick;'));
      expect(
        output,
        hasCode(
          '(Form object, Object? value) => object.nick = (value as String?);',
        ),
      );
      expect(
        output,
        matches(
          RegExp(
            r"IntrospectedProperty<Form>\(r'id',typeInfo:ClassType<int>\(\),"
            r'hasInitialValue:true,initialValue:1,get:_\$get\d+\)',
          ),
        ),
      );
      expect(
        output,
        matches(
          RegExp(
            r"r'computed',typeInfo:ClassType<int>\(\),get:_\$get\d+,"
            r'set:_\$set\d+',
          ),
        ),
      );
      expect(
        output,
        hasCode(
          '(Form object, Object? value) => object.computed = (value as int);',
        ),
      );
      expect(output, hasCode('annotations: [Marker()]'));
      expect(output, hasCode("r'baseName'"));
      expect(output, isNot(contains('callback')));
      // `Function.apply` checks what an expression passes.
      expect(
        output,
        matches(
          RegExp(
            r"IntrospectedMethod<Form>\(r'greet',returnType:String,parameterTypes:"
            r'\[String,int\],invoke:_\$invoke\d+\)',
          ),
        ),
      );
      expect(
        output,
        hasCode(
          '(Form object, List<Object?> arguments) => '
          'Function.apply(object.greet, arguments);',
        ),
      );
      expect(output, hasCode("IntrospectedMethod<Form>(r'baseMethod',"));
      expect(
        output,
        hasCode("IntrospectedMethod<Form>(r'later', returnType: Future<void>,"),
      );
      for (final skipped in ["r'configure'", "r'typed'", "r'util'"]) {
        expect(output, isNot(contains(skipped)));
      }
      expect(output, hasCode('instantiate: Form.new'));
      final noCtor = output.substring(
        output.indexOf('Introspection<NoCtor>'),
      );
      expect(noCtor, isNot(contains('instantiate')));
    });

    test('a class reached by scan and @Import is emitted once', () async {
      final output = await generateModule('''
@Configuration()
class Shared {}

@Configuration()
@Import([Shared])
class A {}

@Configuration()
@Import([Shared])
class B {}
''');
      expect("name:r'shared'".allMatches(output), hasLength(1));
    });

    test('only beans under the scanned directory', () async {
      final result = await buildPackage({
        'lib/src/beans.dart': scanRoot,
        'lib/src/inside/a.dart': '$coreImport@Component() class Inside {}',
        'lib/outside.dart': '$coreImport@Component() class Outside {}',
      });
      final output = moduleText(result);
      expect(output, contains('Inside'));
      expect(output, isNot(contains('Outside')));
    });

    test('scan roots outside lib use relative imports', () async {
      final result = await buildPackage({
        'test/fixtures/beans.dart': r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import '../spring_gen/fixtures/beans.spring.dart';

@ComponentScan()
final BeanModule testBeans = $testBeans;

@Component()
class TestOnly {}
''',
      });
      expect(result.errors, isEmpty);
      final output = moduleText(result);
      expect(output, contains("import '../../fixtures/beans.dart' as _i2;"));
    });

    test('nothing without @ComponentScan', () async {
      final result = await buildPackage({
        'lib/src/service.dart': '$coreImport@Component() class A {}',
        'lib/src/mentions.dart':
            '// ComponentScan is only mentioned here\nclass B {}',
        'lib/src/part.dart': "part of 'service.dart';",
      });
      expect(result.succeeded, isTrue);
      expect(result.outputs, isEmpty);
    });
  });

  group('modern syntax', () {
    test('primary constructors and new/factory constructors', () async {
      final output = await generateModule(r'''
abstract interface class Api { String call(); }

@Component()
class Settings(@Value(r'${app.name:demo}') final String name);

@Service()
class Repository(final Settings settings, {@Qualifier('settings') final Settings? backup});

@Service()
class const Clock();

@Service()
class Gateway implements Api {
  final Repository repository;
  final int _retries;

  @Autowired()
  new(this.repository, {required this._retries});
  new withDefaults(Repository repository) : this(repository, retries: 3);

  @override
  String call() => '${repository.settings.name}:$_retries';
}

@Service()
class Picked {
  final Clock clock;
  new direct(this.clock);
  @Autowired()
  factory create(Clock clock) => Picked.direct(clock);
}

@Configuration()
class Config(final Settings settings) {
  @Bean() int retries() => settings.name.length;
}

@Introspected()
class Form(var String email, {var int age = 0});
''', proxyMode: ProxyMode.all);
      expect(
        output,
        hasCode(r"Settings(r.value<String>(r'${app.name:demo}'))"),
      );
      expect(
        output,
        hasCode(
          "Repository(r.dependency<Settings>(name: r'settings'), "
          "backup: r.optionalDependency<Settings>(qualifier: r'settings', "
          "name: r'backup'))",
        ),
      );
      expect(output, hasCode('create: (r) => Clock()'));
      // Private named parameter: called with its public name; the
      // `@Autowired` `new(...)` constructor wins over `new withDefaults(...)`.
      // Private state: created as its subclass proxy.
      expect(
        output,
        hasCode(
          r"_$GatewayProxy(r.dependency<Repository>(name: r'repository'), "
          "retries: r.dependency<int>(name: r'retries'))",
        ),
      );
      expect(
        output,
        hasCode("Picked.create(r.dependency<Clock>(name: r'clock'))"),
      );
      // A full-mode @Configuration: created as its generated subclass.
      expect(
        output,
        hasCode(
          r'_$ConfigConfiguration(r, r.dependency<Settings>(name: '
          "r'settings'))",
        ),
      );
      expect(
        output,
        hasCode(r'class _$GatewayProxy extends Gateway with AdvisedSubclass'),
      );
      // A constant description: the type comes from typeInfo, the
      // accessors are top-level functions.
      expect(
        output,
        matches(
          RegExp(
            r"IntrospectedProperty<Form>\(r'email',typeInfo:ClassType<String>\(\),"
            r'get:_\$get\d+,set:_\$set\d+\)',
          ),
        ),
      );
      expect(output, hasCode(r'Object? _$get'));
      expect(output, hasCode('(Form object) => object.email;'));
      expect(
        output,
        hasCode(
          '(Form object, Object? value) => object.email = (value as String);',
        ),
      );
      expect(output, hasCode("IntrospectedProperty<Form>(r'age', typeInfo:"));
    });
  });

  group('review fixes', () {
    test('@Lazy injection points get a generated lazy proxy', () async {
      final output = await generateModule('''
abstract interface class Pricing {
  double price(String isbn, {int quantity = 1});
  T convert<T extends num>(T value);
  int get count;
  set count(int value);
}

@Service()
class DefaultPricing implements Pricing {
  DefaultPricing(@Lazy() this.self);
  final Pricing self;

  @Lazy()
  @Autowired()
  late final Pricing other;

  @override
  double price(String isbn, {int quantity = 1}) => 10.0 * quantity;
  @override
  T convert<T extends num>(T value) => value;
  @override
  int count = 0;
}
''');
      // Independent of aop_proxies (none here).
      expect(
        output,
        hasCode(
          r'class _$PricingLazy implements Pricing { '
          r'_$PricingLazy(this._resolve); '
          'final Pricing Function() _resolve; '
          '@override String toString() => this._resolve().toString(); '
          '@override double price(String isbn, {int quantity = 1}) => '
          'this._resolve().price(isbn, quantity: quantity); '
          '@override T convert<T extends num>(T value) => '
          'this._resolve().convert<T>(value); '
          '@override int get count => this._resolve().count; '
          '@override set count(int value) { this._resolve().count = value; } }',
        ),
      );
      // One class per type, shared by both injection points.
      expect(RegExp(r'class_\$PricingLazy').allMatches(output), hasLength(1));
      expect(
        output,
        hasCode(r"_$PricingLazy(r.lazyDependency<Pricing>(name: r'self'))"),
      );
      expect(
        output,
        hasCode(
          r'bean.other = _$PricingLazy(r.lazyDependency<Pricing>(name: '
          "r'other'));",
        ),
      );
      expect(output, hasCode("Dependency.lazy(Pricing, name: r'self')"));
      expect(output, hasCode("Dependency.lazy(Pricing, name: r'other')"));
    });

    test('parameter defaults are kept when nothing is found', () async {
      final output = await generateModule(r'''
abstract interface class Clock {}

class SystemClock implements Clock {
  const SystemClock();
}

@Component()
class Retrying {
  Retrying({
    this.clock = const SystemClock(),
    this.retries = 3,
    @Value(r'${retry.delay}') this.delay = const Duration(seconds: 5),
  });
  final Clock clock;
  final int retries;
  final Duration delay;
}
''');
      expect(
        output,
        hasCode(
          "clock: r.optionalDependency<Clock>(name: r'clock') ?? "
          'const SystemClock()',
        ),
      );
      expect(
        output,
        hasCode("retries: r.optionalDependency<int>(name: r'retries') ?? 3"),
      );
      expect(
        output,
        hasCode(
          r"delay: r.optionalValue<Duration>(r'${retry.delay}') ?? "
          'const Duration(seconds: 5)',
        ),
      );
      expect(
        output,
        hasCode("Dependency(int, optional: true, name: r'retries')"),
      );
    });

    test('objects returned from @Bean methods are processed', () async {
      final output = await generateModule('''
abstract interface class Clock {}

@Component()
class SystemClock implements Clock {}

class Pool {
  @Autowired()
  late final Clock clock;

  @PostConstruct()
  void start() {}

  @PreDestroy()
  void close() {}

  @EventListener()
  void onRefresh(ContextRefreshedEvent event) {}
}

@Configuration()
class PoolConfig {
  @Bean()
  Pool pool() => Pool();
}
''');
      expect(
        output,
        hasCode("bean.clock = r.dependency<Clock>(name: r'clock');"),
      );
      expect(output, hasCode('postConstruct: (bean) { bean.start(); }'));
      // `close` is both @PreDestroy and the inferred destroy method: it
      // runs once.
      expect(output, hasCode('preDestroy: (bean) { bean.close(); }'));
      expect(output, isNot(hasCode('destroyMethod: (bean)')));
      expect(output, hasCode('eventListeners:'));
    });

    test('imported classes inherit the importer conditions', () async {
      // CloudData is not a component itself: it is reachable only through
      // the import (a component in the scan root is registered regardless
      // of importers, as in Spring).
      final output = await generateModule('''
class CloudData {
  @Bean()
  String store() => 'cloud';
}

@Configuration()
@Profile(['cloud'])
@Import([CloudData])
@PropertySource(['file:cloud.properties'])
class CloudConfig {}
''');
      // The importer's profile gates the imported class, its @Bean methods
      // and the property source.
      expect(
        output,
        hasCode(
          "BeanDefinition<CloudData>(name: r'cloudData', "
          "source: r'package:pkg/src/service.dart#CloudData', "
          "conditions: [ConditionGroup(r'package:pkg/src/service.dart#CloudData', "
          "[ConditionGroup(r'package:pkg/src/service.dart#CloudConfig', [const ProfileCondition([r'cloud'])])])]",
        ),
      );
      expect(
        output,
        hasCode(
          "PropertySourceDeclaration(const [r'file:cloud.properties'], "
          "conditions: [ConditionGroup(r'package:pkg/src/service.dart#CloudConfig', [const ProfileCondition([r'cloud'])])])",
        ),
      );
    });
  });

  group('asynchronous lifecycle methods', () {
    test('are awaited by async callbacks (refreshAsync / closeAsync)', () async {
      final output = await generateModule('''
class Conn {
  Future<void> open() async {}
  Future<void> close() async {}
}

@Component()
class Cache {
  @PostConstruct()
  Future<void> warmUp() async {}

  @PostConstruct()
  void check() {}

  @PreDestroy()
  Future<void> flush() async {}
}

@Configuration()
class Config {
  @Bean(initMethod: 'open', destroyMethod: 'close')
  Conn conn() => Conn();
}
''');
      expect(
        output,
        hasCode(
          'postConstruct: (bean) async { await bean.warmUp(); bean.check(); }',
        ),
      );
      expect(
        output,
        hasCode('preDestroy: (bean) async { await bean.flush(); }'),
      );
      expect(
        output,
        hasCode('initMethod: (bean) async { await bean.open(); }'),
      );
      expect(
        output,
        hasCode('destroyMethod: (bean) async { await bean.close(); }'),
      );
    });
  });

  group('container metadata', () {
    const source = '''
abstract interface class Store<T> {}
class User {}

class Closable {
  void close() {}
  void open() {}
}

class Marker {
  const Marker(this.level);
  final int level;
}

class _Hidden {
  const _Hidden();
}

const _hidden = Marker(0);

@Component()
@Marker(1)
@_Hidden()
class UserStore implements Store<User> {}

@Component()
@Marker(2)
@_hidden
class Holder {
  Holder(this.stores, this.factory);
  final List<Store> stores;
  final ObjectFactory<UserStore> factory;
}

@Configuration()
class Config {
  @Bean(defaultCandidate: false, initMethod: 'open')
  @Marker(3)
  Closable audit() => Closable();

  @Bean(destroyMethod: 'close')
  static Closable plain() => Closable();
}

class Base {
  @Autowired()
  late UserStore baseField;

  @Autowired()
  void baseMethod(UserStore store) {}
}

@Component()
class Child extends Base {
  @Autowired()
  late UserStore childField;

  @Autowired()
  set childSetter(UserStore store) {}
}

@Configurable()
class Screen {
  @Autowired()
  late UserStore store;

  @PostConstruct()
  void init() {}

  @PreDestroy()
  void dispose() {}
}
''';

    test('raw generic types, ObjectFactory and named providers', () async {
      final output = await generateModule(source);
      // `Store` (a raw type) means `Store<dynamic>`: every Store bean.
      expect(
        output,
        hasCode(
          'types: const [UserStore, Store<User>, '
          'Store<dynamic>]',
        ),
      );
      expect(output, hasCode('r.optionalDependencyList<Store<dynamic>>()'));
      expect(output, hasCode("r.provider<UserStore>(name: r'factory')"));
    });

    test('@Bean factory method, candidacy and lifecycle names', () async {
      final output = await generateModule(source);
      expect(output, hasCode('defaultCandidate: false'));
      expect(
        output,
        hasCode("factoryBeanName: r'config', factoryMethodName: r'audit'"),
      );
      expect(output, hasCode("initMethodName: r'open'"));
      expect(output, hasCode("destroyMethodName: r'(inferred)'"));
      // A static @Bean method has no factory bean, like in Spring.
      final plain = output.substring(output.indexOf("name:r'plain'"));
      expect(
        plain.substring(0, plain.indexOf('create:')),
        allOf(
          contains("factoryMethodName:r'plain'"),
          isNot(contains('factoryBeanName')),
        ),
      );
      expect(output, hasCode("destroyMethodName: r'close'"));
    });

    test('annotations that can be re-created', () async {
      final output = await generateModule(source);
      expect(output, hasCode('annotations: const [Component(), Marker(1)]'));
      // A top-level constant is re-created through its constructor.
      expect(
        output,
        hasCode('annotations: const [Component(), Marker(2), Marker(0)]'),
      );
      expect(output, hasCode('Marker(3)'));
      expect(output, isNot(contains('_Hidden')));
    });

    test('superclass members first, fields before methods', () async {
      final output = await generateModule(source);
      final child = output.substring(output.indexOf("name:r'child'"));
      final inject = child.substring(child.indexOf('inject:'));
      final order = [
        'bean.baseField=',
        'bean.baseMethod(',
        'bean.childField=',
        'bean.childSetter=',
      ].map(inject.indexOf).toList();
      expect(order, everyElement(greaterThanOrEqualTo(0)));
      expect(order, orderedEquals([...order]..sort()));
    });

    test('@Configurable lifecycle methods', () async {
      final output = await generateModule(source);
      expect(
        output,
        hasCode(
          'configurablePostConstruct: {Screen: (bean) { '
          'final target = (bean as Screen); target.init();}}',
        ),
      );
      expect(
        output,
        hasCode(
          'configurablePreDestroy: {Screen: (bean) { '
          'final target = (bean as Screen); target.dispose();}}',
        ),
      );
    });

    test('the generated code compiles', () async {
      expect(await compileErrors({'lib/src/service.dart': source}), isEmpty);
    });
  });

  group('conditional declarations may share a bean name', () {
    const source = """
import 'package:spring_boot_dart/spring_boot_dart.dart';
abstract interface class DataSource {}
class Embedded implements DataSource {}
class Pooled implements DataSource {}
abstract interface class Mailer {}

@Configuration() @Profile(['dev'])
class DevConfig { @Bean() DataSource dataSource() => Embedded(); }

@Configuration() @Profile(['prod'])
class ProdConfig { @Bean() DataSource dataSource() => Pooled(); }

@Component('mailer') @Profile(['dev'])
class FakeMailer implements Mailer {}

@Component('mailer') @Profile(['!dev'])
class SmtpMailer implements Mailer {}

@Configuration(proxyBeanMethods: false)
class Caches {
  @Bean(name: 'cache') @ConditionalOnProperty('cache.kind', havingValue: 'a')
  Object a() => 1;
  @Bean(name: 'cache') @ConditionalOnMissingBean.named('cache')
  Object b() => 2;
  @Bean() @ConditionalOnMissingBean()
  @ConditionalOnCloudPlatform(CloudPlatform.kubernetes)
  Pooled probe() => Pooled();
  @Bean()
  @ConditionalOnMissingBean.where(
    types: [DataSource],
    ignored: [Embedded],
    search: SearchStrategy.current,
  )
  String text() => 'x';
}
""";

    test('builds, one definition per declaration', () async {
      final output = await generateModule(source);
      for (final name in ['dataSource', 'mailer', 'cache']) {
        expect("name:r'$name',".allMatches(output), hasLength(2), reason: name);
      }
    });

    test('the generated code compiles', () async {
      expect(await compileErrors({'lib/src/service.dart': source}), isEmpty);
    });

    test('a clash of two unconditional declarations fails', () async {
      await expectBuildError('''
@Configuration(proxyBeanMethods: false)
class Config {
  @Bean(name: 'x') Object a() => 1;
  @Bean(name: 'x') @Profile(['dev']) Object b() => 1;
  @Bean(name: 'x') Object c() => 1;
}
''', "Bean name 'x' is used by both the @Bean method Config.a");
    });
  });

  group('inherited members', () {
    test('@Bean methods of superclasses and mixins', () async {
      final output = await generateModule('''
class Pool {}
class Clock {}
abstract class BaseConfig {
  @Bean()
  Pool pool() => Pool();
  @Bean()
  static Clock clock() => Clock();
}
mixin Extra {
  @Bean()
  String greeting() => 'hi';
}
@Configuration(proxyBeanMethods: false)
class AppConfig extends BaseConfig with Extra {
  // An override without @Bean still creates the bean (Spring registers
  // the annotated superclass method; the call dispatches to the override).
  @override
  Pool pool() => Pool();
}
''');
      expect(
        output,
        hasCode("r.dependency<AppConfig>(qualifier: r'appConfig').pool()"),
      );
      expect(
        output,
        hasCode("r.dependency<AppConfig>(qualifier: r'appConfig').greeting()"),
      );
      // A static method is not inherited: called on its declaring class.
      expect(output, hasCode('create: (r) => BaseConfig.clock()'));
    });

    test('a full-mode subclass overrides inherited @Bean methods, with the '
        'type arguments of a generic superclass substituted', () async {
      const source = '''
class Store<T> {}
class User {}
abstract class BaseConfig<T> {
  @Bean()
  Store<T> store() => Store<T>();
}
@Configuration()
class UserConfig extends BaseConfig<User> {}
''';
      final output = await generateModule(source);
      expect(output, hasCode('BeanDefinition<Store<User>>('));
      expect(
        output,
        hasCode(r'class _$UserConfigConfiguration extends UserConfig'),
      );
      expect(output, hasCode('Store<User> store()'));
      expect(await compileErrors({'lib/src/service.dart': source}), isEmpty);
    });

    test('lifecycle methods of mixins and the members of a generic '
        'superclass', () async {
      const source = '''
class User {}
class UserEvent {}
class Repo<T> {}
@Component() class UserRepo extends Repo<User> {}
abstract class BaseService<R, E> {
  @Autowired()
  late Repo<R> repo;
  Repo<R>? other;
  @Autowired()
  set otherRepo(Repo<R>? value) => other = value;
  @Autowired()
  void wire(List<Repo<R>> all) {}
  @EventListener()
  void on(E event) {}
  @PostConstruct()
  void baseInit() {}
  @PreDestroy()
  void baseDestroy() {}
}
mixin Audited {
  @PostConstruct()
  void auditInit() {}
  @PreDestroy()
  void auditDestroy() {}
}
@Service()
class UserService extends BaseService<User, UserEvent> with Audited {
  @PostConstruct()
  void init() {}
  @PreDestroy()
  void destroy() {}
}
''';
      final output = await generateModule(source);
      expect(
        output,
        hasCode("bean.repo = r.dependency<Repo<User>>(name: r'repo');"),
      );
      expect(
        output,
        hasCode(
          "if (r.optionalDependency<Repo<User>>(name: r'otherRepo') case final "
          'value?) { bean.otherRepo = value; }',
        ),
      );
      expect(output, contains('dependencyList<Repo<User>>()'));
      expect(
        output,
        hasCode(
          "EventListenerMethod.of<UserService, UserEvent>(r'UserService.on'",
        ),
      );
      expect(
        output,
        hasCode(
          'postConstruct: (bean) {bean.baseInit(); bean.auditInit(); '
          'bean.init();}',
        ),
      );
      expect(
        output,
        hasCode(
          'preDestroy: (bean) {bean.destroy(); bean.auditDestroy(); '
          'bean.baseDestroy();}',
        ),
      );
      expect(await compileErrors({'lib/src/service.dart': source}), isEmpty);
    });
  });

  group('@ComponentScan filters and lazyInit', () {
    const classes = '''
class Plugin { const Plugin(); }
abstract class Handler {}
@Plugin() class Audit {}
class LoginHandler implements Handler {}
abstract class BaseHandler implements Handler {}
@Component() class Stub {}
@Component() class Real {}
@Component() @Lazy(false) class Eager {}
@Configuration() class Config { @Bean() Object thing() => 1; }
''';
    String scan(String options) =>
        '''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';
import 'package:pkg/src/service.dart';

@ComponentScan($options)
final BeanModule pkgBeans = \$pkgBeans;
''';
    Future<TestBuilderResult> build(String options) => buildPackage({
      'lib/src/beans.dart': scan(options),
      'lib/src/service.dart': '$coreImport$classes',
    });
    Future<String> generate(String options) async {
      final result = await build(options);
      expect(result.errors, isEmpty);
      return normalize(
        moduleText(result),
      );
    }

    test('include filters add beans without @Component, excludes win, '
        'abstract classes are skipped', () async {
      final output = await generate(r'''
includeFilters: [
  Filter(classes: [Plugin]),
  Filter(type: FilterType.assignableType, classes: [Handler]),
],
excludeFilters: [Filter(type: FilterType.regex, pattern: [r'Stub$'])],
''');
      expect(output, hasCode("name: r'audit'"));
      expect(output, hasCode("name: r'loginHandler'"));
      expect(output, hasCode("name: r'real'"));
      expect(output, isNot(contains('BaseHandler')));
      expect(output, isNot(contains('Stub')));
    });

    test('useDefaultFilters: false scans only the includes', () async {
      final output = await generate(
        'useDefaultFilters: false, includeFilters: [Filter(classes: [Plugin])]',
      );
      expect(output, hasCode("name: r'audit'"));
      expect(output, isNot(contains("r'real'")));
      expect(output, isNot(contains("r'thing'")));
    });

    test(
      'lazyInit marks every scanned bean lazy unless @Lazy(false)',
      () async {
        final output = await generate('lazyInit: true');
        final definitions = output.split('BeanDefinition<').skip(1);
        String? named(String name) =>
            definitions.firstWhere((d) => d.contains("name:r'$name'"));
        for (final name in ['stub', 'real', 'config', 'thing']) {
          expect(named(name), contains('lazy:true'), reason: name);
        }
        expect(named('eager'), isNot(contains('lazy:true')));
      },
    );

    test('invalid filters fail the build', () async {
      for (final (options, message) in [
        (
          'includeFilters: [Filter(type: FilterType.regex)]',
          'includeFilters[0]: a FilterType.regex filter needs `pattern`',
        ),
        (
          "excludeFilters: [Filter(classes: [Plugin], pattern: ['x'])]",
          'excludeFilters[0]: a FilterType.annotation filter uses `classes`, '
              'not `pattern`',
        ),
        (
          "excludeFilters: [Filter(type: FilterType.regex, pattern: ['('])]",
          "invalid pattern '('",
        ),
      ]) {
        final result = await build(options);
        expect(result.succeeded, isFalse, reason: options);
        expect(result.errors.join('\n'), contains(message), reason: options);
      }
    });
  });

  group('registrars and @Async listeners', () {
    const source = '''
class Clock {}

class Registrar implements BeanRegistrar {
  const Registrar();
  @override
  void register(BeanRegistry registry, Environment environment) =>
      registry.registerBean<Clock>((_) => Clock(), name: 'clock');
}

class Selector implements ImportSelector {
  @override
  List<BeanModule> selectImports() => const [];
}

class Definitions implements ImportBeanDefinitionRegistrar {
  @override
  void registerBeanDefinitions(BeanDefinitionRegistry registry) {}
}

@Configuration()
@Import([Registrar, Selector])
@Profile(['cloud'])
class Config {}

@Configuration()
@Import([Definitions, Registrar])
class Other {}

@Component()
class Mailer {
  @EventListener()
  @Async()
  Future<void> onText(String text) async {}

  @EventListener(classes: [int, double])
  @Async('pool')
  void onNumber() {}
}
''';

    test('are emitted and compile', () async {
      final output = await generateModule(source);
      expect(
        output,
        hasCode(
          'registrars: [ImportDeclaration(Registrar.new, conditions: '
          "[ConditionGroup(r'package:pkg/src/service.dart#Config', "
          "[const ProfileCondition([r'cloud'])])], "
          "importer: r'package:pkg/src/service.dart#Config'), "
          'ImportDeclaration(Selector.new, conditions: [',
        ),
      );
      // Imported once: the first importer wins.
      expect(
        output,
        hasCode(
          'ImportDeclaration(Definitions.new, '
          "importer: r'package:pkg/src/service.dart#Other')]",
        ),
      );
      expect(output, isNot(hasCode("name: r'registrar'")));
      expect(output, hasCode('async: const Async()'));
      expect(output, hasCode("async: const Async(r'pool')"));
      expect(await compileErrors({'lib/src/s.dart': source}), isEmpty);
    });

    test('misuse is reported', () async {
      await expectBuildError(
        '''
class Registrar implements BeanRegistrar {
  Registrar(this.name);
  final String name;
  @override
  void register(BeanRegistry registry, Environment environment) {}
}

@Configuration()
@Import([Registrar])
class Config {}
''',
        'must be a public, non-abstract, non-generic class with a no-argument '
            'constructor',
      );
      await expectBuildError('''
@Component()
class Mailer {
  @Async()
  void send() {}
}
''', '@Async is supported on @EventListener methods only');
    });
  });
}
