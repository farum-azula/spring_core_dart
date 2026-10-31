// Several in-memory builds per test; the machine may be busy with other
// test processes.
@Timeout(Duration(minutes: 5))
library;

// `build_runner build --workspace` builds every package of a pub workspace
// from one working directory. The files the builders read outside the
// build (the generated file kept while the sources have errors, an asset
// the build does not see) must come from the directory of the package
// built, never from the working directory: that may be another package,
// whose file would be written as this package's output.
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/test_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

// Missing `}`: does not parse.
const _syntaxError =
    "import 'package:spring_core_dart/spring_core_dart.dart';\n"
    '@Service()\nclass Greeter {\n';

const _output = 'lib/src/beans.spring.dart';

late Directory _workspace;

// A pub workspace on disk: the package config at the root lists `app`
// and `pkg` under packages/; the build below is of `pkg`.
void _createWorkspace() {
  _workspace = Directory.systemTemp.createTempSync('workspace_build_test');
  File('${_workspace.path}/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final name in ['app', 'pkg'])
            {
              'name': name,
              'rootUri': '../packages/$name',
              'packageUri': 'lib/',
            },
        ],
      }),
    );
  for (final name in ['app', 'pkg']) {
    Directory('${_workspace.path}/packages/$name').createSync(recursive: true);
  }
}

Directory _package(String name) =>
    Directory('${_workspace.path}/packages/$name');

void _write(String package, String path, String content) =>
    File(
        '${_package(package).path}/$path',
      )
      ..createSync(recursive: true)
      ..writeAsStringSync(content);

/// Builds `pkg` with [builder]; returns the result and the generated
/// [output] (`null` when not written).
Future<(TestBuilderResult, String?)> _build(
  Builder builder,
  Map<String, String> sources, {
  String output = _output,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    builder,
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  final id = AssetId('pkg', output);
  final testing = result.readerWriter.testing;
  return (result, testing.exists(id) ? testing.readString(id) : null);
}

void main() {
  setUp(_createWorkspace);
  tearDown(() => _workspace.deleteSync(recursive: true));

  test("a package's directory comes from the workspace's package config, "
      'whichever package directory the build runs in', () {
    for (final from in [_workspace, _package('app'), _package('pkg')]) {
      final directories = PackageDirectories(workingDirectory: from);
      expect(
        directories.directoryOf('pkg'),
        _package('pkg').absolute.uri,
        reason: from.path,
      );
      expect(
        directories.file(AssetId('pkg', _output))!.path,
        File('${_package('pkg').path}/$_output').absolute.path,
      );
      expect(directories.directoryOf('other'), isNull);
    }
  });

  group('the output kept while the sources have errors', () {
    // The build runs in app's directory and builds pkg.
    SpringBuilder builder() => SpringBuilder(
      proxyMode: ProxyMode.none,
      packageDirectories: PackageDirectories(workingDirectory: _package('app')),
    );

    test("is the built package's file, not the working directory's", () async {
      _write('app', _output, "// app's output\n");
      _write('pkg', _output, "// pkg's output\n");
      final (result, kept) = await _build(builder(), {
        'lib/src/beans.dart': _scan,
        'lib/src/service.dart': _syntaxError,
      });
      expect(result.succeeded, isTrue);
      expect(kept, "// pkg's output\n");
    });

    test('is none when the built package has none: the build fails, '
        "app's file is not taken", () async {
      _write('app', _output, "// app's output\n");
      final (result, kept) = await _build(builder(), {
        'lib/src/beans.dart': _scan,
        'lib/src/service.dart': _syntaxError,
      });
      expect(result.succeeded, isFalse);
      expect(kept, isNull);
    });
  });

  test("the test builder keeps the test package's generated file", () async {
    const output = 'test/spring/shop.test.spring.dart';
    _write('app', output, "// app's tests\n");
    _write('pkg', output, "// pkg's tests\n");
    final (result, kept) = await _build(
      SpringTestBuilder(
        packageDirectories: PackageDirectories(
          workingDirectory: _package('app'),
        ),
      ),
      {
        'test/shop_test.dart':
            "import 'spring/shop.test.spring.dart';\n"
            '@SpringBootTest()\nclass ShopTest {\n',
      },
      output: output,
    );
    expect(result.succeeded, isTrue);
    expect(kept, "// pkg's tests\n");
  });

  group('an asset the build does not see', () {
    const app = '''
import 'package:spring_core_dart/spring_core_dart.dart';

@Component()
class AppAssets {
  AppAssets(@Value('asset:images/logo.png') this.logo);
  final Resource logo;
}
''';
    const pubspec = 'name: pkg\nflutter:\n  assets:\n    - images/\n';

    Future<TestBuilderResult> build() async => (await _build(
      SpringBuilder(
        packageDirectories: PackageDirectories(workingDirectory: _workspace),
      ),
      {
        'lib/src/beans.dart': _scan,
        'lib/src/app.dart': app,
        'pubspec.yaml': pubspec,
      },
    )).$1;

    test("is found in the built package's directory, from the workspace "
        'root', () async {
      _write('pkg', 'images/logo.png', 'png');
      expect((await build()).errors, isEmpty);
    });

    test("is not found in another package's directory", () async {
      _write('app', 'images/logo.png', 'png');
      final result = await build();
      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains('there is no file images/logo.png in the package pkg'),
      );
    });
  });
}
