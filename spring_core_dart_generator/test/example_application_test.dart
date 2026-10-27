// `@SpringBootApplication` under example/ (a package's example on pub.dev):
// only example/ is scanned and the package's own auto-configuration is
// used, as for any application depending on the package. Elsewhere (bin/,
// lib/) the package's lib/ is scanned and its own auto-configuration is
// not, as before.
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.spring.dart';

@Component()
class ExampleGreeter {}

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

const _ownAutoConfiguration = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@AutoConfigurationModule()
final BeanModule pkgAutoConfiguration = BeanModule('pkg', []);
''';

const _libComponent = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@Component()
class StarterService {}
''';

Future<String> _generate(String entry, {String? pubspec}) async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  final packageConfig = PackageConfig([
    ...isolateConfig.packages,
    Package(
      'pkg',
      Uri.parse('file:///pkg/'),
      packageUriRoot: Uri.parse('file:///pkg/lib/'),
    ),
  ]);
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  // The packages' pubspec.yaml, as a real build reads them (the generator
  // follows the dependencies to find the auto-configurations).
  for (final package in isolateConfig.packages) {
    final pubspec = File.fromUri(package.root.resolve('pubspec.yaml'));
    if (pubspec.existsSync()) {
      readerWriter.testing.writeString(
        AssetId(package.name, 'pubspec.yaml'),
        pubspec.readAsStringSync(),
      );
    }
  }
  final result = await testBuilder(
    SpringBuilder(),
    {
      'pkg|$entry': _main,
      'pkg|lib/spring_auto_configuration.dart': _ownAutoConfiguration,
      'pkg|lib/src/starter_service.dart': _libComponent,
      'pkg|lib/resources/application.properties': 'a=lib\nb=lib\n',
      'pkg|example/lib/resources/application.properties': 'a=example\n',
      'pkg|example/lib/resources/banner.txt': 'EXAMPLE BANNER\n',
      'pkg|example/shop/lib/resources/application.properties': 'a=shop\n',
      'pkg|pubspec.yaml': ?pubspec,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: packageConfig,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  return readerWriter.testing.readString(
    result.outputs.singleWhere(
      (id) => id.path.startsWith(entry.split('/').first),
    ),
  );
}

void main() {
  test('example/: own auto-configuration, lib/ not scanned', () async {
    final output = await _generate('example/main.dart');
    expect(output, contains('pkgAutoConfiguration'));
    expect(output, contains('ExampleGreeter'));
    expect(output, isNot(contains('StarterService')));
  });

  test(
    "example/: example/lib/resources/ embedded, winning over lib/'s",
    () async {
      final output = await _generate('example/main.dart');
      expect(output, contains('a=example'));
      expect(output, isNot(contains('a=lib')));
      expect(output, contains('EXAMPLE BANNER'));
    },
  );

  test(
    'a deeper example: the nearest lib/resources/ wins, the others too',
    () async {
      final output = await _generate('example/shop/main.dart');
      expect(output, contains('a=shop'));
      expect(output, isNot(contains('a=example')));
      expect(output, contains('EXAMPLE BANNER'));
    },
  );

  test('the resource directories of an entry point, lowest first', () {
    expect(SpringBuilder.resourceDirectories(null), ['lib/resources/']);
    expect(SpringBuilder.resourceDirectories('lib/src'), ['lib/resources/']);
    expect(SpringBuilder.resourceDirectories('example'), [
      'lib/resources/',
      'example/lib/resources/',
    ]);
    expect(SpringBuilder.resourceDirectories('example/shop/bin'), [
      'lib/resources/',
      'example/lib/resources/',
      'example/shop/lib/resources/',
      'example/shop/bin/lib/resources/',
    ]);
  });

  test("a pub workspace: only the dependencies' auto-configurations", () async {
    // The package config lists every package of this repository (a
    // workspace), the web starter among them; the app depends on
    // spring_boot_dart only.
    final output = await _generate(
      'bin/main.dart',
      pubspec: 'name: pkg\ndependencies:\n  spring_boot_dart: any\n',
    );
    expect(output, contains('springBootAutoConfiguration'));
    expect(output, isNot(contains('springBootStarterWebAutoConfiguration')));
    expect(output, isNot(contains('springBootStarterFeignAutoConfiguration')));
  });

  test('bin/: only lib/resources/ embedded', () async {
    final output = await _generate('bin/main.dart');
    expect(output, contains('a=lib'));
    expect(output, isNot(contains('EXAMPLE BANNER')));
  });

  test('bin/: lib/ scanned, own auto-configuration not used', () async {
    final output = await _generate('bin/main.dart');
    expect(output, isNot(contains('pkgAutoConfiguration')));
    expect(output, contains('ExampleGreeter'));
    expect(output, contains('StarterService'));
  });
}
