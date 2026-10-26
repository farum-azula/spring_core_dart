// `@SpringBootApplication` under example/ (a package's example on pub.dev):
// only example/ is scanned and the package's own auto-configuration is
// used, as for any application depending on the package. Elsewhere (bin/,
// lib/) the package's lib/ is scanned and its own auto-configuration is
// not, as before.
import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _main = r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.spring.dart';

@Component()
class ExampleGreeter {}

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

const _ownAutoConfiguration = r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@AutoConfigurationModule()
final BeanModule pkgAutoConfiguration = BeanModule('pkg', []);
''';

const _libComponent = r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@Component()
class StarterService {}
''';

Future<String> _generate(String entry) async {
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
  final result = await testBuilder(
    SpringBuilder(),
    {
      'pkg|$entry': _main,
      'pkg|lib/spring_auto_configuration.dart': _ownAutoConfiguration,
      'pkg|lib/src/starter_service.dart': _libComponent,
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

  test('bin/: lib/ scanned, own auto-configuration not used', () async {
    final output = await _generate('bin/main.dart');
    expect(output, isNot(contains('pkgAutoConfiguration')));
    expect(output, contains('ExampleGreeter'));
    expect(output, contains('StarterService'));
  });
}
