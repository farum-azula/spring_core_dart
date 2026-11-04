// Writes what the reader accepts for every component as JSON, for
// tool/theme_metadata.dart (which cannot import Flutter itself):
//
//   THEME_CATALOG_OUT=build/theme_catalog.json \
//     flutter test test/support/theme_catalog_dump.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'theme_catalog.dart';

void main() {
  test('writes the theme catalog', () {
    final out = Platform.environment['THEME_CATALOG_OUT'];
    if (out == null) {
      return;
    }
    final catalog = {
      for (final MapEntry(:key, :value) in themeCatalog().entries)
        key: [
          for (final p in value)
            {'name': p.name, 'kind': p.kind, 'states': p.states},
        ],
    };
    File(out).writeAsStringSync(jsonEncode(catalog));
  });
}
