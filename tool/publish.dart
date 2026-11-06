// Publishes every package of the family to pub.dev, dependencies first, and
// skips versions that are already there (a re-run after a partial failure
// continues where it stopped). Run by .github/workflows/publish.yml when a
// `v<version>` tag is pushed.
//
// pub.dev lets only a person publish the first version of a new package, so
// on GitHub a package that is not on pub.dev yet is skipped with a warning.
// Publish such packages from your machine (after `dart pub login`), from the
// release tag — everything missing is published in order:
//
//   git fetch --tags && git checkout v<version>
//   dart run tool/publish.dart
//
// then enable automated publishing on each new package's admin page
// (repository farum-azula/spring_core_dart, tag pattern v{{version}}).
//
//   dart run tool/publish.dart                     # publish every package
//   dart run tool/publish.dart --package <name>    # only one (one CI job each)
//   dart run tool/publish.dart --dry-run           # validate only
//   dart run tool/publish.dart --dry-run --dart    # only the Dart packages
//   dart run tool/publish.dart --dry-run --flutter # only the Flutter ones
//
// CI validates every package with --dry-run on each push, so what pub.dev
// would refuse (a package imported from lib/ but not in `dependencies`, a
// file too large, a missing field) fails there and not in the release.
import 'dart:io';

import 'version.dart' as family;

/// Packages of the family kept in the repository, not on pub.dev yet: a
/// git dependency until they are released (their version stays the
/// family's).
const notPublished = {'spring_search_dart'};

Future<void> main(List<String> args) async {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final dryRun = args.contains('--dry-run');
  final dartOnly = args.contains('--dart');
  final flutterOnly = args.contains('--flutter');
  final only = args.contains('--package')
      ? args[args.indexOf('--package') + 1]
      : null;
  if (only != null && !family.family.contains(only)) {
    stderr.writeln(
      'Unknown package $only; one of ${family.family.join(', ')}.',
    );
    exit(64);
  }
  final problems = family.check();
  if (problems.isNotEmpty) {
    problems.forEach(stderr.writeln);
    exit(1);
  }
  final version = _version('spring_core_dart');
  // On GitHub the tag must match the version in the pubspecs; locally the
  // checkout must be that tag (never publish unreleased code from main).
  final ref = Platform.environment['GITHUB_REF_NAME'];
  // A dry run (CI, on every push) validates from any branch.
  if (ref != null && !dryRun && ref != 'v$version') {
    stderr.writeln('Tag $ref does not match the version $version.');
    exit(1);
  }
  if (ref == null && !dryRun && !_isCheckedOutTag('v$version')) {
    stderr.writeln(
      'Publish from the release tag: git fetch --tags && git checkout '
      'v$version (the checkout is not at v$version).',
    );
    exit(1);
  }
  // `family` is already in dependency order: core, generator, Boot, starters.
  for (final package in [?only, if (only == null) ...family.family]) {
    if (notPublished.contains(package)) {
      stdout.writeln('$package is not published yet, skipped.');
      continue;
    }
    if ((dartOnly && _usesFlutter(package)) ||
        (flutterOnly && !_usesFlutter(package))) {
      continue;
    }
    if (!dryRun && await _isPublished(package, version)) {
      stdout.writeln('$package $version is already on pub.dev, skipped.');
      continue;
    }
    // pub.dev accepts GitHub's token only for packages that exist already:
    // a new one is skipped, the others are still published.
    if (!dryRun && ref != null && !await _exists(package)) {
      _skipNew(package, ref);
      continue;
    }
    stdout.writeln(
      '\n=== ${dryRun ? 'Validating' : 'Publishing'} $package $version ===',
    );
    // Flutter packages need the Flutter SDK's pub (FLUTTER_ROOT).
    final flutter = _usesFlutter(package);
    final executable = flutter ? 'flutter' : Platform.resolvedExecutable;
    if (dryRun) {
      final result = await Process.run(executable, [
        'pub',
        'publish',
        '--dry-run',
      ], workingDirectory: package);
      final output = '${result.stdout}${result.stderr}';
      stdout.write(output);
      if (result.exitCode != 0 && !acceptedDryRun(output, package)) {
        stderr.writeln('Publishing $package failed.');
        exit(1);
      }
      continue;
    }
    final process = await Process.start(
      executable,
      ['pub', 'publish', '--force'],
      workingDirectory: package,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await process.exitCode != 0) {
      stderr.writeln('Publishing $package failed.');
      exit(1);
    }
  }
}

/// Whether a failed dry run of [package] (its [output]) still passes: its
/// only warning is that the changelog does not mention the current version
/// while it has an `## Unreleased` section, which the release turns into
/// the next version (a package new since the last release has no section
/// of the current one).
bool acceptedDryRun(String output, String package) {
  final changelog = File('$package/CHANGELOG.md');
  final unreleased =
      changelog.existsSync() &&
      RegExp(
        r'^## Unreleased\s*$',
        multiLine: true,
      ).hasMatch(changelog.readAsStringSync());
  return unreleased &&
      RegExp('Package has 1 warning').hasMatch(output) &&
      output.contains("CHANGELOG.md doesn't mention current version");
}

Future<bool> _isPublished(String package, String version) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.https('pub.dev', '/api/packages/$package/versions/$version'),
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode == 200;
  } on Object catch (error) {
    stderr.writeln('Could not ask pub.dev about $package: $error');
    return false;
  } finally {
    client.close();
  }
}

// A warning on the run, and the steps in its summary.
void _skipNew(String package, String ref) {
  stdout.writeln(
    '::warning title=$package is new::$package is not on pub.dev yet: '
    'skipped. Publish it from your machine: git checkout $ref && '
    'dart run tool/publish.dart',
  );
  final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null) {
    File(summary).writeAsStringSync(
      '### $package: not on pub.dev yet, skipped\n\n'
      'pub.dev lets only a person publish the first version. From your '
      'machine (after `dart pub login`):\n\n'
      '```bash\ngit fetch --tags && git checkout $ref\n'
      'dart run tool/publish.dart\n```\n\n'
      'Then enable automated publishing on '
      'https://pub.dev/packages/$package/admin (repository '
      '`farum-azula/spring_core_dart`, tag pattern `v{{version}}`).\n\n',
      mode: FileMode.append,
    );
  }
}

bool _isCheckedOutTag(String tag) {
  final result = Process.runSync('git', ['tag', '--points-at', 'HEAD']);
  return result.exitCode == 0 &&
      (result.stdout as String).split('\n').map((t) => t.trim()).contains(tag);
}

Future<bool> _exists(String package) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.https('pub.dev', '/api/packages/$package'),
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode != 404;
  } on Object {
    return true; // unknown: let `dart pub publish` report the real error
  } finally {
    client.close();
  }
}

String _version(String package) => RegExp(r'^version: (.*)$', multiLine: true)
    .firstMatch(File('$package/pubspec.yaml').readAsStringSync())!
    .group(1)!
    .trim();

/// Whether [package] depends on the Flutter SDK.
bool _usesFlutter(String package) =>
    File('$package/pubspec.yaml')
        .readAsLinesSync()
        .any((line) => line.trim() == 'sdk: flutter');
