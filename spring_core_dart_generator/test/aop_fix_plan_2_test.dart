// Generator side of the second pre-0.2.0 fix plan: aspects declared by
// `@Bean` methods, `@DeclareParents` on subclass proxies, `@Lookup`
// classes with other abstract members, private constants in annotations,
// mixin members in introspection, warnings in generated code, `FutureOr`
// members, missing-import messages, clash-free parameter names and the
// advisor beans of starters.
import 'dart:isolate';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
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
  Map<String, String> starter = const {},
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  PackageConfig? packageConfig;
  if (starter.isNotEmpty) {
    final isolateConfig = await loadPackageConfigUri(
      (await Isolate.packageConfig)!,
    );
    packageConfig = PackageConfig([
      ...isolateConfig.packages,
      Package(
        'neon_aop',
        Uri.parse('file:///neon_aop/'),
        packageUriRoot: Uri.parse('file:///neon_aop/lib/'),
      ),
    ]);
  }
  return testBuilder(
    SpringBuilder(proxyMode: proxyMode),
    {
      for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value,
      for (final MapEntry(:key, :value) in starter.entries)
        'neon_aop|$key': value,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: packageConfig,
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
Future<String> _generate(String beans) async {
  final result = await _build({
    'lib/src/beans.dart': _scan,
    'lib/src/service.dart': '$_header$beans',
  });
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

/// The analyzer diagnostics (errors and warnings) of the generated library
/// built from [files] (plus the scan root unless [app]).
Future<List<String>> _diagnostics(
  Map<String, String> files, {
  bool app = false,
  bool warnings = false,
}) async {
  final sources = {
    if (app) 'bin/main.dart': _main else 'lib/src/beans.dart': _scan,
    for (final MapEntry(:key, :value) in files.entries) key: '$_header$value',
  };
  final result = await _build(sources);
  expect(result.errors, isEmpty);
  final path = app ? 'bin/main.spring.dart' : 'lib/src/beans.spring.dart';
  final output = _output(result, path);
  return resolveSources<List<String>>(
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
            if (diagnostic.severity == Severity.error ||
                (warnings && diagnostic.severity != Severity.error))
              '${diagnostic.diagnosticCode.lowerCaseName}: ${diagnostic.message}',
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|$path',
    readAllSourcesFromFilesystem: true,
  );
}

void main() {
  test('generated code has no warnings for members marked '
      '@visibleForTesting, @internal, @Deprecated or @nonVirtual', () async {
    final diagnostics = await _diagnostics({
      'lib/src/service.dart': '''
import 'package:meta/meta.dart';

class Audited {
  const Audited();
}

@Service()
class Legacy {
  @visibleForTesting
  String probe() => 'probe';

  @internal
  String inside() => 'inside';

  @Deprecated('use fresh')
  String stale() => 'stale';

  @nonVirtual
  String fixed() => 'fixed';

  @protected
  String guarded() => 'guarded';

  @Deprecated('use count')
  int total = 0;
}

// Private member: proxied by a generated subclass.
@Service()
class Sealed {
  int _calls = 0;

  @nonVirtual
  int fixed() => ++_calls;

  @visibleForTesting
  String probe() => 'probe';

  @Deprecated('use fresh')
  String stale() => 'stale';
}

@Aspect()
@Component()
class AuditAspect {
  @Before('within(Legacy) || within(Sealed)')
  void before() {}
}
''',
    }, warnings: true);
    expect(diagnostics, isEmpty);
  });

  group('a missing import names the type and the import to add', () {
    Future<String> errorsOf(String service) async {
      final result = await _build({
        'lib/src/beans.dart': _scan,
        'lib/src/clock.dart': 'class Clock {}',
        'lib/src/service.dart': '$_header$service',
      });
      expect(result.succeeded, isFalse);
      return result.errors.join('\n');
    }

    const hint =
        'the type Clock, which is not defined in package:pkg/src/service.dart '
        "(a missing import or a typo): add import 'package:pkg/src/clock.dart';";

    test('an @Autowired setter', () async {
      expect(
        await errorsOf('''
@Service()
class Uses {
  @Autowired()
  set clock(Clock value) {}
}
'''),
        contains(hint),
      );
    });

    test('a List<T> parameter', () async {
      expect(
        await errorsOf('''
@Service()
class Uses {
  Uses(this.clocks);
  final List<Clock> clocks;
}
'''),
        contains(hint),
      );
    });

    test('an ObjectProvider<T> parameter', () async {
      expect(
        await errorsOf('''
@Service()
class Uses {
  Uses(this.clocks);
  final ObjectProvider<Clock> clocks;
}
'''),
        contains(hint),
      );
    });

    test('an advice parameter', () async {
      expect(
        await errorsOf('''
@Aspect()
@Component()
class Watch {
  @Before('args(clock)')
  void before(Clock clock) {}
}
'''),
        contains(hint),
      );
    });

    test('a @Lookup return type', () async {
      expect(
        await errorsOf('''
@Component()
abstract class Uses {
  @Lookup()
  Clock clock();
}
'''),
        contains(hint),
      );
    });
  });

  group('an @Aspect declared through a @Bean method', () {
    const source = r'''
@Service()
class Orders {
  void place() {}
}

@Service()
class Mail {
  void send() {}
}

@Aspect()
class Audit {
  @Before('execution(* Orders.*(..))')
  void before() {}
}

@Configuration()
class AopConfig {
  @Bean()
  Audit audit() => Audit();
}
''';

    test('gets aspect metadata and generated code compiles', () async {
      final output = await _generate(source);
      expect(output, _has('aspect: AspectMetadata<Audit>('));
      expect(await _diagnostics({'lib/src/service.dart': source}), isEmpty);
    });

    test('pruning keeps the proxies it advises', () async {
      final result = await _build({
        'bin/main.dart': _main,
        'lib/src/service.dart': '$_header$source',
      });
      expect(result.errors, isEmpty);
      final root = _normalize(_output(result, 'bin/main.spring.dart'));
      expect(root, contains(r'class_$OrdersProxy'));
      expect(root, isNot(contains(r'class_$MailProxy')));
    });

    test('of a nested module keeps the proxies it advises', () async {
      final result = await _build({
        'bin/main.dart': _main,
        'lib/src/service.dart':
            '''
$_header
@Service()
class Orders {
  void place() {}
}
''',
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
class Audit {
  @Before('execution(* Orders.*(..))')
  void before() {}
}

@Configuration()
class AopConfig {
  @Bean()
  Audit audit() => Audit();
}
''',
      });
      expect(result.errors, isEmpty);
      final root = _normalize(_output(result, 'bin/main.spring.dart'));
      expect(root, contains(r'class_$OrdersProxy'));
    });
  });

  test('@DeclareParents applies to subclass proxies', () async {
    const source = r'''
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

// Private state: a subclass proxy.
@Service()
class Orders {
  int _placed = 0;

  int place() => ++_placed;
}

@Aspect()
@Component()
class Usage {
  @DeclareParents('Orders', defaultImpl: DefaultUsageTracked)
  static UsageTracked? mixin;

  @Before('execution(* Orders.*(..)) && this(usage)')
  void count(UsageTracked usage) => usage.increment();
}
''';
    final output = await _generate(source);
    expect(
      output,
      _has(
        r'class _$OrdersProxy extends Orders implements UsageTracked, Advised',
      ),
    );
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
        r'int get useCount => ((this._$invoker ?? '
        "ProxyInvoker.notIntroduced(this, r'UsageTracked'))"
        '.introduction(0) as UsageTracked).useCount;',
      ),
    );
    expect(await _diagnostics({'lib/src/service.dart': source}), isEmpty);
  });

  test('an abstract @Lookup class with another abstract member fails the '
      'build', () async {
    expect(
      await _errors('''
class Command {}

@Component()
abstract class Manager {
  @Lookup()
  Command createCommand();

  String name();

  int get size;
}
'''),
      contains(
        'Manager has @Lookup methods, which a generated subclass overrides '
        'to return beans of the container, but it also has the abstract '
        'members name(), get size, which the generated subclass cannot '
        'implement',
      ),
    );
  });

  group('annotations with private constants', () {
    test('on proxied members are left out and the code compiles', () async {
      const source = r'''
class Audited {
  const Audited(this.format);
  final String Function(Object) format;
}

String _format(Object value) => '$value';

class Level {
  const Level(this.value);
  final int value;
}

const _high = Level(3);

class Wrapped {
  const Wrapped(this.level);
  final Level level;
}

class _Marker {
  const _Marker();
}

@Service()
class Orders {
  @Audited(_format)
  void place() {}

  @Level(1)
  void cancel() {}

  @_Marker()
  void archive() {}

  @Wrapped(_high)
  void restore() {}
}

@Aspect()
@Component()
class Audit {
  @Before('within(Orders)')
  void before() {}
}
''';
      final output = await _generate(source);
      expect(output, isNot(contains('_format')));
      expect(output, _has('annotations: [Level(1)]'));
      expect(output, _has('annotations: [Wrapped(Level(3))]'));
      expect(await _diagnostics({'lib/src/service.dart': source}), isEmpty);
    });

    test('a constraint with a private value fails the build', () async {
      expect(
        await _errors(r'''
bool _check(Object? value) => value != null;

class CheckedBy extends Constraint {
  const CheckedBy(this.check) : super(message: 'bad');
  final bool Function(Object?) check;
}

@Introspected()
class Form {
  @CheckedBy(_check)
  String name = '';
}
'''),
        contains('@CheckedBy on '),
      );
    });
  });

  test('introspection includes mixin members', () async {
    const source = r'''
mixin Named {
  String name = '';
  String greet() => 'hi $name';
}

mixin Aged {
  int age = 0;
}

class Base with Aged {
  String id = '';
}

@Introspected()
class Person extends Base with Named {
  String city = '';
}
''';
    final output = await _generate(source);
    for (final property in ['city', 'name', 'age', 'id', 'greet']) {
      expect(output, contains("r'$property'"), reason: property);
    }
    expect(await _diagnostics({'lib/src/service.dart': source}), isEmpty);
  });

  test(
    'FutureOr methods and Future getters are advised on the future',
    () async {
      const source = r'''
import 'dart:async';

@Service()
class Orders {
  FutureOr<int> count() => 1;

  Future<String> get name async => 'orders';

  FutureOr<String> get label => 'label';

  Future<int>? maybe() => null;
}

// Private state: a subclass proxy.
@Service()
class Stock {
  int _n = 0;

  FutureOr<int> reserve() => ++_n;

  Future<int> get total async => _n;
}

@Aspect()
@Component()
class Audit {
  @Before('within(Orders) || within(Stock)')
  void before() {}
}
''';
      final output = await _generate(source);
      expect(output, contains('invokeFutureOr<int>(this,this._target,'));
      expect(output, contains('invokeAsync<String>(this,this._target,'));
      expect(output, contains('invokeFutureOr<String>(this,this._target,'));
      expect(output, contains(r'_$i.invokeFutureOr<int>(this,this,'));
      expect(output, contains(r'_$i.invokeAsync<int>(this,this,'));
      // `Future<T>?` stays an ordinary value.
      expect(output, isNot(contains('invokeAsync<int>(this,this._target,')));
      expect(await _diagnostics({'lib/src/service.dart': source}), isEmpty);
    },
  );

  test(
    r'a parameter named _$i does not clash with the generated local',
    () async {
      const source = r'''
@Service()
class Orders {
  int _placed = 0;

  int place(int _$i, [int _$i$ = 0]) => _placed += _$i + _$i$;
}

@Aspect()
@Component()
class Audit {
  @Before('within(Orders)')
  void before() {}
}
''';
      final output = await _generate(source);
      expect(output, contains(r'final_$i$$=this._$invoker;'));
      expect(await _diagnostics({'lib/src/service.dart': source}), isEmpty);
    },
  );

  group('advisor beans of starters and proxy pruning', () {
    const app = {
      'bin/main.dart': _main,
      'lib/src/service.dart':
          '''
$_header
@Service()
class Orders {
  void place() {}
}

@Aspect()
@Component()
class Audit {
  @Before('execution(* Nothing.*(..))')
  void before() {}
}
''',
    };

    String starter(String advisor) =>
        '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

class Marked {
  const Marked();
}

final class MarkedPointcut implements AnnotationPointcut {
  const MarkedPointcut();

  @override
  bool matches(MethodSignature signature, String beanName) =>
      signature.annotations.any((a) => a is Marked);
}

class Tag implements MethodInterceptor {
  @override
  Object? invoke(MethodInvocation invocation) => invocation.proceed();
}

@AutoConfigurationModule()
final BeanModule neonAop = BeanModule('neonAop', [
  BeanDefinition<DefaultPointcutAdvisor>(
    name: 'neonAdvisor',
    types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor],
    create: (_) => $advisor,
  ),
]);
''';

    Future<String> root(String advisor) async {
      final result = await _build(
        app,
        starter: {'lib/spring_auto_configuration.dart': starter(advisor)},
      );
      expect(result.errors, isEmpty);
      return _normalize(_output(result, 'bin/main.spring.dart'));
    }

    test('an annotation-driven advisor keeps pruning on', () async {
      expect(
        await root('DefaultPointcutAdvisor(const MarkedPointcut(), Tag())'),
        isNot(contains(r'class_$OrdersProxy')),
      );
    });

    test('any other advisor turns pruning off', () async {
      expect(
        await root(
          "DefaultPointcutAdvisor(ExpressionPointcut('bean(orders)'), Tag())",
        ),
        contains(r'class_$OrdersProxy'),
      );
    });
  });

  test('execution type patterns: String||int without parentheses fails '
      'the build, (String || int) builds', () async {
    String aspect(String pointcut) =>
        '''
@Aspect()
@Component()
class Audit {
  @Before('$pointcut')
  void before() {}
}
''';
    expect(
      await _errors(aspect('execution(String||int *(..))')),
      contains("write '(String||int)'"),
    );
    expect(
      await _errors(aspect('execution(Animal+ *(..))')),
      contains('the subtypes of Animal are unknown'),
    );
    await _generate(aspect('execution((String || int) *(java.lang.String))'));
  });
}
