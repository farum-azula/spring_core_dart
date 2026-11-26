// The build switches of the Flutter starters' debug features, as the
// starters declare them (read from their spring_auto_configuration.dart):
// the debug console is in the build only with its enabled `true`; not set
// or `false`, main.spring.dart has none of its code. Each segment is in it
// only when `segments` names it (or holds `*`, or is not set and its
// default names it), and only with the console; each pane (the commands
// with `commands`) only when `panes` names it or holds `*`, `logs` also
// when `panes` is not set (its default), the export command only with it.
// The panel's switch beside it, not set: in debug builds only (a profile
// build has it only with `true`); a tab of the panel leaves with the panel
// whatever its own switch says, and the Console tab needs both the panel
// and the console.
import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show springBootVersion;
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

import '../support/module_files.dart';
import '../support/starter_build_switches.dart';

const _app = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

const _flutter = 'spring_boot_starter_flutter';

/// main.spring.dart and the files beside it, without whitespace, for an
/// application with [config] and a starter whose one module [module] has
/// the switch of [package]'s module of that name.
Future<String> _output(
  String module, {
  String? config,
  String package = _flutter,
}) async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  final packageConfig = PackageConfig([
    ...isolateConfig.packages,
    Package(
      'neon_debug',
      Uri.parse('file:///neon_debug/'),
      packageUriRoot: Uri.parse('file:///neon_debug/lib/'),
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
      'neon_debug|lib/spring_auto_configuration.dart':
          '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@AutoConfigurationModule(requires: '^$springBootVersion', build: ${starterBuildSwitch(module, package: package)})
final BeanModule $module = BeanModule('$module', []);
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

void main() {
  for (final (what, module, key, parent) in [
    (
      'the console',
      'springBootStarterFlutterDebugConsoleAutoConfiguration',
      'spring.flutter.debug.console.enabled',
      '',
    ),
  ]) {
    group(what, () {
      test('its switch is its enabled', () {
        expect(starterBuildSwitch(module), contains("'$key'"));
      });

      test('not set: no code', () async {
        expect(
          await _output(module, config: parent),
          isNot(contains(module)),
        );
      });

      test('false: no code', () async {
        expect(
          await _output(module, config: '$parent$key=false'),
          isNot(contains(module)),
        );
      });

      test('true: in every build', () async {
        final code = await _output(module, config: '$parent$key=true');
        expect(code, matches(RegExp('[\\[,]_i\\d+\\.$module,')));
        expect(
          code,
          isNot(
            matches(RegExp('_\\\$debugAutoConfigurations=>\\[[^\\]]*$module')),
          ),
        );
      });
    });
  }

  test('the panel, not set: in debug builds only', () async {
    const module = 'springBootStarterFlutterDebugAutoConfiguration';
    final code = await _output(module);
    expect(
      code,
      matches(
        RegExp('_\\\$debugAutoConfigurations=>\\[[^\\]]*_i\\d+\\.$module'),
      ),
    );
  });

  group('the segments', () {
    const console = 'spring.flutter.debug.console.enabled=true';
    const header = 'spring.flutter.debug.console.segments';
    for (final (segment, module, package, byDefault) in [
      (
        'fps',
        'springBootStarterFlutterDebugConsoleFpsAutoConfiguration',
        _flutter,
        true,
      ),
      (
        'frames-lost',
        'springBootStarterFlutterDebugConsoleFramesLostAutoConfiguration',
        _flutter,
        true,
      ),
      (
        'filter',
        'springBootStarterFlutterDebugConsoleFilterAutoConfiguration',
        _flutter,
        true,
      ),
      (
        'isolates',
        'springBootStarterFlutterDebugConsoleIsolatesAutoConfiguration',
        _flutter,
        false,
      ),
      (
        'timeline',
        'springBootStarterFlutterDebugConsoleTimelineAutoConfiguration',
        _flutter,
        false,
      ),
      (
        'scene-fps',
        'springBootStarterFlutterSceneDebugConsoleAutoConfiguration',
        'spring_boot_starter_flutter_scene',
        true,
      ),
      (
        'signals',
        'springBootStarterFlutterSignalsDebugConsoleAutoConfiguration',
        'spring_boot_starter_flutter_signals',
        false,
      ),
    ]) {
      group(segment, () {
        Future<bool> built(String? config) async => _always(
          await _output(module, config: config, package: package),
          module,
        );

        test('without the console: no code, even named', () async {
          expect(await built('$header=$segment,*'), isFalse);
          expect(
            await _output(module, package: package),
            isNot(contains(module)),
          );
        });

        test('segments not set: ${byDefault ? 'in' : 'out'}, as its default '
            'says', () async {
          expect(await built(console), byDefault);
        });

        test('segments without it: no code', () async {
          expect(
            await built('$console\n$header=nothing'),
            isFalse,
          );
        });

        // The `isolates` and `timeline` segments are inside their tab's
        // switch too, which says `true` here.
        const tools =
            'spring.flutter.debug.isolates.enabled=true\n'
            'spring.flutter.debug.timeline.enabled=true';

        test('segments naming it, or holding *: in every build', () async {
          expect(await built('$console\n$tools\n$header=$segment'), isTrue);
          expect(await built('$console\n$tools\n$header=nothing,*'), isTrue);
        });
      });
    }
  });

  group('the commands pane, and the commands with it', () {
    const module =
        'springBootStarterFlutterDebugConsoleCommandsAutoConfiguration';
    const console = 'spring.flutter.debug.console.enabled=true';
    const panes = 'spring.flutter.debug.console.panes';
    Future<bool> built(String? config) async =>
        _always(await _output(module, config: config), module);

    test('without the console: no code, even named', () async {
      expect(await built('$panes=commands,*'), isFalse);
    });

    test(
      'panes not set (its default names none), or without it: no code',
      () async {
        expect(await _output(module, config: console), isNot(contains(module)));
        expect(
          await _output(module, config: '$console\n$panes=network'),
          isNot(contains(module)),
        );
      },
    );

    test('panes naming it, or holding *: in every build', () async {
      expect(await built('$console\n$panes=commands'), isTrue);
      expect(await built('$console\n$panes=other,*'), isTrue);
    });

    test('no input switch any more', () {
      expect(starterSource(_flutter), isNot(contains('console.input')));
    });
  });

  group('the logs pane, its selection and the export command with it', () {
    const module = 'springBootStarterFlutterDebugConsoleLogsAutoConfiguration';
    const export =
        'springBootStarterFlutterDebugConsoleExportCommandAutoConfiguration';
    const console = 'spring.flutter.debug.console.enabled=true';
    const panes = 'spring.flutter.debug.console.panes';
    Future<bool> built(String? config, [String of = module]) async =>
        _always(await _output(of, config: config), of);

    test('without the console: no code, even named', () async {
      expect(await built('$panes=logs,*'), isFalse);
    });

    test('panes not set: in the build, its default names it', () async {
      expect(await built(console), isTrue);
    });

    test(
      'panes listed without it: no code of the pane nor of export',
      () async {
        const config =
            '$console\n$panes=commands\n'
            'spring.flutter.debug.logs.export.enabled=true';
        expect(await _output(module, config: config), isNot(contains(module)));
        expect(await _output(export, config: config), isNot(contains(export)));
        expect(await built(config, export), isFalse);
      },
    );

    test('panes naming it, or holding *: in every build', () async {
      expect(await built('$console\n$panes=logs'), isTrue);
      expect(await built('$console\n$panes=commands,*'), isTrue);
    });

    test('export: with the logs, the commands and the log export', () async {
      expect(
        await built(
          '$console\n$panes=logs,commands\n'
          'spring.flutter.debug.logs.export.enabled=true',
          export,
        ),
        isTrue,
      );
    });
  });

  group('the Console tab needs the panel and the console', () {
    const module =
        'springBootStarterFlutterDebugConsoleSectionAutoConfiguration';
    const console = 'spring.flutter.debug.console.enabled';

    test('without the console: no code, the panel on or not', () async {
      for (final config in [null, 'spring.flutter.debug.enabled=true']) {
        expect(
          await _output(module, config: config),
          isNot(contains(module)),
          reason: config,
        );
      }
    });

    test('the console without the panel: no code', () async {
      expect(
        await _output(
          module,
          config: '$console=true\nspring.flutter.debug.enabled=false',
        ),
        isNot(contains(module)),
      );
    });

    test(
      'the console, the panel not set: debug builds only',
      () async {
        expect(
          await _output(module, config: '$console=true'),
          matches(_inDebugOnly(module)),
        );
      },
    );

    test('both on: in every build', () async {
      expect(
        _always(
          await _output(
            module,
            config: '$console=true\nspring.flutter.debug.enabled=true',
          ),
          module,
        ),
        isTrue,
      );
    });
  });

  group('a tab of the debug panel leaves with the panel', () {
    for (final (module, package, own) in [
      (
        'springBootStarterFlutterDebugFlutterToolsAutoConfiguration',
        _flutter,
        'spring.flutter.debug.flutter-tools.enabled',
      ),
      (
        'springBootStarterFlutterSignalsDebugAutoConfiguration',
        'spring_boot_starter_flutter_signals',
        'spring.flutter.signals.debug.enabled',
      ),
      (
        'springBootStarterFlutterSceneDebugAutoConfiguration',
        'spring_boot_starter_flutter_scene',
        'spring.flutter.scene.debug.enabled',
      ),
    ]) {
      group(module, () {
        test('the panel off: no code, its own switch unset or true', () async {
          for (final config in [
            'spring.flutter.debug.enabled=false',
            'spring.flutter.debug.enabled=false\n$own=true',
          ]) {
            expect(
              await _output(module, config: config, package: package),
              isNot(contains(module)),
              reason: config,
            );
          }
        });

        test('the panel on, its own switch unset: debug builds only (the '
            'narrowest)', () async {
          final code = await _output(
            module,
            config: 'spring.flutter.debug.enabled=true',
            package: package,
          );
          expect(code, matches(_inDebugOnly(module)));
        });

        test('both on: in every build', () async {
          expect(
            _always(
              await _output(
                module,
                config: 'spring.flutter.debug.enabled=true\n$own=true',
                package: package,
              ),
              module,
            ),
            isTrue,
          );
        });
      });
    }
  });
}

// Whether [code] has [module] in every build.
bool _always(String code, String module) =>
    RegExp('[\\[,]_i\\d+\\.$module,').hasMatch(code) &&
    !_inDebugOnly(module).hasMatch(code);

// [module] among the auto-configurations of debug builds only.
RegExp _inDebugOnly(String module) =>
    RegExp('_\\\$debugAutoConfigurations=>\\[[^\\]]*_i\\d+\\.$module');
