// The code boxes on the pages quote the YAML of this app and of neon_ui.
// Every line of every box must be in one of the files, so the pages cannot
// say something the files do not.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:theme_showcase_neon/src/widgets/yaml_box.dart';

import 'support/app.dart';
import 'support/neon_ui_files.dart';

/// A line without its indentation and with one space between words.
String _normal(String line) => line.trim().replaceAll(RegExp(r'\s+'), ' ');

Set<String> _fileLines() => {
  for (final file in [
    File('lib/resources/application.yml'),
    neonUiFile('lib/resources/themes/neon.yml'),
  ])
    for (final line in file.readAsLinesSync()) _normal(line),
};

void main() {
  testWidgets('every line of every YAML box is in the resources', (
    tester,
  ) async {
    await startApp(tester);
    final known = _fileLines();
    final missing = <String>[];
    var boxes = 0;
    for (final (label, _) in pageTitles.values) {
      await openPage(tester, label);
      for (final box in tester.widgetList<YamlBox>(find.byType(YamlBox))) {
        boxes++;
        for (final line in box.text.split('\n')) {
          if (_normal(line).isNotEmpty && !known.contains(_normal(line))) {
            missing.add('$label: ${line.trim()}');
          }
        }
      }
    }
    expect(boxes, greaterThan(10));
    expect(missing, isEmpty);
    await stopApp(tester);
  });
}
