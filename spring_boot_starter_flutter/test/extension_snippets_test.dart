// The editor's theme snippets (extensions/zed/dart_spring/snippets/
// yaml.json and properties.json), expanded with their defaults, are
// valid configuration: an application starts with each one, every theme
// is read, and the values arrive. Keeps the snippets in step with the
// starter.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

const _snippets = '../extensions/zed/dart_spring/snippets';

/// prefix → the snippet's text with every placeholder at its default.
Map<String, String> expanded(String file) {
  final json = jsonDecode(
    File('$_snippets/$file').readAsStringSync(),
  ) as Map<String, Object?>;
  return {
    for (final snippet in json.values.cast<Map<String, Object?>>())
      snippet['prefix']! as String: () {
        var text = (snippet['body']! as List<Object?>).join('\n');
        for (var i = 0; i < 3; i++) {
          text = text.replaceAllMapped(
            RegExp(r'\$\{\d+:([^{}]*)\}'),
            (m) => m[1]!,
          );
        }
        return text.replaceAll(RegExp(r'\$\d+'), '');
      }(),
  };
}

Future<ConfigurableApplicationContext> start(String file, String content) =>
    SpringApplication(
      [
        BeanModule(
          'm',
          const [],
          resources: {file: EmbeddedResource.text(content)},
        ),
      ],
      autoConfigurations: [springBootStarterFlutterAutoConfiguration],
      bannerMode: BannerMode.off,
    ).runAsync(const []);

void main() {
  final available = Directory(_snippets).existsSync();

  for (final (file, config) in [
    ('yaml.json', 'application.yml'),
    ('properties.json', 'application.properties'),
  ]) {
    group(file, skip: available ? null : 'outside the repository', () {
      final snippets = available ? expanded(file) : <String, String>{};

      for (final MapEntry(key: prefix, value: text) in snippets.entries) {
        test('$prefix starts an application, every theme read', () async {
          final context = await start(config, text);
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

      test('the values arrive', () async {
        Future<ConfigurableApplicationContext> of(String prefix) async {
          final context = await start(config, snippets[prefix]!);
          addTearDown(context.close);
          return context;
        }

        final app = FlutterAppSettings.of(await of('spapp'));
        expect(
          (app.type, app.title, app.debugShowCheckedModeBanner),
          (AppType.material, 'My app', true),
        );

        final theme = SpringThemes.of(await of('sptheme'));
        expect(
          theme.data('light').seedColor!.toARGB32(),
          Colors.deepPurple.toARGB32(),
        );
        expect(theme.data('dark').seedColor, Colors.deepPurple.shade200);
        expect(theme.data('light').fontFamily, 'Roboto');
        expect(
          theme.material('light').cardTheme.shape,
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        );
        expect(theme.material('light').appBarTheme.centerTitle, isTrue);

        final added = SpringThemes.of(await of('spthemenew'));
        expect(added.names, contains('ocean'));
        expect(
          added.data('ocean').seedColor!.toARGB32(),
          Colors.teal.toARGB32(),
        );

        final colors = SpringThemes.of(await of('spcolors')).data('light');
        expect(colors.colorScheme.primary, const Color(0xFF6750A4));
        expect(colors.colorScheme.surface, const Color(0xFFFEF7FF));

        final typography = SpringThemes.of(await of('sptypography'))
            .data('light');
        expect(typography.fontFamilyFallback, ['Noto Sans JP']);
        expect(
          typography.textStyle('displayLarge').fontFamily,
          'Roboto Condensed',
        );
        expect(typography.textStyle('code').fontFamily, 'monospace');

        expect(
          SpringThemes.of(await of('spshape'))
              .data('light')
              .shape('extra-large'),
          28,
        );
        expect(
          SpringThemes.of(await of('spcomponents'))
              .material('light')
              .inputDecorationTheme
              .border,
          isA<OutlineInputBorder>(),
        );
        final tokens = SpringThemes.of(await of('sptokens')).data('light');
        expect(tokens.tokenColor('brand.accent'), const Color(0xFFFF6B00));
        expect(tokens.tokenNumber('brand.hero-height'), 240);

        final fonts = await of('spfonts');
        expect(
          fonts.environment.getProperty('spring.flutter.fonts.auto-load'),
          'true',
        );
      });
    });
  }

  test(
    'both files offer the same snippets (YAML also the full reference)',
    skip: available ? null : 'outside the repository',
    () {
      expect(
        expanded('yaml.json').keys
            .toSet()
            .difference(expanded('properties.json').keys.toSet()),
        {'spthemeall'},
      );
      expect(
        expanded('properties.json').keys
            .toSet()
            .difference(expanded('yaml.json').keys.toSet()),
        isEmpty,
      );
    },
  );
}
