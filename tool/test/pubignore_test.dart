// What each published package sends to pub.dev: its .pubignore keeps the
// tests and the development tools in the repository (they need its
// fixtures and servers, add weight, and their test keys look like leaked
// secrets to pub.dev).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../version.dart' as family;

void main() {
  final root = p.dirname(p.dirname(p.dirname(Platform.script.toFilePath())));
  String repo(String path) =>
      Directory(path).existsSync() || File(path).existsSync()
      ? path
      : p.join(root, path);

  for (final package in family.family) {
    test('$package keeps its tests out of pub.dev', () {
      final file = File(repo(p.join(package, '.pubignore')));
      expect(file.existsSync(), isTrue, reason: '$package has no .pubignore');
      final rules = file
          .readAsLinesSync()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toSet();
      expect(rules, containsAll(['/test/', '/coverage/', '/tool/']));
      // lib/ and example/ must stay: never ignore them.
      for (final kept in ['lib', 'example', 'android', 'darwin']) {
        expect(
          rules.where((rule) => rule.replaceAll('/', '') == kept),
          isEmpty,
          reason: '$package must publish $kept/',
        );
      }
    });
  }
}
