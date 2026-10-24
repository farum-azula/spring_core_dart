import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

// Scan rules matching Spring: targets, conditions, nested roots, names,
// constructor selection and error reporting.

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

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

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

Matcher _has(String code) => contains(_normalize(code));

String _output(TestBuilderResult result, String path) =>
    _normalize(result.readerWriter.testing.readString(AssetId('pkg', path)));

Future<String> _generate(String beans, {ProxyMode? proxyMode}) async {
  final result = await _build({
    'lib/src/beans.dart': _scan,
    'lib/src/service.dart': '$_header$beans',
  }, proxyMode: proxyMode ?? ProxyMode.none);
  expect(result.errors, isEmpty);
  return _output(result, 'lib/src/beans.spring.dart');
}

Future<String> _errors(Map<String, String> files) async {
  final result = await _build({
    'lib/src/beans.dart': _scan,
    for (final MapEntry(:key, :value) in files.entries) key: '$_header$value',
  });
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

Future<String> _error(String beans) => _errors({'lib/src/service.dart': beans});

/// The diagnostics of the generated library at [severities] (errors and
/// warnings by default), resolved with the real runtime.
Future<List<String>> _diagnostics(
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
      'pkg|lib/src/beans.spring.dart': output,
    },
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('pkg', 'lib/src/beans.spring.dart'),
      );
      final errors = await library.session.getErrors(
        library.firstFragment.source.fullName,
      );
      return [
        if (errors case ErrorsResult(:final diagnostics))
          for (final diagnostic in diagnostics)
            if (diagnostic.severity != Severity.info)
              '${diagnostic.diagnosticCode.lowerCaseName}: ${diagnostic.message}',
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|lib/src/beans.spring.dart',
    readAllSourcesFromFilesystem: true,
  );
}

