// Prepares a release of the whole family (run by .github/workflows/release.yml,
// the "Release" button on main; works locally too):
//
//   dart run tool/release.dart --bump=patch  # 0.1.6 -> 0.1.7
//   dart run tool/release.dart --bump=minor  # 0.1.6 -> 0.2.0
//   dart run tool/release.dart --bump=... --dry-run  # only print
//   dart run tool/release.dart --check  # CI: every change has its changelog
//
// The bump is chosen by hand (the Release button asks for it): `patch` or
// `minor`; there is no major release before 1.0.0, so none can be made by
// accident. When no commit since the last `v*` tag changes a published
// package (commits touching only extensions/, .github/, tool/, roadmap/ or
// the repository README are ignored), nothing is released. Without a tag
// yet, the current version is released as it is.
//
// Every package gets the version (tool/version.dart). Changelogs: an
// `## Unreleased` section (written by hand, only what concerns that
// package) becomes `## <version>`. Commit subjects never go into a
// changelog (a squash merge's subject is the pull request's title, which
// says nothing about a package). A package without the section gets a
// line of its own only when nothing of its own changed: its generated
// code (`lib/spring_gen/`, `*.spring.dart`) regenerated, or only its tests,
// examples or README. Hand-written code under `lib/` or the `pubspec.yaml`
// changed without an `## Unreleased` section fails the release before
// anything is written, and `--check` (CI, on every push) fails the same
// way, so a missing changelog shows on the pull request, not at the
// release. The version is printed and, on GitHub Actions, written to
// `$GITHUB_OUTPUT` as `version` (empty when there is nothing to release).
import 'dart:io';

import 'version.dart' as family;

void main(List<String> args) {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final dryRun = args.contains('--dry-run');
  if (args.contains('--check')) {
    final problems = changelogProblems(_lastTag());
    if (problems.isNotEmpty) {
      problems.forEach(stderr.writeln);
      exit(1);
    }
    stdout.writeln('Every changed package has its changelog.');
    return;
  }
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
  final lastTag = _lastTag();
  final commits = _commitsSince(lastTag);
  if (lastTag != null && commits.isEmpty) {
    stdout.writeln('Nothing to release since $lastTag.');
    _output('');
    return;
  }
  final next = lastTag == null ? current : _bump(current, bump);
  final since = lastTag == null
      ? 'first release'
      : '${commits.length} commits since $lastTag';
  stdout.writeln('Release $next ($since)');
  // Checked before anything is written: a failed release changes no file.
  final missing = changelogProblems(lastTag);
  if (missing.isNotEmpty) {
    missing.forEach(stderr.writeln);
    exit(1);
  }
  if (dryRun) {
    for (final commit in commits) {
      stdout.writeln('  - ${commit.subject}');
    }
    return;
  }
  // The kinds are read before setVersion, which turns `## Unreleased` into
  // the version.
  final changes = {
    for (final package in family.family)
      package: packageChange(package, _changedFiles(lastTag, package)),
  };
  family.setVersion(next);
  for (final package in family.family) {
    updateChangelog('$package/CHANGELOG.md', next, changes[package]!);
  }
  final problems = family.check();
  if (problems.isNotEmpty) {
    problems.forEach(stderr.writeln);
    exit(1);
  }
  _output(next);
}

/// What changed in a package since the last release, for its changelog
/// when it has no `## Unreleased` section.
enum PackageChange {
  /// Nothing, or only its tests, examples or README.
  none,

  /// Its generated code (`lib/spring_gen/`, `*.spring.dart`) and nothing of
  /// its own.
  generated,

  /// Hand-written code under `lib/` or its `pubspec.yaml`: it needs an
  /// `## Unreleased` section written by hand.
  own,
}

/// The kind of change of [package] from [files], the paths (from the
/// repository's root) changed since the last release.
PackageChange packageChange(String package, Iterable<String> files) {
  var change = PackageChange.none;
  for (final file in files) {
    if (!file.startsWith('$package/')) {
      continue;
    }
    final path = file.substring(package.length + 1);
    if (path == 'pubspec.yaml') {
      return PackageChange.own;
    }
    if (!path.startsWith('lib/')) {
      continue;
    }
    final generated =
        path.startsWith('lib/spring_gen/') || path.endsWith('.spring.dart');
    if (!generated) {
      return PackageChange.own;
    }
    change = PackageChange.generated;
  }
  return change;
}

/// One line per package whose own code changed since [tag] without an
/// `## Unreleased` section in its changelog; empty when there is none (or
/// no tag yet).
List<String> changelogProblems(String? tag) {
  if (tag == null) {
    return const [];
  }
  return [
    for (final package in family.family)
      if (!hasUnreleased('$package/CHANGELOG.md') &&
          packageChange(package, _changedFiles(tag, package)) ==
              PackageChange.own)
        _missingChangelog(package, tag),
  ];
}

String _missingChangelog(String package, String tag) =>
    '$package changed since $tag (lib/ or pubspec.yaml) but '
    '$package/CHANGELOG.md has no "## Unreleased" section: write what '
    'changed for its users there.';

/// Whether the changelog at [path] starts a `## Unreleased` section.
bool hasUnreleased(String path) {
  final file = File(path);
  return file.existsSync() &&
      RegExp(
        r'^## Unreleased\s*$',
        multiLine: true,
      ).hasMatch(file.readAsStringSync());
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

// The files of [package] changed between [tag] and HEAD (all of them
// without a tag).
List<String> _changedFiles(String? tag, String package) => [
  for (final line in _git([
    if (tag != null) ...[
      'diff',
      '--name-only',
      tag,
      'HEAD',
    ] else ...[
      'ls-files',
    ],
    '--',
    package,
  ]).split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

String? _lastTag() =>
    _git(['tag', '--list', 'v[0-9]*', '--sort=-v:refname'])
        .split('\n')
        .where((tag) => tag.trim().isNotEmpty)
        .firstOrNull;

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
// published) is merged into it.
/// Puts the [version] section into the changelog at [path]: its
/// `## Unreleased` section if it has one, else a line for [change]
/// ([PackageChange.own] never gets here: the release stops before).
void updateChangelog(String path, String version, PackageChange change) {
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
  final entry = switch (change) {
    PackageChange.generated =>
      '- No changes of its own: its generated code (`lib/spring_gen/`) is '
          'regenerated with spring_core_dart_generator $version.',
    _ => '- No changes of its own; released with the family version $version.',
  };
  file.writeAsStringSync('$heading\n\n$entry\n\n$text');
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
