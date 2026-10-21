// Runs the tests of every workspace package (the `workspace:` list of the
// root pubspec.yaml, example included) twice: from the package directory,
// as `dart test` is usually run, and from the workspace root, as IDEs and
// `dart test <dir>` do, so nothing may depend on the working directory.
// New packages are picked up automatically.
//
//   dart run tool/test_all.dart            # both passes
//   dart run tool/test_all.dart --packages # only from the package directories
//   dart run tool/test_all.dart --root     # only from the workspace root
import 'dart:io';

Future<void> main(List<String> args) async {
  // The workspace root (this script is in tool/), wherever it is run from.
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final packageRun = !args.contains('--root');
  final rootRun = !args.contains('--packages');
  final packages = [
    for (final package in workspacePackages())
      if (Directory('$package/test').existsSync()) package,
  ];
  stdout.writeln('Packages with tests: ${packages.join(', ')}');

  final failures = <String>[];
  if (packageRun) {
    for (final package in packages) {
      if (!await _run('dart test (in $package)', ['test'], package)) {
        failures.add('$package (from its directory)');
      }
    }
  }
  if (rootRun) {
    final directories = [for (final package in packages) '$package/test'];
    if (!await _run('dart test (from the root)', [
      'test',
      ...directories,
    ], '.')) {
      failures.add('workspace root run');
    }
  }

  if (failures.isEmpty) {
    stdout.writeln('\nAll tests passed in ${packages.length} packages.');
    return;
  }
  stderr.writeln('\nFailed: ${failures.join(', ')}');
  exit(1);
}

/// The `workspace:` entries of the root pubspec.yaml.
List<String> workspacePackages() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final start = lines.indexWhere((line) => line.trim() == 'workspace:');
  if (start < 0) {
    throw StateError('No workspace: list in pubspec.yaml');
  }
  return [
    for (final line
        in lines
            .skip(start + 1)
            .takeWhile((line) => line.trim().isEmpty || line.startsWith(' ')))
      if (line.trim().startsWith('- ')) line.trim().substring(2).trim(),
  ];
}

Future<bool> _run(String title, List<String> args, String directory) async {
  stdout.writeln('\n=== $title ===');
  final process = await Process.start(
    Platform.resolvedExecutable,
    args,
    workingDirectory: directory,
    mode: ProcessStartMode.inheritStdio,
  );
  return await process.exitCode == 0;
}