void main() {
  test('annotations of primary-constructor parameters survive a library '
      'resolved by two builds', () async {
    final result = await _build({
      'lib/a/beans.dart': r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/a/beans.spring.dart';

@ComponentScan()
final BeanModule aBeans = $aBeans;
''',
      'lib/a/settings.dart': '''$_header
@Component()
class Settings(
  @Value(r'\${app.name:demo}') final String name,
  @Qualifier('clock') final Object? clock,
);

@Introspected()
class Form(@NotBlank() var String email);
''',
      'lib/b/beans.dart': r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/b/beans.spring.dart';

@ComponentScan()
final BeanModule bBeans = $bBeans;
''',
      'lib/b/config.dart': '''${_header}import 'package:pkg/a/settings.dart';

@Configuration()
@Import([Settings])
class BConfig {
  @Bean()
  Form form() => Form('x');
}
''',
    });
    expect(result.errors, isEmpty);
    for (final path in ['lib/a/beans.spring.dart', 'lib/b/beans.spring.dart']) {
      final output = _output(result, path);
      expect(
        output,
        _has(
          "Settings(r.value<String>(r'\${app.name:demo}'), "
          "r.optionalDependency<Object>(qualifier: r'clock', name: r'clock'))",
        ),
        reason: path,
      );
    }
    expect(
      _output(result, 'lib/a/beans.spring.dart'),
      _has("r'email', type: String"),
    );
    expect(
      _output(result, 'lib/a/beans.spring.dart'),
      _has('annotations: const [NotBlank()]'),
    );
  });

  group('unsupported targets fail the build', () {
    for (final (source, message) in [
      ('@Component() mixin Audit {}', '@Component on mixin Audit'),
      ('@Service() enum Mode { a }', '@Service on enum Mode'),
      (
        '@Component() extension type Meters(int value) {}',
        '@Component on extension type Meters',
      ),
      (
        '@Component() extension Shout on String {}',
        '@Component on extension Shout',
      ),
      ('@Bean() Object clock() => Object();', '@Bean on top-level function'),
      ('@ComponentScan() class Scanned {}', '@ComponentScan on class Scanned'),
      (
        'extension type Meters(int value) {}\n'
            '@Component() class Track { Track(this.length); final Meters length; }',
        'Cannot inject extension type Meters',
      ),
      (
        'extension type Meters(int value) {}\n'
            '@Configuration() class Config { @Bean() Meters m() => Meters(1); }',
        '@Bean method m returns extension type Meters',
      ),
    ]) {
      test(message, () async {
        expect(await _error(source), contains(message));
      });
    }
  });

  group('conditions and @Lazy', () {
    test('subclasses of Profile and Conditional count like the base', () async {
      final output = await _generate('''
class Dev extends Profile { const Dev() : super(const ['dev']); }

class OnLinux implements Condition {
  const OnLinux();
  @override
  bool matches(ConditionContext context) => true;
}

class IfLinux extends Conditional { const IfLinux() : super(const [OnLinux]); }

@Component() @Dev() class DevOnly {}
@Component() @IfLinux() class LinuxOnly {}
''');
      expect(output, _has("ProfileCondition([r'dev'])"));
      expect(output, _has('OnLinux()'));
    });

    test('class-level @Lazy on a lite configuration makes its @Bean methods '
        'lazy unless they say otherwise', () async {
      final output = await _generate('''
class A {}
class B {}
class C {}

@Component() @Lazy()
class Lite {
  @Bean() A a() => A();
  @Bean() @Lazy(false) B b() => B();
}

@Configuration(proxyBeanMethods: false) @Lazy()
class NoProxies {
  @Bean() C c() => C();
}
''');
      String definition(String name) {
        final start = output.indexOf("name:r'$name'");
        return output.substring(start, output.indexOf('create:', start));
      }

      expect(definition('a'), contains('lazy:true'));
      expect(definition('b'), isNot(contains('lazy:true')));
      expect(definition('c'), contains('lazy:true'));
    });
  });

  group('@ComponentScan roots', () {
    test('a nested root is imported, not scanned again', () async {
      final result = await _build({
        'lib/src/beans.dart': _scan,
        'lib/src/top.dart': '$_header@Component() class Top {}',
        'lib/src/feature/feature.dart': r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/feature/feature.spring.dart';

@ComponentScan()
final BeanModule featureBeans = $featureBeans;
''',
        'lib/src/feature/service.dart': '$_header@Component() class Inner {}',
        'lib/src/feature/deep/feature.dart': r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/feature/deep/feature.spring.dart';

@ComponentScan()
final BeanModule deepBeans = $deepBeans;
''',
        'lib/src/feature/deep/service.dart':
            '$_header@Component() class Deep {}',
      });
      expect(result.errors, isEmpty);
      final top = _output(result, 'lib/src/beans.spring.dart');
      expect(top, contains("name:r'top'"));
      expect(top, isNot(contains("name:r'inner'")));
      expect(top, isNot(contains("name:r'deep'")));
      expect(top, contains('imports:[featureBeans]'));
      final feature = _output(result, 'lib/src/feature/feature.spring.dart');
      expect(feature, contains("name:r'inner'"));
      expect(feature, isNot(contains("name:r'deep'")));
      expect(feature, contains('imports:[deepBeans]'));
    });

    test('@SpringBootApplication imports @ComponentScan modules', () async {
      final result = await _build({
        'bin/main.dart': r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''',
        'lib/src/beans.dart': _scan,
        'lib/src/service.dart': '$_header@Component() class Inner {}',
        'lib/other.dart': '$_header@Component() class Other {}',
      });
      expect(result.errors, isEmpty);
      final app = _output(result, 'bin/main.spring.dart');
      expect(app, contains("name:r'other'"));
      expect(app, isNot(contains("name:r'inner'")));
      expect(app, contains('imports:[pkgBeans]'));
    });

    test('two roots in one directory fail the build', () async {
      final message = await _errors({
        'lib/src/more.dart': r'''
import 'package:pkg/src/more.spring.dart';

@ComponentScan()
final BeanModule moreBeans = $moreBeans;
''',
      });
      expect(message, contains('Two @ComponentScan roots in lib/src/'));
    });

    test('glob characters in the directory name are escaped', () async {
      final result = await _build({
        'lib/v{1}/beans.dart': r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'beans.spring.dart';

@ComponentScan()
final BeanModule v1Beans = $v1Beans;
''',
        'lib/v{1}/service.dart': '$_header@Component() class Versioned {}',
        'lib/v1/service.dart': '$_header@Component() class Elsewhere {}',
      });
      expect(result.errors, isEmpty);
      final output = _output(result, 'lib/v{1}/beans.spring.dart');
      expect(output, contains("name:r'versioned'"));
      expect(output, isNot(contains("name:r'elsewhere'")));
    });
  });

  group('explicit bean names', () {
    for (final (source, message) in [
      (
        "@Component('') class A {}",
        "The bean name of A is empty: give a name, or remove it to use the "
            "default name 'a'.",
      ),
      ("@Service('  ') class A {}", 'The bean name of A is blank'),
      (
        "class A {}\n@Configuration() class C { @Bean(name: ' a') A a() => A(); }",
        "The bean name of @Bean method C.a ' a' starts or ends with "
            "whitespace: use 'a'.",
      ),
      (
        "class A {}\n@Configuration() class C { @Bean(aliases: ['']) A a() => A(); }",
        'An alias of @Bean method C.a is empty',
      ),
    ]) {
      test(message, () async {
        expect(await _error(source), contains(message));
      });
    }
  });

  group('constructors', () {
    test('super parameters carry the super constructor parameter '
        'annotations', () async {
      final output = await _generate(r'''
class Clock {}
abstract class Base {
  Base(@Value(r'${app.url}') this.url, @Qualifier('utc') this.clock);
  final String url;
  final Clock clock;
}

@Component()
class Child extends Base {
  Child(super.url, super.clock);
}

@Component()
class Own extends Base {
  Own(@Value(r'${own.url}') super.url, super.clock);
}
''');
      expect(
        output,
        _has(
          "Child(r.value<String>(r'\${app.url}'), "
          "r.dependency<Clock>(qualifier: r'utc', name: r'clock'))",
        ),
      );
      expect(output, _has("Own(r.value<String>(r'\${own.url}')"));
    });

    test('several @Autowired(required: false) constructors: the greediest '
        'one whose beans exist', () async {
      final files = {
        'lib/src/service.dart': '''
class Clock {}
class Zone {}

@Component()
class Report {
  @Autowired(required: false)
  Report.full(Clock this.clock, @Qualifier('utc') Zone this.zone);
  @Autowired(required: false)
  Report.clock(Clock this.clock) : zone = null;
  Report() : clock = null, zone = null;
  final Clock? clock;
  final Zone? zone;
}
''',
      };
      final result = await _build({
        'lib/src/beans.dart': _scan,
        for (final MapEntry(:key, :value) in files.entries)
          key: '$_header$value',
      });
      expect(result.errors, isEmpty);
      final output = _output(result, 'lib/src/beans.spring.dart');
      expect(
        output,
        _has(
          "create: (r) => r.containsBeanOfType(Clock) && "
          "r.containsBeanOfType(Zone, qualifier: r'utc') "
          "? Report.full(r.dependency<Clock>(name: r'clock'), "
          "r.dependency<Zone>(qualifier: r'utc', name: r'zone')) "
          ': r.containsBeanOfType(Clock) '
          "? Report.clock(r.dependency<Clock>(name: r'clock')) "
          ': Report()',
        ),
      );
      // No parameter is a required dependency in the metadata.
      expect(output, _has("Dependency(Clock, optional: true, name: r'clock')"));
      expect(await _diagnostics(files, proxyMode: ProxyMode.none), isEmpty);
    });

    test('without @Autowired: the single, the primary or the no-argument '
        'constructor', () async {
      final output = await _generate('''
class Clock {}

@Component()
class Single { Single.named(Clock clock); }

@Component()
class Primary(final Clock clock) {
  Primary.empty() : this(Clock());
}

@Component()
class NoArgument {
  NoArgument(Clock clock);
  NoArgument.empty();
  factory NoArgument.of(Clock clock) => NoArgument(clock);
}
''');
      expect(output, _has("Single.named(r.dependency<Clock>(name: r'clock'))"));
      expect(output, _has("Primary(r.dependency<Clock>(name: r'clock'))"));
      expect(output, _has('create: (r) => NoArgument.empty()'));
    });

    for (final (source, message) in [
      (
        'class Clock {}\n@Component() class A { A(Clock c); A.other(Clock c); }',
        'Cannot choose a constructor for A: it has several public '
            'constructors (A, A.other), neither a primary one nor a single '
            'one callable without arguments.',
      ),
      (
        '@Component() class A { @Autowired() A(); @Autowired(required: false) A.b(); }',
        'Only one constructor may be @Autowired when one of them is '
            'required: A is required',
      ),
      (
        '@Component() class A { A._(); }',
        'Bean class A has no public constructor',
      ),
      (
        'class Clock {}\n@Component() class A { @Autowired(required: false) late final Clock clock; }',
        '@Autowired(required: false) on field clock of A',
      ),
    ]) {
      test('rejects: $message', () async {
        expect(await _error(source), contains(message));
      });
    }
  });

  group('build errors', () {
    test('independent problems are reported together with their library '
        'URIs', () async {
      final message = await _errors({
        'lib/src/a.dart': '@Component() abstract class Broken {}',
        'lib/src/b.dart': "@Component('') class Unnamed {}",
      });
      expect(message, contains('2 problems in this build'));
      expect(message, contains('Bean class Broken must not be abstract.'));
      expect(message, contains('package:pkg/src/a.dart'));
      expect(message, contains('The bean name of Unnamed is empty'));
      expect(message, contains('package:pkg/src/b.dart'));
    });

    test(
      'generated code has no warnings; proxy classes are UpperCamelCase',
      () async {
        final files = {
          'lib/src/service.dart': r'''
abstract interface class Api { String call(); }
class ApiImpl implements Api { @override String call() => 'x'; }

@Configuration()
class Config {
  @Bean() Api api() => ApiImpl();
}

@Component()
class Greeter {
  Greeter(this.api, {@Value(r'${greeting:hi}') this.greeting = 'hi'});
  final Api api;
  final String greeting;
}
''',
        };
        expect(await _diagnostics(files), isEmpty);
        final output = await _generate(
          files['lib/src/service.dart']!,
          proxyMode: ProxyMode.all,
        );
        expect(output, contains(r'class_$Config$ApiProxy'));
      },
    );
  });
}
