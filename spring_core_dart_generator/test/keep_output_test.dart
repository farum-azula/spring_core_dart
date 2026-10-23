// An error in the sources never removes or changes an existing output:
// `build_runner watch` while typing (syntax errors most of the time) must
// not make the generated file flicker in and out on every keystroke.
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
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

const _good = '$_header@Service()\nclass Greeter {}\n';

// Missing `}`: does not parse.
const _syntaxError = '$_header@Service()\nclass Greeter {\n';

// Parses, but a private bean class is a generator error.
const _validationError = '$_header@Service()\nclass _Greeter {}\n';

final _output = AssetId('pkg', 'lib/src/beans.beans.dart');

SpringBuilder _builder({Future<String?> Function(AssetId)? read}) =>
    SpringBuilder(
      proxyMode: ProxyMode.none,
      readExistingOutput: read ?? (_) async => null,
    );

/// Builds the scan root and [service] with [builder]; returns the result,
/// the generated content (`null` when there is none) and the log records
/// as `LEVEL: message`.
Future<(TestBuilderResult, String?, List<String>)> _build(
  SpringBuilder builder,
  String service,
) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final logs = <String>[];
  final result = await testBuilder(
    builder,
    {'pkg|lib/src/beans.dart': _scan, 'pkg|lib/src/service.dart': service},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
  );
  final testing = result.readerWriter.testing;
  return (
    result,
    testing.exists(_output) ? testing.readString(_output) : null,
    logs,
  );
}

Iterable<String> _warnings(List<String> logs) =>
    logs.where((log) => log.startsWith('WARNING: '));

Iterable<String> _severe(List<String> logs) =>
    logs.where((log) => log.startsWith('SEVERE: '));

void main() {
  test(
    'syntax error after a good build keeps the output, warns once',
    () async {
      final builder = _builder();
      final (good, content, _) = await _build(builder, _good);
      expect(good.succeeded, isTrue);
      expect(content, contains('Greeter'));

      var (result, kept, logs) = await _build(builder, _syntaxError);
      expect(result.succeeded, isTrue);
      expect(result.errors, isEmpty);
      expect(kept, content);
      expect(_warnings(logs), hasLength(1));
      expect(
        _warnings(logs).single,
        allOf(
          contains('lib/src/beans.beans.dart is kept unchanged'),
          contains('lib/src/service.dart has syntax errors'),
        ),
      );

      // Still broken: no second warning.
      (result, kept, logs) = await _build(builder, '$_syntaxError  void f(');
      expect(result.succeeded, isTrue);
      expect(kept, content);
      expect(_warnings(logs), isEmpty);

      // Fixed: generated again; the next syntax error warns again.
      (result, kept, logs) = await _build(
        builder,
        '$_good@Service()\nclass Other {}\n',
      );
      expect(result.succeeded, isTrue);
      expect(kept, isNot(content));
      (result, _, logs) = await _build(builder, _syntaxError);
      expect(result.succeeded, isTrue);
      expect(_warnings(logs), hasLength(1));
    },
  );

  test('syntax error after a fresh start reads the file on disk', () async {
    const onDisk = '// previous generation\n';
    final reads = <AssetId>[];
    final builder = _builder(
      read: (id) async {
        reads.add(id);
        return onDisk;
      },
    );
    final (result, kept, logs) = await _build(builder, _syntaxError);
    expect(result.succeeded, isTrue);
    expect(kept, onDisk);
    expect(reads, [_output]);
    expect(_warnings(logs), hasLength(1));
  });

  test('cold build with a syntax error fails', () async {
    final (result, kept, logs) = await _build(_builder(), _syntaxError);
    expect(result.succeeded, isFalse);
    expect(result.errors, isNotEmpty);
    expect(kept, isNull);
    expect(_warnings(logs), isEmpty);
  });

  test('validation error after a good build keeps the output', () async {
    final builder = _builder();
    final (_, content, _) = await _build(builder, _good);
    final (result, kept, logs) = await _build(builder, _validationError);
    expect(kept, content);
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      allOf(
        contains('lib/src/beans.beans.dart is kept unchanged'),
        contains('Bean class _Greeter must be public'),
      ),
    );
    expect(_severe(logs), hasLength(1));
  });

  test('cold build with a validation error fails as before', () async {
    final (result, kept, _) = await _build(_builder(), _validationError);
    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains('must be public'));
    expect(kept, isNull);
  });
}
