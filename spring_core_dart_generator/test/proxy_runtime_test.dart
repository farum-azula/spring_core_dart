// Generated proxies run: the generator output for an application is written
// next to its sources and started in a separate process, so the advice the
// tests expect is the advice the generated code really applies.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _header = "import 'package:spring_core_dart/spring_core_dart.dart';\n";

/// Builds the application of [library] (`package:pkg/app.dart`) and [main]
/// (`bin/main.dart`), runs it and returns the JSON value it prints after
/// `RESULT `.
Future<Object?> _run(
  String library,
  String main, {
  ProxyMode proxyMode = ProxyMode.all,
}) async {
  final sources = {'lib/app.dart': '$_header$library', 'bin/main.dart': main};
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(proxyMode: proxyMode),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final directory = await Directory.systemTemp.createTemp('spring_proxy_');
  addTearDown(() => directory.delete(recursive: true));
  final files = {
    ...sources,
    for (final output in result.outputs)
      output.path: readerWriter.testing.readString(output),
  };
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File('${directory.path}/$key');
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }
  final workspace = await loadPackageConfigUri((await Isolate.packageConfig)!);
  await savePackageConfig(
    PackageConfig([
      ...workspace.packages,
      Package(
        'pkg',
        directory.uri,
        packageUriRoot: directory.uri.resolve('lib/'),
      ),
    ]),
    directory,
  );
  final process = await Process.run(Platform.resolvedExecutable, [
    '--packages=${directory.path}/.dart_tool/package_config.json',
    '${directory.path}/bin/main.dart',
  ]);
  final output = '${process.stdout}';
  final line = LineSplitter.split(output)
      .where((line) => line.startsWith('RESULT '))
      .firstOrNull;
  expect(line, isNotNull, reason: '$output\n${process.stderr}');
  return jsonDecode(line!.substring('RESULT '.length));
}

/// A `main` that starts the application, calls [calls] (statements using
/// `context`) and prints the calls `Tracer` recorded.
String _main(String calls) =>
    '''
import 'dart:convert';

import 'package:pkg/app.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'main.spring.dart';

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await runApplicationAsync([
    '--spring.main.banner-mode=off',
    '--logging.level.root=off',
  ]);
  $calls
  print('RESULT \${jsonEncode(context.getBean<Tracer>().calls)}');
  context.close();
}
''';

const _ledger = r'''

@Service()
class Ledger extends Base {
  int _calls = 0;

  @override
  String overridden(String name) => 'ledger ${++_calls}';
}
''';

const _ledgerCalls = '''
  final ledger = context.getBean<Ledger>();
  call(() => ledger.overridden('ok'));
  call(() => ledger.inherited());
''';

