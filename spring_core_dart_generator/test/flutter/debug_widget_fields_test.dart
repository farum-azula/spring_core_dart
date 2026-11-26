// The readers of the application's widgets' fields (`debugWidgetFields`)
// are written only in a build with the widgets layer of the graph, as the
// Flutter starter's modules that bring it decide by their own
// `AutoConfigurationBuild`s: the part reads the switches from the modules,
// it keeps no copy of them. Flutter and the starter are stubbed.
import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

import '../support/module_files.dart';
import '../support/starter_build_switches.dart';

const _flutter = 'flutter';
const _starter = 'spring_boot_starter_flutter';

const _layerModules = [
  'springBootStarterFlutterDebugWidgetsGraphAutoConfiguration',
  'springBootStarterFlutterDebugConsoleWidgetsGraphPaneAutoConfiguration',
];

const _app = '''
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

class PassportCard extends Widget {
  PassportCard(this.player);
  final String player;
}

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

// The starter's auto-configuration with [modules] (by name, the source of
// each one's `build:`), empty modules.
String _autoConfiguration(Map<String, String> modules) => [
  "import 'package:spring_boot_dart/spring_boot_dart.dart';",
  for (final MapEntry(key: module, value: build) in modules.entries) ...[
    '@AutoConfigurationModule(build: $build)',
    "final BeanModule $module = BeanModule('$module', []);",
  ],
].join('\n');

Future<String> _output({String? config, Map<String, String>? modules}) async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  Package stub(String name) => Package(
    name,
    Uri.parse('file:///$name/'),
    packageUriRoot: Uri.parse('file:///$name/lib/'),
  );
  final packageConfig = PackageConfig([
    for (final package in isolateConfig.packages)
      if (package.name != _flutter && package.name != _starter) package,
    stub(_flutter),
    stub(_starter),
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
      'pkg|lib/resources/application.yml': ?config,
      '$_flutter|lib/widgets.dart': "export 'src/widgets/framework.dart';",
      '$_flutter|lib/src/widgets/framework.dart': '''
abstract class Widget {}
abstract class State<T extends Widget> {}
''',
      '$_starter|lib/$_starter.dart': 'class DebugWidgetFields {}',
      '$_starter|lib/spring_auto_configuration.dart': _autoConfiguration(
        modules ??
            {
              for (final module in _layerModules)
                module: starterBuildSwitch(module),
            },
      ),
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: packageConfig,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  return moduleText(result).replaceAll(RegExp(r'\s+'), '');
}

void main() {
  test('the layer not set: the readers, in the debug part', () async {
    final code = await _output();
    expect(code, contains("r'debugWidgetFields'"));
    expect(code, contains("PassportCard:[(r'player',"));
  });

  test('the layers without widgets and no console: no readers', () async {
    final code = await _output(
      config: '''
spring:
  flutter:
    debug:
      graph:
        layers: [beans]
''',
    );
    expect(code, isNot(contains('debugWidgetFields')));
  });

  test('the panel false: no readers', () async {
    final code = await _output(
      config: 'spring:\n  flutter:\n    debug:\n      enabled: false\n',
    );
    expect(code, isNot(contains('debugWidgetFields')));
  });

  test("the modules' own switches decide, not a copy of them", () async {
    final code = await _output(
      modules: {
        for (final module in _layerModules)
          module:
              "AutoConfigurationBuild('neon.widgets.enabled', "
              'whenMissing: BuildInclusion.never)',
      },
    );
    expect(code, isNot(contains('debugWidgetFields')));
  });
}
