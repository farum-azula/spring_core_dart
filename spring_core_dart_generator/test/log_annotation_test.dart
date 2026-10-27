// `@Log`: a `log` getter generated as an extension on the class, like
// Lombok's `@Slf4j`. The output is compiled with the scanned library.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _header = '''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';
''';

Future<TestBuilderResult> _build(String app) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(),
    {'pkg|lib/src/beans.dart': _scan, 'pkg|lib/src/app.dart': '$_header$app'},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

String _normalize(String code) =>
    code.replaceAll(RegExp(r'\b_i\d+\.'), '').replaceAll(RegExp(r'\s'), '');

/// The generated library (normalized), after checking that it and the
/// scanned library using the getters compile.
Future<String> _generate(String app) async {
  final result = await _build(app);
  expect(result.errors, isEmpty);
  const path = 'lib/src/beans.spring.dart';
  final output = result.readerWriter.testing.readString(
    result.outputs.singleWhere((o) => o.path == path),
  );
  final errors = await resolveSources<List<String>>(
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': '$_header$app',
      'pkg|$path': output,
    },
    (resolver) async {
      final messages = <String>[];
      for (final library in ['lib/src/app.dart', path]) {
        final element = await resolver.libraryFor(AssetId('pkg', library));
        final errors = await element.session.getErrors(
          element.firstFragment.source.fullName,
        );
        if (errors case ErrorsResult(:final diagnostics)) {
          messages.addAll([
            for (final diagnostic in diagnostics)
              if (diagnostic.severity == Severity.error) diagnostic.message,
          ]);
        }
      }
      return messages;
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|$path',
    readAllSourcesFromFilesystem: true,
  );
  expect(errors, isEmpty, reason: output);
  return _normalize(output);
}

Future<String> _errors(String app) async {
  final result = await _build(app);
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

void main() {
  test('a getter named log, the logger named <package>.<Class>', () async {
    final output = await _generate('''
@Component()
@Log()
class Checkout {
  void pay() => log.info('paid');
}

// Not a bean: works too.
@Log(topic: 'neon.payments', fieldName: 'logger')
class Payments {
  void refund() => logger.warning('refund');
}

@Log()
class Repo<T> {
  void save(T value) => log.debug(() => 'saving');
}
''');
    expect(
      output,
      contains(
        _normalize(r'''
extension $CheckoutLog on Checkout {
  SpringLog get log => const SpringLog(r'pkg.Checkout');
}'''),
      ),
    );
    expect(
      output,
      contains(
        _normalize(r'''
extension $PaymentsLog on Payments {
  SpringLog get logger => const SpringLog(r'neon.payments');
}'''),
      ),
    );
    expect(output, contains(_normalize(r'extension $RepoLog on Repo {')));
  });

  test('a getter that cannot work fails the build', () async {
    for (final (source, message) in [
      (
        '@Log()\nclass _Hidden {}\nvoid use() => _Hidden();',
        '@Log on _Hidden: the class is private',
      ),
      (
        "@Log(fieldName: 'class')\nclass A {}",
        '@Log on A: fieldName "class" is not a valid getter name',
      ),
      (
        "@Log(fieldName: '1log')\nclass B {}",
        '@Log on B: fieldName "1log" is not a valid getter name',
      ),
      (
        '@Log()\nclass C {\n  final log = 1;\n}',
        '@Log on C: C already has a member "log"',
      ),
      (
        'class Base {\n  void log() {}\n}\n@Log()\nclass D extends Base {}',
        '@Log on D: D already has a member "log"',
      ),
    ]) {
      expect(await _errors(source), contains(message), reason: source);
    }
  });
}
