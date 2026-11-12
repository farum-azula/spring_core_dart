// The Flutter examples of docs/configuration.md that set properties of
// both design libraries (`components.*` next to `cupertino.*`) start a
// real application with both starters: every theme is read and made
// Material and Cupertino, the app widget's settings are read. The
// Material starter checks the other examples; it has no Cupertino.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/designs.dart';

final _doc = File('docs/configuration.md').existsSync()
    ? 'docs/configuration.md'
    : '../docs/configuration.md';

// The kinds the examples name (`kind: doors`, `kind: neon-gate`): an app
// of its own has one (@ThemeLoaderKind); the starter alone has none, so
// the test brings one.
class _Doors extends ThemeLoaderPainter<Object?> {
  const _Doors();

  @override
  void paint(Canvas canvas, Size size, LoaderFrame<Object?> frame) {}
}

void registerDoors() {
  setUpAll(() {
    ThemeLoaderKinds.register<Object?>('doors', painter: const _Doors());
    ThemeLoaderKinds.register<Object?>('neon-gate', painter: const _Doors());
  });
  tearDownAll(ThemeLoaderKinds.clear);
}

void main() {
  registerDoors();
  final available = File(_doc).existsSync();
  final examples = <(String, String, int)>[];
  if (available) {
    final lines = File(_doc).readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final open = RegExp(r'^```(yaml|properties)\s*$').firstMatch(lines[i]);
      if (open == null) {
        continue;
      }
      final start = i + 1;
      final code = <String>[];
      for (i++; i < lines.length && lines[i] != '```'; i++) {
        code.add(lines[i]);
      }
      final text = code.join('\n');
      if ((text.contains('spring.flutter') ||
              RegExp(r'^\s+flutter:', multiLine: true).hasMatch(text)) &&
          text.contains('cupertino')) {
        examples.add((open[1]!, text, start));
      }
    }
  }

  test(
    'the page has Flutter examples for both design libraries',
    skip: available ? null : 'outside the repository',
    () {
      expect(examples.length, greaterThanOrEqualTo(4));
    },
  );

  for (final (language, text, line) in examples) {
    test('$language example at line $line starts an application', () async {
      final context = await SpringApplication(
        [
          BeanModule(
            'm',
            const [],
            resources: {
              'application.${language == 'yaml' ? 'yml' : 'properties'}':
                  EmbeddedResource.text(text),
            },
          ),
        ],
        autoConfigurations: designedAutoConfigurations,
        autoConfigurationMetadata: designAutoConfigurationMetadata,
        defaultProperties: designDefaultProperties,
        bannerMode: BannerMode.off,
      ).runAsync(const []);
      addTearDown(context.close);
      final themes = SpringThemes.of(context);
      for (final name in themes.names) {
        themes.material(name);
        themes.cupertino(name);
      }
      FlutterAppSettings.of(context);
      ThemeSelection.of(context);
    });
  }
}
