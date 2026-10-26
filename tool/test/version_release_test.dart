// tool/version.dart (the family version everywhere, docs/ included) and
// tool/release.dart (each package's changelog gets only what concerns it).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../release.dart' show Commit, updateChangelog;
import '../version.dart' as family;

void main() {
  group('version.dart', () {
    test('docs/ is among the files whose snippets carry the version', () {
      final files = family.docFiles();
      expect(files, contains(p.join('docs', 'testing.md')));
      expect(files, contains(p.join('docs', 'configuration.md')));
      expect(files.where((f) => f.endsWith('CHANGELOG.md')), isEmpty);
      expect(files.where((f) => f.endsWith('.spring.dart')), isEmpty);
    });

    test('a family constraint in a docs snippet is recognized', () {
      const snippet = '''
```yaml
dev_dependencies:
  spring_boot_starter_test: ^0.3.0
  build_runner: ^2.17.0
```
''';
      final matches = family.docConstraint.allMatches(snippet).toList();
      expect(matches, hasLength(1));
      expect(matches.single[2], '^0.3.0');
    });

    test('every snippet of this repository has the current version', () {
      expect(family.check(), isEmpty);
    });
  });

  group('release.dart changelogs', () {
    late Directory directory;
    late String path;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('changelog_');
      path = p.join(directory.path, 'CHANGELOG.md');
    });

    tearDown(() => directory.deleteSync(recursive: true));

    test('an Unreleased section written by hand is kept', () {
      // setVersion has turned `## Unreleased` into the version already.
      File(path).writeAsStringSync('## 0.4.0\n\n- Own change.\n\n## 0.3.0\n');
      updateChangelog(path, '0.4.0', [Commit('feat(other): unrelated', '')]);
      expect(
        File(path).readAsStringSync(),
        '## 0.4.0\n\n- Own change.\n\n## 0.3.0\n',
      );
    });

    test('without one: the commits of this package', () {
      File(path).writeAsStringSync('## 0.3.0\n\n- Old.\n');
      updateChangelog(path, '0.4.0', [Commit('fix(cache): eviction', '')]);
      expect(
        File(path).readAsStringSync(),
        '## 0.4.0\n\n- fix(cache): eviction\n\n## 0.3.0\n\n- Old.\n',
      );
    });

    test('without commits of its own: says so', () {
      File(path).writeAsStringSync('## 0.3.0\n');
      updateChangelog(path, '0.4.0', const []);
      expect(
        File(path).readAsStringSync(),
        startsWith(
          '## 0.4.0\n\n- No changes of its own; released with the family '
          'version 0.4.0.\n',
        ),
      );
    });
  });
}
