import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The table of colours Flutter's ColorScheme.fromSeed makes. The generator
// computes the same colours at build time (its own port of the Material
// colour code) and compares itself with this file. Set UPDATE_FIXTURE=1 to
// write the file again after a Flutter upgrade.
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
  'primary': s.primary.toARGB32(),
  'onPrimary': s.onPrimary.toARGB32(),
  'primaryContainer': s.primaryContainer.toARGB32(),
  'onPrimaryContainer': s.onPrimaryContainer.toARGB32(),
  'primaryFixed': s.primaryFixed.toARGB32(),
  'primaryFixedDim': s.primaryFixedDim.toARGB32(),
  'onPrimaryFixed': s.onPrimaryFixed.toARGB32(),
  'onPrimaryFixedVariant': s.onPrimaryFixedVariant.toARGB32(),
  'secondary': s.secondary.toARGB32(),
  'onSecondary': s.onSecondary.toARGB32(),
  'secondaryContainer': s.secondaryContainer.toARGB32(),
  'onSecondaryContainer': s.onSecondaryContainer.toARGB32(),
  'secondaryFixed': s.secondaryFixed.toARGB32(),
  'secondaryFixedDim': s.secondaryFixedDim.toARGB32(),
  'onSecondaryFixed': s.onSecondaryFixed.toARGB32(),
  'onSecondaryFixedVariant': s.onSecondaryFixedVariant.toARGB32(),
  'tertiary': s.tertiary.toARGB32(),
  'onTertiary': s.onTertiary.toARGB32(),
  'tertiaryContainer': s.tertiaryContainer.toARGB32(),
  'onTertiaryContainer': s.onTertiaryContainer.toARGB32(),
  'tertiaryFixed': s.tertiaryFixed.toARGB32(),
  'tertiaryFixedDim': s.tertiaryFixedDim.toARGB32(),
  'onTertiaryFixed': s.onTertiaryFixed.toARGB32(),
  'onTertiaryFixedVariant': s.onTertiaryFixedVariant.toARGB32(),
  'error': s.error.toARGB32(),
  'onError': s.onError.toARGB32(),
  'errorContainer': s.errorContainer.toARGB32(),
  'onErrorContainer': s.onErrorContainer.toARGB32(),
  'surface': s.surface.toARGB32(),
  'onSurface': s.onSurface.toARGB32(),
  'onSurfaceVariant': s.onSurfaceVariant.toARGB32(),
  'surfaceDim': s.surfaceDim.toARGB32(),
  'surfaceBright': s.surfaceBright.toARGB32(),
  'surfaceContainerLowest': s.surfaceContainerLowest.toARGB32(),
  'surfaceContainerLow': s.surfaceContainerLow.toARGB32(),
  'surfaceContainer': s.surfaceContainer.toARGB32(),
  'surfaceContainerHigh': s.surfaceContainerHigh.toARGB32(),
  'surfaceContainerHighest': s.surfaceContainerHighest.toARGB32(),
  'surfaceTint': s.surfaceTint.toARGB32(),
  'inverseSurface': s.inverseSurface.toARGB32(),
  'onInverseSurface': s.onInverseSurface.toARGB32(),
  'inversePrimary': s.inversePrimary.toARGB32(),
  'outline': s.outline.toARGB32(),
  'outlineVariant': s.outlineVariant.toARGB32(),
  'shadow': s.shadow.toARGB32(),
  'scrim': s.scrim.toARGB32(),
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

  test('the fixture the generator is checked against is current', () {
    final json = jsonEncode(_table());
    if (Platform.environment['UPDATE_FIXTURE'] == '1') {
      file.writeAsStringSync('$json\n');
    }
    expect(file.readAsStringSync().trim(), json);
  });
}
