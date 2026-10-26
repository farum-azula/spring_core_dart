// Prepares a release of the whole family (run by .github/workflows/release.yml,
// the "Release" button on main; works locally too):
//
//   dart run tool/release.dart --bump=patch  # 0.1.6 -> 0.1.7
//   dart run tool/release.dart --bump=minor  # 0.1.6 -> 0.2.0
//   dart run tool/release.dart --bump=... --dry-run  # only print
//
// The bump is chosen by hand (the Release button asks for it): `patch` or
// `minor`; there is no major release before 1.0.0, so none can be made by
// accident. The commits since the last `v*` tag that change a published
// package (commits touching only extensions/, .github/, tool/, roadmap/ or
// the repository README are ignored) are listed and go into the changelogs
// of packages without an `## Unreleased` section; when there are none,
// nothing is released. Without a tag yet, the current version is released
// as it is.
//
// Every package gets the version (tool/version.dart). Changelogs: an
// `## Unreleased` section (written by hand, only what concerns that
// package) becomes `## <version>`; a package without one gets the subjects
// of the commits that changed its own folder, or a line saying it has no
// changes of its own — never the commits of the other packages. The
// version is printed and, on
// GitHub Actions, written to `$GITHUB_OUTPUT` as `version` (empty when
// there is nothing to release).
import 'dart:io';

import 'version.dart' as family;

void main(List<String> args) {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final dryRun = args.contains('--dry-run');
  final bump = args
      .where((a) => a.startsWith('--bump='))
      .map((a) => a.substring('--bump='.length))
      .firstOrNull;
  if (bump == null || (bump != 'patch' && bump != 'minor')) {
    stderr.writeln(
      'usage: dart run tool/release.dart --bump=patch|minor [--dry-run]',
    );
    exit(64);
  }

  final current = _currentVersion();
  final lastTag = _git(['tag', '--list', 'v[0-9]*', '--sort=-v:refname'])
      .split('\n')
      .where((tag) => tag.trim().isNotEmpty)
      .firstOrNull;
  final commits = _commitsSince(lastTag);
  if (lastTag != null && commits.isEmpty) {
    stdout.writeln('Nothing to release since $lastTag.');
    _output('');
    return;
  }
  final next = lastTag == null ? current : _bump(current, bump);
  stdout.writeln(
    'Release $next '
    '(${lastTag == null ? 'first release' : '${commits.length} commits since $lastTag'})',
  );
  if (dryRun) {
    for (final commit in commits) {
      stdout.writeln('  - ${commit.subject}');
    }
    return;
  }
  family.setVersion(next);
  for (final package in family.family) {
    updateChangelog(
      '$package/CHANGELOG.md',
      next,
      _commitsSince(lastTag, paths: [package]),
    );
  }
  final problems = family.check();
  if (problems.isNotEmpty) {
    problems.forEach(stderr.writeln);
    exit(1);
  }
  _output(next);
}

/// A commit: its subject and body.
final class Commit {
  Commit(this.subject, this.body);
  final String subject;
  final String body;
}

// Only commits that change a published package count: editor extensions,
// CI, tools and the repository README do not make a new pub.dev release.
// [paths]: only commits changing these (by default any published package).
List<Commit> _commitsSince(String? tag, {List<String>? paths}) {
  const separator = '\x1e';
  final log = _git([
    'log',
    '--no-merges',
    '--format=%s%x1f%b$separator',
    if (tag != null) '$tag..HEAD',
    '--',
    ...?paths,
    if (paths == null) ...family.family,
  ]);
  return [
    for (final entry in log.split(separator))
      if (entry.trim().isNotEmpty)
        () {
          final [subject, ...body] = entry.trim().split('\x1f');
          return Commit(subject.trim(), body.join().trim());
        }(),
  ].where((c) => !c.subject.startsWith('chore(release)')).toList();
}

String _bump(String version, String bump) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version)!;
  final [major, minor, patch] = [
    for (var i = 1; i <= 3; i++) int.parse(match.group(i)!),
  ];
  // Before 1.0.0 a minor release may break (pub's caret: ^0.2.0 < 0.3.0).
  return bump == 'minor'
      ? '$major.${minor + 1}.0'
      : '$major.$minor.${patch + 1}';
}

// After setVersion an `## Unreleased` section is already `## <version>`;
// a second, older `## <version>` heading (a version that was never
// published) is merged into it. Without such a section the commit subjects
// become one.
/// Puts the [version] section into the changelog at [path]: its
/// `## Unreleased` section if it has one, else the subjects of [commits]
/// (the commits that changed this package), else a line saying it has no
/// changes of its own.
void updateChangelog(String path, String version, List<Commit> commits) {
  final file = File(path);
  final heading = '## $version';
  var text = file.existsSync() ? file.readAsStringSync() : '';
  final first = text.indexOf('$heading\n');
  if (first >= 0) {
    final second = text.indexOf('\n$heading\n', first + heading.length);
    if (second >= 0) {
      text =
          text.substring(0, second) +
          text.substring(second + heading.length + 1);
    }
    file.writeAsStringSync(text);
    return;
  }
  final entries = commits.isEmpty
      ? ['- No changes of its own; released with the family version $version.']
      : [for (final commit in commits) '- ${commit.subject}'];
  file.writeAsStringSync('$heading\n\n${entries.join('\n')}\n\n$text');
}

String _currentVersion() => RegExp(r'^version: (.*)$', multiLine: true)
    .firstMatch(File('spring_core_dart/pubspec.yaml').readAsStringSync())!
    .group(1)!
    .trim();

String _git(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) {
    stderr.writeln('git ${args.join(' ')} failed: ${result.stderr}');
    exit(1);
  }
  return result.stdout as String;
}

void _output(String version) {
  final output = Platform.environment['GITHUB_OUTPUT'];
  if (output != null) {
    File(output).writeAsStringSync('version=$version\n', mode: FileMode.append);
  }
}
