// Publishes every package of the family to pub.dev, dependencies first, and
// skips versions that are already there (a re-run after a partial failure
// continues where it stopped). Run by .github/workflows/publish.yml when a
// `v<version>` tag is pushed; locally (after `dart pub login`) for the first
// release, before automated publishing can be enabled on pub.dev.
//
//   dart run tool/publish.dart                     # publish every package
//   dart run tool/publish.dart --package <name>    # only one (one CI job each)
//   dart run tool/publish.dart --dry-run           # validate only
import 'dart:io';

import 'version.dart' as family;

Future<void> main(List<String> args) async {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final dryRun = args.contains('--dry-run');
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
  // On GitHub the tag must match the version in the pubspecs.
  final ref = Platform.environment['GITHUB_REF_NAME'];
  if (ref != null && ref != 'v$version') {
    stderr.writeln('Tag $ref does not match the version $version.');
    exit(1);
  }
  // `family` is already in dependency order: core, generator, Boot, starters.
  for (final package in [?only, if (only == null) ...family.family]) {
    if (!dryRun && await _isPublished(package, version)) {
      stdout.writeln('$package $version is already on pub.dev, skipped.');
      continue;
    }
    // pub.dev accepts GitHub's token only for packages that exist already.
    if (!dryRun && ref != null && !await _exists(package)) {
      stderr.writeln(
        '$package is not on pub.dev yet. A new package must be published '
        'by hand once: `git checkout $ref`, then `dart pub publish` in '
        '$package/, then enable automated publishing on its admin page '
        '(repository farum-azula/spring_core_dart, tag pattern '
        'v{{version}}) and re-run this job.',
      );
      exit(1);
    }
    stdout.writeln(
      '\n=== ${dryRun ? 'Validating' : 'Publishing'} $package $version ===',
    );
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['pub', 'publish', if (dryRun) '--dry-run' else '--force'],
      workingDirectory: package,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await process.exitCode != 0) {
      stderr.writeln('Publishing $package failed.');
      exit(1);
    }
  }
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
