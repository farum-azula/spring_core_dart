// `@Lookup` methods: a bean class with lookup methods (abstract or not)
// is created as a generated subclass whose lookup methods return beans of
// the container; a subclass AOP proxy extends that subclass.
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

/// The analyzer errors of the generated library [output] built from
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
            if (diagnostic.severity == Severity.error) diagnostic.message,
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|$path',
    readAllSourcesFromFilesystem: true,
  );
}

const _beans = r'''
@Component()
@Scope(ScopeType.prototype)
class Command {}

@Component()
class AuditLog {}

@Component()
abstract class CommandManager {
  @Lookup()
  Command createCommand();

  @Lookup('auditLog')
  AuditLog auditLog();

  @Lookup()
  AuditLog? optionalLog();

  @Lookup('auditLog')
  AuditLog? namedOptionalLog();

  String process() => '${createCommand()}';
}
''';

void main() {
  test('an abstract @Component class with @Lookup methods is a bean '
      'created as a generated subclass: by type and by name', () async {
    final output = await _generate(_beans, proxyMode: ProxyMode.none);
    expect(
      output,
      _has(r'class _$CommandManagerLookup extends CommandManager {'),
    );
    expect(
      output,
      _has(r'''
        _$CommandManagerLookup(this._$beanFactory);
        final BeanFactory _$beanFactory;
        @override
        Command createCommand() => this._$beanFactory.getBean<Command>();
        @override
        AuditLog auditLog() =>
            (this._$beanFactory.getBeanByName(r'auditLog') as AuditLog);
        @override
        AuditLog? optionalLog() => this._$beanFactory.findBean<AuditLog>();
        @override
        AuditLog? namedOptionalLog() =>
            NullBean.orNull<AuditLog>(this._$beanFactory.getBeanByName(r'auditLog'));
      '''),
    );
    expect(output, _has(r'create: (r) => _$CommandManagerLookup(r)'));
    expect(
      output,
      _has("BeanDefinition<CommandManager>(name: r'commandManager'"),
    );
    expect(await _compileErrors({'lib/src/service.dart': _beans}), isEmpty);
  });

  test('a concrete @Lookup method is overridden (its body never runs); '
      'constructor parameters are forwarded', () async {
    const beans = r'''
@Component()
@Scope(ScopeType.prototype)
class Command {}

@Component()
class Clock {}

@Component()
class Dispatcher {
  Dispatcher(this.clock, {this.name = 'main'});

  final Clock clock;
  final String name;

  @Lookup()
  Command command() => throw StateError('never called');
}
''';
    final output = await _generate(beans, proxyMode: ProxyMode.none);
    expect(
      output,
      _has(r'''
        class _$DispatcherLookup extends Dispatcher {
          _$DispatcherLookup(this._$beanFactory, super.p0, {super.name});
      '''),
    );
    expect(output, _has(r'create: (r) => _$DispatcherLookup(r,'));
    expect(await _compileErrors({'lib/src/service.dart': beans}), isEmpty);
  });

  test('lookup methods declared by a superclass, through a named '
      'constructor of a generic class', () async {
    const beans = r'''
@Component()
@Scope(ScopeType.prototype)
class Command {}

abstract class Base<T extends Object> {
  @Lookup()
  T next();
}

@Component()
abstract base class Runner extends Base<Command> {
  Runner.create();
}
''';
    final output = await _generate(beans, proxyMode: ProxyMode.none);
    expect(
      output,
      _has(r'''
        final class _$RunnerLookup extends Runner {
          _$RunnerLookup(this._$beanFactory) : super.create();
      '''),
    );
    expect(
      output,
      _has(r'Command next() => this._$beanFactory.getBean<Command>();'),
    );
    expect(await _compileErrors({'lib/src/service.dart': beans}), isEmpty);
  });

  group('lookup on an advised bean', () {
    test('a wrapper proxy forwards to the lookup subclass', () async {
      final output = await _generate(_beans);
      expect(
        output,
        _has(r'class _$CommandManagerProxy implements CommandManager'),
      );
      expect(output, _has(r'create: (r) => _$CommandManagerLookup(r)'));
      expect(await _compileErrors({'lib/src/service.dart': _beans}), isEmpty);
    });

    test('a subclass proxy extends the lookup subclass', () async {
      const beans = r'''
@Component()
@Scope(ScopeType.prototype)
class Command {}

@Component()
abstract class Counter {
  Counter(this.step);

  final int step;
  int _n = 0;

  int next() => _n += step;

  @Lookup()
  Command command();
}

@Configuration(proxyBeanMethods: false)
class Steps {
  @Bean()
  int step() => 2;
}
''';
      final output = await _generate(beans);
      expect(
        output,
        _has(r'''
          class _$CounterProxy extends _$CounterLookup implements Advised {
            _$CounterProxy(super.p0, super.p1);
        '''),
      );
      expect(output, _has(r'create: (r) => _$CounterProxy(r,'));
      expect(output, _has('AopProxyFactory.subclass('));
      expect(await _compileErrors({'lib/src/service.dart': beans}), isEmpty);
    });
  });

  test(
    'an abstract class without @Lookup methods is still no candidate',
    () async {
      final output = await _generate(
        '@Component() abstract class Base { void run(); }',
        proxyMode: ProxyMode.none,
      );
      expect(output, isNot(contains('Base')));
    },
  );

  group('build errors', () {
    Future<void> expectError(String beans, String message) async =>
        expect(await _errors(beans), contains(message));

    test(
      'a lookup method with parameters',
      () => expectError('''
@Component() class Command {}
@Component()
abstract class Manager {
  @Lookup()
  Command create(String name);
}
''', '@Lookup method Manager.create must not take parameters'),
    );

    test('a private, static or generic lookup method', () async {
      await expectError('''
@Component() class Command {}
@Component()
abstract class Manager {
  @Lookup()
  Command _create();
  void run() => _create();
}
''', '@Lookup method Manager._create must be public');
      await expectError('''
@Component() class Command {}
@Component()
class Manager {
  @Lookup()
  static Command create() => Command();
}
''', '@Lookup method Manager.create must not be static');
      await expectError('''
@Component()
abstract class Manager {
  @Lookup()
  T create<T>();
}
''', '@Lookup method Manager.create must not be generic');
    });

    test(
      'a getter or field',
      () => expectError('''
@Component() class Command {}
@Component()
abstract class Manager {
  @Lookup()
  Command get command;
}
''', '@Lookup on Manager.command: only methods can be lookup methods'),
    );

    test('a lookup by type without a class return type', () async {
      await expectError('''
@Component()
abstract class Manager {
  @Lookup()
  Object create();
}
''', '@Lookup method Manager.create returns Object: a lookup by type');
      await expectError('''
@Component()
abstract class Manager {
  @Lookup()
  void Function() create();
}
''', 'a lookup by type needs the bean class as return type');
    });

    test('a class the generated library cannot extend', () async {
      await expectError(
        '''
@Component() class Command {}
@Component()
final class Manager {
  @Lookup()
  Command create() => Command();
}
''',
        'Manager has @Lookup methods, which a generated subclass overrides to '
            'return beans of the container, but it cannot be extended (it is '
            'final)',
      );
      await expectError('''
@Component() class Command {}
@Component()
abstract class Manager {
  factory Manager() => throw UnimplementedError();
  @Lookup()
  Command create();
}
''', 'is created through the factory constructor');
    });

    test(
      'a full-mode @Configuration class',
      () => expectError('''
class Command {}
@Configuration()
class Config {
  @Bean()
  Command command() => Command();
  @Lookup()
  Command create() => command();
}
''', 'is a full-mode @Configuration class'),
    );

    test(
      'several optional constructors',
      () => expectError('''
@Component() class Command {}
@Component()
abstract class Manager {
  @Autowired(required: false)
  Manager();
  @Autowired(required: false)
  Manager.other(Command command);
  @Lookup()
  Command create();
}
''', 'Manager is created as a generated subclass (@Lookup methods)'),
    );
  });
}
