// tool/publish.dart: a dry run passes with the one warning a package new
// since the last release gets (its changelog has no section of the current
// version, only `## Unreleased`), and fails with any other.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../publish.dart' show acceptedDryRun, invalidTopics;
import '../version.dart' as family;

const _versionWarning =
    "* /x/CHANGELOG.md doesn't mention current version (0.7.0).\n"
    'Package has 1 warning and 5 hints.';

// The repository: the tests run from it, or from tool/.
final String _repository = Directory('tool').existsSync()
    ? Directory.current.path
    : Directory.current.parent.path;

void main() {
  late Directory package;

  setUp(() => package = Directory.systemTemp.createTempSync('publish_'));
  tearDown(() => package.deleteSync(recursive: true));

  void changelog(String text) =>
      File(p.join(package.path, 'CHANGELOG.md')).writeAsStringSync(text);

  group('the topics pub.dev refuses at the upload, not in a dry run', () {
    test('a topic must start with a letter', () {
      expect(
        invalidTopics('name: x\ntopics:\n  - flutter\n  - 3d\n  - scene\n'),
        ['3d'],
      );
    });

    test('lowercase, no double dash, no dash at the end, two letters at '
        'least, five topics at most', () {
      expect(
        invalidTopics(
          'topics:\n  - State\n  - a--b\n  - web-\n  - x\n'
          '  - spring\n  - dart\n  - one-too-many\n\nenvironment:\n',
        ),
        ['State', 'a--b', 'web-', 'x', 'dart', 'one-too-many'],
      );
    });

    test('good topics, and a pubspec without any', () {
      expect(
        invalidTopics('topics:\n  - dependency-injection\n  - http2\n'),
        isEmpty,
      );
      expect(invalidTopics('name: x\nversion: 1.0.0\n'), isEmpty);
    });

    test('every package of the family has topics pub.dev takes', () {
      for (final package in family.family) {
        final pubspec = File(p.join(_repository, package, 'pubspec.yaml'));
        expect(
          invalidTopics(pubspec.readAsStringSync()),
          isEmpty,
          reason: package,
        );
      }
    });
  });

  test('a new package with an Unreleased section passes', () {
    changelog('## Unreleased\n\n- First version.\n');
    expect(acceptedDryRun(_versionWarning, package.path), isTrue);
  });

  test('without an Unreleased section the warning fails', () {
    changelog('## 0.6.3\n\n- Old.\n');
    expect(acceptedDryRun(_versionWarning, package.path), isFalse);
  });

  test('another warning fails', () {
    changelog('## Unreleased\n\n- First version.\n');
    expect(
      acceptedDryRun(
        "* /x/CHANGELOG.md doesn't mention current version (0.7.0).\n"
        '* 6 checked-in files are modified in git.\n'
        'Package has 2 warnings and 5 hints.',
        package.path,
      ),
      isFalse,
    );
    expect(
      acceptedDryRun(
        '* 6 checked-in files are modified in git.\nPackage has 1 warning.',
        package.path,
      ),
      isFalse,
    );
  });
}
