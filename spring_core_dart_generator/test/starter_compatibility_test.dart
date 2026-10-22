import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show springBootVersion;
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _app = r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.beans.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

String _starter(String requires) =>
    '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@AutoConfigurationModule(requires: '$requires')
final BeanModule neonCacheAutoConfiguration = BeanModule('neonCache', []);
''';

/// Builds an application depending on a fake `neon_cache` starter.
Future<TestBuilderResult> _build(String requires) async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  final packageConfig = PackageConfig([
    ...isolateConfig.packages,
    Package(
      'neon_cache',
      Uri.parse('file:///neon_cache/'),
      packageUriRoot: Uri.parse('file:///neon_cache/lib/'),
    ),
  ]);
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return testBuilder(
    const SpringBuilder(),
    {
      'pkg|bin/main.dart': _app,
      'neon_cache|lib/spring_auto_configuration.dart': _starter(requires),
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: packageConfig,
    flattenOutput: true,
  );
}

void main() {
  test('a compatible starter is discovered', () async {
    final result = await _build('^$springBootVersion');
    expect(result.errors, isEmpty);
    final output = result.readerWriter.testing.readString(
      result.outputs.single,
    );
    expect(output, contains('neonCacheAutoConfiguration'));
  });

  test('an incompatible starter stops the build with an explanation', () async {
    final result = await _build('^0.4.0');
    expect(result.succeeded, isFalse);
    final errors = result.errors.join('\n');
    expect(
      errors,
      contains(
        'Incompatible starter: neon_cache requires spring_boot_dart ^0.4.0',
      ),
    );
    expect(errors, contains('but $springBootVersion is used'));
  });

  test('an invalid range is reported', () async {
    final result = await _build('not a range');
    expect(
      result.errors.join('\n'),
      contains("invalid requires 'not a range'"),
    );
  });
}
