// tool/publish.dart: a dry run passes with the one warning a package new
// since the last release gets (its changelog has no section of the current
// version, only `## Unreleased`), and fails with any other.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../publish.dart' show acceptedDryRun;

const _versionWarning =
    "* /x/CHANGELOG.md doesn't mention current version (0.7.0).\n"
    'Package has 1 warning and 5 hints.';

void main() {
  late Directory package;

  setUp(() => package = Directory.systemTemp.createTempSync('publish_'));
  tearDown(() => package.deleteSync(recursive: true));

  void changelog(String text) =>
      File(p.join(package.path, 'CHANGELOG.md')).writeAsStringSync(text);

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
