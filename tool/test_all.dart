// Runs the tests of every workspace package (the `workspace:` list of the
// root pubspec.yaml, example included) twice: from the package directory,
// as `dart test` is usually run, and from the workspace root, as IDEs and
// `dart test <dir>` do, so nothing may depend on the working directory.
// New packages are picked up automatically.
//
//   dart run tool/test_all.dart            # both passes
//   dart run tool/test_all.dart --packages # only from the package directories
//   dart run tool/test_all.dart --root     # only from the workspace root
//
// The runs go in parallel (a pool sized by the CPU count), and slow test
// suites are split into shards (`dart test --total-shards`), so the whole
// thing takes about as long as its slowest shard. Each run prints one line;
// the output of a failed run is printed in full at the end.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Packages whose tests take minutes (in-memory builds), split into shards.
const _slow = {'spring_core_dart_generator'};

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

  final cpus = Platform.numberOfProcessors;
  final shards = cpus >= 8 ? 4 : 2;
  final runs = <_Run>[
    // Slow ones first, so they don't end up last in the queue.
    if (rootRun)
      for (var shard = 0; shard < shards; shard++)
        _Run('from the root (shard ${shard + 1}/$shards)', '.', [
          ...[for (final package in packages) '$package/test'],
          '--total-shards=$shards',
          '--shard-index=$shard',
        ], failure: 'workspace root run'),
    if (packageRun)
      for (final package in packages.where(_slow.contains))
        for (var shard = 0; shard < shards; shard++)
          _Run('in $package (shard ${shard + 1}/$shards)', package, [
            '--total-shards=$shards',
            '--shard-index=$shard',
          ], failure: '$package (from its directory)'),
    if (packageRun)
      for (final package in packages.where((p) => !_slow.contains(p)))
        _Run(
          'in $package',
          package,
          const [],
          failure: '$package (from its directory)',
        ),
  ];

  final watch = Stopwatch()..start();
  await _pool(runs, concurrency: (cpus / 2).ceil().clamp(2, 8));

  final failed = [
    for (final run in runs)
      if (!run.passed) run,
  ];
  for (final run in failed) {
    stderr
      ..writeln('\n=== FAILED: dart test ${run.title} ===')
      ..write(run.output);
  }
  final seconds = (watch.elapsedMilliseconds / 1000).toStringAsFixed(0);
  if (failed.isEmpty) {
    stdout.writeln(
      '\nAll tests passed in ${packages.length} packages (${seconds}s).',
    );
    return;
  }
  final names = {for (final run in failed) run.failure};
  stderr.writeln('\nFailed: ${names.join(', ')}');
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

/// One `dart test` process: its directory, arguments and outcome.
final class _Run {
  _Run(this.title, this.directory, this.args, {required this.failure});

  final String title;
  final String directory;
  final List<String> args;

  /// How a failure is named in the summary.
  final String failure;

  bool passed = false;
  String output = '';

  Future<void> start() async {
    final watch = Stopwatch()..start();
    final process = await Process.start(Platform.resolvedExecutable, [
      'test',
      ...args,
    ], workingDirectory: directory);
    final out = StringBuffer();
    await Future.wait([
      process.stdout.transform(utf8.decoder).forEach(out.write),
      process.stderr.transform(utf8.decoder).forEach(out.write),
    ]);
    passed = await process.exitCode == 0;
    output = out.toString();
    final seconds = (watch.elapsedMilliseconds / 1000).toStringAsFixed(0);
    stdout.writeln(
      '${passed ? 'ok  ' : 'FAIL'} dart test $title '
      '(${_summary(output)}, ${seconds}s)',
    );
  }

  // The last "+N -M" counter of the test runner's output.
  static String _summary(String output) {
    final counts = RegExp(r'\+(\d+)(?: ~\d+)?(?: -(\d+))?:').allMatches(output);
    if (counts.isEmpty) return 'no tests run';
    final last = counts.last;
    final failed = last.group(2);
    return failed == null
        ? '${last.group(1)} passed'
        : '${last.group(1)} passed, $failed failed';
  }
}

/// Runs [runs] with at most [concurrency] at a time.
Future<void> _pool(List<_Run> runs, {required int concurrency}) async {
  final queue = [...runs];
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      await queue.removeAt(0).start();
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
}
