import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

// JSR-330 Provider<T>, JSR-250 @Resource and scoped proxies.

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

const _jakarta = "import 'package:spring_core_dart/jakarta.dart' as jakarta;\n";

const _greeters = '''
abstract interface class Greeter { String greet(); }

@Component()
class English implements Greeter {
  @override
  String greet() => 'hello';
}
''';

void main() {
  test('Provider<T> points get the lazy provider', () async {
    final code = await _generate('''
$_jakarta$_greeters
@Component()
class Clock {
  Clock(this.greeter);
  final jakarta.Provider<Greeter> greeter;

  @Autowired()
  late jakarta.Provider<English> english;
}
''');
    expect(code, _has("r.provider<Greeter>(name: r'greeter')"));
    expect(code, _has("Dependency.provider(Greeter, name: r'greeter')"));
    expect(code, _has("r.provider<English>(name: r'english')"));
  });

  test('@Resource fields and setters inject by name', () async {
    final code = await _generate('''
$_jakarta$_greeters
@Component()
class Reports {
  @jakarta.Resource()
  late Greeter english;

  @jakarta.Resource(name: 'english')
  Greeter? other;

  Greeter? _viaSetter;
  @jakarta.Resource()
  set viaSetter(Greeter greeter) => _viaSetter = greeter;
}
''');
    expect(
      code,
      _has(
        "bean.english = r.resource<Greeter>(r'english', fallbackToType: true)",
      ),
    );
    expect(code, _has("r.optionalResource<Greeter>(r'english')"));
    expect(
      code,
      _has(
        "bean.viaSetter = r.resource<Greeter>(r'viaSetter', fallbackToType: true)",
      ),
    );
    expect(
      code,
      _has("Dependency.resource(Greeter, r'english', fallbackToType: true)"),
    );
    expect(
      code,
      _has("Dependency.resource(Greeter, r'english', optional: true)"),
    );
  });

  test('@Resource is rejected where Spring rejects it', () async {
    expect(
      await _error('''
$_jakarta$_greeters
@Component()
class Reports {
  Reports(@jakarta.Resource() this.greeter);
  final Greeter greeter;
}
'''),
      contains('fields and setters only'),
    );
    expect(
      await _error('''
$_jakarta$_greeters
@Component()
class Reports {
  @jakarta.Resource()
  late List<Greeter> greeters;
}
'''),
      contains('one bean by name'),
    );
  });

  test('@Scope(proxyMode:) registers the lazy proxy as scoped proxy', () async {
    const source = '''
@Component()
@Scope('session', proxyMode: ScopedProxyMode.targetClass)
class Cart {
  final items = <String>[];
  int get size => items.length;
}

@Component()
class Shop {
  Shop(this.cart);
  final Cart cart;
}
''';
    final code = await _generate(source);
    expect(code, _has(r"scope: r'session', scopedProxy: _$CartLazy.new"));
    expect(code, _has(r'class _$CartLazy implements Cart'));
    expect(
      await _diagnostics({'lib/src/service.dart': source}),
      isEmpty,
      reason: 'the generated code compiles against the runtime',
    );
    expect(
      await _error('''
@Component()
@Scope(ScopeType.singleton, proxyMode: ScopedProxyMode.interfaces)
class Cart {}
'''),
      contains('a singleton needs no scoped proxy'),
    );
  });

  test('Provider and @Resource generated code compiles', () async {
    expect(
      await _diagnostics({
        'lib/src/service.dart':
            '''
$_jakarta$_greeters
@Component()
class Reports {
  Reports(this.provider);
  final jakarta.Provider<Greeter> provider;

  @jakarta.Resource()
  late Greeter english;
}
''',
      }),
      isEmpty,
    );
  });
}