void main() {
  test('a class with private state and an implementable superclass, '
      'interface or mixin is proxied by a subclass: advice matched on the '
      'class, its supertypes and its mixins runs', () async {
    final calls = await _run(
      r'''
class Audited {
  const Audited();
}

abstract interface class Orders {
  int place(String item);
}

class Base {
  String describe() => 'base';
}

mixin Auditing {
  final entries = <String>[];

  void record(String entry) => entries.add(entry);
}

// Private state, an implementable superclass and interface.
@Service()
class DefaultOrders extends Base implements Orders {
  int _placed = 0;

  @Audited()
  @override
  int place(String item) => ++_placed;
}

// A base class: only a base / final subclass can extend it.
@Service()
base class Ledger implements Orders {
  @Audited()
  @override
  int place(String item) => item.length;
}

// Private state and a mixin.
@Service()
class Journal with Auditing {
  final _lines = <String>[];

  @Audited()
  int write(String line) {
    _lines.add(line);
    return _lines.length;
  }
}

@Aspect()
@Component()
class Tracer {
  final calls = <String>[];

  @Before('@annotation(Audited)')
  void audited(JoinPoint joinPoint) =>
      calls.add('audited ${joinPoint.signature.name}');

  @Before('execution(* Orders.*(..))')
  void orders(JoinPoint joinPoint) =>
      calls.add('orders ${joinPoint.signature.name}');

  @Before('execution(* Base.*(..)) || execution(* Auditing.*(..))')
  void inherited(JoinPoint joinPoint) =>
      calls.add('inherited ${joinPoint.signature.name}');
}
''',
      _main('''
  context.getBean<DefaultOrders>().place('book');
  context.getBean<DefaultOrders>().describe();
  context.getBean<Ledger>().place('pen');
  context.getBean<Journal>().write('line');
  context.getBean<Journal>().record('entry');
'''),
    );
    expect(calls, [
      'audited place',
      'orders place',
      'inherited describe',
      'audited place',
      'orders place',
      'audited write',
      'inherited record',
    ]);
  });

  test('annotations with Symbol and record values are kept', () async {
    final calls = await _run(
      r'''
class Tagged {
  const Tagged(this.symbol, this.range, {this.pair});
  final Symbol symbol;
  final (int, {String unit}) range;
  final (String,)? pair;
}

@Service()
class Meter {
  @Tagged(#speed, (10, unit: 'km/h'), pair: ('x',))
  int read() => 1;
}

@Aspect()
@Component()
class Tracer {
  final calls = <String>[];

  @Before('@annotation(tag)')
  void tagged(Tagged tag) =>
      calls.add('${tag.symbol == #speed} ${tag.range} ${tag.pair}');
}
''',
      _main('''
  context.getBean<Meter>().read();
'''),
    );
    expect(calls, ['true (10, unit: km/h) (x)']);
  });

  test('wildcard parameters are forwarded', () async {
    final calls = await _run(
      r'''
abstract interface class Sink {
  String put(int _, int _, [String _ = 'x']);
}

@Service()
class Writer implements Sink {
  Writer(int _);

  final _log = <String>[];

  @override
  String put(int _, int _, [String _ = 'x']) {
    _log.add('put');
    return 'ok ${_log.length}';
  }
}

@Configuration()
class Numbers {
  @Bean()
  int number() => 1;
}

@Aspect()
@Component()
class Tracer {
  final calls = <String>[];

  @Around('execution(* put(..))')
  Object? around(ProceedingJoinPoint joinPoint) {
    final result = joinPoint.proceed();
    calls.add('${joinPoint.args} $result');
    return result;
  }
}
''',
      _main('''
  context.getBean<Writer>().put(1, 2);
  context.getBean<Sink>().put(3, 4, 'y');
'''),
    );
    expect(calls, ['[1, 2, x] ok 1', '[3, 4, y] ok 2']);
  });
  test('a full-mode @Configuration @Bean method with wildcard parameters '
      'is overridden and its inter-bean calls return the bean', () async {
    final calls = await _run(
      r'''
class Label {
  Label(this.text);
  final String text;
}

class Greeting {
  Greeting(this.label);
  final Label label;
}

@Configuration()
class Wiring {
  var created = 0;

  @Bean()
  int number() => 7;

  @Bean()
  Label label(int _, [String _ = 'x']) => Label('label ${++created}');

  @Bean()
  Greeting greeting() => Greeting(label(1));
}

@Component()
class Tracer {
  final calls = <String>[];
}
''',
      _main('''
  final tracer = context.getBean<Tracer>();
  final greeting = context.getBean<Greeting>();
  tracer.calls.add(greeting.label.text);
  tracer.calls.add(
    '\${identical(greeting.label, context.getBean<Label>())}',
  );
  tracer.calls.add(
    '\${identical(context.getBean<Wiring>().label(2, 'y'), greeting.label)}',
  );
'''),
    );
    expect(calls, ['label 1', 'true', 'true']);
  });
  for (final proxyMode in ProxyMode.values.where((m) => m != ProxyMode.none)) {
    test(
      'parameter constraints of implemented interfaces and superclasses '
      'are validated ($proxyMode proxies, like Hibernate Validator)',
      () async {
        final calls = await _run(
          r'''
abstract interface class Root {
  String rename(@Size(min: 2) String name);
}

abstract interface class Accounts implements Root {
  String register(@NotBlank() String email);
}

abstract class Labelled {
  String label({@NotNull() String? tag});
}

@Service()
@Validated()
class DefaultAccounts extends Labelled implements Accounts {
  final _log = <String>[];

  @override
  String register(String email) {
    _log.add(email);
    return 'registered ${_log.length}';
  }

  @override
  String rename(String name) => 'renamed';

  @override
  String label({String? tag}) => 'labelled';
}

@Component()
class Tracer {
  final calls = <String>[];
}
''',
          _main('''
  final tracer = context.getBean<Tracer>();
  final accounts = context.getBean<Accounts>();
  void call(Object? Function() action) {
    try {
      tracer.calls.add('\${action()}');
    } on ConstraintViolationException catch (e) {
      tracer.calls.addAll([
        for (final v in e.constraintViolations) '\${v.propertyPath}: \${v.message}',
      ]);
    }
  }
  call(() => accounts.register(''));
  call(() => accounts.register('a@b.c'));
  call(() => accounts.rename('x'));
  call(() => (accounts as Labelled).label());
'''),
          proxyMode: proxyMode,
        );
        expect(calls, [
          'register.email: must not be blank',
          'registered 1',
          'rename.name: size must be between 2 and 2147483647',
          'label.tag: must not be null',
        ]);
      },
    );
  }
  for (final proxyMode in ProxyMode.values.where((m) => m != ProxyMode.none)) {
    test('@annotation sees the implementation and interface declarations, '
        'not an overridden superclass method (like AspectJ), while '
        'constraints are inherited ($proxyMode proxies)', () async {
      final calls = await _run(
        r'''
class Audited {
  const Audited();
}

abstract interface class Api {
  @Audited()
  String declared();

  String overridden(String name);
}

class Base {
  @Audited()
  @NotBlank()
  String overridden(@Size(min: 2) String name) => 'base';

  @Audited()
  String inherited() => 'base';
}

@Service()
@Validated()
class Child extends Base implements Api {
  @override
  String declared() => 'declared';

  @override
  String overridden(String name) => name == 'empty' ? '' : 'child';
}

@Aspect()
@Component()
class Tracer {
  final calls = <String>[];

  @Before('@annotation(Audited)')
  void audited(JoinPoint joinPoint) =>
      calls.add('audited ${joinPoint.signature.name}');
}
'''
        // Private state: a subclass proxy (`all` mode only, it implements
        // no interface).
        '${proxyMode == ProxyMode.all ? _ledger : ''}',
        _main('''
  final tracer = context.getBean<Tracer>();
  final api = context.getBean<Api>();
  void call(Object? Function() action) {
    try {
      tracer.calls.add('\${action()}');
    } on ConstraintViolationException catch (e) {
      tracer.calls.addAll([
        for (final v in e.constraintViolations) '\${v.propertyPath}: \${v.message}',
      ]);
    }
  }
  call(() => api.declared());
  call(() => api.overridden('ok'));
  call(() => api.overridden('x'));
  call(() => api.overridden('empty'));
  if (api is Child) call(() => api.inherited());
  ${proxyMode == ProxyMode.all ? _ledgerCalls : ''}
'''),
        proxyMode: proxyMode,
      );
      expect(calls, [
        'audited declared',
        'declared',
        'child',
        'overridden.name: size must be between 2 and 2147483647',
        'overridden.<return value>: must not be blank',
        if (proxyMode == ProxyMode.all) ...[
          'audited inherited',
          'base',
          'ledger 1',
          'audited inherited',
          'base',
        ],
      ]);
    });
  }
  for (final proxyMode in ProxyMode.values.where((m) => m != ProxyMode.none)) {
    test('@Cacheable and @Validated on an overridden superclass method apply '
        'to the override (like Spring\'s annotation sources), while '
        '@annotation does not match it ($proxyMode proxies)', () async {
      final calls = await _run(
        r'''
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';

class Audited {
  const Audited();
}

abstract interface class Catalog {
  String find(String isbn);

  String title(String isbn);
}

class Strict {}

class BaseCatalog {
  @Cacheable('books')
  @Audited()
  String find(String isbn) => 'base';

  @Validated([Strict])
  String title(@Size(min: 2, groups: [Strict]) String isbn) => 'base';
}

@Service()
@Validated()
class Books extends BaseCatalog implements Catalog {
  int lookups = 0;

  @override
  String find(String isbn) => '$isbn ${++lookups}';

  @override
  String title(String isbn) => 'title $isbn';
}

@Aspect()
@Component()
class Tracer {
  final calls = <String>[];

  @Before('@annotation(Audited)')
  void audited(JoinPoint joinPoint) =>
      calls.add('audited ${joinPoint.signature.name}');
}
''',
        _main('''
  final tracer = context.getBean<Tracer>();
  final catalog = context.getBean<Catalog>();
  void call(Object? Function() action) {
    try {
      tracer.calls.add('\${action()}');
    } on ConstraintViolationException catch (e) {
      tracer.calls.addAll([
        for (final v in e.constraintViolations) '\${v.propertyPath}: \${v.message}',
      ]);
    }
  }
  call(() => catalog.find('a'));
  call(() => catalog.find('a'));
  call(() => catalog.find('b'));
  call(() => catalog.title('x'));
  call(() => catalog.title('xy'));
'''),
        proxyMode: proxyMode,
      );
      expect(calls, [
        'a 1',
        'a 1',
        'b 2',
        'title.isbn: size must be between 2 and 2147483647',
        'title xy',
      ]);
    });
  }

  test('@CacheConfig and class-level cache annotations are read from the '
      'class declaring the method and its superclasses, like Spring', () async {
    final calls = await _run(
      r'''
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';

@CacheConfig(cacheNames: ['books'])
abstract class CachedRepo {
  int lookups = 0;

  @Cacheable.of()
  String find(String isbn) => '$isbn ${++lookups}';
}

@Service()
class BookRepo extends CachedRepo {}

@Cacheable('authors')
class BaseAuthors {
  int lookups = 0;

  String find(String name) => '$name ${++lookups}';
}

class MiddleAuthors extends BaseAuthors {}

@Service()
class Authors extends MiddleAuthors {}

@Component()
class Tracer {
  Tracer(this.cacheManager);

  final CacheManager cacheManager;
  final calls = <String>[];
}
''',
      _main('''
  final tracer = context.getBean<Tracer>();
  final books = context.getBean<BookRepo>();
  final authors = context.getBean<Authors>();
  tracer.calls.addAll([
    books.find('a'),
    books.find('a'),
    authors.find('x'),
    authors.find('x'),
    ...tracer.cacheManager.cacheNames,
  ]);
'''),
    );
    expect(calls, ['a 1', 'a 1', 'x 1', 'x 1', 'books', 'authors']);
  });

  test('Boot bean conditions are decided when beans register: registrar '
      'beans make auto-configurations and later classes back off, and a '
      'class, its beans and its imports share one decision', () async {
    final calls = await _run(r"""
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';

class Ticker {
  Ticker(this.name);
  final String name;
}

class Audit {}

class Feature {}

class Pool {}

class CacheRegistrar implements BeanRegistrar {
  @override
  void register(BeanRegistry registry, Environment environment) =>
      registry.registerBean<CacheManager>(
        (_) => InMemoryCacheManager(),
        name: 'appCacheManager',
      );
}

class TickerRegistrar implements ImportBeanDefinitionRegistrar {
  @override
  void registerBeanDefinitions(BeanDefinitionRegistry registry) =>
      registry.registerBeanDefinition(
        BeanDefinition<Ticker>(
          name: 'registrarTicker',
          create: (_) => Ticker('registrar'),
        ),
      );
}

class AuditRegistrar implements BeanRegistrar {
  @override
  void register(BeanRegistry registry, Environment environment) =>
      registry.registerBean<Audit>((_) => Audit(), name: 'registrarAudit');
}

class FallbackRegistrar implements BeanRegistrar {
  @override
  void register(BeanRegistry registry, Environment environment) =>
      registry.registerBean<Audit>((_) => Audit(), name: 'fallbackAudit');
}

class FeatureSelector implements ImportSelector {
  @override
  List<BeanModule> selectImports() => [
    BeanModule('feature', [
      BeanDefinition<Feature>(name: 'feature', create: (_) => Feature()),
    ]),
  ];
}

@Configuration()
@Import([CacheRegistrar])
class AppConfig {}

@Configuration()
@Import([TickerRegistrar])
class AEarlier {}

@Configuration()
class BLater {
  @Bean()
  @ConditionalOnMissingBean()
  Ticker laterTicker() => Ticker('later');
}

@Configuration()
@ConditionalOnBean(Ticker)
@Import([AuditRegistrar, FeatureSelector])
class AuditConfig {
  @Bean()
  Audit audit() => Audit();
}

@Configuration()
@ConditionalOnMissingBean(Ticker)
@Import([FallbackRegistrar])
class FallbackConfig {
  @Bean()
  Ticker fallbackTicker() => Ticker('fallback');
}

class HikariConfig {
  @Bean()
  Pool pool() => Pool();
}

@Configuration()
@ConditionalOnMissingBean(Pool)
@Import([HikariConfig])
class PooledConfig {}

@Component()
class Tracer {
  final calls = <String>[];
}

List<String> report(ApplicationContext context) => [
  ...context.getBeanNamesForType(CacheManager),
  ...context.getBeanNamesForType(Ticker),
  for (final name in [
    'auditConfig',
    'audit',
    'registrarAudit',
    'feature',
    'fallbackConfig',
    'fallbackAudit',
    'hikariConfig',
    'pool',
    'pooledConfig',
  ])
    '$name ${context.containsBean(name)}',
];
""", _main('context.getBean<Tracer>().calls.addAll(report(context));'));
    expect(calls, [
      'appCacheManager',
      'registrarTicker',
      'auditConfig true',
      'audit true',
      'registrarAudit true',
      'feature true',
      'fallbackConfig false',
      'fallbackAudit false',
      'hikariConfig true',
      'pool true',
      'pooledConfig true',
    ]);
  });

  test('Boot bean conditions of components and imported classes are '
      'decided in the reader, in class order', () async {
    final calls = await _run(r"""
import 'package:spring_boot_dart/spring_boot_dart.dart';

abstract interface class Clock {}

class RegistrarClock implements Clock {}

abstract interface class Greeting {}

class RegistrarGreeting implements Greeting {}

class Mailer {}

class ClockRegistrar implements BeanRegistrar {
  @override
  void register(BeanRegistry registry, Environment environment) {
    registry.registerBean<Clock>((_) => RegistrarClock(), name: 'registrarClock');
    registry.registerBean<Greeting>(
      (_) => RegistrarGreeting(),
      name: 'registrarGreeting',
    );
  }
}

@Configuration()
@Import([ClockRegistrar])
class AConfig {}

@Component()
@ConditionalOnMissingBean(Clock)
class DefaultClock implements Clock {}

// Before the @Bean it looks for in class order: decided first.
@Component()
@ConditionalOnBean(Mailer)
class EarlyListener {}

@Configuration()
class BConfig {
  @Bean()
  @ConditionalOnMissingBean()
  Mailer mailer() => Mailer();
}

@Component()
@ConditionalOnBean(Mailer)
class MailListener {}

@ConditionalOnMissingBean(Greeting)
class DefaultGreeting implements Greeting {}

@Configuration()
@Import([DefaultGreeting])
class CConfig {}

@Component()
class Tracer {
  final calls = <String>[];
}

List<String> report(ApplicationContext context) => [
  ...context.getBeanNamesForType(Clock),
  ...context.getBeanNamesForType(Greeting),
  for (final name in ['mailer', 'earlyListener', 'mailListener'])
    '$name ${context.containsBean(name)}',
];
""", _main('context.getBean<Tracer>().calls.addAll(report(context));'));
    expect(calls, [
      'registrarClock',
      'registrarGreeting',
      'mailer true',
      'earlyListener false',
      'mailListener true',
    ]);
  });
}
