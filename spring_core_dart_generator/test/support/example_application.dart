// The application of `pkg` the tests of entry points share (test/core/,
// test/actuator/): an entry point under example/, bin/ or lib/, the
// package's own auto-configuration, resources at several levels.
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/core/spring_builder.dart';
import 'package:spring_core_dart_generator/src/starters.dart';
import 'package:test/test.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

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

/// Builds the application of `pkg` whose `@SpringBootApplication` is in
/// [entry] (with its own auto-configuration, a component in lib/ and
/// resources under lib/ and example/), its pubspec.yaml [pubspec]; returns
/// the generated library of the entry point.
Future<String> generateEntryPoint(String entry, {String? pubspec}) async {
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
    SpringBuilder(generations: starterGenerations),
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
