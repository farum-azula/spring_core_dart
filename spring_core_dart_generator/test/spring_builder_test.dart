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

/// Drops whitespace, trailing commas (formatter choices) and import
/// prefixes (``, whose numbers depend on the order of first use).
String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
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
          "if (r.optionalDependency<Clock>(name: r'clock') case final value?) "
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
          "if (r.optionalDependency<Clock>(name: r'audit') case final value?) "
          '{ bean.audit = value; }',
        ),
      );
      // Required points are assigned as before.
      expect(output, _has("bean.size = r.value<int>(r'\${report.size:10}');"));
    },
  );

  test('a bean that cannot be proxied keeps its signatures and the reason', () async {
    final output = await _generate(r'''
class Counter {
  int _n = 0;
  @Timed()
  int next() => _n++;
}

class Timed {
  const Timed();
}

@Configuration()
class Config {
  @Bean()
  Counter counter() => Counter();
}
''', proxyMode: ProxyMode.all);
    expect(output, isNot(contains('class_\$Config_counterProxy')));
    expect(output, _has('aopProxy: AopProxyFactory.unavailable('));
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

  group('subclass proxies', () {
    const counter = r'''
class Counter {
  Counter(this.step, {this.name = 'n'});
  final int step;
  final String name;
  int _n = 0;
  int next() => _n += step;
  void reset() {
    _n = 0;
  }
  Future<int> later() async => _n;
  Duration wait([Duration d = const Duration(seconds: 1)]) => d;
  int get count => _n;
  set count(int value) {
    _n = value;
  }
  Counter operator +(Counter other) => this;
}
''';

    test('a component with private members and no interface', () async {
      final output = await _generate(
        '@Component() $counter',
        proxyMode: ProxyMode.all,
      );
      expect(
        output,
        _has(r'class _$CounterProxy extends Counter implements Advised {'),
      );
      expect(output, _has(r'_$CounterProxy(super.p0, {super.name});'));
      expect(output, _has(r'ProxyInvoker? _$invoker;'));
      expect(
        output,
        _has(
          r'_$CounterProxy _$advise(ProxyInvoker invoker) { _$invoker = invoker; return this; }',
        ),
      );
      expect(output, _has('Object get aopTarget => this;'));
      expect(
        output,
        _has(
          r'List<PointcutAdvisor> get aopAdvisors => _$invoker?.advisors ?? const [];',
        ),
      );
      expect(
        output,
        _has(
          r'int next() { final invoker = _$invoker; return invoker == null ? super.next() : (invoker.invoke(this, this, 0, const [], (args) => super.next()) as int); }',
        ),
      );
      expect(
        output,
        _has(
          r'void reset() { final invoker = _$invoker; if (invoker == null) { super.reset(); } else { invoker.invoke(this, this, 1, const [], (args) { super.reset(); return null; }); } }',
        ),
      );
      expect(output, _has('Future<int> later() { final invoker'));
      expect(
        output,
        _has(
          'invoker.invokeAsync<int>(this, this, 2, const [], (args) => super.later())',
        ),
      );
      // A constant default value is re-created, like an annotation.
      expect(
        output,
        _has('Duration wait([Duration d = const Duration(seconds: 1)])'),
      );
      expect(output, _has('super.wait((args[0] as Duration))'));
      expect(
        output,
        _has(
          r'int get count { final invoker = _$invoker; return invoker == null ? super.count : (invoker.invoke(',
        ),
      );
      expect(output, _has('set count(int value) { final invoker'));
      expect(output, _has('super.count = value;'));
      expect(
        output,
        isNot(contains('operator')),
        reason: 'operators are inherited',
      );
      expect(output, isNot(contains('toString')));
      expect(
        output,
        _has(
          'aopProxy: AopProxyFactory.subclass(signatures: const [MethodSignature(',
        ),
      );
      expect(
        output,
        _has(
          r'advise: (bean, invoker) => bean is _$CounterProxy ? bean._$advise(invoker) : null',
        ),
      );
      expect(output, _has(r'create: (r) => _$CounterProxy('));
    });

    test('a named constructor and a base class', () async {
      final output = await _generate(r'''
@Component()
class Named {
  @Autowired()
  Named.create([int size = 1]) : _size = size;
  final int _size;
  int size() => _size;
}

@Component()
base class Guarded {
  int _n = 0;
  int tick() => ++_n;
}
''', proxyMode: ProxyMode.all);
      expect(output, _has(r'_$NamedProxy([super.p0]) : super.create();'));
      expect(
        output,
        _has(r'final class _$GuardedProxy extends Guarded implements Advised'),
      );
      expect(
        output,
        _has(r'create: (r) => _$NamedProxy(r.optionalDependency<int>'),
      );
    });

    test('the generated code compiles', () async {
      expect(
        await _compileErrors({
          'lib/src/service.dart':
              '''
@Component() $counter
@Component()
class Named {
  @Autowired()
  Named.create([int size = 1]) : _size = size;
  final int _size;
  int size() => _size;
}
@Component()
base class Guarded {
  int _n = 0;
  int tick() => ++_n;
}
''',
        }),
        isEmpty,
      );
    });

    test('a class that cannot be extended fails the build', () async {
      await _expectError(
        '@Component() final class Locked { int _n = 0; int next() => _n++; }',
        'Locked cannot be proxied for AOP: Locked cannot be implemented by a '
            'generated class',
        proxyMode: ProxyMode.all,
      );
      await _expectError(
        '@Component() final class Locked { int _n = 0; int next() => _n++; }',
        'because Locked cannot be extended (it is final). Remove `final`, add '
            'an interface with the advised methods and inject the bean by it, '
            'or generate no proxy for it (aop_proxies: interfaces or none).',
        proxyMode: ProxyMode.all,
      );
      await _expectError(
        '@Component() interface class Api { int _n = 0; int next() => _n++; }',
        'Api cannot be extended (it is interface). Remove `interface`',
        proxyMode: ProxyMode.all,
      );
      await _expectError(
        '@Component() class Made { Made._(); factory Made() => Made._(); '
            'int _n = 0; int next() => _n++; }',
        'is created through the factory constructor',
        proxyMode: ProxyMode.all,
      );
      // Only `all` generates subclass proxies: `interfaces` keeps the
      // signatures and fails at startup when advice matches.
      final output = await _generate(
        '@Component() final class Locked { int _n = 0; int next() => _n++; }',
        proxyMode: ProxyMode.interfaces,
      );
      expect(output, _has('aopProxy: AopProxyFactory.unavailable('));
    });

    test('a @Bean method type cannot get a subclass proxy', () async {
      final output = await _generate('''
$counter
@Configuration()
class Config {
  @Bean()
  Counter counter() => Counter(1);
}
''', proxyMode: ProxyMode.all);
      expect(output, isNot(contains('extends Counter')));
      expect(output, _has('aopProxy: AopProxyFactory.unavailable('));
    });
  });

  group('argument binding', () {
    test('bound parameters are read from the bindings map', () async {
      final output = await _generate(r'''
class Timed {
  const Timed();
}

@Service()
class Svc {
  @Timed()
  int find(int id) => id;
}

@Aspect()
@Component()
class Audit {
  @Pointcut('args(id, ..)')
  void withId() {}

  @Before('@annotation(timed) && withId()')
  void tagged(JoinPoint jp, Timed timed, int id) {}

  @AfterReturning('withId() && this(proxy) && target(bean)', returning: 'result')
  void returned(int result, Svc bean, Object proxy, int id) {}

  @AfterThrowing('@within(timed)', throwing: 'error')
  void failed(Timed timed, StateError error) {}

  @Around('@target(timed) && args(id, ..)')
  Object? around(ProceedingJoinPoint pjp, Timed timed, int? id) => pjp.proceed();
}
''', proxyMode: ProxyMode.all);
      expect(
        output,
        _has(
          "aspect.tagged(joinPoint, (bindings[r'timed'] as Timed), (bindings[r'id'] as int)), "
          "bindings: {r'timed': AdviceBinding(r'Timed', (value) => value is Timed), "
          "r'id': AdviceBinding(r'int', (value) => value is int)}",
        ),
      );
      expect(
        output,
        _has(
          "aspect.returned((value as int), (bindings[r'bean'] as Svc), "
          "(bindings[r'proxy'] as Object), (bindings[r'id'] as int)), "
          "bindings: {r'bean': AdviceBinding(r'Svc', (value) => value is Svc), "
          "r'proxy': AdviceBinding(r'Object', (value) => value is Object), "
          "r'id': AdviceBinding(r'int', (value) => value is int)}, "
          'accepts: (value) => value is int',
        ),
      );
      expect(
        output,
        _has(
          "aspect.failed((bindings[r'timed'] as Timed), (value as StateError)), "
          "bindings: {r'timed': AdviceBinding(r'Timed', (value) => value is Timed)}, "
          'accepts: (value) => value is StateError',
        ),
      );
      expect(
        output,
        _has(
          "aspect.around((joinPoint as ProceedingJoinPoint), (bindings[r'timed'] as Timed), (bindings[r'id'] as int?)), "
          "bindings: {r'timed': AdviceBinding(r'Timed', (value) => value is Timed), "
          "r'id': AdviceBinding(r'int', (value) => value is int?)}",
        ),
      );
    });

    test(
      'advice and pointcuts of superclasses and mixins are inherited',
      () async {
        final output = await _generate(r'''
class Timed {
  const Timed();
}

abstract class BaseAspect {
  @Pointcut('within(Svc)')
  void svc() {}

  @Before('svc() && @annotation(timed)')
  void inherited(Timed timed) {}

  @After('svc()')
  void overridden() {}
}

mixin Logging {
  @AfterReturning('svc()')
  void logged(Object? result) {}
}

@Aspect()
@Component()
class Child extends BaseAspect with Logging {
  @override
  void overridden() {}

  @Around('svc()')
  Object? own(ProceedingJoinPoint pjp) => pjp.proceed();
}
''');
        expect(
          output,
          _has(
            "methodName: r'inherited', invoke: (aspect, joinPoint, value, bindings) => aspect.inherited((bindings[r'timed'] as Timed)), "
            "bindings: {r'timed': AdviceBinding(r'Timed', (value) => value is Timed)}",
          ),
        );
        expect(output, _has("methodName: r'logged'"));
        expect(output, _has("methodName: r'own'"));
        expect(output, _has("pointcuts: {r'svc': r'within(Svc)'}"));
        // The override without @After is not advice.
        expect(output, isNot(contains("methodName: r'overridden'")));
      },
    );

    test(
      'a parameter of another class\'s pointcut is bound at runtime',
      () async {
        final output = await _generate(r'''
@Aspect()
@Component()
class Audit {
  @Before('Common.withId()')
  void before(int id) {}
}
''');
        expect(output, _has("aspect.before((bindings[r'id'] as int))"));
      },
    );

    test('binding mistakes fail the build', () async {
      await _expectError(
        "@Aspect() @Component() class A { @Before('execution(* *(..))') void b(String s) {} }",
        'Unexpected parameter s of @Before advice b: the pointcut does not '
            'bind it. Bind it with @annotation(s), @within(s), @target(s), '
            'this(s), target(s) or args(s, ..).',
      );
      await _expectError(
        "@Aspect() @Component() class A { @AfterReturning('execution(* *(..))', returning: 'r') void b(Object? r, String s) {} }",
        'or name it in `returning:`.',
      );
      await _expectError(
        "@Aspect() @Component() class A { @Before('@annotation(timed)') void b() {} }",
        "The pointcut of @Before advice b binds 'timed', which is not a "
            'parameter of the advice method. Add a parameter named timed, or '
            'match by type with a type name (starting with an uppercase '
            'letter).',
      );
      await _expectError(
        "@Aspect() @Component() class A { @AfterThrowing('x()', throwing: 'e') void b(Object? error) {} }",
        "@AfterThrowing advice b names the throwing parameter 'e', which it "
            'does not declare.',
      );
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
        _has(r"BeanModule get $pkgBeans => BeanModule(r'pkgBeans',"),
      );
      expect(output, _has("name: r'apiImpl'"));
      expect(output, _has("source: r'package:pkg/src/service.dart#ApiImpl'"));
      expect(output, _has('types: const [ApiImpl, Api]'));
      expect(
        output,
        _has(
          "ApiImpl(r.dependency<Other>(name: r'dep'), "
          "other: r.optionalDependency<Other>(qualifier: r'x', name: r'other'),)",
        ),
      );
      expect(output, _has("Dependency(Other, name: r'dep')"));
      expect(
        output,
        _has(
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
        _has("r.dependency<Custom>(qualifier: r'custom', name: r'c')"),
      );
      expect(
        output,
        _has("r.dependency<Plain>(qualifier: r'plain', name: r'plain')"),
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
      expect(output, _has('r.optionalDependencyList<Plugin>() ?? <Plugin>[]'));
      // A Set keeps registration order, like Spring (only lists are sorted).
      expect(output, _has('r.optionalDependencyMap<Plugin>()?.values.toSet()'));
      expect(
        output,
        _has('r.optionalDependencyMap<Plugin>() ?? <String, Plugin>{}'),
      );
      expect(output, _has('r.optionalDependencyMap<Plugin>()'));
      // The provider resolves for the injection point, named like it.
      expect(output, _has("r.provider<Plugin>(name: r'provider')"));
      expect(output, _has(r"r.value<int>(r'${port:80}')"));
      expect(output, _has(r"r.optionalValue<Duration>(r'${maybe}')"));
      expect(output, _has('Dependency.collection(Plugin, optional: true)'));
      expect(output, _has('Dependency.map(Plugin, optional: true)'));
      expect(output, _has("Dependency.provider(Plugin, name: r'provider')"));
      expect(output, _has(r"Dependency.value(r'${port:80}')"));
      expect(output, _has(r"Dependency.value(r'${maybe}', optional: true)"));
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
          "if (r.optionalDependency<Dep>(name: r'dep') case final value?) { bean.dep = value; }",
        ),
      );
      expect(
        output,
        _has("bean.inherited = r.dependency<Dep>(name: r'inherited');"),
      );
      expect(
        output,
        _has(
          r"bean.wire(r.dependency<Dep>(name: r'dep'), x: r.optionalValue<int>(r'${x:1}') ?? 0,);",
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
        expect(output, _has('create: (r) => Config.shut()'));
        expect(
          output,
          _has(
            "(r.dependency<Config>(qualifier: r'config') "
            r"as _$ConfigConfiguration)._$closable(r)",
          ),
        );
        expect(output, _has("const ProfileCondition([r'cloud'])"));
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
      expect(output, _has('factoryObjectTypes: const [Product]'));
      // The raw `FactoryBean` (instantiated to bounds) finds every factory.
      expect(
        output,
        _has(
          'types: const [ProductFactory, FactoryBean<Product>, '
          'FactoryBean<Object>]',
        ),
      );
      expect(
        output,
        _has(
          "EventListenerMethod.of<Listener, Shipped>(r'Listener.onApplicationEvent', "
          '(bean, event) {bean.onApplicationEvent(event); return null;}, order: 5,)',
        ),
      );
      expect(
        output,
        _has(
          "EventListenerMethod.of<Listener, Placed>(r'Listener.onPlaced', "
          '(bean, event) => bean.onPlaced(event), order: 1, condition: isImportant,)',
        ),
      );
      expect(
        output,
        _has("EventListenerMethod<Listener>.matching(id: r'custom',"),
      );
      expect(output, _has('candidate is Placed || candidate is Shipped'));
      expect(output, _has('condition: Conditions.always'));
      expect(
        output,
        _has(
          'return bean.onTyped((EventListenerMethod.match(event, (candidate) => candidate is Placed) as Object));',
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
          "const OnMode(Mode.on, names: [r'a'], weights: {r'w': 1.5}, "
          'flags: {true}, type: String, nested: Nested(), check: OnMode.always, nothing: null)',
        ),
      );
      expect(output, _has('const OnMode(Mode.off)'));
      expect(output, _has('Custom()'));
      expect(output, _has("source: r'package:pkg/src/service.dart#Imported'"));
      expect(
        output,
        _has("r.dependency<Imported>(qualifier: r'imported').text()"),
      );
      expect(
        output,
        // The declaring class's conditions gate its property sources.
        _has(
          "PropertySourceDeclaration(const [r'file:a.properties'], "
          "conditions: [ConditionGroup(r'package:pkg/src/service.dart#Config', [const OnMode(",
        ),
      );
      expect(
        output,
        _has(
          r"PropertySourceDeclaration(const [r'${dir}/b.yml'], name: r'b', "
          'ignoreResourceNotFound: true, factory: YamlFactory(), conditions: [',
        ),
      );
      expect(
        output,
        _has(
          'configurers: {Screen: (bean, r) {final target = (bean as Screen);',
        ),
      );
      expect(output, _has(r"target.title = r.value<String>(r'${title}');"));
      expect(
        output,
        _has("target.wire(r.dependency<Config>(name: r'config'));"),
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
      expect(output, _has('BeanIntrospection<Form>('));
      expect(
        output,
        _has(
          "BeanProperty<Form>(r'nick', type: String, nullable: true, "
          'typeInfo: const ClassType<String>(nullable: true), get: (bean) => bean.nick, '
          'set: (bean, value) => bean.nick = (value as String?), annotations: const [Size(max: 3)])',
        ),
      );
      expect(
        output,
        _has(
          "BeanProperty<Form>(r'id', type: int, typeInfo: const ClassType<int>(), get: (bean) => bean.id)",
        ),
      );
      expect(
        output,
        _has(
          "r'computed', type: int, typeInfo: const ClassType<int>(), get: (bean) => bean.computed, set: (bean, value) => bean.computed = (value as int)",
        ),
      );
      expect(output, _has("annotations: const [Marker()]"));
      expect(output, _has("r'baseName'"));
      expect(output, isNot(contains('callback')));
      expect(
        output,
        _has(
          "BeanMethod<Form>(r'greet', returnType: String, parameterTypes: const [String, int], "
          'invoke: (bean, arguments) => Function.apply(bean.greet, arguments))',
        ),
      );
      expect(output, _has("BeanMethod<Form>(r'baseMethod',"));
      expect(
        output,
        _has("BeanMethod<Form>(r'later', returnType: Future<void>,"),
      );
      for (final skipped in ["r'configure'", "r'typed'", "r'util'"]) {
        expect(output, isNot(contains(skipped)));
      }
      expect(output, _has('instantiate: () => Form()'));
      final noCtor = output.substring(
        output.indexOf('BeanIntrospection<NoCtor>'),
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
      expect(output, _has("Settings(r.value<String>(r'\${app.name:demo}'))"));
      expect(
        output,
        _has(
          "Repository(r.dependency<Settings>(name: r'settings'), "
          "backup: r.optionalDependency<Settings>(qualifier: r'settings', "
          "name: r'backup'))",
        ),
      );
      expect(output, _has('create: (r) => Clock()'));
      // Private named parameter: called with its public name; the unnamed
      // `new(...)` constructor wins over `new withDefaults(...)`.
      expect(
        output,
        _has(
          "Gateway(r.dependency<Repository>(name: r'repository'), "
          "retries: r.dependency<int>(name: r'retries'))",
        ),
      );
      expect(
        output,
        _has("Picked.create(r.dependency<Clock>(name: r'clock'))"),
      );
      // A full-mode @Configuration: created as its generated subclass.
      expect(
        output,
        _has(
          r"_$ConfigConfiguration(r, r.dependency<Settings>(name: r'settings'))",
        ),
      );
      expect(output, _has(r'class _$GatewayProxy implements Api'));
      expect(
        output,
        _has(
          "BeanProperty<Form>(r'email', type: String, "
          'typeInfo: const ClassType<String>(), '
          'get: (bean) => bean.email, '
          'set: (bean, value) => bean.email = (value as String))',
        ),
      );
      expect(output, _has("BeanProperty<Form>(r'age', type: int"));
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

  @AfterReturning('all()')
  void someResult(Object result) {}

  @AfterThrowing('all()')
  void failed(StateError error) {}

  @Around('@annotation(Marker)')
  Object? around(ProceedingJoinPoint pjp) => pjp.proceed();
}
''', proxyMode: ProxyMode.all);
      expect(output, _has('aspect: AspectMetadata<Audit>('));
      expect(
        output,
        _has(
          "kind: AdviceKind.before, pointcut: r'all()', methodName: r'before', invoke: (aspect, joinPoint, value, bindings) => aspect.before(joinPoint))",
        ),
      );
      expect(
        output,
        _has('invoke: (aspect, joinPoint, value, bindings) => aspect.after()'),
      );
      expect(
        output,
        _has(
          "aspect.returned(joinPoint, (value as String)), accepts: (value) => value is String",
        ),
      );
      expect(output, _has('aspect.anyResult((value as Object?))'));
      // A void method returns null: a non-nullable Object skips it.
      expect(
        output,
        _has(
          'aspect.someResult((value as Object)), '
          'accepts: (value) => value is Object',
        ),
      );
      expect(
        output,
        _has('accepts: (value) => value is StateError'.replaceAll('', '')),
      );
      expect(output, _has('aspect.around((joinPoint as ProceedingJoinPoint))'));
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
        _has('class _\$ImplProxy implements Impl, Api, Advised {'),
      );
      expect(output, _has('_\$ImplProxy(this._target, this._invoker);'));
      expect(output, _has('Object get aopTarget => _target;'));
      expect(
        output,
        _has('List<PointcutAdvisor> get aopAdvisors => _invoker.advisors;'),
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
          'Future<int> later() => _invoker.invokeAsync<int>(this, _target, 3, const [], (args) => _target.later());',
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
          "MethodSignature(name: r'plain', declaringType: r'Api', targetType: r'Impl', declaringTypes: [r'Impl', r'Api'], returnType: r'String', parameterTypes: [r'int', r'int', r'String'], parameterNames: [r'a', r'b', r'c'], annotations: [Note()], annotationTypes: [r'Note'], targetTypes: [r'Impl', r'Api'], targetAnnotations: [Service(), Note()], targetAnnotationTypes: [r'Service', r'Note'])",
        ),
      );
      expect(output, _has('kind: MemberKind.getter'));
      expect(output, _has('kind: MemberKind.setter'));
      expect(output, _has("parameterTypes: [r'Function', r'Record']"));
      expect(
        output,
        _has(
          'create: (target, invoker) => _\$ImplProxy((target as Impl), invoker)',
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
        _has('Future<T> run<T>(T value) => _invoker.invokeAsync<T>('),
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
        contains(r'class_$WithPrivateProxyimplementsApi,'),
        reason: 'class with private members: interface only',
      );
      expect(all, contains(r'class_$PlainProxyimplementsPlain,'));
      expect(all, contains(r'class_$BothProxyimplementsBoth,Base,Api,'));
      // Operators cannot be forwarded: a subclass proxy inherits them.
      expect(
        all,
        contains(r'class_$OpsProxyextendsOpsimplementsAdvised{'),
        reason: 'operators',
      );
      expect(all, isNot(contains('operator')));
      expect(
        all,
        contains(r'class_$OnlyOpsProxyextendsOnlyOpsimplementsAdvised{'),
      );
      // A constant default value is re-created.
      expect(
        all,
        contains(r'class_$ComplexDefaultProxyimplementsComplexDefault,Api,'),
        reason: 'non-literal default',
      );
      expect(all, contains('run([Durationd=constDuration(seconds:1)])'));
      // A member the subclass cannot override stays inherited.
      expect(
        all,
        contains(r'class_$UntypedProxyextendsUntypedimplementsAdvised{'),
        reason: 'generic function type parameter',
      );
      expect(all, isNot(contains('typed(')));
      for (final excluded in ['Product', 'Processor', 'Config']) {
        expect(all, isNot(contains('_\$${excluded}Proxy')), reason: excluded);
      }
      // The bean type is inferred from the method body (`Both()`).
      expect(all, contains(r'class_$Config_apiProxyimplementsBoth,Base,Api,'));
      expect(all, isNot(contains(r'_$Config_textProxy')), reason: 'SDK types');

      final interfaces = await _generate(
        source,
        proxyMode: ProxyMode.interfaces,
      );
      expect(interfaces, contains(r'class_$BothProxyimplementsBase,Api,'));
      expect(interfaces, isNot(contains(r'_$PlainProxy')));
      expect(
        interfaces,
        contains(r'class_$Config_apiProxyimplementsBase,Api,'),
      );

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
          'class _\$PricingLazy implements Pricing { '
          '_\$PricingLazy(this._resolve); '
          'final Pricing Function() _resolve; '
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
        _has("_\$PricingLazy(r.lazyDependency<Pricing>(name: r'self'))"),
      );
      expect(
        output,
        _has(
          "bean.other = _\$PricingLazy(r.lazyDependency<Pricing>(name: r'other'));",
        ),
      );
      expect(output, _has("Dependency.lazy(Pricing, name: r'self')"));
      expect(output, _has("Dependency.lazy(Pricing, name: r'other')"));
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
          "clock: r.optionalDependency<Clock>(name: r'clock') ?? "
          'const SystemClock()',
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
      expect(output, _has("Dependency(int, optional: true, name: r'retries')"));
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
      expect(output, _has("bean.clock = r.dependency<Clock>(name: r'clock');"));
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
          "BeanDefinition<CloudData>(name: r'cloudData', "
          "source: r'package:pkg/src/service.dart#CloudData', "
          "types: const [CloudData], conditions: [ConditionGroup(r'package:pkg/src/service.dart#CloudData', "
          "[ConditionGroup(r'package:pkg/src/service.dart#CloudConfig', [const ProfileCondition([r'cloud'])])])]",
        ),
      );
      expect(
        output,
        _has(
          "PropertySourceDeclaration(const [r'file:cloud.properties'], "
          "conditions: [ConditionGroup(r'package:pkg/src/service.dart#CloudConfig', [const ProfileCondition([r'cloud'])])])",
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
      contains("r'application.properties':EmbeddedResource.text("),
    );
    expect(output, contains("r'img/logo.bin':EmbeddedResource.base64("));
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
        // discovered, listed by package (SpringApplication sorts them).
        expect(
          output,
          contains('autoConfigurations:[springBootAutoConfiguration,'),
        );
        // Every starter of the workspace is discovered.
        for (final starter in [
          'springBootStarterLoggingAutoConfiguration',
          'springBootStarterSchedulingAutoConfiguration',
          'springBootStarterCacheAutoConfiguration',
        ]) {
          expect(output, contains(starter));
        }
        expect(
          output,
          contains(
            'runApplicationAsync(List<String>args)=>springApplication.runAsync(args)',
          ),
        );
        expect(output, _has("BeanDefinition<CliRunner>(name: r'cliRunner'"));
        expect(output, _has("name: r'deep'"));
        // @ConfigurationProperties: a bean plus introspection metadata.
        expect(output, _has("name: r'dbProps'"));
        expect(output, _has('BeanIntrospection<'));
        expect(output, contains("ConfigurationProperties(r'db')"));
        // Getters, so a hot reload sees the beans of the new code.
        expect(
          output,
          _has(r"BeanModule get $application => BeanModule(r'application'"),
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
            'reloadApplication(ConfigurableApplicationContext running, '
            '{bool runners = true}) => '
            'springApplication.reload(running, runners: runners);',
          ),
        );
        expect(
          output,
          _has(
            'reloadApplicationAsync(ConfigurableApplicationContext '
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

  group('@ConfigurationProperties constructor binding', () {
    const boot = "import 'package:spring_boot_dart/spring_boot_dart.dart';\n";

    test('the only constructor with parameters is bound from properties, '
        'not beans', () async {
      const db = '''
@ConfigurationProperties('db')
class DbProperties {
  const DbProperties(
    this.url, {
    @DefaultValue('10') required this.maxSize,
    this.hosts = const [],
    this.owner,
  });
  final String url;
  final int maxSize;
  final List<String> hosts;
  final String? owner;
}
''';
      final output = await _generate('', extra: {'lib/src/db.dart': boot + db});
      // Spring Boot's ConstructorBound: no String / int / List beans.
      expect(
        output,
        matches(
          RegExp(
            r"create:\(r\)=>ConstructorBound\.from<DbProperties>"
            r"\(r,r'dbProperties'\)",
          ),
        ),
      );
      expect(output, isNot(contains('Dependency(')));
      // The introspection carries the same constructor, with @DefaultValue.
      expect(output, contains("DefaultValue(r'10')"));
      expect(output, contains('BeanConstructor<'));
      expect(await _compileErrors({'lib/src/db.dart': boot + db}), isEmpty);
    });

    test('a named single constructor is the bound one', () async {
      final output = await _generate(
        '',
        extra: {
          'lib/src/mail.dart':
              '''
$boot
@ConfigurationProperties('mail')
class MailProperties {
  MailProperties.of(this.host, [this.port = 25]);
  final String host;
  final int port;
}
''',
        },
      );
      expect(output, contains('ConstructorBound.from<'));
      expect(output, contains('MailProperties.of,'));
    });

    test('mutable classes keep the no-argument constructor', () async {
      final output = await _generate(
        '',
        extra: {
          'lib/src/shop.dart':
              '''
$boot
@ConfigurationProperties('shop')
class ShopProperties {
  String name = '';
}
''',
        },
      );
      expect(output, contains('ShopProperties()'));
      expect(output, isNot(contains('ConstructorBound')));
    });
  });

  group('asynchronous lifecycle methods', () {
    test('are awaited by async callbacks (refreshAsync / closeAsync)', () async {
      final output = await _generate(r'''
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
        _has(
          'postConstruct: (bean) async { await bean.warmUp(); bean.check(); }',
        ),
      );
      expect(output, _has('preDestroy: (bean) async { await bean.flush(); }'));
      expect(output, _has('initMethod: (bean) async { await bean.open(); }'));
      expect(
        output,
        _has('destroyMethod: (bean) async { await bean.close(); }'),
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
      'async lifecycle method of a @Configurable': (
        '@Configurable() class A { @PreDestroy() Future<void> close() async {} }',
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
        "@Aspect() @Component() class A { @Before('execution(* *(..))') void b(String s) {} }",
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
          "annotatedMethods: [BeanMethod<Poller>(r'check', "
          'parameterTypes: const [int, String], '
          'invoke: (bean, arguments) => Function.apply(bean.check, arguments), '
          'annotations: const [Every(Duration(seconds: 30), name: r\'inbox\'), Plain()])',
        ),
      );
      // Declared on the interface, implemented by the bean.
      expect(
        output,
        _has(
          "BeanMethod<Poller>(r'tick', "
          'invoke: (bean, arguments) => Function.apply(bean.tick, arguments), '
          'annotations: const [Every(Duration(minutes: 1))])',
        ),
      );
      expect(output, isNot(contains('notMarked')));
      // The return type of a @Bean method is scanned too.
      expect(
        output,
        _has(
          "annotatedMethods: [BeanMethod<Report>(r'hourly', "
          'invoke: (bean, arguments) => Function.apply(bean.hourly, arguments), '
          'annotations: const [Every(Duration(hours: 1))])]',
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
          "BeanProperty<Book>(r'tags', type: List<String>, "
          'typeInfo: const ListType<String>(ClassType<String>()),',
        ),
      );
      expect(output, _has('typeInfo: const ClassType<Author>(nullable: true)'));
      expect(
        output,
        _has(
          'typeInfo: EnumType<Stock>(Stock.values, '
          'jsonValue: (value) => value.json)',
        ),
      );
      expect(output, _has('typeInfo: const EnumType<Genre>(Genre.values)'));
      expect(
        output,
        _has(
          'typeInfo: const MapType<String, dynamic>('
          'ClassType<String>(), DynamicType())',
        ),
      );
      // The constructor, with symbols for named parameters.
      expect(
        output,
        _has(
          "BeanParameter(r'isbn', type: const ClassType<String>(), "
          'symbol: #isbn, isRequired: true)',
        ),
      );
      expect(
        output,
        _has(
          'create: (positional, named) => '
          '(Function.apply(Book.new, positional, named) as Book)',
        ),
      );
      // Author (used by Book, same package) is introspected automatically,
      // with positional parameters.
      expect(output, _has('BeanIntrospection<Author>('));
      expect(
        output,
        _has(
          "BeanParameter(r'born', type: const ClassType<int>(nullable: true))",
        ),
      );
      // @Introspected(classes:) and @JsonCreator.
      expect(
        output,
        _has(
          'typeInfo: const ListType<Money?>('
          'ClassType<Money>(nullable: true))',
        ),
      );
      expect(
        output,
        _has('Function.apply(Money.of, positional, named) as Money'),
      );
      // A class with its own fromJson / toJson.
      expect(
        output,
        _has(
          'fromJson: (json) => Legacy.fromJson((json as Map<String, dynamic>))',
        ),
      );
      expect(output, _has('toJson: (bean) => bean.toJson()'));
      // Enums are described by EnumType, not introspected.
      expect(output, isNot(contains('BeanIntrospection<Genre>')));
    });

    test('the generated code compiles', () async {
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    });
  });

  group('@InterfaceProxy', () {
    const source = r"""
@InterfaceProxy(primary: true)
class Remote {
  const Remote(this.name);
  final String name;
}

class Tag {
  const Tag(this.value);
  final String value;
}

class Book {
  const Book(this.isbn, {this.title = ''});
  final String isbn;
  final String title;
}

@Remote('catalog')
abstract interface class CatalogClient {
  @Tag('find')
  Future<Book> find(@Tag('isbn') String isbn, {int page = 0});

  Future<List<Book>> all();

  Future<Book> create(Book book);

  Future<void> remove(String isbn);

  String version();

  void ping();

  Stream<Book> changes();
}
""";

    test('a generated implementation forwarding to the handler', () async {
      final output = await _generate(source);
      expect(
        output,
        _has(r'class _$CatalogClientImpl implements CatalogClient {'),
      );
      expect(
        output,
        _has(r'static _$CatalogClientImpl $create(DependencyResolver r) {'),
      );
      expect(
        output,
        _has(
          r"final metadata = InterfaceMetadata<CatalogClient>(typeName: r'CatalogClient', "
          r"annotations: const [Remote(r'catalog')],",
        ),
      );
      expect(
        output,
        _has(
          '@override Future<Book> find(String isbn, {int page = 0}) => '
          'retypeFuture<Book>(_handler.invoke(_metadata.methods[0], [isbn, page]));',
        ),
      );
      expect(
        output,
        _has(
          "BeanParameter(r'isbn', type: const ClassType<String>(), isRequired: true, "
          "annotations: const [Tag(r'isbn')])",
        ),
      );
      expect(
        output,
        _has(
          "BeanParameter(r'page', type: const ClassType<int>(), symbol: #page)",
        ),
      );
      expect(
        output,
        _has(
          'call: (target, arguments) => (target as CatalogClient).find('
          '(arguments[0] as String), page: (arguments[1] as int))',
        ),
      );
      expect(
        output,
        _has(
          'returnType: const ListType<Book>(ClassType<Book>()), isFuture: true',
        ),
      );
      expect(
        output,
        _has(
          '@override String version() => (_handler.invoke(_metadata.methods[4], const []) as String);',
        ),
      );
      expect(
        output,
        _has(
          '@override void ping() { _handler.invoke(_metadata.methods[5], const []); }',
        ),
      );
      // A sync generic result (e.g. a Feign EventStream<T>): described with
      // its type argument and cast.
      expect(
        output,
        _has(
          'returnType: const GenericType<Stream<Book>>([ClassType<Book>()])',
        ),
      );
      expect(
        output,
        _has(
          '@override Stream<Book> changes() => '
          '(_handler.invoke(_metadata.methods[6], const []) as Stream<Book>);',
        ),
      );
      // The bean: primary (from @InterfaceProxy(primary: true)), created by
      // the implementation.
      expect(
        output,
        _has(
          "BeanDefinition<CatalogClient>(name: r'catalogClient', "
          "source: r'package:pkg/src/service.dart#CatalogClient', "
          'types: const [CatalogClient], primary: true,',
        ),
      );
      expect(output, _has(r'create: (r) => _$CatalogClientImpl.$create(r)'));
      // Book, used by the interface, is introspected for JSON.
      expect(output, _has('BeanIntrospection<Book>('));
    });

    test('the generated code compiles', () async {
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    });

    test('primary and qualifiers of the annotation itself, like '
        '@FeignClient(primary: false, qualifiers: [...])', () async {
      final output = await _generate(r"""
@InterfaceProxy(primary: true)
class Remote {
  const Remote(this.name, {this.primary = true, this.qualifiers = const []});
  final String name;
  final bool primary;
  final List<String> qualifiers;
}

@Remote('catalog', primary: false, qualifiers: ['books', 'catalogFeign'])
abstract interface class CatalogClient {
  Future<String> ping();
}

@Remote('stock')
abstract interface class StockClient {
  Future<String> ping();
}
""");
      expect(
        output,
        _has(
          "BeanDefinition<CatalogClient>(name: r'catalogClient', "
          "source: r'package:pkg/src/service.dart#CatalogClient', "
          'types: const [CatalogClient], qualifiers: const {',
        ),
      );
      expect(output, _has("r'books', r'catalogFeign'"));
      expect(
        output,
        _has(
          "BeanDefinition<StockClient>(name: r'stockClient', "
          "source: r'package:pkg/src/service.dart#StockClient', "
          'types: const [StockClient], primary: true,',
        ),
      );
    });

    test('rejects what cannot be implemented', () async {
      const remote = r"""
@InterfaceProxy()
class Remote {
  const Remote();
}
""";
      await _expectError(
        '$remote@Remote() class NotAbstract {}',
        'must be abstract',
      );
      await _expectError(
        '$remote@Remote() abstract class WithBody { int count() => 1; }',
        'has a body',
      );
      await _expectError(
        '$remote@Remote() abstract class WithGetter { int get count; }',
        'only methods are supported',
      );
      await _expectError(
        '$remote@Remote() abstract class Generic { T read<T>(); }',
        'must not be generic',
      );
    });
  });

  group('validation', () {
    test('constraints on unsupported types fail the build', () async {
      final cases = <String, (String, String)>{
        'Size on int': (
          '@Introspected() class Form { @Size(max: 3) int age = 0; }',
          '@Size on Form.age: it validates String, Iterable, Map values, not '
              'int',
        ),
        'NotBlank on a list': (
          '@Introspected() class Form { @NotBlank() List<String> tags = []; }',
          '@NotBlank on Form.tags',
        ),
        'Past on a string': (
          '@Introspected() class Form { @Past() String? day; }',
          '@Past on Form.day: it validates DateTime values, not String',
        ),
        'AssertTrue on an int': (
          '@Introspected() class Form { @AssertTrue() int? ok; }',
          '@AssertTrue on Form.ok',
        ),
        'Min on an Object': (
          '@Introspected() class Form { @Min(1) Object? any; }',
          '@Min on Form.any',
        ),
        'constructor parameter': (
          '@Introspected() class Form { Form(@Email() this.id); final int id; }',
          '@Email on Form(id)',
        ),
        'method parameter': (
          '@Service() @Validated() class Users { '
              'void save(@NotBlank() int id) {} }',
          '@NotBlank on Users.save(id)',
        ),
        'return value': (
          '@Service() @Validated() class Users { '
              '@Size(max: 2) int count() => 1; }',
          '@Size on Users.count (return value)',
        ),
      };
      for (final MapEntry(key: name, value: (source, message))
          in cases.entries) {
        final result = await _build({
          'lib/src/beans.dart': _scan,
          'lib/src/service.dart': '$_header$source',
        }, proxyMode: ProxyMode.all);
        expect(result.succeeded, isFalse, reason: name);
        expect(result.errors.join('\n'), contains(message), reason: name);
      }
    });

    test('supported types build', () async {
      final output = await _generate(r'''
@Introspected()
class Form {
  @NotBlank() @Matches('[a-z]+') @Email() String? name;
  @Size(max: 3) @NotEmpty() Map<String, int> scores = {};
  @Size(max: 3) Set<int> ids = {};
  @Min(1) @Digits(integer: 3, fraction: 0) int age = 1;
  @DecimalMax('9.5') double rate = 0;
  @Positive() BigInt big = BigInt.one;
  @Max(10) String numeric = '1';
  @FutureOrPresent() DateTime? start;
  @AssertFalse() bool locked = false;
  @NotNull() Object? any;
  @Size(max: 1) dynamic loose;
}

@Service()
@Validated()
class Users {
  @NotBlank()
  Future<String> find(@Min(1) int id) async => 'x';
}
''', proxyMode: ProxyMode.all);
      expect(output, contains('Form'));
    });

    test('proxy signatures carry the parameter annotations', () async {
      final output = await _generate(r"""
@Service()
@Validated()
class Users {
  @NotBlank()
  String register(@NotBlank() @Email() String email, int age, {@Valid() Object? extra}) => email;
}
""", proxyMode: ProxyMode.all);
      expect(
        output,
        _has(
          'parameterAnnotations: [[NotBlank(), Email()], [], '
          '[Valid()]]',
        ),
      );
    });

    test('the generated code compiles', () async {
      expect(
        await _compileErrors({
          'lib/src/service.dart': r"""
abstract interface class Registration {
  String register(@NotBlank() String email, {@Min(18) int age = 18});
}

@Service()
@Validated()
class DefaultRegistration implements Registration {
  @override
  @Size(max: 20)
  String register(String email, {int age = 18}) => email;
}
""",
        }),
        isEmpty,
      );
    });
  });

  group('container metadata', () {
    const source = r'''
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
      final output = await _generate(source);
      // `Store` (a raw type) means `Store<dynamic>`: every Store bean.
      expect(
        output,
        _has(
          'types: const [UserStore, Store<User>, '
          'Store<dynamic>]',
        ),
      );
      expect(output, _has('r.optionalDependencyList<Store<dynamic>>()'));
      expect(output, _has("r.provider<UserStore>(name: r'factory')"));
    });

    test('@Bean factory method, candidacy and lifecycle names', () async {
      final output = await _generate(source);
      expect(output, _has('defaultCandidate: false'));
      expect(
        output,
        _has("factoryBeanName: r'config', factoryMethodName: r'audit'"),
      );
      expect(output, _has("initMethodName: r'open'"));
      expect(output, _has("destroyMethodName: r'(inferred)'"));
      // A static @Bean method has no factory bean, like in Spring.
      final plain = output.substring(output.indexOf("name:r'plain'"));
      expect(
        plain.substring(0, plain.indexOf('create:')),
        allOf(
          contains("factoryMethodName:r'plain'"),
          isNot(contains('factoryBeanName')),
        ),
      );
      expect(output, _has("destroyMethodName: r'close'"));
    });

    test('annotations that can be re-created', () async {
      final output = await _generate(source);
      expect(output, _has('annotations: const [Component(), Marker(1)]'));
      // A top-level constant is re-created through its constructor.
      expect(
        output,
        _has('annotations: const [Component(), Marker(2), Marker(0)]'),
      );
      expect(output, _has('Marker(3)'));
      expect(output, isNot(contains('_Hidden')));
    });

    test('superclass members first, fields before methods', () async {
      final output = await _generate(source);
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
      final output = await _generate(source);
      expect(
        output,
        _has(
          'configurablePostConstruct: {Screen: (bean) {'
          'final target = (bean as Screen); target.init();}}',
        ),
      );
      expect(
        output,
        _has(
          'configurablePreDestroy: {Screen: (bean) {'
          'final target = (bean as Screen); target.dispose();}}',
        ),
      );
    });

    test('the generated code compiles', () async {
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    });
  });

  group('full-mode @Configuration', () {
    const source = r"""
class Calculator {}
class Pricing { Pricing(this.calculator); final Calculator calculator; }
class Id {}

@Configuration()
class AppConfig {
  AppConfig.named(this.prefix, [this.count = 2]);
  final Calculator prefix;
  final int count;

  @Bean()
  Calculator calculator() => Calculator();

  @Bean()
  Pricing pricing(Calculator calc, {int n = 3,
      Duration d = const Duration(seconds: 1)}) => Pricing(calculator());

  @Bean()
  @Scope(ScopeType.prototype)
  Id id([String? tag]) => Id();

  @Bean()
  @Qualifier('nullable')
  Pricing other(Calculator? calc) => Pricing(calc ?? calculator());

  @Bean()
  static Calculator shared() => Calculator();
}

base class Seed {}

@Configuration()
base class BaseConfig {
  BaseConfig({@Value('x') required this.name, this.size = 1});
  final String name;
  final int size;
  @Bean() Seed seed() => Seed();
}
""";

    test('a generated subclass returns the container\'s beans', () async {
      final output = await _generate(source);
      // The subclass forwards the constructor arguments (super parameters
      // keep types and defaults); a `base` class gets a `final` subclass.
      expect(
        output,
        _has(
          r'class _$AppConfigConfiguration extends AppConfig {'
          r'_$AppConfigConfiguration(this._$beanFactory, super.p0, '
          r'[super.p1]) : super.named();',
        ),
      );
      expect(
        output,
        _has(
          r'final class _$BaseConfigConfiguration extends BaseConfig {'
          r'_$BaseConfigConfiguration(this._$beanFactory, '
          r'{required super.name, super.size});',
        ),
      );
      // Inter-bean calls get the bean of the container.
      expect(
        output,
        _has(
          '@override Calculator calculator() => '
          r"(_$beanFactory.getBeanByName(r'calculator') as Calculator);",
        ),
      );
      // Arguments of an inter-bean call are used when that call creates
      // the bean (Spring's getBean(name, args)) ...
      expect(
        output,
        _has(
          'Pricing pricing(Calculator calc, {int n = 3, '
          'Duration d = const Duration(seconds: 1)}) {'
          'final arguments = <Object?>[calc, n, d];'
          r"_$arguments[r'pricing'] = arguments;",
        ),
      );
      expect(
        output,
        _has(
          r"final arguments = _$arguments.remove(r'pricing');"
          'if (arguments != null) {return super.pricing('
          '(arguments[0] as Calculator), n: (arguments[1] as int), '
          'd: (arguments[2] as Duration));}',
        ),
      );
      // ... but not for a singleton when one is null (Spring: "stubbed
      // null arguments just for reference purposes"); a prototype keeps
      // them.
      expect(
        output,
        _has(
          'if (!arguments.contains(null)) '
          r"{_$arguments[r'other'] = arguments;}",
        ),
      );
      expect(
        output,
        _has(
          'Id id([String? tag]) {final arguments = <Object?>[tag];'
          r"_$arguments[r'id'] = arguments;",
        ),
      );
      // The container creates the configuration through the subclass and
      // the beans through `_$method(r)`.
      expect(
        output,
        _has(
          r'create: (r) => _$AppConfigConfiguration(r, '
          "r.dependency<Calculator>(name: r'prefix'), ",
        ),
      );
      expect(
        output,
        _has(
          "create: (r) => (r.dependency<AppConfig>(qualifier: r'appConfig') "
          r'as _$AppConfigConfiguration)._$calculator(r)',
        ),
      );
      // Static @Bean methods are not intercepted.
      expect(output, _has('create: (r) => AppConfig.shared()'));
      expect(output, isNot(contains(r'_$shared')));
    });

    test('the generated code compiles', () async {
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    });

    test('lite mode: proxyBeanMethods false, @Component, imported classes, '
        '@AutoConfiguration', () async {
      final output = await _generate(r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
class Calculator {}

@Configuration(proxyBeanMethods: false)
class Lite { @Bean() Calculator a() => Calculator(); }

@Component()
class WithBeans { @Bean() Calculator b() => Calculator(); }

@AutoConfiguration()
class Auto { @Bean() Calculator c() => Calculator(); }

class Plain { @Bean() Calculator d() => Calculator(); }

@Component()
@Import([Plain])
class Importer {}
''');
      expect(output, isNot(contains('Configurationextends')));
      for (final (owner, method) in [
        ('Lite', 'a'),
        ('WithBeans', 'b'),
        ('Auto', 'c'),
        ('Plain', 'd'),
      ]) {
        final name = owner[0].toLowerCase() + owner.substring(1);
        expect(
          output,
          _has("r.dependency<$owner>(qualifier: r'$name').$method()"),
        );
      }
    });

    test('FactoryBean @Bean methods return the factory itself', () async {
      final output = await _generate(r'''
class Client {}
class ClientFactory implements FactoryBean<Client> {
  @override Client getObject() => Client();
  @override bool get isSingleton => true;
  @override Type get objectType => Client;
}

@Configuration()
class Config { @Bean() ClientFactory client() => ClientFactory(); }
''');
      expect(
        output,
        _has(r"(_$beanFactory.getBeanByName(r'&client') as ClientFactory)"),
      );
    });

    test('rejects what cannot be subclassed, naming the fix', () async {
      for (final (source, message) in [
        (
          '@Configuration() final class C { @Bean() Object o() => 1; }',
          'remove `final`',
        ),
        (
          '@Configuration() interface class C { @Bean() Object o() => 1; }',
          'remove `interface`',
        ),
        (
          '@Configuration() class C { C._(); factory C() => C._(); '
              '@Bean() Object o() => 1; }',
          'add a public generative constructor',
        ),
      ]) {
        final result = await _build({
          'lib/src/beans.dart': _scan,
          'lib/src/service.dart': '$_header$source',
        });
        expect(result.succeeded, isFalse, reason: source);
        expect(
          result.errors.join('\n'),
          allOf(contains(message), contains('proxyBeanMethods: false')),
          reason: source,
        );
      }
      // Lite mode builds, and so does a class without instance @Bean
      // methods (nothing to intercept: no subclass).
      await _generate(
        '@Configuration(proxyBeanMethods: false) '
        'final class C { @Bean() Object o() => 1; }',
      );
      final output = await _generate(
        '@Configuration() final class C { @Bean() static Object o() => 1; }',
      );
      expect(output, isNot(contains('Configurationextends')));
      expect(output, _has('create: (r) => C()'));
    });
  });

  group('conditional declarations may share a bean name', () {
    const source = r"""
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
}
""";

    test('builds, one definition per declaration', () async {
      final output = await _generate(source);
      for (final name in ['dataSource', 'mailer', 'cache']) {
        expect("name:r'$name',".allMatches(output), hasLength(2), reason: name);
      }
    });

    test('the generated code compiles', () async {
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    });

    test('a clash of two unconditional declarations fails', () async {
      await _expectError('''
@Configuration(proxyBeanMethods: false)
class Config {
  @Bean(name: 'x') Object a() => 1;
  @Bean(name: 'x') @Profile(['dev']) Object b() => 1;
  @Bean(name: 'x') Object c() => 1;
}
''', "Bean name 'x' is used by both a and c.");
    });
  });

  group('@Bean types inferred from the method body', () {
    const source = r"""
abstract interface class DataSource {}
class HikariDataSource implements DataSource {
  void close() {}
}
abstract interface class Store<T> {}
class MemoryStore<T> implements Store<T> {}
abstract class Shape {}
class Circle extends Shape {}
class Square extends Shape {}
class Plain {}
class _Hidden implements DataSource {}

@Configuration()
class Config {
  @Bean() DataSource dataSource() => HikariDataSource();
  @Bean() Store<Object> store() => MemoryStore<String>();
  @Bean() Object shape(@Value('true') bool round) {
    if (round) {
      return Circle();
    }
    final square = Square();
    return square;
  }
  @Bean() Plain plain() => Plain();
  @Bean() Plain failing() => throw StateError('no');
  @Bean() Object closure() {
    final make = () { return 1; };
    make();
    return Plain();
  }
  @Bean() DataSource hidden() => _Hidden();
  @Bean() static DataSource shared() => HikariDataSource();
}
""";

    test(
      'the concrete class with full type arguments, plus supertypes',
      () async {
        final output = await _generate(source);
        expect(
          output,
          _has(
            "BeanDefinition<HikariDataSource>(name: r'dataSource', "
            "source: r'package:pkg/src/service.dart#Config.dataSource', "
            'types: const [HikariDataSource, DataSource],',
          ),
        );
        // The call is cast to the inferred type; the destroy method of the
        // concrete class is inferred.
        expect(
          output,
          _has(
            "create: (r) => ((r.dependency<Config>(qualifier: r'config') "
            r'as _$ConfigConfiguration)._$dataSource(r) as HikariDataSource),'
            'destroyMethod: (bean) {bean.close();}',
          ),
        );
        expect(
          output,
          _has('create: (r) => (Config.shared() as HikariDataSource)'),
        );
        // The override keeps the declared signature.
        expect(output, _has('@override DataSource dataSource() =>'));
        expect(
          output,
          _has(
            "BeanDefinition<MemoryStore<String>>(name: r'store', "
            "source: r'package:pkg/src/service.dart#Config.store', "
            'types: const [MemoryStore<String>, Store<String>, '
            'MemoryStore<dynamic>, Store<dynamic>, Store<Object>],',
          ),
        );
        // Several returns: the common supertype.
        expect(output, _has("BeanDefinition<Shape>(name: r'shape',"));
        // Same as declared, `throw`, closures, private classes: unchanged.
        for (final name in ['plain', 'failing', 'closure']) {
          expect(output, _has("BeanDefinition<Plain>(name: r'$name',"));
        }
        expect(output, _has("BeanDefinition<DataSource>(name: r'hidden',"));
      },
    );

    test('AOP proxies see the concrete class', () async {
      final output = await _generate(r'''
abstract interface class Api { void run(); }
class Impl implements Api {
  @override void run() {}
  void extra() {}
}

@Configuration(proxyBeanMethods: false)
class Config { @Bean() Api api() => Impl(); }
''', proxyMode: ProxyMode.all);
      expect(output, contains(r'class_$Config_apiProxyimplementsImpl,Api'));
      expect(output, _has("name: r'extra'"));
      expect(output, _has("targetType: r'Impl'"));
    });

    test('the generated code compiles', () async {
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    });
  });

  group('private declarations fail the build, naming the fix', () {
    const uri = 'declared in package:pkg/src/service.dart';
    final cases = <String, (String, String)>{
      'constructor parameter type': (
        'class _Dep {} @Component() class A { A(_Dep d); }',
        'Constructor parameter d of A',
      ),
      'the message names the type, its library and the fix': (
        'class _Dep {} @Component() class A { A(_Dep d); }',
        'has the private type _Dep ($uri), which the generated module '
            'cannot reference: make _Dep public.',
      ),
      'type argument': (
        'class _Dep {} @Component() class A { A(List<_Dep> d); }',
        'has the private type _Dep',
      ),
      '@Bean return type (lite mode)': (
        'class _Pool {} @Configuration(proxyBeanMethods: false) class C { '
            '@Bean() _Pool pool() => _Pool(); }',
        '@Bean method C.pool returns the private type _Pool ($uri), which '
            'the generated module cannot reference: make _Pool public, or '
            'declare a public supertype as the return type.',
      ),
      '@Bean parameter (full mode)': (
        'class _P {} @Configuration() class C { @Bean() Object o(_P? p) => 1; }',
        'Parameter p of @Bean method C.o has the private type _P',
      ),
      'injected field': (
        'class _Dep {} @Component() class A { @Autowired() late _Dep d; }',
        'Field d of A has the private type _Dep',
      ),
      '@Autowired method parameter': (
        'class _Dep {} @Component() class A { '
            '@Autowired() void wire(_Dep d) {} }',
        'Parameter d of method A.wire has the private type _Dep',
      ),
      'event type': (
        'class _Evt {} @Component() class A { '
            '@EventListener() void on(_Evt e) {} }',
        'Method A.on listens to the private type _Evt',
      ),
      'private function as a default value': (
        'int _zero() => 0; @Component() class A { '
            r'A({@Value(r"${f}") Object f = _zero}); }',
        'The default value of constructor parameter f of A uses the private '
            '_zero ($uri), which the generated module cannot reference: make '
            'it public, or declare the parameter without a default.',
      ),
      'private class as a default value': (
        'class _Opts { const _Opts(); } @Component() class A { '
            r'A({@Value(r"${o}") Object o = const _Opts()}); }',
        'uses the private _Opts ($uri)',
      ),
      'private constructor as a default value': (
        'class Opts { const Opts._(); } @Component() class A { '
            r'A({@Value(r"${o}") Object o = const Opts._()}); }',
        'uses the private Opts._ ($uri)',
      ),
      'private bean class': (
        '@Component() class _A {}',
        'Bean class _A must be public: the generated module cannot reference '
            'a private class of package:pkg/src/service.dart. Make it public, '
            'or move it out of the scanned directory.',
      ),
    };
    for (final MapEntry(key: name, value: (source, message)) in cases.entries) {
      test(name, () => _expectError(source, message));
    }
  });

  group('inherited members', () {
    test('@Bean methods of superclasses and mixins', () async {
      final output = await _generate(r'''
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
        _has("r.dependency<AppConfig>(qualifier: r'appConfig').pool()"),
      );
      expect(
        output,
        _has("r.dependency<AppConfig>(qualifier: r'appConfig').greeting()"),
      );
      // A static method is not inherited: called on its declaring class.
      expect(output, _has('create: (r) => BaseConfig.clock()'));
    });

    test('a full-mode subclass overrides inherited @Bean methods, with the '
        'type arguments of a generic superclass substituted', () async {
      const source = r'''
class Store<T> {}
class User {}
abstract class BaseConfig<T> {
  @Bean()
  Store<T> store() => Store<T>();
}
@Configuration()
class UserConfig extends BaseConfig<User> {}
''';
      final output = await _generate(source);
      expect(output, _has('BeanDefinition<Store<User>>('));
      expect(
        output,
        _has(r'class _$UserConfigConfiguration extends UserConfig'),
      );
      expect(output, _has('Store<User> store()'));
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    });

    test('lifecycle methods of mixins and the members of a generic '
        'superclass', () async {
      const source = r'''
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
      final output = await _generate(source);
      expect(
        output,
        _has("bean.repo = r.dependency<Repo<User>>(name: r'repo');"),
      );
      expect(
        output,
        _has(
          "if (r.optionalDependency<Repo<User>>(name: r'otherRepo') case final value?) { bean.otherRepo = value; }",
        ),
      );
      expect(output, contains('dependencyList<Repo<User>>()'));
      expect(
        output,
        _has(
          "EventListenerMethod.of<UserService, UserEvent>(r'UserService.on'",
        ),
      );
      expect(
        output,
        _has(
          'postConstruct: (bean) {bean.baseInit(); bean.auditInit(); bean.init();}',
        ),
      );
      expect(
        output,
        _has(
          'preDestroy: (bean) {bean.destroy(); bean.auditDestroy(); bean.baseDestroy();}',
        ),
      );
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    });
  });

  group('@ComponentScan filters and lazyInit', () {
    const classes = r'''
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
import 'package:pkg/src/beans.beans.dart';
import 'package:pkg/src/service.dart';

@ComponentScan($options)
final BeanModule pkgBeans = \$pkgBeans;
''';
    Future<TestBuilderResult> build(String options) => _build({
      'lib/src/beans.dart': scan(options),
      'lib/src/service.dart': '$_header$classes',
    });
    Future<String> generate(String options) async {
      final result = await build(options);
      expect(result.errors, isEmpty);
      return _normalize(
        result.readerWriter.testing.readString(result.outputs.single),
      );
    }

    test('include filters add beans without @Component, excludes win, '
        'abstract classes are skipped', () async {
      final output = await generate('''
includeFilters: [
  Filter(classes: [Plugin]),
  Filter(type: FilterType.assignableType, classes: [Handler]),
],
excludeFilters: [Filter(type: FilterType.regex, pattern: [r'Stub\$'])],
''');
      expect(output, _has("name: r'audit'"));
      expect(output, _has("name: r'loginHandler'"));
      expect(output, _has("name: r'real'"));
      expect(output, isNot(contains('BaseHandler')));
      expect(output, isNot(contains('Stub')));
    });

    test('useDefaultFilters: false scans only the includes', () async {
      final output = await generate(
        'useDefaultFilters: false, includeFilters: [Filter(classes: [Plugin])]',
      );
      expect(output, _has("name: r'audit'"));
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
}
