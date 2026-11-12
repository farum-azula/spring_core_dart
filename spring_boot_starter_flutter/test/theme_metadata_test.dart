// tool/theme_metadata.json (the source of the theme pages in docs/ and,
// later, of the language server) describes every property it lists, and
// its flat `properties` have every key a theme may have. That it lists
// exactly what the mapping of the components reads is the Material
// starter's test (its theme_metadata_test.dart); what the Cupertino
// starter reads under `cupertino` is checked here. When this fails, run
//   dart run tool/theme_metadata.dart
// in spring_boot_starter_flutter, then dart run tool/theme_docs.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/designs.dart';
import 'support/theme_catalog.dart';

void main() {
  final json = jsonDecode(
    File('tool/theme_metadata.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final components = {
    for (final c in json['components'] as List)
      (c as Map)['name'] as String: c.cast<String, dynamic>(),
  };

  test('lists cupertino last, with a root of its own and exactly the '
      'properties the Cupertino starter reads', () {
    expect(components.keys.last, 'cupertino');
    expect(
      [
        for (final component in components.values)
          if (component['ownRoot'] == true) component['name'],
      ],
      ['cupertino'],
    );
    final properties = themeCatalog()['cupertino']!;
    final listed = {
      for (final p in components['cupertino']!['properties'] as List)
        (p as Map<String, dynamic>)['key'] as String: p,
    };
    expect(listed.keys.toList(), [for (final p in properties) p.name]);
    for (final p in properties) {
      final entry = listed[p.name]!;
      expect(entry['states'], p.states, reason: p.name);
      final choice = p.kind.startsWith('one of: ');
      expect(
        entry['type'],
        choice ? 'choice' : p.kind,
        reason: 'the type of ${p.name}',
      );
      if (choice) {
        expect(
          (entry['values'] as List).join(' | '),
          p.kind.substring('one of: '.length),
          reason: 'the choices of ${p.name}',
        );
      }
    }
  });

  test('describes every property, with its Flutter field and default', () {
    for (final component in components.values) {
      expect(
        (component['description'] as String).trim(),
        isNotEmpty,
        reason: component['name'] as String,
      );
      for (final p
          in (component['properties'] as List).cast<Map<String, dynamic>>()) {
        final where = '${component['name']}.${p['key']}';
        expect((p['description'] as String).trim(), isNotEmpty, reason: where);
        expect(p['description'], isNot(contains('[')), reason: where);
        expect(p['flutterField'], contains('.'), reason: where);
        expect((p['default'] as String).trim(), isNotEmpty, reason: where);
      }
    }
  });

  group('properties (the theme section of spring_metadata.json)', () {
    final properties = [
      for (final p in json['properties'] as List)
        (p as Map).cast<String, dynamic>(),
    ];
    final names = {for (final p in properties) p['name'] as String};

    test('has every component property under components.<name>', () {
      for (final component in components.values) {
        final prefix = component['ownRoot'] == true ? '' : 'components.';
        for (final p
            in (component['properties'] as List).cast<Map<String, dynamic>>()) {
          expect(
            names,
            contains('$prefix${component['name']}.${p['key']}'),
          );
        }
      }
    });

    test('has every top-level key the reader accepts', () {
      final sections = {for (final n in names) n.split('.').first};
      for (final key in [
        ...SpringThemeData.themeProperties,
        // Those of the design starters.
        for (final design in testDesigns.all) ...design.themeProperties,
      ]) {
        expect(sections, contains(key), reason: key);
      }
      for (final key in [
        'active',
        'system-light',
        'system-dark',
        'extends',
        'source',
        'source-sha256',
        'refresh',
      ]) {
        expect(names, contains(key), reason: key);
      }
    });

    test('says where the root-only and theme-only keys work', () {
      Map<String, dynamic> byName(String name) =>
          properties.firstWhere((p) => p['name'] == name);
      expect(byName('active')['scope'], 'root');
      expect(byName('extends')['scope'], 'theme');
      expect(byName('seed-color')['scope'], isNull);
    });

    test('has every color role, with a description', () {
      final roles = names.where((n) => n.startsWith('colors.'));
      expect(roles.length, 46);
      for (final p in properties.where(
        (p) => (p['name'] as String).startsWith('colors.'),
      )) {
        expect(p['type'], 'color');
        expect((p['description'] as String).trim(), isNotEmpty);
      }
    });

    test('names are unique and every named type exists', () {
      expect(names.length, properties.length);
      final types = (json['types'] as Map).keys.toSet();
      const structural = {
        'choice',
        'text',
        'map',
        'list of colors',
        'list of numbers',
        'list of texts',
        'list of maps',
      };
      for (final p in properties) {
        final type = p['type'] as String;
        expect(
          types.contains(type) || structural.contains(type),
          isTrue,
          reason: '${p['name']}: $type',
        );
      }
    });
  });
}
