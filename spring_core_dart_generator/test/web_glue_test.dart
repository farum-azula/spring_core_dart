// The glue between the web starter and the data starter: a module of an
// application that depends on both gets the data starter's template (with
// the library's import prefixes) and a HandlerExceptionResolver bean
// definition that answers data errors with their HTTP status; with only one
// of them, or without the template, nothing is added. The starters are the
// real ones: the generated code must compile against them.
//
// What the resolver answers is checked in web_glue_runtime_test.dart.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _template =
    'spring_boot_starter_data|'
    'lib/src/web/data_access_exception_resolver.dart.tmpl';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _service = '''
import 'package:spring_core_dart/spring_core_dart.dart';

@Service()
class Greeter {}
''';

String _pubspec({
  bool web = true,
  bool data = true,
  bool sqlite = false,
  bool dev = false,
}) {
  final dependencies = [
    if (data) '  spring_boot_starter_data: any',
    if (web && !dev) '  spring_boot_starter_web: any',
    if (sqlite) '  sqlite3: any',
  ];
  return [
    'name: pkg',
    'dependencies:',
    ...dependencies,
    if (web && dev) ...['dev_dependencies:', '  spring_boot_starter_web: any'],
  ].join('\n');
}

Map<String, Object> _sources({String? pubspec}) => {
  'pkg|pubspec.yaml': pubspec ?? _pubspec(),
  'pkg|lib/src/beans.dart': _scan,
  'pkg|lib/src/service.dart': _service,
};

Future<String> _build(
  Map<String, Object> sources, {
  bool template = true,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  // The isolate's sources include the real starters: their real template
  // is the one under test.
  await readerWriter.testing.loadIsolateSources();
  if (!template) {
    readerWriter.testing.delete(AssetId.parse(_template));
  }
  final result = await testBuilder(
    SpringBuilder(),
    sources,
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  return result.readerWriter.testing.readString(result.outputs.single);
}

String _normalize(String code) => code.replaceAll(RegExp(r'\s'), '');

void main() {
  group('with both starters among the dependencies', () {
    late String output;

    setUpAll(() async => output = await _build(_sources()));

    test('the resolver is written into the module', () {
      expect(output, contains(r'class _$DataAccessExceptionResolver'));
      expect(output, contains(r'_$dataAccessExceptionResolver()'));
      expect(output, contains("'The resource was changed by someone else'"));
      expect(output, contains("'The resource already exists'"));
      expect(output, contains("'Not found'"));
      expect(output, contains("'Invalid sort property'"));
      expect(output, contains("'Invalid page or sort request'"));
    });

    test('the symbols get the library import prefixes', () {
      expect(output, isNot(contains('{{')));
      expect(output, isNot(contains('}}')));
      final web = RegExp(
        "import 'package:spring_boot_starter_web/"
        r"spring_boot_starter_web.dart'\s+as (_i\d+);",
      ).firstMatch(output);
      expect(web, isNotNull);
      final data = RegExp(
        "import 'package:spring_boot_starter_data/"
        r"spring_boot_starter_data.dart'\s+as (_i\d+);",
      ).firstMatch(output);
      expect(data, isNotNull);
      final w = web![1];
      final d = data![1];
      expect(output, contains('implements $w.HandlerExceptionResolver'));
      expect(output, contains('$d.OptimisticLockingFailureException()'));
      expect(output, contains('$d.DuplicateKeyException()'));
      expect(output, contains('$d.EmptyResultDataAccessException()'));
      expect(output, contains('$d.PropertyReferenceException()'));
      expect(output, contains('$d.InvalidPagingRequestException()'));
      expect(output, contains('$w.ResponseStatusException('));
      expect(output, contains('$w.HttpStatus.conflict'));
      expect(output, contains('$w.HttpStatus.notFound'));
      expect(output, contains('$w.HttpStatus.badRequest'));
    });

    test('the documentation of the template is not copied', () {
      expect(output, isNot(contains('NOT a Dart library')));
      expect(output, isNot(contains('placeholder syntax')));
    });

    test('a HandlerExceptionResolver bean definition, once, replaceable by '
        'name', () {
      final code = _normalize(output);
      expect(code, contains("name:r'dataAccessExceptionResolver'"));
      expect(code, contains('BeanDefinition<'));
      expect(code, contains(r'create:(r)=>_$dataAccessExceptionResolver()'));
      expect(code, contains(".named(r'dataAccessExceptionResolver')"));
      expect(code, contains('HandlerExceptionResolver],'));
      expect(
        RegExp(r'HandlerExceptionResolver>\(').allMatches(output),
        hasLength(1),
      );
    });

    test('no database driver glue: no sqlite3 among the dependencies', () {
      expect(output, isNot(contains('sqlite3')));
      expect(output, isNot(contains('JdbcDriver')));
    });

    test('the generated code compiles against the starters', () async {
      final errors = await resolveSources<List<String>>(
        {
          for (final MapEntry(:key, :value) in _sources().entries)
            key: value as String,
          'pkg|lib/src/beans.spring.dart': output,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId('pkg', 'lib/src/beans.spring.dart'),
          );
          final result = await library.session.getErrors(
            library.firstFragment.source.fullName,
          );
          return [
            if (result case ErrorsResult(:final diagnostics))
              for (final diagnostic in diagnostics)
                if (diagnostic.severity == Severity.error) diagnostic.message,
          ];
        },
        rootPackage: 'pkg',
        resolverFor: 'pkg|lib/src/beans.spring.dart',
        readAllSourcesFromFilesystem: true,
      );
      expect(errors, isEmpty);
    });
  });

  test('with sqlite3 too, each glue is written once', () async {
    final output = await _build(_sources(pubspec: _pubspec(sqlite: true)));
    expect(
      RegExp(r'HandlerExceptionResolver>\(').allMatches(output),
      hasLength(1),
    );
    expect(RegExp(r'JdbcDriver>\(').allMatches(output), hasLength(1));
  });

  group('nothing is written', () {
    Future<void> expectNoGlue(
      Map<String, Object> sources, {
      bool template = true,
    }) async {
      final output = await _build(sources, template: template);
      expect(output, isNot(contains('HandlerExceptionResolver')));
      expect(output, isNot(contains('DataAccessException')));
      expect(output, isNot(contains('ResponseStatusException')));
    }

    test('without the web starter among the dependencies', () async {
      await expectNoGlue(_sources(pubspec: _pubspec(web: false)));
    });

    test('with the web starter only as a dev dependency of a lib/ '
        'module', () async {
      await expectNoGlue(_sources(pubspec: _pubspec(dev: true)));
    });

    test('without the data starter among the dependencies', () async {
      await expectNoGlue(_sources(pubspec: _pubspec(data: false)));
    });

    test('without either', () async {
      await expectNoGlue(
        _sources(pubspec: _pubspec(web: false, data: false)),
      );
    });

    test('without the data starter template', () async {
      await expectNoGlue(_sources(), template: false);
    });

    test('without a readable pubspec', () async {
      await expectNoGlue(_sources()..remove('pkg|pubspec.yaml'));
    });
  });
}
