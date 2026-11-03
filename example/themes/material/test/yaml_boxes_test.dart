// The grey boxes on the pages quote the YAML in lib/resources/. Every line
// of every box must be in one of the files, so the pages cannot say
// something the files do not.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

import 'support/app.dart';

/// A line without its indentation, and without the `#` of a commented-out
/// line, so that a block shown from a comment still matches.
String _normal(String line) => line
    .trim()
    .replaceFirst(RegExp(r'^#\s*'), '')
    .replaceAll(RegExp(r'\s+'), ' ');

Set<String> _fileLines() => {
  for (final file in [
    File('lib/resources/application.yml'),
    File('lib/resources/application-network.yml'),
    ...Directory('lib/resources/themes').listSync().whereType<File>(),
  ])
    for (final line in file.readAsLinesSync()) _normal(line),
};

void main() {
  testWidgets('every line of every YAML box is in lib/resources/', (
    tester,
  ) async {
    await startApp(tester);
    final known = _fileLines();
    final missing = <String>[];
    var boxes = 0;
    void check() {
      for (final box in tester.widgetList<YamlBox>(find.byType(YamlBox))) {
        boxes++;
        for (final line in box.text.split('\n')) {
          if (_normal(line).isNotEmpty && !known.contains(_normal(line))) {
            missing.add(line.trim());
          }
        }
      }
    }

    for (final title in [
      'Colors',
      'Type and space',
      'Tokens',
      'Components',
      'Own widgets',
      'Motion',
      'Background',
      'Images',
      'Themes',
    ]) {
      await openPage(tester, title);
      check();
      if (title == 'Components') {
        for (final tab in [
          'Selection',
          'Inputs',
          'Feedback',
          'Navigation',
          'Lists and cards',
          'Cupertino',
        ]) {
          await tester.tap(find.widgetWithText(Tab, tab));
          await settle(tester);
          check();
        }
      }
    }
    expect(boxes, greaterThan(30));
    expect(missing, isEmpty);
    await stopApp(tester);
  });
}
