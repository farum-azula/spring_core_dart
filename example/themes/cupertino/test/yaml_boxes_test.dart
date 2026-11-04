// The grey boxes on the pages quote the YAML in lib/resources/. Every line
// of every box must be in one of the files, so the pages cannot say
// something the files do not.
import 'dart:io';

import 'package:flutter/cupertino.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

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
    final seen = <String>{};
    for (final title in [
      'Colors',
      'Typography',
      'Tokens',
      'Own widgets',
      'Controls',
      'Motion',
      'Loaders',
      'Background',
      'Images',
      'Themes',
    ]) {
      await openPage(tester, title);
      // Scroll down the page so that every box is built.
      for (var i = 0; i < 12; i++) {
        for (final box in tester.widgetList<YamlBox>(find.byType(YamlBox))) {
          seen.add(box.text);
          for (final line in box.text.split('\n')) {
            if (_normal(line).isNotEmpty && !known.contains(_normal(line))) {
              missing.add('$title: ${line.trim()}');
            }
          }
        }
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -700),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(seen.length, greaterThan(20));
    expect(missing.toSet(), isEmpty);
    await stopApp(tester);
  });
}
