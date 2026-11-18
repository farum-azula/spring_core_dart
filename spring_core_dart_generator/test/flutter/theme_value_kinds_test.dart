// The generator reads theme values the way the runtime does: every row of
// the starter's fixture, the image token rule, the names of the generated
// classes and the root sections.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:io';

import 'package:spring_core_dart_generator/src/material_color_values.dart';
import 'package:spring_core_dart_generator/src/spring_key_files.dart';
import 'package:spring_core_dart_generator/src/theme_references.dart';
import 'package:spring_core_dart_generator/src/theme_value_syntax.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _fixturePath =
    'spring_boot_starter_flutter/test/fixtures/theme_value_kinds.yaml';

/// A file of the starter, from the generator's folder or the repository's
/// root (the workspace run).
File _starterFile(String path) {
  for (final base in ['..', '.']) {
    final file = File('$base/$path');
    if (file.existsSync()) {
      return file;
    }
  }
  return File('../$path');
}

({String? code, KeysDiagnostics diagnostics}) _theme(String yaml) {
  final diagnostics = KeysDiagnostics();
  final parts = SpringKeyFiles.generate({'application.yml': yaml}, diagnostics);
  return (code: parts.theme, diagnostics: diagnostics);
}

String _flat(String? code) => (code ?? '').replaceAll(RegExp(r'\s+'), ' ');

// The kind of [value] as a token, the way the generator reads it.
ValueKind _kindOf(String value) {
  final diagnostics = KeysDiagnostics();
  final set = ThemeSet.read([
    (
      file: 'a.yml',
      name: 'spring.flutter.theme.tokens.g.v',
      value: value,
    ),
  ], diagnostics)!;
  final scope = set.scope('light');
  final node = scope.node(const ['tokens', 'g', 'v'])!;
  return scope.nodeKind(node, insets: true)!;
}

