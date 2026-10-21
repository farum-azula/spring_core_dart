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
        _has(r"final _i1.BeanModule $pkgBeans = _i1.BeanModule(r'pkgBeans',"),
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
        _has("bean.dep = r.optionalDependency<_i2.Dep>(name: r'dep');"),
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
          "_i1.BeanProperty<_i2.Form>(r'nick', type: String, nullable: true, get: (bean) => bean.nick, "
          'set: (bean, value) => bean.nick = (value as String?), annotations: const [_i1.Size(max: 3)])',
        ),
      );
      expect(
        output,
        _has(
          "_i1.BeanProperty<_i2.Form>(r'id', type: int, get: (bean) => bean.id)",
        ),
      );
      expect(
        output,
        _has(
          "r'computed', type: int, get: (bean) => bean.computed, set: (bean, value) => bean.computed = (value as int)",
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
      expect(output, _has('Object get targetObject => _target;'));
      expect(
        output,
        _has('List<_i2.PointcutAdvisor> get advisors => _invoker.advisors;'),
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
          "_i2.MethodSignature(name: r'plain', declaringType: r'Api', targetType: r'Impl', declaringTypes: [r'Impl', r'Api'], returnType: r'String', parameterTypes: [r'int', r'int', r'String'], annotations: [_i1.Note()], annotationTypes: [r'Note'], targetTypes: [r'Impl', r'Api'], targetAnnotations: [_i2.Service(), _i1.Note()], targetAnnotationTypes: [r'Service', r'Note'])",
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
        expect(output, contains('.springBootStarterLoggingAutoConfiguration]'));
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
        expect(
          output,
          _has(r"BeanModule $application = _i1.BeanModule(r'application'"),
        );
        expect(
          output,
          _has(
            'runApplication(List<String> args) => springApplication.run(args);',
          ),
        );
      },
    );
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
}
