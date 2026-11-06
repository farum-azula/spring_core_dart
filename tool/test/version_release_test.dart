// tool/version.dart (the family version everywhere, docs/ included) and
// tool/release.dart (each package's changelog gets only what concerns it).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../release.dart'
    show PackageChange, hasUnreleased, packageChange, updateChangelog;
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
      updateChangelog(path, '0.4.0', PackageChange.generated);
      expect(
        File(path).readAsStringSync(),
        '## 0.4.0\n\n- Own change.\n\n## 0.3.0\n',
      );
    });

    test('only regenerated code: says so, never a commit subject', () {
      File(path).writeAsStringSync('## 0.3.0\n\n- Old.\n');
      updateChangelog(path, '0.4.0', PackageChange.generated);
      expect(
        File(path).readAsStringSync(),
        '## 0.4.0\n\n- No changes of its own: its generated code '
        '(`lib/spring_gen/`) is regenerated with spring_core_dart_generator '
        '0.4.0.\n\n## 0.3.0\n\n- Old.\n',
      );
    });

    test('nothing of its own: says so', () {
      File(path).writeAsStringSync('## 0.3.0\n');
      updateChangelog(path, '0.4.0', PackageChange.none);
      expect(
        File(path).readAsStringSync(),
        startsWith(
          '## 0.4.0\n\n- No changes of its own; released with the family '
          'version 0.4.0.\n',
        ),
      );
    });

    test('an Unreleased heading is found', () {
      File(path).writeAsStringSync('## Unreleased\n\n- New.\n\n## 0.3.0\n');
      expect(hasUnreleased(path), isTrue);
      File(path).writeAsStringSync('## 0.3.0\n\n- Unreleased was here.\n');
      expect(hasUnreleased(path), isFalse);
    });
  });

  group('release.dart kinds of change', () {
    test('hand-written lib/ or pubspec.yaml is the package own change', () {
      expect(
        packageChange('spring_web_dart', [
          'spring_web_dart/lib/spring_gen/src/a.spring.dart',
          'spring_web_dart/lib/src/path_pattern.dart',
        ]),
        PackageChange.own,
      );
      expect(
        packageChange('spring_web_dart', ['spring_web_dart/pubspec.yaml']),
        PackageChange.own,
      );
    });

    test('generated code only', () {
      expect(
        packageChange('spring_boot_starter_web', [
          'spring_boot_starter_web/lib/spring_gen/src/config/config.spring.dart',
          'spring_boot_starter_web/lib/spring_gen/spring_metadata.json',
          'spring_boot_starter_web/test/spring_gen/app/app.spring.dart',
          'spring_boot_starter_web/README.md',
        ]),
        PackageChange.generated,
      );
    });

    test('tests, examples, README and other packages are not its own', () {
      expect(
        packageChange('spring_boot_starter_test', [
          'spring_boot_starter_test/test/deferred_proxies_test.dart',
          'spring_boot_starter_test/example/README.md',
          'spring_boot_starter_test/CHANGELOG.md',
          'spring_boot_starter_web/lib/src/web_server.dart',
          // Another package whose name starts the same.
          'spring_boot_starter_testing/lib/a.dart',
        ]),
        PackageChange.none,
      );
    });
  });
}
