// The Flutter examples of docs/configuration.md (YAML and .properties)
// start a real application: every theme is read and made, the app
// widget's settings are read. Keeps the reference in step with the starter.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// docs/configuration.md, from the package folder or the repository root.
final _doc = File('docs/configuration.md').existsSync()
    ? 'docs/configuration.md'
    : '../docs/configuration.md';

void main() {
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
        autoConfigurations: [springBootStarterFlutterAutoConfiguration],
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
