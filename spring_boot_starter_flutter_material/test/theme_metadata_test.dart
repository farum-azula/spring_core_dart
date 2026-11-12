// tool/theme_metadata.json of the Flutter starter (the source of the theme
// pages in docs/) lists, for the components of Material, exactly what
// this starter's mapping reads: no missing property, no extra one. When
// this fails, run
//   dart run tool/theme_metadata.dart
// in spring_boot_starter_flutter, then dart run tool/theme_docs.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/theme_catalog.dart';

final _file = File('../spring_boot_starter_flutter/tool/theme_metadata.json');

void main() {
  final available = _file.existsSync();
  final json = available
      ? jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>
      : const <String, dynamic>{'components': <Object>[]};
  // A component with a root of its own (`cupertino`) is another design's.
  final components = {
    for (final c in json['components'] as List)
      if ((c as Map)['ownRoot'] != true)
        c['name'] as String: c.cast<String, dynamic>(),
  };
  final skip = available ? null : 'outside the repository';

  test('lists the same components as the mapping, in the same order', () {
    expect(components.keys.toList(), themeCatalog().keys.toList());
  }, skip: skip);

  test('lists exactly the properties the mapping reads', () {
    for (final MapEntry(key: name, value: properties)
        in themeCatalog().entries) {
      final listed = {
        for (final p in components[name]!['properties'] as List)
          (p as Map<String, dynamic>)['key'] as String: p,
      };
      expect(listed.keys.toList(), [
        for (final p in properties) p.name,
      ], reason: 'the properties of $name');
      for (final p in properties) {
        final entry = listed[p.name]!;
        expect(entry['states'], p.states, reason: '${p.name} of $name');
        final choice = p.kind.startsWith('one of: ');
        expect(
          entry['type'],
          choice ? 'choice' : p.kind,
          reason: 'the type of ${p.name} of $name',
        );
        if (choice) {
          expect(
            (entry['values'] as List).join(' | '),
            p.kind.substring('one of: '.length),
            reason: 'the choices of ${p.name} of $name',
          );
        }
      }
    }
  }, skip: skip);
}
