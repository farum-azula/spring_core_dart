// The build switch of the Flutter starter's network recorder, as the
// starter declares it (read from its spring_auto_configuration.dart): the
// recorder and the Network tab are in the build only with
// `spring.flutter.debug.network.enabled: true`, and only as far as the
// debug panel's switch, its parent, lets them in. Not set or `false`,
// main.spring.dart names no module of it, so the app has none of its code.
import 'dart:io';
import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show springBootVersion;
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

import '../support/module_files.dart';

const _module = 'springBootStarterFlutterDebugNetworkAutoConfiguration';
const _key = 'spring.flutter.debug.network.enabled';
const _panel = 'spring.flutter.debug.enabled';

const _app = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

/// The `build:` argument of the network module, as the Flutter starter
/// writes it, its parent included.
String _build() {
  String? source;
  for (final base in ['..', '.']) {
    final file = File(
      '$base/spring_boot_starter_flutter/lib/spring_auto_configuration.dart',
    );
    if (file.existsSync()) {
      source = file.readAsStringSync();
      break;
    }
  }
  if (source == null) {
    throw StateError('spring_boot_starter_flutter not found');
  }
  final declaration = RegExp('final BeanModule\\s+$_module\\b').firstMatch(
    source,
  );
  expect(declaration, isNotNull, reason: '$_module in the starter');
  final annotation = source.lastIndexOf(
    '@AutoConfigurationModule(',
    declaration!.start,
  );
  final start = source.indexOf('AutoConfigurationBuild', annotation);
  expect(start, lessThan(declaration.start), reason: 'it has a build switch');
  var depth = 0;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    switch (source[i]) {
      case '(':
        depth++;
      case ')':
        depth--;
        if (depth == 0) {
          return source.substring(start, i + 1);
        }
    }
  }
  throw StateError('unbalanced build switch');
}

/// main.spring.dart and the files beside it, without whitespace, for an
/// application with [config] and a starter whose one module has the
/// network module's switch.
Future<String> _output({String? config}) async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  final packageConfig = PackageConfig([
    ...isolateConfig.packages,
    Package(
      'neon_network',
      Uri.parse('file:///neon_network/'),
      packageUriRoot: Uri.parse('file:///neon_network/lib/'),
    ),
  ]);
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(generations: packageGenerations),
    {
      'pkg|bin/main.dart': _app,
      'pkg|lib/resources/application.properties': ?config,
      'neon_network|lib/spring_auto_configuration.dart':
          '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@AutoConfigurationModule(requires: '^$springBootVersion', build: ${_build()})
final BeanModule $_module = BeanModule('$_module', []);
''',
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: packageConfig,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  return moduleText(result).replaceAll(RegExp(r'\s+'), '');
}

final _named = RegExp('_i\\d+\\.$_module');
final _debugOnly = RegExp(
  '_\\\$debugAutoConfigurations=>\\[[^\\]]*_i\\d+\\.$_module',
);

void main() {
  test('its switch is its enabled, off unless true, inside the panel', () {
    final build = _build();
    expect(build, contains("'$_key'"));
    expect(build, contains('BuildInclusion.never'));
    expect(build, contains("parents: [AutoConfigurationBuild('$_panel')]"));
  });

  test('not set: no code', () async {
    expect(await _output(), isNot(matches(_named)));
  });

  test('false: no code', () async {
    expect(await _output(config: '$_key=false'), isNot(matches(_named)));
  });

  test('true, the panel not set: in debug builds only', () async {
    expect(await _output(config: '$_key=true'), matches(_debugOnly));
  });

  test('true with the panel true: in every build', () async {
    final code = await _output(config: '$_key=true\n$_panel=true');
    expect(code, matches(_named));
    expect(code, isNot(matches(_debugOnly)));
  });

  test('true without the panel: no code', () async {
    expect(
      await _output(config: '$_key=true\n$_panel=false'),
      isNot(matches(_named)),
    );
  });
}
