// Generator side of the fix plan items on proxies, pointcuts and the bean
// types Spring accepts (function, record, nullable and generic beans).
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

const _header = "import 'package:spring_core_dart/spring_core_dart.dart';\n";

Future<TestBuilderResult> _build(
  Map<String, Object> sources, {
  ProxyMode proxyMode = ProxyMode.all,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(proxyMode: proxyMode),
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

String _output(TestBuilderResult result, String path) => result
    .readerWriter
    .testing
    .readString(result.outputs.singleWhere((o) => o.path == path));

/// The generated module of a `@ComponentScan` of [beans].
Future<String> _generate(
  String beans, {
  ProxyMode proxyMode = ProxyMode.all,
}) async {
  final result = await _build({
    'lib/src/beans.dart': _scan,
    'lib/src/service.dart': '$_header$beans',
  }, proxyMode: proxyMode);
  expect(result.errors, isEmpty);
  return _normalize(_output(result, 'lib/src/beans.spring.dart'));
}

/// The build errors of a `@ComponentScan` of [beans].
Future<String> _errors(String beans) async {
  final result = await _build({
    'lib/src/beans.dart': _scan,
    'lib/src/service.dart': '$_header$beans',
  });
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

/// The analyzer errors of the generated library `output` built from
/// [files] (plus the scan root unless [app]): the code must compile.
Future<List<String>> _compileErrors(
  Map<String, String> files, {
  bool app = false,
}) async {
  final sources = {
    if (app) 'bin/main.dart': _main else 'lib/src/beans.dart': _scan,
    for (final MapEntry(:key, :value) in files.entries) key: '$_header$value',
  };
  final result = await _build(sources);
  expect(result.errors, isEmpty);
  final path = app ? 'bin/main.spring.dart' : 'lib/src/beans.spring.dart';
  final output = _output(result, path);
  return await resolveSources<List<String>>(
    {
      for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value,
      'pkg|$path': output,
    },
    (resolver) async {
      final library = await resolver.libraryFor(AssetId('pkg', path));
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
    resolverFor: 'pkg|$path',
    readAllSourcesFromFilesystem: true,
  );
}

const _orders = '''
@Service()
class Orders {
  void place() {}
}

@Service()
class Mail {
  void send() {}
}
''';

void main() {
  group('proxy pruning sees every module of the application', () {
    test('an aspect of a nested module keeps the proxy of a root bean it '
        'advises; the nested module itself is never pruned', () async {
      final result = await _build({
        'bin/main.dart': _main,
        'lib/src/service.dart': '$_header$_orders',
        'lib/src/aspects/aspects.dart': r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/aspects/aspects.spring.dart';

@ComponentScan()
final BeanModule aspectBeans = $aspectBeans;
''',
        'lib/src/aspects/audit.dart':
            '''
$_header
@Aspect()
@Component()
class Audit {
  @Before('execution(* Orders.*(..))')
  void before() {}
}

@Service()
class Clock {
  int now() => 0;
}
''',
      });
      expect(result.errors, isEmpty);
      final root = _normalize(_output(result, 'bin/main.spring.dart'));
      // Orders is advised by the nested module's aspect: kept.
      expect(root, contains(r'class_$OrdersProxy'));
      // Mail matches no pointcut of any module: pruned.
      expect(root, isNot(contains(r'class_$MailProxy')));
      expect(
        root,
        _has('found no pointcut of the application that matches Mail'),
      );
      // The nested module may be imported by others: every proxy stays.
      final nested = _normalize(
        _output(result, 'lib/src/aspects/aspects.spring.dart'),
      );
      expect(nested, contains(r'class_$ClockProxy'));
    });

    test('this(t) bound to Object matches every bean', () async {
      final result = await _build({
        'bin/main.dart': _main,
        'lib/src/service.dart':
            '''
$_header$_orders
@Aspect()
@Component()
class Tracing {
  @Before('this(proxy)')
  void before(Object proxy) {}
}
''',
      });
      expect(result.errors, isEmpty);
      final root = _normalize(_output(result, 'bin/main.spring.dart'));
      expect(root, contains(r'class_$OrdersProxy'));
      expect(root, contains(r'class_$MailProxy'));
    });
  });

  group('classes that cannot be proxied', () {
    test('final, sealed, interface classes and factory-only constructors '
        'build and compile without any aspect', () async {
      expect(
        await _compileErrors({
          'lib/src/service.dart': '''
@Component()
final class Locked {
  int _n = 0;
  int next() => _n++;
}

@Component()
interface class Api {
  int _n = 0;
  int next() => _n++;
}

@Component()
class Made {
  Made._();
  factory Made() => Made._();
  int _n = 0;
  int next() => _n++;
}
''',
        }),
        isEmpty,
      );
      final output = await _generate(
        '@Component() final class Locked { int _n = 0; int next() => _n++; }',
      );
      expect(output, _has('aopProxy: AopProxyFactory.unavailable('));
      expect(output, isNot(contains('extendsLocked')));
    });
  });

  group('clash-free generated code', () {
    test('parameters named _target, _invoker, invoker, args, arguments and '
        '_resolve compile', () async {
      expect(
        await _compileErrors({
          'lib/src/service.dart': '''
abstract interface class Api {
  int run(int _target, int _invoker, {int args = 0});
  int other(int _resolve);
}

@Service()
class ApiImpl implements Api {
  @override
  int run(int _target, int _invoker, {int args = 0}) =>
      _target + _invoker + args;

  @override
  int other(int _resolve) => _resolve;
}

@Service()
class Counter {
  int _n = 0;
  int add(int invoker) => _n += invoker;
  void reset(int invoker) {
    _n = invoker;
  }
}

@Service()
class UsesLazy {
  UsesLazy(@Lazy() this.api);
  final Api api;
}

class Foo {
  Foo(this.bar);
  final Bar bar;
}

class Bar {}

@Configuration()
class Cfg {
  @Bean()
  Bar bar() => Bar();

  @Bean()
  Foo foo(Bar arguments) => Foo(arguments);

  @Bean()
  Foo other() => foo(bar());
}
''',
        }),
        isEmpty,
      );
    });

    test('generated proxies ignore unnecessary_cast', () async {
      final result = await _build({
        'lib/src/beans.dart': _scan,
        'lib/src/service.dart': '$_header$_orders',
      });
      expect(
        _output(result, 'lib/src/beans.spring.dart'),
        contains(
          '// ignore_for_file: type=lint, implementation_imports, '
          'unnecessary_cast',
        ),
      );
    });

    test('proxies are Advised: advisors can be added and removed', () async {
      final output = await _generate(_orders);
      expect(
        output,
        _has(
          'void addAdvisor(PointcutAdvisor advisor) => '
          'this._invoker.addAdvisor(advisor);',
        ),
      );
      expect(
        output,
        _has(
          'bool removeAdvice(MethodInterceptor advice) => '
          'this._invoker.removeAdvice(advice);',
        ),
      );
      final subclass = await _generate(
        '@Service() class Counter { int _n = 0; int add(int i) => _n += i; }',
      );
      expect(
        subclass,
        _has(
          r'void addAdvisor(PointcutAdvisor advisor) => (this._$invoker ?? '
          'ProxyInvoker.notAdvised(this)).addAdvisor(advisor);',
        ),
      );
    });
  });

  group('pointcut metadata', () {
    test('args(Type) gets a runtime type test, @args(A) the annotated '
        'classes', () async {
      final output = await _generate('''
class Audited {
  const Audited();
}

@Audited()
class Order {}

@Service()
class Orders {
  void place(Object order) {}
}

@Aspect()
@Component()
class Checks {
  @Before('execution(* Orders.*(..)) && args(String)')
  void strings() {}

  @Before('@args(Audited)')
  void audited() {}
}
''');
      expect(
        output,
        _has("typeTests: {r'String': (value) => value is String}"),
      );
      expect(
        output,
        _has(
          "argumentAnnotations: {r'Audited': (value) => value is Order "
          '? const Audited() : null}',
        ),
      );
    });

    test('an inherited member records the class of its body (within, '
        '@within) and @protected members are marked', () async {
      final output = await _generate('''
import 'package:meta/meta.dart';

class Marker {
  const Marker();
}

@Marker()
class Base {
  void inherited() {}
}

@Service()
class Sub extends Base {
  void own() {}

  @protected
  void hook() {}
}
''');
      String signature(String name) => output
          .split('MethodSignature(')
          .singleWhere((part) => part.startsWith("name:r'$name'"));
      // Inherited from Base: within(Base) / @within(Marker) match it.
      expect(
        signature('inherited'),
        _has(
          "implementingTypes: [r'Base'], "
          'implementingTypeAnnotations: [Marker()], '
          "implementingTypeAnnotationTypes: [r'Marker']",
        ),
      );
      // Declared by the bean class: the target's types count.
      expect(signature('own'), isNot(contains('implementingTypes')));
      expect(signature('hook'), _has('isProtected: true'));
      expect(signature('own'), isNot(contains('isProtected')));
    });

    test('perthis / pertarget aspects', () async {
      final output = await _generate('''
$_orders
@Aspect('perthis(execution(* Orders.*(..)))')
@Component()
@Scope('prototype')
class PerOrders {
  @Before('execution(* Orders.*(..))')
  void before() {}
}
''');
      expect(output, _has("perClause: r'perthis(execution(* Orders.*(..)))'"));
      expect(
        await _errors('''
@Aspect('pertarget(execution(* *(..)))')
@Component()
class Single {
  @Before('execution(* *(..))')
  void before() {}
}
'''),
        contains(
          "Bean with name 'single' is a singleton, but aspect instantiation "
          'model is not singleton',
        ),
      );
      expect(
        await _errors('''
@Aspect('percflow(execution(* *(..)))')
@Component()
@Scope('prototype')
class Flow {
  @Before('execution(* *(..))')
  void before() {}
}
'''),
        contains('percflow is not supported by Spring AOP'),
      );
      expect(
        await _errors('''
@Aspect('perthis(execution(* *(..))')
@Component()
@Scope('prototype')
class Broken {
  @Before('execution(* *(..))')
  void before() {}
}
'''),
        contains(
          "The instantiation model @Aspect('perthis(execution(* *(..))')",
        ),
      );
    });

    test('@DeclareParents: matching proxies implement the interface and '
        'forward it to one defaultImpl per proxy', () async {
      const source = '''
abstract interface class UsageTracked {
  int get useCount;
  void increment();
}

class DefaultUsageTracked implements UsageTracked {
  int _n = 0;

  @override
  int get useCount => _n;

  @override
  void increment() => _n++;
}

@Service()
class Orders {
  void place() {}
}

@Service()
class Mail {
  void send() {}
}

@Aspect()
@Component()
class Usage {
  @DeclareParents('Orders+', defaultImpl: DefaultUsageTracked)
  static UsageTracked? mixin;

  @Before('execution(* Orders.*(..)) && this(usage)')
  void count(UsageTracked usage) => usage.increment();
}
''';
      final output = await _generate(source);
      expect(
        output,
        _has(r'class _$OrdersProxy implements Orders, UsageTracked, Advised'),
      );
      expect(output, _has(r'class _$MailProxy implements Mail, Advised'));
      expect(
        output,
        _has(
          "introductions: [Introduction(interfaceName: r'UsageTracked', "
          "aspectType: r'Usage', create: () => DefaultUsageTracked())]",
        ),
      );
      expect(
        output,
        _has(
          'int get useCount => '
          '(this._invoker.introduction(0) as UsageTracked).useCount;',
        ),
      );
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
      expect(
        await _errors('''
abstract interface class Tracked {}
@Aspect()
@Component()
class Bad {
  @DeclareParents('*', defaultImpl: Bad)
  static Tracked? mixin;
}
'''),
        contains(
          'defaultImpl Bad must be a public, non-abstract class '
          'implementing Tracked',
        ),
      );
    });
  });

  group('bean types Spring accepts', () {
    test('function-typed and record beans are registered and injected by '
        'their type', () async {
      const source = r'''
typedef Greet = String Function(String);

@Configuration(proxyBeanMethods: false)
class Lite {
  @Bean()
  Greet greet() => (name) => 'hi $name';

  @Bean()
  String Function(int) label() => (i) => '#$i';

  @Bean()
  (int, String) pair() => (1, 'one');
}

@Configuration()
class Full {
  @Bean()
  int Function() counter() => () => 1;

  @Bean()
  Reader reader() => Reader(counter());
}

class Reader {
  Reader(this.counter);
  final int Function() counter;
}

@Service()
class User {
  User(this.greet, this.label, this.pair, [this.missing]);
  final Greet greet;
  final String Function(int) label;
  final (int, String) pair;
  final void Function()? missing;
}
''';
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
      final output = await _generate(source, proxyMode: ProxyMode.none);
      expect(output, _has('BeanDefinition<String Function(String)>('));
      expect(output, _has('types: const [Greet, Function]'));
      expect(
        output,
        _has(r'types: [_$typeOf<String Function(int)>(), Function]'),
      );
      expect(output, _has(r'types: [_$typeOf<(int, String)>(), Record]'));
      expect(output, _has(r'Type _$typeOf<T>() => T;'));
      expect(
        output,
        _has("r.dependency<String Function(String)>(name: r'greet')"),
      );
      expect(output, _has("r.dependency<(int, String)>(name: r'pair')"));
    });

    test('a @Bean method may return null (a NullBean)', () async {
      const source = '''
class Cache {}

class Store {
  Store(this.cache);
  final Cache? cache;
}

@Configuration()
class Full {
  @Bean()
  Cache? cache() => null;

  @Bean()
  Store store() => Store(cache());
}

@Configuration(proxyBeanMethods: false)
class Lite {
  @Bean()
  Cache? other() => null;
}
''';
      expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
      final output = await _generate(source);
      expect(
        output,
        _has(
          'Cache? cache() => NullBean.orNull<Cache>( '
          r"this._$beanFactory.getBeanByName(r'cache'));",
        ),
      );
      expect(output, _has('BeanDefinition<Cache>('));
    });

    test(
      'generic bean and @Configuration classes use their raw type',
      () async {
        const source = '''
class Item {}

@Component()
class Repo<T> {
  List<T> all() => [];
}

class Store<T extends Item> {}

@Configuration()
class StoreConfig<T extends Item> {
  @Bean()
  Store<T> store() => Store<T>();
}
''';
        expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
        final output = await _generate(source, proxyMode: ProxyMode.none);
        expect(output, _has('BeanDefinition<Repo<dynamic>>('));
        expect(output, _has('BeanDefinition<Store<Item>>('));
      },
    );

    test('an abstract @Component is skipped, not an error', () async {
      final output = await _generate('''
@Component()
abstract class Base {
  void run();
}

@Service()
class Impl extends Base {
  @override
  void run() {}
}
''', proxyMode: ProxyMode.none);
      expect(output, isNot(contains('BeanDefinition<Base>')));
      expect(output, contains('BeanDefinition<Impl>'));
    });
  });

  test('a missing import names the type and the import to add', () async {
    final result = await _build({
      'lib/src/beans.dart': _scan,
      'lib/src/clock.dart': 'class Clock {}',
      'lib/src/service.dart':
          '''
$_header
@Service()
class Uses {
  Uses(this.clock);
  final Clock clock;
}
''',
    });
    expect(result.succeeded, isFalse);
    final message = result.errors.join('\n');
    expect(
      message,
      contains(
        'the type Clock, which is not defined in package:pkg/src/service.dart '
        "(a missing import or a typo): add import 'package:pkg/src/clock.dart';",
      ),
    );
  });

  test('a defaulted @Bean parameter left out of an inter-bean call is '
      'resolved like the container resolves it', () async {
    const source = '''
class Clock {
  const Clock();
}

class Timer {
  Timer(this.clock);
  final Clock clock;
}

class Report {
  Report(this.timer);
  final Timer timer;
}

@Configuration()
class Cfg {
  @Bean()
  Timer timer({Clock clock = const Clock()}) => Timer(clock);

  @Bean()
  Report report() => Report(timer());
}
''';
    expect(await _compileErrors({'lib/src/service.dart': source}), isEmpty);
    final output = await _generate(source, proxyMode: ProxyMode.none);
    expect(output, _has(r'Timer timer({Object? clock = const _$Absent()})'));
    expect(
      output,
      _has(
        r"_$args[0] is _$Absent ? r.optionalDependency<Clock>(name: r'clock') "
        r'?? const Clock() : (_$args[0] as Clock)',
      ),
    );
    expect(output, _has(r'class _$Absent { const _$Absent(); }'));
  });
}
