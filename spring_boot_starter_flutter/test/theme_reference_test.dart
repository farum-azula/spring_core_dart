// The component reference in docs/configuration.md is generated from the
// mapping, so it cannot drift: this test fails when it differs. To
// rewrite it: UPDATE_THEME_DOCS=1 flutter test test/theme_reference_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/theme_reference.dart';

const _start = '<!-- theme-components:start -->';
const _end = '<!-- theme-components:end -->';

final _doc = File('docs/configuration.md').existsSync()
    ? File('docs/configuration.md')
    : File('../docs/configuration.md');

void main() {
  test(
    'docs/configuration.md lists the components the mapping reads',
    skip: _doc.existsSync() ? null : 'outside the repository',
    () {
      final text = _doc.readAsStringSync();
      final from = text.indexOf(_start);
      final to = text.indexOf(_end);
      expect(from, isNonNegative, reason: 'missing $_start');
      expect(to, greaterThan(from), reason: 'missing $_end');
      final expected = '$_start\n\n${themeReference()}\n\n';
      if (Platform.environment['UPDATE_THEME_DOCS'] == '1') {
        _doc.writeAsStringSync(
          text.replaceRange(from, to, expected),
        );
        return;
      }
      expect(
        text.substring(from, to),
        expected,
        reason:
            'run UPDATE_THEME_DOCS=1 flutter test '
            'test/theme_reference_test.dart in spring_boot_starter_flutter',
      );
    },
  );
}
