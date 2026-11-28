// The generator for spring_boot_starter_flutter_signals: a bean with a
// @Signal, @Computed or @Effect member is made as a generated subclass whose
// followed members go straight to their signals; advice is a wrapper around
// it, and a build error unless allowed; a misplaced annotation fails the
// build. The starter is stubbed: the generator knows it by address.
import 'dart:isolate';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

import '../support/module_files.dart';
import '../support/starter_build_switches.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _starter = 'spring_boot_starter_flutter_signals';

const _stubs = {
  '$_starter|lib/src/annotations.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';

enum OnScopeEnd { discard, flush, defer }

@AccessHook()
class Signal {
  const Signal({
    this.hidden = false,
    this.queued = true,
    this.queue,
    this.eager,
    this.onScopeEnd,
  });
  final bool hidden;
  final bool queued;
  final String? queue;
  final bool? eager;
  final OnScopeEnd? onScopeEnd;
}

@AccessHook()
class Computed {
  const Computed();
}

@BeanMethodAnnotation()
@AccessHook()
class Effect {
  const Effect();
}

@BeanMethodAnnotation()
@AccessHook()
class OnWatched {
  const OnWatched(this.signals, {this.each = false});
  final List<String> signals;
  final bool each;
}

@BeanMethodAnnotation()
@AccessHook()
class OnUnwatched {
  const OnUnwatched(this.signals, {this.each = false});
  final List<String> signals;
  final bool each;
}

abstract class SignalMember {}

class ValueMember extends SignalMember {
  Object? read() => null;
  Object? readDirect() => null;
  void write(Object? value) {}
  void writeDirect(Object? value) {}
}

class ComputedMember extends SignalMember {
  Object? read() => null;
}

class AsyncMember extends ComputedMember {}

class SignalBean {
  SignalBean(this.label);
  final String label;
  ValueMember field(
    String name,
    Object? Function() initial, {
    List<TypeCapture<Object?>> arguments = const [],
    String? type,
    Signal options = const Signal(),
  }) => ValueMember();
  ComputedMember computed(String name, Object? Function() compute) =>
      ComputedMember();
  AsyncMember asynchronous(String name, Object? Function() compute) =>
      AsyncMember();
  T effectBody<T>(String name, T Function() body) => body();
  Future<T> buffered<T>(Future<T> Function() body) => body();
}

class ProbedSignalBean extends SignalBean {
  ProbedSignalBean(super.label);
}

abstract interface class SignalBeanHolder {
  SignalBean get signalBean;
  Map<String, SignalMember Function()> get signalMembers;
  List<String> get eagerSignals;
  List<String> get signalQueues;
}
''',
  '$_starter|lib/src/signal_buffer.dart': '''
class SignalBuffer {
  const SignalBuffer([this.enabled = true]);
  final bool enabled;
}
''',
  '$_starter|lib/$_starter.dart': '''
export 'src/annotations.dart';
export 'src/signal_buffer.dart';
''',
};

const _header =
    '''
import 'package:$_starter/$_starter.dart';
import 'package:spring_core_dart/spring_core_dart.dart';
''';

Future<PackageConfig> _packageConfig() async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  return PackageConfig([
    for (final package in isolateConfig.packages)
      if (package.name != _starter) package,
    Package(
      _starter,
      Uri.parse('file:///$_starter/'),
      packageUriRoot: Uri.parse('file:///$_starter/lib/'),
    ),
  ]);
}

const _allowAdvice = '''
spring:
  flutter:
    signals:
      allow-advice: true
''';

const _bufferAll = '''
spring:
  flutter:
    signals:
      buffer:
        async-methods: true
''';

// The starter's debug modules, each with its build switch as the starter
// writes it: the part decides the probes by them.
const _debugModules = [
  'springBootStarterFlutterSignalsDebugAutoConfiguration',
  'springBootStarterFlutterSignalsDebugConsoleAutoConfiguration',
  'springBootStarterFlutterSignalsDebugConsolePaneAutoConfiguration',
  'springBootStarterFlutterSignalsDebugGraphAutoConfiguration',
  'springBootStarterFlutterSignalsDebugGraphPaneAutoConfiguration',
];

// The starter's auto-configuration with [modules] (by name, the source of
// each one's `build:`), empty modules.
String _autoConfiguration(Map<String, String>? modules) {
  final switches =
      modules ??
      {
        for (final module in _debugModules)
          module: starterBuildSwitch(module, package: _starter),
      };
  return [
    "import 'package:spring_boot_dart/spring_boot_dart.dart';",
    for (final MapEntry(key: module, value: build) in switches.entries) ...[
      '@AutoConfigurationModule(build: $build)',
      "final BeanModule $module = BeanModule('$module', []);",
    ],
  ].join('\n');
}

Future<TestBuilderResult> _build(
  String beans, {
  bool allowAdvice = false,
  bool bufferAll = false,
  String? config,
  Map<String, String>? modules,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(generations: packageGenerations),
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': '$_header$beans',
      if (allowAdvice) 'pkg|lib/resources/application.yml': _allowAdvice,
      if (bufferAll) 'pkg|lib/resources/application.yml': _bufferAll,
      'pkg|lib/resources/application.yml': ?config,
      ..._stubs,
      '$_starter|lib/spring_auto_configuration.dart': _autoConfiguration(
        modules,
      ),
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: await _packageConfig(),
    flattenOutput: true,
  );
}

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

Matcher _has(String code) => contains(_normalize(code));

/// The generated module of [beans] (normalized), after checking that it
/// compiles against the stubs.
Future<String> _generate(
  String beans, {
  bool allowAdvice = false,
  bool bufferAll = false,
  String? config,
  Map<String, String>? modules,
}) async {
  final result = await _build(
    beans,
    allowAdvice: allowAdvice,
    bufferAll: bufferAll,
    config: config,
    modules: modules,
  );
  expect(result.errors, isEmpty);
  const path = 'lib/spring_gen/src/beans.spring.dart';
  final output = moduleText(result, AssetId('pkg', path));
  final errors = await resolveSources<List<String>>(
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': '$_header$beans',
      ...moduleSources(output),
      ..._stubs,
    },
    (resolver) async {
      final library = await resolver.libraryFor(AssetId('pkg', path));
      final errors = await moduleErrors(library);
      return [
        if (errors case ErrorsResult(:final diagnostics))
          for (final diagnostic in diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic.message,
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|$path',
    packageConfig: await _packageConfig(),
    readAllSourcesFromFilesystem: true,
  );
  expect(errors, isEmpty, reason: output);
  return _normalize(output);
}

Future<String> _errors(String beans) async {
  final result = await _build(beans);
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

void main() {
  group('the proxy of a bean with followed state', () {
    test(
      'is made as a subclass over its signals, with no advice in it',
      () async {
        final output = await _generate('''
class Book {
  const Book(this.title);
  final String title;
}

@Component()
class Basket {
  @Signal()
  List<Book> items = [];

  @Signal(queued: false)
  String? coupon;

  @Computed()
  int get count => items.length;

  @Effect()
  void save() {}

  // No annotation: the class's own, nothing is generated for it.
  void clear() => coupon = null;
}
''');
        expect(output, _has(r'class _$BasketSignals extends Basket'));
        expect(output, _has(r'create: (r) => _$BasketSignals()'));
        expect(output, isNot(_has('adviseSelfCalls')));
        expect(
          output,
          isNot(_has(r'class _$BasketSignals extends Basket { void clear')),
        );
        expect(output, _has('_itemsSignal.read()'));
        expect(output, _has('_itemsSignal.write(value)'));
        // A field that takes no part in a buffer pays for none.
        expect(output, _has('_couponSignal.readDirect()'));
        expect(output, _has('_couponSignal.writeDirect(value)'));
        expect(output, _has('_countComputed.read()'));
        expect(output, _has('arguments: const [TypeCapture<Book>()]'));
        expect(output, _has("signalBean.effectBody('save'"));
      },
    );

    group('the debug probe is in the builds of the debug tools', () {
      const bean = '''
@Component()
class Basket {
  @Signal()
  int count = 0;
}
''';
      String debug(String debug, String console) =>
          '''
spring:
  flutter:
    debug:
      console:
        enabled: $console
    signals:
      debug:
        enabled: $debug
''';

      test('not set: debug builds only, under the constant a profile or a '
          'release build folds', () async {
        final output = await _generate(bean);
        expect(
          output,
          _has(
            'final SignalBean signalBean = '
            "(!const bool.fromEnvironment('dart.vm.product') && "
            "!const bool.fromEnvironment('dart.vm.profile')) "
            "? ProbedSignalBean('Basket') : SignalBean('Basket');",
          ),
        );
      });

      test('both false: no probe in any build', () async {
        final output = await _generate(bean, config: debug('false', 'false'));
        expect(
          output,
          _has("final SignalBean signalBean = SignalBean('Basket');"),
        );
        expect(output, isNot(_has('ProbedSignalBean')));
      });

      test('the console true with no tool of the signals in it: no probe, '
          'nothing would listen', () async {
        final output = await _generate(bean, config: debug('false', 'true'));
        expect(output, isNot(_has('ProbedSignalBean')));
      });

      for (final (tool, list) in [
        ('the segment', 'segments: [signals]'),
        ('the signals pane', 'panes: [signals]'),
        ('the graph pane', 'panes: [graph]'),
      ]) {
        test('the console true with $tool: in every build, a release one '
            'too', () async {
          final output = await _generate(
            bean,
            config: debug('false', 'true\n        $list'),
          );
          expect(
            output,
            _has("final SignalBean signalBean = ProbedSignalBean('Basket');"),
          );
        });
      }

      test('the graph pane without the signals layer: no probe', () async {
        final output = await _generate(
          bean,
          config: '''
spring:
  flutter:
    debug:
      console:
        enabled: true
        panes: [graph]
      graph:
        layers: [widgets]
    signals:
      debug:
        enabled: false
''',
        );
        expect(output, isNot(_has('ProbedSignalBean')));
      });

      test('the panel false: no probe, the Signals tab and the graph leave '
          'with it', () async {
        final output = await _generate(
          bean,
          config: '''
spring:
  flutter:
    debug:
      enabled: false
''',
        );
        expect(output, isNot(_has('ProbedSignalBean')));
      });

      test('the panel true, the Signals tab not set: the narrowest, debug '
          'builds only', () async {
        final output = await _generate(
          bean,
          config: '''
spring:
  flutter:
    debug:
      enabled: true
''',
        );
        expect(output, _has("(!const bool.fromEnvironment('dart.vm.product')"));
        expect(output, _has("? ProbedSignalBean('Basket') : SignalBean("));
      });

      test("the starter's own switch, not a copy of it: a module whose "
          'switch is not set is not in', () async {
        final output = await _generate(
          bean,
          config: '''
spring:
  flutter:
    signals:
      debug:
        enabled: true
''',
          modules: {
            'springBootStarterFlutterSignalsDebugAutoConfiguration':
                "AutoConfigurationBuild('spring.flutter.signals.debug.other', "
                'whenMissing: BuildInclusion.never)',
          },
        );
        expect(output, isNot(_has('ProbedSignalBean')));
      });

      test('the State tab off and the console not set: no probe, as the '
          'console is built only when asked for', () async {
        final output = await _generate(
          bean,
          config: '''
spring:
  flutter:
    signals:
      debug:
        enabled: false
''',
        );
        expect(output, isNot(_has('ProbedSignalBean')));
      });
    });

    test('with advice allowed: an ordinary wrapper around the subclass, '
        'private members or not', () async {
      final output = await _generate('''
class Marked {
  const Marked();
}

@Aspect()
@Component()
class Marking {
  @Around('@annotation(Marked)')
  Object? around(ProceedingJoinPoint point) => point.proceed();
}

@Component()
class Basket {
  int _hidden = 0;

  @Signal()
  int count = 0;

  @Marked()
  int bump() => _hidden++;
}
''', allowAdvice: true);
      expect(output, _has(r'class _$BasketSignals extends Basket'));
      expect(output, _has(r'class _$BasketProxy with AdvisedWrapper'));
      expect(output, _has('implements Basket'));
      expect(output, isNot(_has('adviseSelfCalls')));
    });

    test('advice is a build error by default, naming where and how to allow '
        'it', () async {
      final errors = await _errors('''
class Marked {
  const Marked();
}

@Aspect()
@Component()
class Marking {
  @Around('@annotation(Marked)')
  Object? around(ProceedingJoinPoint point) => point.proceed();
}

@Component()
class Basket {
  @Signal()
  int count = 0;

  @Marked()
  void bump() {}
}
''');
      expect(errors, contains('Advice on a bean with @Signal'));
      expect(errors, contains('Basket.bump'));
      expect(errors, contains('spring.flutter.signals.allow-advice: true'));
    });

    test('@SignalBuffer: the method runs in a buffer of its bean, with '
        'its parameters', () async {
      final output = await _generate('''
@Component()
class Basket {
  @Signal()
  int count = 0;

  @SignalBuffer()
  Future<void> fill(int amount, {String note = ''}) async => count += amount;

  Future<void> plain() async {}
}
''');
      expect(
        output,
        _has(
          "Future<void> fill(int amount, {String note = ''}) => "
          'signalBean.buffered(() => super.fill(amount, note: note));',
        ),
      );
      expect(output, isNot(_has('super.plain()')));
    });

    test(
      'buffer.async-methods: every async method, but @SignalBuffer(false)',
      () async {
        final output = await _generate('''
@Component()
class Basket {
  @Signal()
  int count = 0;

  Future<void> fill() async => count++;

  @SignalBuffer(false)
  Future<void> load() async {}

  void sync() {}
}
''', bufferAll: true);
        expect(output, _has('signalBean.buffered(() => super.fill())'));
        expect(output, isNot(_has('super.load()')));
        expect(output, isNot(_has('super.sync()')));
      },
    );

    for (final (name, source, expected) in [
      (
        'a stream',
        '@SignalBuffer()\n  Stream<int> feed() async* {}',
        'which makes a stream',
      ),
      (
        'a sync method',
        '@SignalBuffer()\n  void fill() {}',
        'which is not async',
      ),
    ]) {
      test('@SignalBuffer on $name fails the build', () async {
        final errors = await _errors('''
@Component()
class Basket {
  @Signal()
  int count = 0;

  $source
}
''');
        expect(errors, contains(expected));
      });
    }

    test('@SignalBuffer on a bean without signals fails the build', () async {
      final errors = await _errors('''
@Component()
class Plain {
  @SignalBuffer()
  Future<void> fill() async {}
}
''');
      expect(errors, contains('has no @Signal field'));
    });

    for (final (name, method, expected) in [
      (
        'an unknown name, with a hint',
        "@OnWatched(['cuont'])\n  void on() {}",
        "Did you mean 'count'?",
      ),
      ('an empty list', '@OnWatched([])\n  void on() {}', 'an empty list'),
      (
        'a private method',
        "@OnWatched(['count'])\n  void _on() {}",
        'the private method',
      ),
      (
        'a static method',
        "@OnUnwatched(['count'])\n  static void on() {}",
        'the static method',
      ),
      (
        'parameters',
        "@OnUnwatched(['count'])\n  void on(int value) {}",
        'takes parameters',
      ),
    ]) {
      test('@OnWatched / @OnUnwatched: $name fails the build', () async {
        final errors = await _errors('''
@Component()
class Basket {
  @Signal()
  int count = 0;

  $method
}
''');
        expect(errors, contains(expected));
      });
    }

    test('a bean without such a member is as before', () async {
      final output = await _generate('''
@Component()
class Plain {
  int count = 0;

  int twice() => count * 2;
}
''');
      expect(output, isNot(_has('adviseSelfCalls')));
      expect(output, isNot(_has('TypeCapture')));
    });

    test('the type arguments of a map, and none for a plain type', () async {
      final output = await _generate('''
@Component()
class Prices {
  @Signal()
  Map<String, double> byIsbn = {};

  @Signal()
  int total = 0;
}
''');
      expect(
        output,
        _has('arguments: const [TypeCapture<String>(), TypeCapture<double>()]'),
      );
      expect(_normalize('TypeCapture<').allMatches(output), hasLength(2));
    });

    test('a filtered Map carries its types, directly and in a Future, and '
        'a member without a filter none', () async {
      final output = await _generate('''
import 'package:spring_security_core/spring_security_core.dart';

@Service()
class Owners {
  @Signal()
  Map<String, int> all = {};

  @PostFilter('true')
  Map<String, int> kept() => all;

  @PostFilter('true')
  Future<Map<String, bool>> later() async => {};

  @PreFilter('true')
  int count(int limit, Map<int, String> incoming) => limit;

  Map<String, double> plain() => {};
}
''', allowAdvice: true);
      expect(output, _has('resultMapTypes:MapTypes<String,int>()'));
      expect(output, _has('resultMapTypes:MapTypes<String,bool>()'));
      expect(output, _has('parameterMapTypes:[null,MapTypes<int,String>()]'));
      expect(output, isNot(contains('MapTypes<String,double>')));
    });

    test('a class that cannot be extended fails the build', () async {
      final errors = await _errors('''
@Component()
final class Basket {
  @Signal()
  int count = 0;
}
''');
      expect(errors, contains('@Signal on a member of Basket'));
      expect(errors, contains('final'));
    });
  });

  group('a misplaced annotation', () {
    Future<String> inBean(String members) => _errors('''
@Component()
class Basket {
$members
}
''');

    test('@Signal on a private field', () async {
      expect(
        await inBean(
          '@Signal()\n  int _count = 0;\n  int get count => _count;',
        ),
        allOf(
          contains('@Signal on the private field Basket._count'),
          contains('Make the field public'),
        ),
      );
    });

    test('@Signal on a final field', () async {
      expect(
        await inBean('@Signal()\n  final int count = 0;'),
        contains('@Signal on the final field Basket.count'),
      );
    });

    test('@Signal on a getter', () async {
      expect(
        await inBean('@Signal()\n  int get count => 0;'),
        allOf(
          contains('@Signal on the getter Basket.count'),
          contains('@Computed'),
        ),
      );
    });

    test('@Computed with parameters', () async {
      expect(
        await inBean('@Computed()\n  int priceOf(String isbn) => 0;'),
        contains('@Computed on Basket.priceOf, which takes parameters'),
      );
    });

    test('@Transactional on a @Computed getter: no transaction would start, '
        'a method is named instead', () async {
      final errors = await _errors('''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

@Service()
class Loaded {
  @Transactional()
  @Computed()
  Future<int> get total async => 1;
}
''');
      expect(errors, contains('@Transactional on the @Computed getter'));
      expect(errors, contains('Loaded.total'));
      expect(errors, contains('Make it a method'));
    });

    test('@Transactional on a @Computed method builds', () async {
      await _generate('''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

@Service()
class Loaded {
  @Transactional()
  @Computed()
  Future<int> total() async => 1;
}
''', allowAdvice: true);
    });

    test('@Computed on a field', () async {
      expect(
        await inBean('@Computed()\n  int total = 0;'),
        contains('@Computed on the field Basket.total'),
      );
    });

    test('@Effect with parameters, or with a value', () async {
      expect(
        await inBean('@Effect()\n  void save(int count) {}'),
        contains('@Effect on Basket.save, which takes parameters'),
      );
      expect(
        await inBean('@Effect()\n  int save() => 0;'),
        contains('@Effect on Basket.save, which returns a value'),
      );
    });

    test('in a @Configuration class', () async {
      final errors = await _errors('''
@Configuration()
class Config {
  @Signal()
  int count = 0;
}
''');
      expect(
        errors,
        allOf(
          contains('@Configuration class Config'),
          contains('Move the state into a component'),
        ),
      );
    });
  });

  group('an annotation marked @AccessHook', () {
    test('that no part of the generator writes code for fails the build, '
        'naming it and what is supported', () async {
      final errors = await _errors('''
@AccessHook()
class Tracked {
  const Tracked();
}

@Component()
class Basket {
  @Tracked()
  int count = 0;

  @Signal()
  int total = 0;
}
''');
      expect(
        errors,
        allOf(
          contains('@Tracked on Basket.count'),
          contains(
            '@AccessHook currently supports only the annotations of '
            'spring_boot_starter_flutter_signals',
          ),
          contains('@Signal, @Computed, @Effect, @OnWatched, @OnUnwatched'),
        ),
      );
      expect(errors, isNot(contains('@Signal on Basket.total')));
    });

    test('on a member of a class that is no bean fails the same way', () async {
      expect(
        await _errors('''
@AccessHook()
class Tracked {
  const Tracked();
}

abstract class Plain {
  @Tracked()
  int count = 0;
}
'''),
        contains(
          '@Tracked on Plain.count: Tracked is marked @AccessHook, and no '
          'part of the generator writes code for it',
        ),
      );
    });
  });

  group('an annotation where no proxy follows it', () {
    test('a class that is no bean', () async {
      expect(
        await _errors('''
class Plain {
  @Signal()
  int count = 0;
}
'''),
        allOf(
          contains('@Signal on Plain.count, and Plain is no bean'),
          contains('Annotate Plain as a component, or make it abstract'),
        ),
      );
    });

    test('a base of a component is no mistake, abstract or not, nor is a '
        'mixin', () async {
      final output = await _generate('''
abstract class Counted {
  @Signal()
  int count = 0;
}

class Named {
  @Signal()
  String name = '';
}

mixin Priced {
  @Computed()
  int get price => 1;
}

@Component()
class Basket extends Counted with Priced {}

@Component()
class Customer extends Named {}
''');
      expect(output, _has('@override set count(int value)'));
      expect(output, _has('@override int get price'));
      expect(output, _has('@override set name(String value)'));
      expect('Signalsextends'.allMatches(output), hasLength(2));
    });

    test('a mixin is checked like a class', () async {
      expect(
        await _errors('''
mixin Counting {
  @Signal()
  int _count = 0;
  int get count => _count;
}

@Component()
class Basket with Counting {}
'''),
        contains('@Signal on the private field Counting._count'),
      );
    });

    test('an enum, an extension, the top level', () async {
      final errors = await _errors('''
enum Mode {
  day,
  night;

  @Computed()
  int get twice => index * 2;
}

@Component()
class Basket {}

extension on Basket {
  @Computed()
  int get size => 0;
}

@Signal()
int count = 0;

@Effect()
void save() {}
''');
      expect(
        errors,
        allOf(
          contains('@Computed on twice, in the enum Mode'),
          contains('@Computed on size, in the extension on Basket'),
          contains('@Signal on count, in the top level of'),
          contains('@Effect on save, in the top level of'),
          contains('it goes on a member of a component class'),
        ),
      );
    });

    test('a bean the container does not proxy', () async {
      expect(
        await _errors('''
@Aspect()
@Component()
class Audit {
  @Signal()
  int calls = 0;
}
'''),
        allOf(
          contains(
            '@Signal on a member of Audit, a bean the container does '
            'not proxy',
          ),
          contains('Move the member into a component of its own'),
        ),
      );
      expect(
        await _errors('''
@Component()
class Renamer implements BeanFactoryPostProcessor {
  @Signal()
  int seen = 0;

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {}
}
'''),
        contains(
          '@Signal on a member of Renamer, a bean the container does '
          'not proxy',
        ),
      );
    });

    test('the result of a @Bean method', () async {
      expect(
        await _errors('''
abstract class Base {}

class Basket extends Base {
  @Signal()
  int count = 0;
}

@Configuration()
class Config {
  @Bean()
  Basket basket() => Basket();
}
'''),
        allOf(
          contains(
            '@Signal on a member of Basket needs a proxy that '
            'extends Basket',
          ),
          contains('not as the result of a @Bean method'),
          isNot(contains('is no bean')),
        ),
      );
    });

    test('a @ConfigurationProperties class', () async {
      expect(
        await _errors('''
@ConfigurationProperties('shop')
class ShopProperties {
  @Signal()
  int limit = 0;
}
'''),
        allOf(
          contains('@ConfigurationProperties class ShopProperties'),
          contains('Keep the state in a component that reads ShopProperties'),
        ),
      );
    });

    test('a repository: its methods are written by the generator', () async {
      expect(
        await _errors('''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

class Book {
  Book({this.id, required this.title});
  int? id;
  String title;
}

abstract interface class BookRepository implements DataRepository<Book, int> {
  @Computed()
  Future<List<Book>> findByTitle(String title);
}
'''),
        allOf(
          contains(
            '@Computed on the abstract method '
            'BookRepository.findByTitle',
          ),
          contains(
            'the method of a repository or of an HTTP client is '
            'written by the generator',
          ),
          contains(
            '@Computed on a member of BookRepository, whose '
            'implementation is generated',
          ),
        ),
      );
    });

    test(
      'a component that reads a repository in a computed getter builds',
      () async {
        final output = await _generate('''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

class Book {
  Book({this.id, required this.title});
  int? id;
  String title;
}

abstract interface class BookRepository implements DataRepository<Book, int> {
  Future<List<Book>> findByTitle(String title);
}

@Service()
class Books {
  Books(this.repository);
  final BookRepository repository;

  @Signal()
  String query = '';

  @Computed()
  Future<List<Book>> get found => repository.findByTitle(query);
}

@Repository()
class Notes {
  @Signal()
  List<String> lines = [];
}
''');
        expect('Signalsextends'.allMatches(output), hasLength(2));
      },
    );

    test('an HTTP client', () async {
      expect(
        await _errors('''
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

@HttpExchange('/books')
abstract interface class BooksClient {
  @Computed()
  @GetExchange()
  Future<List<String>> books();
}

@Configuration()
@ImportHttpServices(types: [BooksClient])
class Clients {}
'''),
        allOf(
          contains('@Computed on the abstract method BooksClient.books'),
          contains(
            '@Computed on a member of BooksClient, whose '
            'implementation is generated',
          ),
        ),
      );
    });

    test('an abstract member', () async {
      expect(
        await _errors('''
abstract class Counted {
  @Signal()
  abstract int count;
}
'''),
        contains('@Signal on the abstract field Counted.count'),
      );
      expect(
        await _errors('''
abstract class Counted {
  @Computed()
  int get twice;
}
'''),
        contains('@Computed on the abstract getter Counted.twice'),
      );
    });

    test('an override without the annotation', () async {
      const base = '''
abstract class Counted {
  @Signal()
  int count = 0;

  @Computed()
  int get twice => count * 2;

  @Effect()
  void save() {}
}
''';
      expect(
        await _errors('''
$base
@Component()
class Basket extends Counted {
  @override
  int count = 5;
}
'''),
        allOf(
          contains(
            'Basket.count overrides the @Signal field Counted.count '
            'without its annotation',
          ),
          contains('Repeat the annotation on Basket.count'),
        ),
      );
      expect(
        await _errors('''
$base
@Component()
class Basket extends Counted {
  @override
  int get twice => 1;
}
'''),
        contains('Basket.twice overrides the @Computed getter Counted.twice'),
      );
      expect(
        await _errors('''
$base
@Component()
class Basket extends Counted {
  @override
  void save() {}
}
'''),
        contains('Basket.save overrides the @Effect method Counted.save'),
      );
      await _generate('''
$base
@Component()
class Basket extends Counted {
  @override
  @Signal()
  int count = 5;

  @override
  @Computed()
  int get twice => 1;

  @override
  @Effect()
  void save() {}
}
''');
    });

    test('a member the proxy cannot override', () async {
      expect(
        await _errors('''
class _Hidden {}

@Component()
class Basket {
  @Signal()
  _Hidden? hidden;
}
'''),
        contains(
          '@Signal on Basket.hidden: the proxy of Basket cannot '
          'override it',
        ),
      );
      expect(
        await _errors('''
@Component()
class Basket {
  @Signal()
  int count = 0;

  @Computed()
  int operator -() => -count;
}
'''),
        contains(
          '@Computed on Basket.-: the proxy of Basket cannot '
          'override it',
        ),
      );
    });

    test('a generic class: the way out is not an interface', () async {
      expect(
        await _errors('''
@Component()
class Store<T> {
  @Signal()
  T? value;
}
'''),
        allOf(
          contains(
            'It cannot be made, because Store is generic. Remove its '
            'type parameters.',
          ),
          isNot(contains('add an interface')),
        ),
      );
    });
  });

  group('@Retryable on a bean with followed state', () {
    test('a buffered method may be retried', () async {
      final result = await _build('''
@Component()
class Basket {
  @Signal()
  int count = 0;

  @SignalBuffer()
  @Retryable()
  Future<void> fill() async => count++;
}
''', allowAdvice: true);
      expect(result.errors, isEmpty);
    });

    test('every async method buffered: retried too', () async {
      final result = await _build(
        '''
@Component()
class Basket {
  @Signal()
  int count = 0;

  @Retryable()
  Future<void> fill() async => count++;
}
''',
        config: '''
spring:
  flutter:
    signals:
      allow-advice: true
      buffer:
        async-methods: true
''',
      );
      expect(result.errors, isEmpty);
    });

    for (final (name, source, expected) in [
      (
        'an unbuffered method',
        '@Retryable()\n  Future<void> fill() async => count++;',
        [
          '@Retryable on Basket.fill, a method of a bean with @Signal',
          'fields that runs without a buffer',
          'Add @SignalBuffer() to Basket.fill',
        ],
      ),
      (
        'a method taken out of the buffer',
        '@SignalBuffer(false)\n  @Retryable()\n'
            '  Future<void> fill() async => count++;',
        ['that runs without a buffer'],
      ),
      (
        'a sync method',
        '@Retryable(delay: Duration.zero)\n  void bump() => count++;',
        [
          'that is not async',
          'Make it return a Future and add @SignalBuffer()',
        ],
      ),
      (
        'a @Computed',
        '@Computed()\n  @Retryable()\n  Future<int> get total async => count;',
        ['@Retryable on the @Computed Basket.total'],
      ),
      (
        'an @Effect',
        '@Effect()\n  @Retryable(delay: Duration.zero)\n  void log() => count;',
        ['@Retryable on the @Effect Basket.log', 'let the @Effect follow it'],
      ),
    ]) {
      test(name, () async {
        final errors = await _errors('''
@Component()
class Basket {
  @Signal()
  int count = 0;

  $source
}
''');
        for (final message in expected) {
          expect(errors, contains(message));
        }
      });
    }

    test('on the class', () async {
      expect(
        await _errors('''
@Component()
@Retryable()
class Basket {
  @Signal()
  int count = 0;
}
'''),
        contains(
          '@Retryable on Basket, a bean with @Signal, @Computed or '
          '@Effect members: on the class',
        ),
      );
    });
  });
}