void main() {
  final fixture =
      loadYaml(_starterFile(_fixturePath).readAsStringSync()) as YamlMap;

  group('the starter fixture', () {
    test('the root sections', () {
      final sections = {
        for (final name in fixture['root-sections'] as YamlList)
          canonicalName('$name'),
      };
      expect(ThemeValueSyntax.rootSections, sections);
    });

    test('the image keys', () {
      final keys = {
        for (final name in fixture['image-keys'] as YamlList)
          canonicalName('$name'),
      };
      expect(ThemeValueSyntax.imageKeys, keys);
    });

    test('every value has its kind', () {
      final wrong = <String>[];
      for (final row in fixture['values'] as YamlList) {
        final map = row as YamlMap;
        final value = '${map['value']}';
        final expected = '${map['kind']}';
        final actual = _kindOf(value).name;
        if (actual != expected) {
          wrong.add('"$value": expected $expected, found $actual');
        }
      }
      expect(wrong, isEmpty);
    });

    test('every color object is a color, or has its error', () {
      final wrong = <String>[];
      for (final row in fixture['color-objects'] as YamlList) {
        final map = row as YamlMap;
        final props = {
          for (final part in '${map['props']}'.split(' | '))
            part.substring(0, part.indexOf('=')): part.substring(
              part.indexOf('=') + 1,
            ),
        };
        final diagnostics = KeysDiagnostics();
        final set = ThemeSet.read([
          for (final MapEntry(:key, :value) in props.entries)
            (
              file: 'a.yml',
              name: 'spring.flutter.theme.colors.x.$key',
              value: value,
            ),
        ], diagnostics)!;
        final scope = set.scope('light')..checkAll();
        final error = map['error'] as String?;
        if (error == null) {
          if (diagnostics.errors.isNotEmpty) {
            wrong.add('"${map['props']}": ${diagnostics.errors}');
          }
          final node = scope.node(const ['colors', 'x'])!;
          if (scope.nodeKind(node)?.name != 'color') {
            wrong.add('"${map['props']}": not a color');
          }
        } else if (!diagnostics.errors.any((e) => e.contains(error))) {
          wrong.add(
            '"${map['props']}": expected "$error", got ${diagnostics.errors}',
          );
        }
      }
      expect(wrong, isEmpty);
    });

    test('the Material names are those of the starter', () {
      final source = _starterFile(
        'spring_boot_starter_flutter/lib/src/theme/material_colors.dart',
      ).readAsStringSync();
      final names = {
        for (final m in RegExp(
          "^  '([A-Za-z0-9.]+)':",
          multiLine: true,
        ).allMatches(source))
          m[1]!,
      };
      expect(materialColorValues.keys.toSet(), names);
    });
  });

  group('image tokens', () {
    test('a group of 0.6.2 with a source and other keys stays a group', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  tokens:
    brand: { source: x, family: y }
''');
      expect(diagnostics.errors, isEmpty);
      final flat = _flat(code);
      expect(flat, contains('AppThemeTokensBrand get brand'));
      expect(
        flat,
        contains("String get source => _values.token('brand.source');"),
      );
      expect(
        flat,
        contains("String get family => _values.token('brand.family');"),
      );
    });

    test('a source with only image keys, deep enough, is an image', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  tokens:
    art: { hero: { source: https://x.test/a.png, source-sha256: ab, timeout: 5s } }
''');
      expect(diagnostics.errors, isEmpty);
      expect(
        _flat(code),
        contains("ThemeImage get hero => _values.tokenImage('art.hero');"),
      );
    });

    test('tokens.<key> with a source is no image (too shallow)', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  tokens:
    hero: { source: https://x.test/a.png }
''');
      expect(diagnostics.errors, isEmpty);
      expect(_flat(code), isNot(contains('ThemeImage')));
    });
  });

  group('references to what the theme does not declare', () {
    test('Material roles are colors and the shape scale numbers', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  tokens:
    a: { c: $colors.tertiary-container, d: { color: $colors.surface-tint, alpha: 10% }, s: $shape.extra-large }
''');
      expect(diagnostics.errors, isEmpty);
      final flat = _flat(code);
      expect(flat, contains("Color get c => _values.tokenColor('a.c');"));
      expect(flat, contains("Color get d => _values.tokenColor('a.d');"));
      expect(flat, contains("double get s => _values.tokenNumber('a.s');"));
    });

    test('an unknown role is an error with a hint', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  tokens:
    a: { c: $colors.surfac }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('Did you mean'));
    });
  });

  group('names of the generated classes', () {
    test('a style is AppStyle<Name>, whatever it is called', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  styles:
    text: { gap: 4 }
    button: { gap: 4 }
    state: { gap: 4 }
    theme: { gap: 4 }
''');
      expect(diagnostics.errors, isEmpty);
      final flat = _flat(code);
      for (final name in ['Text', 'Button', 'State', 'Theme']) {
        expect(
          flat,
          contains(
            'final class AppStyle$name implements ThemeStyle<AppStyle${name}Values>',
          ),
        );
        expect(flat, contains('final class AppStyle${name}Values'));
      }
      expect(flat, isNot(contains('final class TextStyle')));
      expect(flat, isNot(contains('final class ButtonStyle')));
      expect(flat, isNot(contains('final class StateStyle')));
      expect(flat, isNot(contains('final class ThemeStyle')));
    });

    test('a style whose values class would clash is an error', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  styles:
    foo: { gap: 4 }
    foo-values: { gap: 4 }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('AppStyleFooValues'));
    });

    test('a token named like a keyword gets an escaped getter', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  tokens:
    default: { class: 1, x: 2 }
    new: 3
''');
      expect(diagnostics.errors, isEmpty);
      final flat = _flat(code);
      expect(flat, contains(r'AppThemeTokensDefault$ get default$ =>'));
      expect(
        flat,
        contains(r"double get class$ => _values.tokenNumber('default.class');"),
      );
      expect(flat, contains(r"double get new$ => _values.tokenNumber('new');"));
    });

    test('the background is nullable', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  background: { color: '#000000' }
''');
      expect(diagnostics.errors, isEmpty);
      expect(
        _flat(code),
        contains(
          'ThemeBackgroundData? get background => _values.theme.background;',
        ),
      );
    });
  });

  group('classification of the rest', () {
    test('a colors entry that is no color is an error', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  colors: { x: grey.shade999 }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('a color is expected'));
    });

    test('a color object with a reference', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  colors: { primary: '#112233' }
  tokens:
    a: { x: { color: $colors.primary, mix: { with: white, amount: 14% }, alpha: 50% } }
''');
      expect(diagnostics.errors, isEmpty);
      expect(
        _flat(code),
        contains("Color get x => _values.tokenColor('a.x');"),
      );
    });

    test('a color object in colors and a reference to it', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  colors:
    primary: { color: '#112233', alpha: 50% }
    secondary: { color: $colors.primary, mix: { with: white, amount: 10% } }
  tokens:
    a: { x: $colors.primary }
''');
      expect(diagnostics.errors, isEmpty);
      final flat = _flat(code);
      expect(flat, contains('Color get primary'));
      expect(flat, contains("Color get x => _values.tokenColor('a.x');"));
    });

    test('a color object in colors that is wrong is an error', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  colors:
    primary: { color: '#112233', alfa: 50% }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains("did you mean 'alpha'"));
    });

    test('a style value may be a color object', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  styles:
    chip:
      fill:
        default: transparent
        selected: { color: '#FF0000', alpha: 12% }
''');
      expect(diagnostics.errors, isEmpty);
      expect(_flat(code), contains("Color get fill => _values.color('fill');"));
    });
  });
}
