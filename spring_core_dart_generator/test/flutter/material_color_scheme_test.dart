import 'dart:convert';
import 'dart:io';

import 'package:spring_core_dart_generator/src/theme_palette.dart';
import 'package:test/test.dart';

// The fixture is the table Flutter's ColorScheme.fromSeed makes (written by
// spring_boot_starter_flutter/test/color_scheme_fixture_test.dart). The
// generator's own port of the colour code must give the same values.
File _fixture() {
  const path = 'test/fixtures/color_scheme_table.json';
  for (final prefix in ['', 'spring_core_dart_generator/']) {
    final file = File('$prefix$path');
    if (file.existsSync()) {
      return file;
    }
  }
  throw StateError('$path not found from ${Directory.current.path}');
}

void main() {
  test('roles equal Flutter ColorScheme.fromSeed', () {
    final rows = (jsonDecode(_fixture().readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    expect(rows, isNotEmpty);
    var checked = 0;
    for (final row in rows) {
      final scheme = materialScheme(
        row['seed'] as int,
        row['variant'] as String,
        dark: row['brightness'] == 'dark',
        contrast: (row['contrast'] as num).toDouble(),
      );
      final roles = (row['roles'] as Map).cast<String, int>();
      for (final MapEntry(:key, :value) in roles.entries) {
        final got = materialRole(scheme, key.toLowerCase());
        expect(
          got,
          value,
          reason:
              '${row['seed']} ${row['variant']} ${row['brightness']} '
              '${row['contrast']} $key: '
              '0x${got?.toRadixString(16)} != 0x${value.toRadixString(16)}',
        );
        checked++;
      }
    }
    expect(checked, greaterThan(10000));
  });

  test('an unknown variant is tonal spot and an unknown role is null', () {
    final a = materialScheme(0xFF6750A4, 'nope', dark: false);
    final b = materialScheme(0xFF6750A4, 'tonal-spot', dark: false);
    expect(materialRole(a, 'primary'), materialRole(b, 'primary'));
    expect(materialRole(a, 'nothing'), isNull);
  });
}
