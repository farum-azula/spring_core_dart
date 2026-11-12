import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/color_roles.dart';

// The table of colours Material's ColorScheme.fromSeed makes. The generator
// computes the same colours at build time (its own port of the Material
// colour code) and compares itself with this file. Set UPDATE_FIXTURE=1 to
// write the file again after an upgrade of material_ui.
const _seeds = [
  0xFF6750A4,
  0xFF00FF9C,
  0xFFB71C1C,
  0xFF000000,
  0xFFFFFFFF,
  0xFF808080,
  0xFF1E88E5,
  0xFFFFC107,
];
const _contrasts = [-1.0, 0.0, 1.0];

Map<String, int> _roles(ColorScheme s) => {
  for (final MapEntry(:key, :value) in roleColors(s).entries)
    key: value.toARGB32(),
};

List<Map<String, Object?>> _table() => [
  for (final seed in _seeds)
    for (final variant in DynamicSchemeVariant.values)
      for (final brightness in Brightness.values)
        for (final contrast in _contrasts)
          {
            'seed': seed,
            'variant': variant.name,
            'brightness': brightness.name,
            'contrast': contrast,
            'roles': _roles(
              ColorScheme.fromSeed(
                seedColor: Color(seed),
                dynamicSchemeVariant: variant,
                brightness: brightness,
                contrastLevel: contrast,
              ),
            ),
          },
];

void main() {
  final file = File(
    '../spring_core_dart_generator/test/fixtures/color_scheme_table.json',
  );

  test(
    'the fixture the generator is checked against is current',
    skip: file.existsSync() ? null : 'outside the repository',
    () {
      final json = jsonEncode(_table());
      if (Platform.environment['UPDATE_FIXTURE'] == '1') {
        file.writeAsStringSync('$json\n');
      }
      expect(file.readAsStringSync().trim(), json);
    },
  );
}
