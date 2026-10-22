// Publishes every package of the family to pub.dev, dependencies first, and
// skips versions that are already there (a re-run after a partial failure
// continues where it stopped). Run by .github/workflows/publish.yml when a
// `v<version>` tag is pushed; locally (after `dart pub login`) for the first
// release, before automated publishing can be enabled on pub.dev.
//
//   dart run tool/publish.dart            # publish
//   dart run tool/publish.dart --dry-run  # validate only
import 'dart:io';

import 'version.dart' as family;

Future<void> main(List<String> args) async {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final dryRun = args.contains('--dry-run');
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
  for (final package in family.family) {
    if (!dryRun && await _isPublished(package, version)) {
      stdout.writeln('$package $version is already on pub.dev, skipped.');
      continue;
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

String _version(String package) => RegExp(r'^version: (.*)$', multiLine: true)
    .firstMatch(File('$package/pubspec.yaml').readAsStringSync())!
    .group(1)!
    .trim();
