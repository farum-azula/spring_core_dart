// Prepares a release of the whole family (run by .github/workflows/release.yml,
// the "Release" button on main; works locally too):
//
//   dart run tool/release.dart            # bump, write versions and changelogs
//   dart run tool/release.dart --dry-run  # only print what would happen
//
// The next version follows the commits since the last `v*` tag that change
// a published package (commits touching only extensions/, .github/, tool/,
// roadmap/ or the repository README are ignored):
// - a breaking change (`feat!:`, `BREAKING CHANGE`) bumps the major version
//   (the minor one before 1.0.0, where minor releases may break);
// - a feature (`feat:` or a subject starting with "Add") bumps the minor
//   version (the patch one before 1.0.0);
// - anything else bumps the patch version.
// Without a tag yet, the current version is released as it is.
//
// Every package gets the version (tool/version.dart). Changelogs: an
// `## Unreleased` section becomes `## <version>`; packages without one get
// a section listing the commit subjects. The version is printed and, on
// GitHub Actions, written to `$GITHUB_OUTPUT` as `version` (empty when
// there is nothing to release).
import 'dart:io';

import 'version.dart' as family;

void main(List<String> args) {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final dryRun = args.contains('--dry-run');

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
  final next = lastTag == null ? current : _bump(current, commits);
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
    _updateChangelog('$package/CHANGELOG.md', next, commits);
  }
  final problems = family.check();
  if (problems.isNotEmpty) {
    problems.forEach(stderr.writeln);
    exit(1);
  }
  _output(next);
}

final class _Commit {
  _Commit(this.subject, this.body);
  final String subject;
  final String body;

  bool get breaking =>
      RegExp(r'^\w+(\([^)]*\))?!:').hasMatch(subject) ||
      body.contains('BREAKING CHANGE');

  bool get feature =>
      RegExp(r'^feat(\([^)]*\))?:', caseSensitive: false).hasMatch(subject) ||
      RegExp(r'^add\b', caseSensitive: false).hasMatch(subject);
}

// Only commits that change a published package count: editor extensions,
// CI, tools and the repository README do not make a new pub.dev release.
List<_Commit> _commitsSince(String? tag) {
  const separator = '\x1e';
  final log = _git([
    'log',
    '--no-merges',
    '--format=%s%x1f%b$separator',
    if (tag != null) '$tag..HEAD',
    '--',
    ...family.family,
  ]);
  return [
    for (final entry in log.split(separator))
      if (entry.trim().isNotEmpty)
        () {
          final [subject, ...body] = entry.trim().split('\x1f');
          return _Commit(subject.trim(), body.join().trim());
        }(),
  ].where((c) => !c.subject.startsWith('chore(release)')).toList();
}

String _bump(String version, List<_Commit> commits) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version)!;
  var [major, minor, patch] = [
    for (var i = 1; i <= 3; i++) int.parse(match.group(i)!),
  ];
  final breaking = commits.any((c) => c.breaking);
  final feature = commits.any((c) => c.feature);
  if (major == 0) {
    // Before 1.0.0 a minor release may break (pub's caret: ^0.2.0 < 0.3.0).
    if (breaking) {
      return '0.${minor + 1}.0';
    }
    return '0.$minor.${patch + 1}';
  }
  if (breaking) {
    return '${major + 1}.0.0';
  }
  if (feature) {
    return '$major.${minor + 1}.0';
  }
  return '$major.$minor.${patch + 1}';
}

// After setVersion an `## Unreleased` section is already `## <version>`;
// a second, older `## <version>` heading (a version that was never
// published) is merged into it. Without such a section the commit subjects
// become one.
void _updateChangelog(String path, String version, List<_Commit> commits) {
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
      ? ['- Released with the family version $version.']
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
