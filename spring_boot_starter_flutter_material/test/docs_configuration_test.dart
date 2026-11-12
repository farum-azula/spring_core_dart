// The Flutter examples of docs/configuration.md (YAML and .properties)
// start a real application with this starter: every theme is read and
// made Material, the app widget's settings are read. Keeps the reference
// in step with the starters. An example that sets `cupertino.*` needs the
// Cupertino starter as well and is its to check.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

import 'support/application.dart';

/// docs/configuration.md, from the package folder or the repository root.
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

void main() {
  setUpAll(() {
    ThemeLoaderKinds.register<Object?>('doors', painter: const _Doors());
    ThemeLoaderKinds.register<Object?>('neon-gate', painter: const _Doors());
  });
  tearDownAll(ThemeLoaderKinds.clear);

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
      if (text.contains('spring.flutter') ||
          RegExp(r'^\s+flutter:', multiLine: true).hasMatch(text)) {
        examples.add((open[1]!, text, start));
      }
    }
  }

  test(
    'the page has Flutter examples',
    skip: available ? null : 'outside the repository',
    () {
      expect(examples.length, greaterThanOrEqualTo(8));
    },
  );

  for (final (language, text, line) in examples) {
    test(
      '$language example at line $line starts an application',
      skip: text.contains('cupertino')
          ? 'needs spring_boot_starter_flutter_cupertino too'
          : null,
      () async {
        final context = await application(
          files: {
            'application.${language == 'yaml' ? 'yml' : 'properties'}': text,
          },
        ).runAsync(const []);
        addTearDown(context.close);
        final themes = MaterialThemes.of(context);
        for (final name in themes.themes.names) {
          themes.theme(name);
        }
        FlutterAppSettings.of(context);
        ThemeSelection.of(context);
      },
    );
  }
}
