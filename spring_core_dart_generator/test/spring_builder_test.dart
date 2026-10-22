import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/builder.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.beans.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _header = "import 'package:spring_core_dart/spring_core_dart.dart';\n";

Future<TestBuilderResult> _build(
  Map<String, Object> sources, {
  ProxyMode proxyMode = ProxyMode.none,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return testBuilder(
    SpringBuilder(proxyMode: proxyMode),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

/// Builds a scan root plus [beans] and returns the generated source without
/// whitespace (the formatter may wrap lines).
Future<String> _generate(
  String beans, {
  Map<String, Object> extra = const {},
  ProxyMode proxyMode = ProxyMode.none,
}) async {
  final result = await _build({
    'lib/src/beans.dart': _scan,
    'lib/src/service.dart': '$_header$beans',
    ...extra,
  }, proxyMode: proxyMode);
  expect(result.errors, isEmpty);
  return _normalize(
    result.readerWriter.testing.readString(result.outputs.single),
  );
}

/// Drops whitespace and trailing commas (formatter choices).
String _normalize(String code) => code
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

Matcher _has(String code) => contains(_normalize(code));

Future<void> _expectError(
  String beans,
  String message, {
  ProxyMode proxyMode = ProxyMode.none,
}) async {
  final result = await _build({
    'lib/src/beans.dart': _scan,
    'lib/src/service.dart': '$_header$beans',
  }, proxyMode: proxyMode);
  expect(result.succeeded, isFalse);
  expect(result.errors.join('\n'), contains(message));
}

/// Builds [files] (with the scan root) and returns the analyzer errors of
/// the generated library, resolved together with the real runtime: the
/// generated code must compile, not just look right.
Future<List<String>> _compileErrors(
  Map<String, String> files, {
  ProxyMode proxyMode = ProxyMode.all,
}) async {
  final sources = {
    'lib/src/beans.dart': _scan,
    for (final MapEntry(:key, :value) in files.entries) key: '$_header$value',
  };
  final result = await _build(sources, proxyMode: proxyMode);
  expect(result.errors, isEmpty);
  final output = result.readerWriter.testing.readString(result.outputs.single);
  return resolveSources<List<String>>(
    {
      for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value,
      'pkg|lib/src/beans.beans.dart': output,
    },
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('pkg', 'lib/src/beans.beans.dart'),
      );
      final errors = await library.session.getErrors(
        library.firstFragment.source.fullName,
      );
      return [
        if (errors case ErrorsResult(:final diagnostics))
          for (final diagnostic in diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic.message,
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|lib/src/beans.beans.dart',
    readAllSourcesFromFilesystem: true,
  );
}

void main() {
  test('builder factory', () {
    expect(
      springCoreDartBuilder(const BuilderOptions({})),
      isA<SpringBuilder>(),
    );
    expect(const SpringBuilder().buildExtensions, {
      '.dart': ['.beans.dart'],
    });
  });

  group('generated code compiles', () {
    test('SDK types as beans (internal dart:_http, dart:_internal)', () async {
      expect(
        await _compileErrors({
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

    test('Future<T>? members of proxied beans', () async {
      expect(
        await _compileErrors({
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
          await _compileErrors({
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
        await _compileErrors({
          'lib/src/s.dart': '''
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
  String toString([String prefix = '']) => '\${prefix}N';
}
''',
        }),
        isEmpty,
      );
    });

    test('classes with the same name in two directories', () async {
      expect(
        await _compileErrors({
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
        await _compileErrors({
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
      final output = await _generate(r'''
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
        _has(
          "if (r.optionalDependency<_i2.Clock>(name: r'clock') case final value?) "
          '{ bean.clock = value; }',
        ),
      );
      expect(
        output,
        _has(
          "if (r.optionalValue<String>(r'\${report.title}') case final value?) "
          '{ bean.title = value; }',
        ),
      );
      expect(
        output,
        _has(
          "if (r.optionalDependency<_i2.Clock>(name: r'audit') case final value?) "
          '{ bean.audit = value; }',
        ),
      );
      // Required points are assigned as before.
      expect(output, _has("bean.size = r.value<int>(r'\${report.size:10}');"));
    },
  );

  test('a bean that cannot be proxied keeps its signatures and the reason', () async {
    final output = await _generate(r'''
@Component()
class Counter {
  int _n = 0;
  @Timed()
  int next() => _n++;
}

class Timed {
  const Timed();
}
''', proxyMode: ProxyMode.all);
    expect(output, isNot(contains('class_\$CounterProxy')));
    expect(output, _has('aopProxy: _i1.AopProxyFactory.unavailable('));
    expect(output, _has("name: r'next'"));
    expect(output, _has("annotationTypes: [r'Timed']"));
    expect(
      output,
      _has(
        "reason: r'Counter cannot be implemented by a generated class (it has "
        'private members, or is final, base or sealed) and implements no '
        'interface. Add an interface with the advised methods and inject the '
        "bean by it, or make its members public.')",
      ),
    );
  });

  group('generates', () {
    test('module, names, types, constructor arguments', () async {
      final output = await _generate('''
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
        _has(r"_i1.BeanModule get $pkgBeans => _i1.BeanModule(r'pkgBeans',"),
      );
      expect(output, _has("name: r'apiImpl'"));
      expect(output, _has("source: r'package:pkg/src/service.dart#ApiImpl'"));
      expect(output, _has('types: const [_i2.ApiImpl, _i2.Api]'));
      expect(
        output,
        _has(
          "_i2.ApiImpl(r.dependency<_i2.Other>(name: r'dep'), "
          "other: r.optionalDependency<_i2.Other>(qualifier: r'x', name: r'other'),)",
        ),
      );
      expect(output, _has("_i1.Dependency(_i2.Other, name: r'dep')"));
      expect(
        output,
        _has(
          "_i1.Dependency(_i2.Other, qualifier: r'x', optional: true, name: r'other')",
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
        expect(output, _has(fragment));
      }
    });

    test('Spring bean names and @Named', () async {
      final output = await _generate('''
@Component() class URLService {}
@Component() class AuthService {}
@Named() class Plain {}
@Named('custom') class Custom {}
@Component()
class UsesNamed {
  UsesNamed(@Named('custom') Custom c, @Named() Plain plain);
}
''');
      expect(output, _has("name: r'URLService'"));
      expect(output, _has("name: r'authService'"));
      expect(output, _has("name: r'plain'"));
      expect(output, _has("name: r'custom'"));
      expect(
        output,
        _has("r.dependency<_i2.Custom>(qualifier: r'custom', name: r'c')"),
      );
      expect(
        output,
        _has("r.dependency<_i2.Plain>(qualifier: r'plain', name: r'plain')"),
      );
    });

    test('collections, providers and values', () async {
      final output = await _generate(r'''
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
        _has('r.optionalDependencyList<_i2.Plugin>() ?? <_i2.Plugin>[]'),
      );
      expect(output, _has('r.optionalDependencyList<_i2.Plugin>()?.toSet()'));
      expect(
        output,
        _has('r.optionalDependencyMap<_i2.Plugin>() ?? <String, _i2.Plugin>{}'),
      );
      expect(output, _has('r.optionalDependencyMap<_i2.Plugin>()'));
      expect(output, _has('r.provider<_i2.Plugin>()'));
      expect(output, _has(r"r.value<int>(r'${port:80}')"));
      expect(output, _has(r"r.optionalValue<Duration>(r'${maybe}')"));
      expect(
        output,
        _has('_i1.Dependency.collection(_i2.Plugin, optional: true)'),
      );
      expect(output, _has('_i1.Dependency.map(_i2.Plugin, optional: true)'));
      expect(output, _has('_i1.Dependency.provider(_i2.Plugin)'));
      expect(output, _has(r"_i1.Dependency.value(r'${port:80}')"));
      expect(
        output,
        _has(r"_i1.Dependency.value(r'${maybe}', optional: true)"),
      );
    });

    test('fields, setters, methods, inherited members', () async {
      final output = await _generate(r'''
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
      expect(output, _has(r"bean.name = r.value<String>(r'${name}');"));
      expect(
        output,
        _has(
          "if (r.optionalDependency<_i2.Dep>(name: r'dep') case final value?) { bean.dep = value; }",
        ),
      );
      expect(
        output,
        _has("bean.inherited = r.dependency<_i2.Dep>(name: r'inherited');"),
      );
      expect(
        output,
        _has(
          r"bean.wire(r.dependency<_i2.Dep>(name: r'dep'), x: r.optionalValue<int>(r'${x:1}') ?? 0,);",
        ),
      );
      expect(
        output,
        _has('postConstruct: (bean) {bean.baseInit(); bean.childInit();}'),
      );
      expect(
        output,
        _has('preDestroy: (bean) {bean.childDestroy(); bean.baseDestroy();}'),
      );
    });

    test(
      '@Bean methods: options, static, inferred and explicit lifecycle',
      () async {
        final output = await _generate('''
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
        expect(output, _has("name: r'main'"));
        expect(output, _has("aliases: const [r'primaryClosable']"));
        expect(output, _has('initMethod: (bean) {bean.open();}'));
        expect(output, _has('destroyMethod: (bean) {bean.close();}'));
        expect(output, _has('destroyMethod: (bean) {bean.stop();}'));
        expect(output, _has('autowireCandidate: false'));
        expect(output, _has('destroyMethod: (bean) {bean.shutdown();}'));
        expect(output, _has('destroyMethod: (bean) {bean.dispose();}'));
        expect(output, _has('create: (r) => _i2.Config.shut()'));
        expect(
          output,
          _has("r.dependency<_i2.Config>(qualifier: r'config').closable()"),
        );
        expect(output, _has("const _i1.ProfileCondition([r'cloud'])"));
        final noDestroy = output.substring(output.indexOf("name:r'noDestroy'"));
        expect(
          noDestroy.substring(0, noDestroy.indexOf('_i1.BeanDefinition')),
          isNot(contains('destroyMethod')),
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
      final output = await _generate('''
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
}
''');
      expect(output, _has('factoryObjectTypes: const [_i2.Product]'));
      expect(
        output,
        _has('types: const [_i2.ProductFactory, _i1.FactoryBean<_i2.Product>]'),
      );
      expect(
        output,
        _has(
          "_i1.EventListenerMethod.of<_i2.Listener, _i2.Shipped>(r'Listener.onApplicationEvent', "
          '(bean, event) {bean.onApplicationEvent(event); return null;}, order: 5,)',
        ),
      );
      expect(
        output,
        _has(
          "_i1.EventListenerMethod.of<_i2.Listener, _i2.Placed>(r'Listener.onPlaced', "
          '(bean, event) => bean.onPlaced(event), order: 1, condition: _i2.isImportant,)',
        ),
      );
      expect(
        output,
        _has("_i1.EventListenerMethod<_i2.Listener>.matching(id: r'custom',"),
      );
      expect(
        output,
        _has('candidate is _i2.Placed || candidate is _i2.Shipped'),
      );
      expect(output, _has('condition: _i2.Conditions.always'));
      expect(
        output,
        _has(
          'return bean.onTyped((_i1.EventListenerMethod.match(event, (candidate) => candidate is _i2.Placed) as Object));',
        ),
      );
      expect(output, _has('bean.onAsync(event); return null;'));
    });

    test('conditions, imports, property sources, configurables', () async {
      final output = await _generate(r'''
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
  AbstractPropertySource<Object> createPropertySource(String? name, Resource resource) => throw UnimplementedError();
}

class Imported {
  @Bean()
  String text() => 'x';
}

@Configuration()
@Import([Imported])
@PropertySource(['file:a.properties'])
@PropertySource([r'${dir}/b.yml'], name: 'b', ignoreResourceNotFound: true, factory: YamlFactory)
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
        _has(
          "const _i2.OnMode(_i2.Mode.on, names: [r'a'], weights: {r'w': 1.5}, "
          'flags: {true}, type: String, nested: _i2.Nested(), check: _i2.OnMode.always, nothing: null)',
        ),
      );
      expect(output, _has('const _i2.OnMode(_i2.Mode.off)'));
      expect(output, _has('_i2.Custom()'));
      expect(output, _has("source: r'package:pkg/src/service.dart#Imported'"));
      expect(
        output,
        _has("r.dependency<_i2.Imported>(qualifier: r'imported').text()"),
      );
      expect(
        output,
        // The declaring class's conditions gate its property sources.
        _has(
          "_i1.PropertySourceDeclaration(const [r'file:a.properties'], "
          "conditions: [_i1.ConditionGroup(r'package:pkg/src/service.dart#Config', [const _i2.OnMode(",
        ),
      );
      expect(
        output,
        _has(
          r"_i1.PropertySourceDeclaration(const [r'${dir}/b.yml'], name: r'b', "
          'ignoreResourceNotFound: true, factory: _i2.YamlFactory(), conditions: [',
        ),
      );
      expect(
        output,
        _has(
          'configurers: {_i2.Screen: (bean, r) {final target = (bean as _i2.Screen);',
        ),
      );
      expect(output, _has(r"target.title = r.value<String>(r'${title}');"));
      expect(
        output,
        _has("target.wire(r.dependency<_i2.Config>(name: r'config'));"),
      );
    });

    test('introspection metadata', () async {
      final output = await _generate('''
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
  @Autowired()
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
      expect(output, _has('_i1.BeanIntrospection<_i2.Form>('));
      expect(
        output,
        _has(
          "_i1.BeanProperty<_i2.Form>(r'nick', type: String, nullable: true, "
          'typeInfo: const _i1.ClassType<String>(nullable: true), get: (bean) => bean.nick, '
          'set: (bean, value) => bean.nick = (value as String?), annotations: const [_i1.Size(max: 3)])',
        ),
      );
      expect(
        output,
        _has(
          "_i1.BeanProperty<_i2.Form>(r'id', type: int, typeInfo: const _i1.ClassType<int>(), get: (bean) => bean.id)",
        ),
      );
      expect(
        output,
        _has(
          "r'computed', type: int, typeInfo: const _i1.ClassType<int>(), get: (bean) => bean.computed, set: (bean, value) => bean.computed = (value as int)",
        ),
      );
      expect(output, _has("annotations: const [_i2.Marker()]"));
      expect(output, _has("r'baseName'"));
      expect(output, isNot(contains('callback')));
      expect(
        output,
        _has(
          "_i1.BeanMethod<_i2.Form>(r'greet', returnType: String, parameterTypes: const [String, int], "
          'invoke: (bean, arguments) => Function.apply(bean.greet, arguments))',
        ),
      );
      expect(output, _has("_i1.BeanMethod<_i2.Form>(r'baseMethod',"));
      expect(
        output,
        _has(
          "_i1.BeanMethod<_i2.Form>(r'later', returnType: _i3.Future<void>,",
        ),
      );
      for (final skipped in ["r'configure'", "r'typed'", "r'util'"]) {
        expect(output, isNot(contains(skipped)));
      }
      expect(output, _has('instantiate: () => _i2.Form()'));
      final noCtor = output.substring(
        output.indexOf('BeanIntrospection<_i2.NoCtor>'),
      );
      expect(noCtor, isNot(contains('instantiate')));
    });

    test('a class reached by scan and @Import is emitted once', () async {
      final output = await _generate('''
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
      final result = await _build({
        'lib/src/beans.dart': _scan,
        'lib/src/inside/a.dart': '$_header@Component() class Inside {}',
        'lib/outside.dart': '$_header@Component() class Outside {}',
      });
      final output = result.readerWriter.testing.readString(
        result.outputs.single,
      );
      expect(output, contains('Inside'));
      expect(output, isNot(contains('Outside')));
    });

    test('scan roots outside lib use relative imports', () async {
      final result = await _build({
        'test/fixtures/beans.dart': r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'beans.beans.dart';

@ComponentScan()
final BeanModule testBeans = $testBeans;

@Component()
class TestOnly {}
''',
      });
      expect(result.errors, isEmpty);
      final output = result.readerWriter.testing.readString(
        result.outputs.single,
      );
      expect(output, contains("import 'beans.dart' as _i2;"));
    });

    test('nothing without @ComponentScan', () async {
      final result = await _build({
        'lib/src/service.dart': '$_header@Component() class A {}',
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
      final output = await _generate(r'''
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
        _has("_i1.Settings(r.value<String>(r'\${app.name:demo}'))"),
      );
      expect(
        output,
        _has(
          "_i1.Repository(r.dependency<_i1.Settings>(name: r'settings'), "
          "backup: r.optionalDependency<_i1.Settings>(qualifier: r'settings', "
          "name: r'backup'))",
        ),
      );
      expect(output, _has('create: (r) => _i1.Clock()'));
      // Private named parameter: called with its public name; the unnamed
      // `new(...)` constructor wins over `new withDefaults(...)`.
      expect(
        output,
        _has(
          "_i1.Gateway(r.dependency<_i1.Repository>(name: r'repository'), "
          "retries: r.dependency<int>(name: r'retries'))",
        ),
      );
      expect(
        output,
        _has("_i1.Picked.create(r.dependency<_i1.Clock>(name: r'clock'))"),
      );
      expect(
        output,
        _has("_i1.Config(r.dependency<_i1.Settings>(name: r'settings'))"),
      );
      expect(output, _has(r'class _$GatewayProxy implements _i1.Api'));
      expect(
        output,
        _has(
          "_i2.BeanProperty<_i1.Form>(r'email', type: String, "
          'typeInfo: const _i2.ClassType<String>(), '
          'get: (bean) => bean.email, '
          'set: (bean, value) => bean.email = (value as String))',
        ),
      );
      expect(output, _has("_i2.BeanProperty<_i1.Form>(r'age', type: int"));
    });
  });

  group('AOP', () {
    test('aspect metadata', () async {
      final output = await _generate('''
class Marker {
  const Marker();
}

@Aspect()
@Component()
class Audit {
  @Pointcut('execution(* *(..))')
  void all() {}

  @Before('all()')
  void before(JoinPoint jp) {}

  @After('all()')
  void after() {}

  @AfterReturning('all()')
  void returned(JoinPoint jp, String result) {}

  @AfterReturning('all()')
  void anyResult(Object? result) {}

  @AfterThrowing('all()')
  void failed(StateError error) {}

  @Around('@annotation(Marker)')
  Object? around(ProceedingJoinPoint pjp) => pjp.proceed();
}
''', proxyMode: ProxyMode.all);
      expect(output, _has('aspect: _i1.AspectMetadata<_i2.Audit>('));
      expect(
        output,
        _has(
          "kind: _i1.AdviceKind.before, pointcut: r'all()', methodName: r'before', invoke: (aspect, joinPoint, value) => aspect.before(joinPoint))",
        ),
      );
      expect(
        output,
        _has('invoke: (aspect, joinPoint, value) => aspect.after()'),
      );
      expect(
        output,
        _has(
          "aspect.returned(joinPoint, (value as String)), accepts: (value) => value is String",
        ),
      );
      expect(output, _has('aspect.anyResult((value as Object?))'));
      expect(
        output,
        _has(
          'accepts: (value) => value is _i3.StateError'.replaceAll('_i3.', ''),
        ),
      );
      expect(
        output,
        _has('aspect.around((joinPoint as _i1.ProceedingJoinPoint))'),
      );
      expect(output, _has("pointcuts: {r'all': r'execution(* *(..))'}"));
      expect(
        output,
        isNot(contains('_\$AuditProxy')),
        reason: 'aspects are not proxied',
      );
    });

    test('proxy members of every kind', () async {
      final output = await _generate(r'''
class Note {
  const Note();
}

abstract interface class Api {
  @Note()
  String plain(int a, [int b = 2, String? c]);
  T generic<T extends Object>(T value, {required String key, int retries = 3});
  void act();
  Future<int> later();
  int get count;
  set count(int value);
  String transform(String Function(int) f, (int, {String name}) record);
}

@Service()
@Note()
class Impl implements Api {
  @override
  String plain(int a, [int b = 2, String? c]) => '$a$b$c';
  @override
  T generic<T extends Object>(T value, {required String key, int retries = 3}) => value;
  @override
  void act() {}
  @override
  Future<int> later() async => 1;
  @override
  int count = 0;
  @override
  String transform(String Function(int) f, (int, {String name}) record) => f(record.$1);
  @override
  String toString() => 'Impl';
}
''', proxyMode: ProxyMode.all);
      expect(
        output,
        _has('class _\$ImplProxy implements _i1.Impl, _i1.Api, _i2.Advised {'),
      );
      expect(output, _has('_\$ImplProxy(this._target, this._invoker);'));
      expect(output, _has('Object get aopTarget => _target;'));
      expect(
        output,
        _has('List<_i2.PointcutAdvisor> get aopAdvisors => _invoker.advisors;'),
      );
      expect(output, _has('String toString() => _target.toString();'));
      expect(
        output,
        _has(
          'String plain(int a, [int b = 2, String? c]) => (_invoker.invoke(this, _target, 0, [a, b, c], '
          '(args) => _target.plain((args[0] as int), (args[1] as int), (args[2] as String?))) as String);',
        ),
      );
      expect(
        output,
        _has(
          'T generic<T extends Object>(T value, {required String key, int retries = 3}) => '
          '(_invoker.invoke(this, _target, 1, [value, key, retries], (args) => _target.generic<T>((args[0] as T), '
          'key: (args[1] as String), retries: (args[2] as int))) as T);',
        ),
      );
      expect(
        output,
        _has(
          'void act() {_invoker.invoke(this, _target, 2, const [], (args) {_target.act(); return null;});}',
        ),
      );
      expect(
        output,
        _has(
          '_i3.Future<int> later() => _invoker.invokeAsync<int>(this, _target, 3, const [], (args) => _target.later());',
        ),
      );
      expect(
        output,
        _has(
          'int get count => (_invoker.invoke(this, _target, 5, const [], (_) => _target.count) as int);',
        ),
      );
      expect(
        output,
        _has(
          'set count(int value) {_invoker.invoke(this, _target, 6, [value], (args) {_target.count = (args[0] as int); return null;});}',
        ),
      );
      expect(
        output,
        _has(
          'String transform(String Function(int) f, (int, {String name}) record)',
        ),
      );
      expect(
        output,
        _has(
          "_i2.MethodSignature(name: r'plain', declaringType: r'Api', targetType: r'Impl', declaringTypes: [r'Impl', r'Api'], returnType: r'String', parameterTypes: [r'int', r'int', r'String'], parameterNames: [r'a', r'b', r'c'], annotations: [_i1.Note()], annotationTypes: [r'Note'], targetTypes: [r'Impl', r'Api'], targetAnnotations: [_i2.Service(), _i1.Note()], targetAnnotationTypes: [r'Service', r'Note'])",
        ),
      );
      expect(output, _has('kind: _i2.MemberKind.getter'));
      expect(output, _has('kind: _i2.MemberKind.setter'));
      expect(output, _has("parameterTypes: [r'Function', r'Record']"));
      expect(
        output,
        _has(
          'create: (target, invoker) => _\$ImplProxy((target as _i1.Impl), invoker)',
        ),
      );
    });

    test('generic type arguments in proxied signatures', () async {
      final output = await _generate('''
abstract interface class Jobs {
  Future<T> run<T>(T value);
  List<void Function()> hooks();
  Map<String, (int, String)> table();
}

@Service()
class JobRunner implements Jobs {
  @override
  Future<T> run<T>(T value) async => value;
  @override
  List<void Function()> hooks() => [];
  @override
  Map<String, (int, String)> table() => {};
  @override
  bool operator ==(Object other) => identical(this, other);
  @override
  int get hashCode => 0;
}
''', proxyMode: ProxyMode.all);
      expect(
        output,
        _has('_i3.Future<T> run<T>(T value) => _invoker.invokeAsync<T>('),
      );
      expect(output, _has('List<void Function()> hooks()'));
      expect(output, _has('Map<String, (int, String)> table()'));
      expect(output, isNot(contains('operator==')));
    });

    test('@Bean methods returning aspects or configurations', () async {
      final output = await _generate('''
@Aspect()
class Audit { void log() {} }

@Configuration()
class Nested { void helper() {} }

@Configuration()
class Config {
  @Bean() Audit auditAspect() => Audit();
  @Bean() Nested nestedConfig() => Nested();
}
''', proxyMode: ProxyMode.all);
      expect(output, isNot(contains(r'_$Config_auditAspectProxy')));
      expect(output, isNot(contains(r'_$Config_nestedConfigProxy')));
    });

    test('proxy modes and exclusions', () async {
      const source = '''
abstract interface class Api { void run(); }
abstract class Base { void base(); }

@Service() class WithPrivate implements Api { int _secret = 0; @override void run() {} }
@Service() class Plain { void work() {} }
@Service() class Both extends Base implements Api { @override void run() {} @override void base() {} }
@Service() class Ops implements Api { @override void run() {} int operator [](int i) => i; }
@Service() class OnlyOps { int operator +(int other) => other; }
@Service() class ComplexDefault implements Api { @override void run([Duration d = const Duration(seconds: 1)]) {} }
@Service() class Untyped implements Api { @override void run() {} void typed(void Function<T>() f) {} }
@Service() class Product extends FactoryBean<Plain> { @override Plain getObject() => Plain(); }
@Service() class Processor extends BeanPostProcessor {}
@Configuration() class Config { @Bean() Api api() => Both(); @Bean() String text() => ''; }
''';
      final all = await _generate(source, proxyMode: ProxyMode.all);
      expect(
        all,
        contains(r'class_$WithPrivateProxyimplements_i1.Api,'),
        reason: 'class with private members: interface only',
      );
      expect(all, contains(r'class_$PlainProxyimplements_i1.Plain,'));
      expect(
        all,
        contains(r'class_$BothProxyimplements_i1.Both,_i1.Base,_i1.Api,'),
      );
      expect(all, isNot(contains(r'_$OpsProxy')), reason: 'operators');
      expect(all, isNot(contains(r'_$OnlyOpsProxy')));
      expect(
        all,
        isNot(contains(r'_$ComplexDefaultProxy')),
        reason: 'non-literal default',
      );
      expect(
        all,
        isNot(contains(r'_$UntypedProxy')),
        reason: 'generic function type parameter',
      );
      for (final excluded in ['Product', 'Processor', 'Config']) {
        expect(all, isNot(contains('_\$${excluded}Proxy')), reason: excluded);
      }
      expect(all, contains(r'class_$Config_apiProxyimplements_i1.Api,'));
      expect(all, isNot(contains(r'_$Config_textProxy')), reason: 'SDK types');

      final interfaces = await _generate(
        source,
        proxyMode: ProxyMode.interfaces,
      );
      expect(
        interfaces,
        contains(r'class_$BothProxyimplements_i1.Base,_i1.Api,'),
      );
      expect(interfaces, isNot(contains(r'_$PlainProxy')));
      expect(interfaces, contains(r'class_$Config_apiProxyimplements_i1.Api,'));

      final none = await _generate(source);
      expect(none, isNot(contains('Proxy')));
    });

    test('builder option', () {
      expect(
        (springCoreDartBuilder(
          const BuilderOptions({'aop_proxies': 'interfaces'}),
        ) as SpringBuilder).proxyMode,
        ProxyMode.interfaces,
      );
      expect(
        () => springCoreDartBuilder(
          const BuilderOptions({'aop_proxies': 'bogus'}),
        ),
        throwsArgumentError,
      );
    });
  });

  group('review fixes', () {
    test('@Lazy injection points get a generated lazy proxy', () async {
      final output = await _generate(r'''
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
        _has(
          'class _\$PricingLazy implements _i1.Pricing { '
          '_\$PricingLazy(this._resolve); '
          'final _i1.Pricing Function() _resolve; '
          '@override String toString() => _resolve().toString(); '
          '@override double price(String isbn, {int quantity = 1}) => '
          '_resolve().price(isbn, quantity: quantity); '
          '@override T convert<T extends num>(T value) => '
          '_resolve().convert<T>(value); '
          '@override int get count => _resolve().count; '
          '@override set count(int value) { _resolve().count = value; } }',
        ),
      );
      // One class per type, shared by both injection points.
      expect(RegExp(r'class_\$PricingLazy').allMatches(output), hasLength(1));
      expect(
        output,
        _has("_\$PricingLazy(r.lazyDependency<_i1.Pricing>(name: r'self'))"),
      );
      expect(
        output,
        _has(
          "bean.other = _\$PricingLazy(r.lazyDependency<_i1.Pricing>(name: r'other'));",
        ),
      );
      expect(output, _has("_i2.Dependency.lazy(_i1.Pricing, name: r'self')"));
      expect(output, _has("_i2.Dependency.lazy(_i1.Pricing, name: r'other')"));
    });

    test('parameter defaults are kept when nothing is found', () async {
      final output = await _generate(r'''
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
        _has(
          "clock: r.optionalDependency<_i2.Clock>(name: r'clock') ?? "
          'const _i2.SystemClock()',
        ),
      );
      expect(
        output,
        _has("retries: r.optionalDependency<int>(name: r'retries') ?? 3"),
      );
      expect(
        output,
        _has(
          r"delay: r.optionalValue<Duration>(r'${retry.delay}') ?? "
          'const Duration(seconds: 5)',
        ),
      );
      expect(
        output,
        _has("_i1.Dependency(int, optional: true, name: r'retries')"),
      );
    });

    test('objects returned from @Bean methods are processed', () async {
      final output = await _generate(r'''
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
        _has("bean.clock = r.dependency<_i2.Clock>(name: r'clock');"),
      );
      expect(output, _has('postConstruct: (bean) { bean.start(); }'));
      // `close` is both @PreDestroy and the inferred destroy method: it
      // runs once.
      expect(output, _has('preDestroy: (bean) { bean.close(); }'));
      expect(output, isNot(_has('destroyMethod: (bean)')));
      expect(output, _has('eventListeners:'));
    });

    test('imported classes inherit the importer conditions', () async {
      // CloudData is not a component itself: it is reachable only through
      // the import (a component in the scan root is registered regardless
      // of importers, as in Spring).
      final output = await _generate(r'''
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
        _has(
          "_i1.BeanDefinition<_i2.CloudData>(name: r'cloudData', "
          "source: r'package:pkg/src/service.dart#CloudData', "
          "types: const [_i2.CloudData], conditions: [_i1.ConditionGroup(r'package:pkg/src/service.dart#CloudData', "
          "[_i1.ConditionGroup(r'package:pkg/src/service.dart#CloudConfig', [const _i1.ProfileCondition([r'cloud'])])])]",
        ),
      );
      expect(
        output,
        _has(
          "_i1.PropertySourceDeclaration(const [r'file:cloud.properties'], "
          "conditions: [_i1.ConditionGroup(r'package:pkg/src/service.dart#CloudConfig', [const _i1.ProfileCondition([r'cloud'])])])",
        ),
      );
    });
  });

  test('lib/resources files are embedded as classpath resources', () async {
    final output = await _generate(
      '@Component() class A {}',
      extra: {
        'lib/resources/application.properties': "app.name='NEON' \$x\nb=2",
        'lib/resources/img/logo.bin': const [0xff, 0xfe, 0x00],
      },
    );
    expect(
      output,
      contains("r'application.properties':_i1.EmbeddedResource.text("),
    );
    expect(output, contains("r'img/logo.bin':_i1.EmbeddedResource.base64("));
  });

  group('@SpringBootApplication', () {
    test(
      'scans lib/ and the directory of main, declares runApplication',
      () async {
        final result = await _build({
          'bin/main.dart': r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.beans.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);

@Component()
class CliRunner {}
''',
          'lib/src/deep/service.dart': '$_header@Service() class Deep {}',
          'lib/props.dart': r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
@ConfigurationProperties('db')
class DbProps { String url = ''; }
''',
        });
        expect(result.errors, isEmpty);
        final output = _normalize(
          result.readerWriter.testing.readString(result.outputs.single),
        );
        expect(result.outputs.single.path, 'bin/main.beans.dart');
        // lib/spring_auto_configuration.dart of the dependencies is
        // discovered: spring_boot_dart's first (order 0, then by package).
        expect(
          output,
          contains('autoConfigurations:[_i7.springBootAutoConfiguration,'),
        );
        // Every starter of the workspace is discovered.
        for (final starter in [
          'springBootStarterLoggingAutoConfiguration',
          'springBootStarterSchedulingAutoConfiguration',
          'springBootStarterCacheAutoConfiguration',
        ]) {
          expect(output, contains('.$starter'));
        }
        expect(
          output,
          contains(
            'runApplicationAsync(List<String>args)=>springApplication.runAsync(args)',
          ),
        );
        expect(
          output,
          _has("BeanDefinition<_i2.CliRunner>(name: r'cliRunner'"),
        );
        expect(output, _has("name: r'deep'"));
        // @ConfigurationProperties: a bean plus introspection metadata.
        expect(output, _has("name: r'dbProps'"));
        expect(output, _has('BeanIntrospection<'));
        expect(output, contains("ConfigurationProperties(r'db')"));
        // Getters, so a hot reload sees the beans of the new code.
        expect(
          output,
          _has(r"BeanModule get $application => _i1.BeanModule(r'application'"),
        );
        expect(output, _has('SpringApplication get springApplication =>'));
        expect(output, matches(RegExp("fingerprint:'[0-9a-f]{8}'")));
        expect(
          output,
          _has(
            'runApplication(List<String> args) => springApplication.run(args);',
          ),
        );
        expect(
          output,
          _has(
            'reloadApplication(_i6.ConfigurableApplicationContext running, '
            '{bool runners = true}) => '
            'springApplication.reload(running, runners: runners);',
          ),
        );
        expect(
          output,
          _has(
            'reloadApplicationAsync(_i6.ConfigurableApplicationContext '
            'running, {bool runners = true}) => '
            'springApplication.reloadAsync(running, runners: runners);',
          ),
        );
      },
    );

    test('the fingerprint is stable and changes with the beans', () async {
      Future<String> fingerprint(String beans) async {
        final result = await _build({
          'bin/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.beans.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''',
          'lib/beans.dart': '$_header$beans',
        });
        expect(result.errors, isEmpty);
        return RegExp("fingerprint: '([0-9a-f]{8})'")
            .firstMatch(
              result.readerWriter.testing.readString(result.outputs.single),
            )!
            .group(1)!;
      }

      const one = '@Service() class A {}';
      final first = await fingerprint(one);
      expect(await fingerprint(one), first); // same code, same fingerprint
      expect(
        await fingerprint('$one\n@Service() class B {}'), // a new bean
        isNot(first),
      );
      expect(
        await fingerprint(
          "@Service() class A { A(@Value(r'\${x:1}') this.x); final String x; }",
        ),
        isNot(first), // a changed injection point
      );
    });
  });

  group('rejects', () {
    final cases = <String, (String, String)>{
      'abstract bean class': (
        '@Component() abstract class A {}',
        'must not be abstract',
      ),
      'private bean class': ('@Component() class _A {}', 'must be public'),
      'generic bean class': (
        '@Component() class A<T> {}',
        'Generic bean class',
      ),
      'final injected field': (
        '@Component() class A { @Autowired() final A? a = null; }',
        'must be settable',
      ),
      'private injected field': (
        '@Component() class A { @Autowired() A? _a; }',
        'must be public',
      ),
      'private injected setter': (
        '@Component() class A { @Autowired() set _a(A? v) {} }',
        'must be public',
      ),
      'private autowired method': (
        '@Component() class A { @Autowired() void _m() {} }',
        'must be public',
      ),
      'async autowired method': (
        '@Component() class A { @Autowired() Future<void> m() async {} }',
        'must not be async',
      ),
      'several @Autowired constructors': (
        '@Component() class A { @Autowired() A.one(); @Autowired() A.two(); }',
        'Only one constructor may be @Autowired',
      ),
      'private @Autowired constructor': (
        '@Component() class A { @Autowired() A._(); A.x(); A.y(); }',
        'must be public',
      ),
      'ambiguous constructors': (
        '@Component() class A { A.one(); A.two(); }',
        'Cannot choose a constructor',
      ),
      'async @Bean method': (
        'class B {} @Configuration() class C { @Bean() Future<B> b() async => B(); }',
        'must not be async',
      ),
      'nullable @Bean method': (
        'class B {} @Configuration() class C { @Bean() B? b() => null; }',
        'non-nullable class type',
      ),
      'private @Bean method': (
        'class B {} @Configuration() class C { @Bean() B _b() => B(); }',
        'must be public',
      ),
      'generic @Bean method': (
        '@Configuration() class C { @Bean() List<T> b<T>() => []; }',
        'Generic @Bean method',
      ),
      'missing initMethod': (
        "class B {} @Configuration() class C { @Bean(initMethod: 'nope') B b() => B(); }",
        "initMethod 'nope'",
      ),
      'missing destroyMethod': (
        "class B {} @Configuration() class C { @Bean(destroyMethod: 'nope') B b() => B(); }",
        "destroyMethod 'nope'",
      ),
      'function-typed dependency': (
        '@Component() class A { A(void Function() f); }',
        'only class types can be injected',
      ),
      'future dependency': (
        '@Component() class A { A(Future<int> f); }',
        'Cannot inject a Future',
      ),
      'nullable collection element': (
        '@Component() class A { A(List<A?> all); }',
        'must not be nullable',
      ),
      'map without String keys': (
        '@Component() class A { A(Map<int, A> all); }',
        'String keys',
      ),
      'lifecycle method with arguments': (
        '@Component() class A { @PostConstruct() void init(int x) {} }',
        'without required parameters',
      ),
      'async lifecycle method': (
        '@Component() class A { @PreDestroy() Future<void> close() async {} }',
        'must not be async',
      ),
      'listener with two parameters': (
        '@Component() class A { @EventListener() void on(A a, A b) {} }',
        'at most one parameter',
      ),
      'listener without event type': (
        '@Component() class A { @EventListener() void on() {} }',
        'needs an event parameter',
      ),
      'private listener': (
        '@Component() class A { @EventListener() void _on(A a) {} }',
        'must be public',
      ),
      'bad conditional type': (
        '@Component() @Conditional([String]) class A {}',
        'must implement Condition',
      ),
      'condition with arguments': (
        'class C implements Condition { C(this.x); final int x; @override bool matches(ConditionContext c) => true; }\n'
            '@Component() @Conditional([C]) class A {}',
        'no-argument constructor',
      ),
      'import of a non-class': (
        '@Component() @Import([dynamic]) class A {}',
        'class types only',
      ),
      'property source factory with arguments': (
        'class F { F(this.x); final int x; }\n'
            "@Component() @PropertySource(['a'], factory: F) class A {}",
        'no-argument constructor',
      ),
      'private configurable': ('@Configurable() class _S {}', 'must be public'),
      'private introspected': ('@Introspected() class _S {}', 'must be public'),
      'static advice': (
        "@Aspect() @Component() class A { @Before('x()') static void b() {} }",
        'public instance method',
      ),
      'named advice parameter': (
        "@Aspect() @Component() class A { @Before('x()') void b({JoinPoint? jp}) {} }",
        'positional parameters',
      ),
      'unexpected advice parameter': (
        "@Aspect() @Component() class A { @Before('x()') void b(String s) {} }",
        'Unexpected parameter s of @Before',
      ),
      'around without proceeding join point': (
        "@Aspect() @Component() class A { @Around('x()') Object? b(JoinPoint jp) => null; }",
        'needs a ProceedingJoinPoint',
      ),
      'proceeding join point outside around': (
        "@Aspect() @Component() class A { @Before('x()') void b(ProceedingJoinPoint jp) {} }",
        'Only @Around advice',
      ),
      'generic introspected': (
        '@Introspected() class S<T> {}',
        'Generic @Introspected',
      ),
      'generic configurable': (
        '@Configurable() class S<T> {}',
        'Generic @Configurable',
      ),
      'duplicate bean names': (
        "@Component('same') class A {}\n@Component('same') class B {}",
        "Bean name 'same' is used by both",
      ),
      'alias clash': (
        "class B {}\n@Configuration() class C { @Bean(aliases: ['c']) B b() => B(); }",
        "Bean name 'c' is used by both",
      ),
      'lazy nullable': (
        'abstract interface class G {}\n'
            '@Component() class S { S(@Lazy() this.g); final G? g; }',
        'a lazy dependency cannot be nullable',
      ),
      'lazy collection': (
        'abstract interface class G {}\n'
            '@Component() class S { S(@Lazy() this.g); final List<G> g; }',
        'only a single bean can be injected lazily',
      ),
      'lazy value': (
        "@Component() class S { S(@Lazy() @Value('x') this.v); final String v; }",
        'only beans can be injected lazily',
      ),
      'lazy class with private members': (
        'class P { int _n = 0; }\n'
            '@Component() class S { S(@Lazy() this.p); final P p; }',
        'the lazy proxy must implement P',
      ),
      'lazy generic type': (
        'abstract interface class Repo<T> {}\n'
            '@Component() class S { S(@Lazy() this.r); final Repo<int> r; }',
        'generic types (Repo<...>) cannot be injected lazily',
      ),
      'lazy SDK type': (
        '@Component() class S { S(@Lazy() this.s); final StringBuffer s; }',
        'the lazy proxy must implement StringBuffer',
      ),
      'private constant condition': (
        'class _P implements Condition { const _P(); @override bool matches(ConditionContext c) => true; }\n'
            '@Component() @_P() class A {}',
        'private constant',
      ),
    };
    for (final MapEntry(key: name, value: (source, message)) in cases.entries) {
      test(name, () => _expectError(source, message));
    }

    test('two @ComponentScan in one file', () async {
      final result = await _build({
        'lib/src/beans.dart': r'''
import 'package:spring_core_dart/spring_core_dart.dart';
@ComponentScan() final BeanModule a = BeanModule('a', []);
@ComponentScan() final BeanModule b = BeanModule('b', []);
''',
      });
      expect(result.errors.join(), contains('Only one @ComponentScan'));
    });

    test('invalid @ComponentScan variable names', () async {
      for (final name in [r'$x', '_x']) {
        final result = await _build({
          'lib/src/beans.dart':
              "import 'package:spring_core_dart/spring_core_dart.dart';\n"
              "@ComponentScan() final BeanModule $name = BeanModule('x', []);",
        });
        expect(result.errors.join(), contains('must be public'), reason: name);
      }
    });
  });

  group('@BeanMethodAnnotation', () {
    const source = r"""
@BeanMethodAnnotation()
class Every {
  const Every(this.period, {this.name});
  final Duration period;
  final String? name;
}

class Plain {
  const Plain();
}

abstract interface class Job {
  @Every(Duration(minutes: 1))
  void tick();
}

@Component()
class Poller implements Job {
  @override
  void tick() {}

  @Every(Duration(seconds: 30), name: 'inbox')
  @Plain()
  Future<void> check(int attempt, [String? label]) async {}

  @Plain()
  void notMarked() {}
}

class Report {
  @Every(Duration(hours: 1))
  void hourly() {}
}

@Configuration()
class Config {
  @Bean()
  Report report() => Report();
}
""";

    test('marked methods become BeanDefinition.annotatedMethods', () async {
      final output = await _generate(source);
      expect(
        output,
        _has(
          "annotatedMethods: [_i1.BeanMethod<_i2.Poller>(r'check', "
          'parameterTypes: const [int, String], '
          'invoke: (bean, arguments) => Function.apply(bean.check, arguments), '
          'annotations: const [_i2.Every(Duration(seconds: 30), name: r\'inbox\'), _i2.Plain()])',
        ),
      );
      // Declared on the interface, implemented by the bean.
      expect(
        output,
        _has(
          "_i1.BeanMethod<_i2.Poller>(r'tick', "
          'invoke: (bean, arguments) => Function.apply(bean.tick, arguments), '
          'annotations: const [_i2.Every(Duration(minutes: 1))])',
        ),
      );
      expect(output, isNot(contains('notMarked')));
      // The return type of a @Bean method is scanned too.
      expect(
        output,
        _has(
          "annotatedMethods: [_i1.BeanMethod<_i2.Report>(r'hourly', "
          'invoke: (bean, arguments) => Function.apply(bean.hourly, arguments), '
          'annotations: const [_i2.Every(Duration(hours: 1))])]',
        ),
      );
    });

    test('the generated code compiles', () async {
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    });

    test('private, static and required named methods are rejected', () async {
      const every = r"""
@BeanMethodAnnotation()
class Every {
  const Every();
}
""";
      await _expectError(
        '$every@Component() class A { @Every() void _run() {} }',
        'must be a public instance method',
      );
      await _expectError(
        '$every@Component() class A { @Every() static void run() {} }',
        'must be a public instance method',
      );
      await _expectError(
        '$every@Component() class A { @Every() void run({required int n}) {} }',
        'must not have required named parameters',
      );
    });
  });

  test('proxy signatures carry the parameter names', () async {
    final output = await _generate(r"""
class Timed {
  const Timed();
}

@Service()
class Books {
  @Timed()
  String find(String isbn, {int page = 0}) => isbn;
}
""", proxyMode: ProxyMode.all);
    expect(
      output,
      _has(
        "parameterTypes: [r'String', r'int'], parameterNames: [r'isbn', r'page']",
      ),
    );
  });

  group('@Introspected for JSON', () {
    const source = r"""
enum Genre { fiction, science }

enum Stock {
  inStock('in_stock');

  const Stock(this.json);
  @JsonValue()
  final String json;
}

class Author {
  const Author(this.name, [this.born]);
  final String name;
  final int? born;
}

@Introspected()
class Book {
  const Book({
    required this.isbn,
    this.tags = const [],
    this.author,
    this.genre = Genre.fiction,
    this.stock = Stock.inStock,
    this.ratings = const {},
    this.extra = const {},
  });
  @JsonProperty('id')
  final String isbn;
  final List<String> tags;
  final Author? author;
  final Genre genre;
  final Stock stock;
  final Map<String, int> ratings;
  final Map<String, dynamic> extra;
}

class Money {
  Money(this.cents);
  @JsonCreator()
  Money.of({required int cents}) : this(cents);
  final int cents;
}

@Introspected(classes: [Money])
class Wallet {
  List<Money?> monies = [];
}

class Legacy {
  Legacy(this.v);
  factory Legacy.fromJson(Map<String, dynamic> json) => Legacy(json['v'] as String);
  final String v;
  Map<String, dynamic> toJson() => {'v': v};
}

@Introspected()
class Holder {
  Legacy? legacy;
}
""";

    test('types, constructors, JSON hints and used classes', () async {
      final output = await _generate(source);
      expect(
        output,
        _has(
          "_i1.BeanProperty<_i2.Book>(r'tags', type: List<String>, "
          'typeInfo: const _i1.ListType<String>(_i1.ClassType<String>()),',
        ),
      );
      expect(
        output,
        _has('typeInfo: const _i1.ClassType<_i2.Author>(nullable: true)'),
      );
      expect(
        output,
        _has(
          'typeInfo: _i1.EnumType<_i2.Stock>(_i2.Stock.values, '
          'jsonValue: (value) => value.json)',
        ),
      );
      expect(
        output,
        _has('typeInfo: const _i1.EnumType<_i2.Genre>(_i2.Genre.values)'),
      );
      expect(
        output,
        _has(
          'typeInfo: const _i1.MapType<String, dynamic>('
          '_i1.ClassType<String>(), _i1.DynamicType())',
        ),
      );
      // The constructor, with symbols for named parameters.
      expect(
        output,
        _has(
          "_i1.BeanParameter(r'isbn', type: const _i1.ClassType<String>(), "
          'symbol: #isbn, isRequired: true)',
        ),
      );
      expect(
        output,
        _has(
          'create: (positional, named) => '
          '(Function.apply(_i2.Book.new, positional, named) as _i2.Book)',
        ),
      );
      // Author (used by Book, same package) is introspected automatically,
      // with positional parameters.
      expect(output, _has('_i1.BeanIntrospection<_i2.Author>('));
      expect(
        output,
        _has(
          "_i1.BeanParameter(r'born', type: const _i1.ClassType<int>(nullable: true))",
        ),
      );
      // @Introspected(classes:) and @JsonCreator.
      expect(
        output,
        _has(
          'typeInfo: const _i1.ListType<_i2.Money?>('
          '_i1.ClassType<_i2.Money>(nullable: true))',
        ),
      );
      expect(
        output,
        _has('Function.apply(_i2.Money.of, positional, named) as _i2.Money'),
      );
      // A class with its own fromJson / toJson.
      expect(
        output,
        _has(
          'fromJson: (json) => _i2.Legacy.fromJson((json as Map<String, dynamic>))',
        ),
      );
      expect(output, _has('toJson: (bean) => bean.toJson()'));
      // Enums are described by EnumType, not introspected.
      expect(output, isNot(contains('BeanIntrospection<_i2.Genre>')));
    });

    test('the generated code compiles', () async {
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    });
  });
}
