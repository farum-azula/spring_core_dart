// Runs the tests of every workspace package (the `workspace:` list of the
// root pubspec.yaml, example included) twice: from the package directory,
// as `dart test` is usually run, and from the workspace root, as IDEs and
// `dart test <dir>` do, so nothing may depend on the working directory.
// New packages are picked up automatically.
//
//   dart run tool/test_all.dart            # both passes
//   dart run tool/test_all.dart --packages # only from the package directories
//   dart run tool/test_all.dart --root     # only from the workspace root
//   dart run tool/test_all.dart --only a,b # only these packages (CI passes
//                                          # those tool/affected.dart lists)
//   dart run tool/test_all.dart --exclude-tags integration  # unit tests
//   dart run tool/test_all.dart --tags integration          # only those
//   dart run tool/test_all.dart --job 2/4  # the 2nd of 4 equal parts (CI
//                                          # runs each on its own machine)
//   dart run tool/test_all.dart --job 2/4 --list  # print, do not run
//   dart run tool/test_all.dart --help
//
// Tags: `integration` marks the test files that open real sockets/servers
// or start processes (`@Tags(['integration'])` at the top of the file,
// declared in dart_test.yaml). With `--tags <tag>` only the files that
// mention the tag are loaded (not every suite of the repository just to find
// none); with either filter a run without matching tests passes.
//
// The runs go in parallel (a pool sized by the CPU count), and slow test
// suites are split into shards (`dart test --total-shards`), so the whole
// thing takes about as long as its slowest shard. With `--job i/n` the runs
// (both passes, every package, the shards) are dealt to n parts of about
// the same weight, and only part i runs. Each run prints a line when it
// starts and one when it ends, with a progress line every 30 s; the output
// of a failed run is printed in full at the end.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

// Packages whose tests take minutes (in-memory builds), split into shards.
const _slow = {'spring_core_dart_generator'};

/// How much heavier a test file of a [_slow] package weighs than another one
/// when runs are dealt to `--job` parts: the generator's 20 files take about
/// 1400 s of test time, the 170 files of the other packages about 60 s.
const _slowWeight = 100;

/// `dart test`'s exit code when no test ran (e.g. none has the tag).
const _noTestsRan = 79;

const _usage = '''
Runs the tests of every workspace package, from each package directory and
from the workspace root.

usage: dart run tool/test_all.dart [options]

  --packages            only from the package directories
  --root                only from the workspace root
  --only a,b            only these packages (directories, comma-separated)
  --tags <selector>     only tests with these tags (e.g. integration)
  --exclude-tags <sel>  no tests with these tags (e.g. integration)
  --job <i>/<n>         only part i of n parts of about the same weight
  --list                print the runs (of the part) without running them
  -h, --help            this help''';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }
  final options = _Options.parse(args);
  // The workspace root (this script is in tool/), wherever it is run from.
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final packages = [
    for (final package in workspacePackages())
      if (Directory('$package/test').existsSync()) package,
  ];
  if (options.only case final wanted?) {
    packages.retainWhere(wanted.contains);
  }
  // With `--tags <tag>`: only the files that mention the tag.
  final files = <String, List<String>>{
    for (final package in packages)
      package: options.tagFiles == null
          ? const ['test']
          : _filesMentioning(package, options.tagFiles!),
  };
  packages.retainWhere((package) => files[package]!.isNotEmpty);
  if (packages.isEmpty) {
    stdout.writeln('No package to test.');
    return;
  }
  stdout.writeln('Packages with tests: ${packages.join(', ')}');

  final cpus = Platform.numberOfProcessors;
  // Spread over the parts too: a slow package must not end up in one.
  final shards = math.max(cpus >= 8 ? 4 : 2, options.jobs);
  final filters = [
    if (options.tags case final tags?) '--tags=$tags',
    if (options.excludeTags case final tags?) '--exclude-tags=$tags',
  ];
  final all = <_Run>[
    for (final (pass, enabled) in [
      ('root', options.rootRun),
      ('package', options.packageRun),
    ])
      if (enabled)
        for (final package in packages)
          ..._runs(
            package,
            files[package]!,
            fromRoot: pass == 'root',
            shards: _slow.contains(package) ? shards : 1,
            filters: filters,
          ),
  ];
  final runs = _part(all, options.job, options.jobs)
    // Slow ones first, so they don't end up last in the queue.
    ..sort((a, b) => b.weight.compareTo(a.weight));
  if (options.jobs > 1) {
    stdout.writeln(
      'Part ${options.job + 1}/${options.jobs}: ${runs.length} of '
      '${all.length} runs.',
    );
  }
  if (runs.isEmpty) {
    stdout.writeln('Nothing to run in this part.');
    return;
  }
  if (args.contains('--list')) {
    for (final run in runs) {
      stdout.writeln(
        '${run.weight.toStringAsFixed(1).padLeft(6)}  ${run.directory}\$ '
        'dart test ${run.args.join(' ')}',
      );
    }
    return;
  }

  final watch = Stopwatch()..start();
  // A progress line every 30 s: the first runs to finish are the slow ones.
  final progress = Timer.periodic(const Duration(seconds: 30), (_) {
    final done = runs.where((run) => run.finished).length;
    final running = [
      for (final run in runs)
        if (run.started && !run.finished) run.title,
    ];
    stdout.writeln(
      '... ${watch.elapsed.inSeconds}s: $done/${runs.length} done, '
      'running: ${running.join(', ')}',
    );
  });
  await _pool(runs, concurrency: (cpus / 2).ceil().clamp(2, 8));
  progress.cancel();

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

/// The runs of one [package]: its [files] (relative to the package),
/// from its directory or [fromRoot], in [shards].
List<_Run> _runs(
  String package,
  List<String> files, {
  required bool fromRoot,
  required int shards,
  required List<String> filters,
}) {
  final where = fromRoot ? 'from the root' : 'in';
  final weight =
      _testFiles(package, files).length *
      (_slow.contains(package) ? _slowWeight : 1) /
      shards;
  return [
    for (var shard = 0; shard < shards; shard++)
      _Run(
        shards == 1
            ? '$where $package'
            : '$where $package (shard ${shard + 1}/$shards)',
        fromRoot ? '.' : package,
        [
          for (final file in files) fromRoot ? '$package/$file' : file,
          if (shards > 1) ...['--total-shards=$shards', '--shard-index=$shard'],
          ...filters,
        ],
        failure: fromRoot
            ? '$package (from the workspace root)'
            : '$package (from its directory)',
        weight: weight,
        // A shard or a tag filter may leave nothing to run.
        noTestsPass: shards > 1 || filters.isNotEmpty,
      ),
  ];
}

/// Part [job] (from 0) of [all] dealt to [jobs] parts: the heaviest run
/// first, each to the lightest part so far. The same for every part, so
/// the parts together run everything once.
List<_Run> _part(List<_Run> all, int job, int jobs) {
  if (jobs == 1) return [...all];
  final load = List.filled(jobs, 0.0);
  final part = <_Run>[];
  final order = [...all]
    ..sort((a, b) {
      final byWeight = b.weight.compareTo(a.weight);
      return byWeight != 0 ? byWeight : a.title.compareTo(b.title);
    });
  for (final run in order) {
    var lightest = 0;
    for (var i = 1; i < jobs; i++) {
      if (load[i] < load[lightest]) lightest = i;
    }
    load[lightest] += run.weight;
    if (lightest == job) part.add(run);
  }
  return part;
}

/// The test files under [paths] of [package] (`test` or single files).
List<String> _testFiles(String package, List<String> paths) {
  final files = <String>[];
  for (final path in paths) {
    final directory = Directory('$package/$path');
    if (directory.existsSync()) {
      files.addAll([
        for (final entity in directory.listSync(recursive: true))
          if (entity is File && entity.path.endsWith('_test.dart')) entity.path,
      ]);
    } else if (File('$package/$path').existsSync()) {
      files.add('$package/$path');
    }
  }
  return files;
}

/// The test files of [package] (relative to it) that mention [tag] in
/// quotes (`@Tags(['integration'])`, `tags: 'integration'`).
List<String> _filesMentioning(String package, String tag) {
  final mention = RegExp('[\'"]${RegExp.escape(tag)}[\'"]');
  return [
    for (final path in _testFiles(package, const ['test']))
      if (mention.hasMatch(File(path).readAsStringSync()))
        path.substring(package.length + 1).replaceAll(r'\', '/'),
  ]..sort();
}

/// The command line of test_all.
final class _Options {
  _Options({
    required this.packageRun,
    required this.rootRun,
    required this.only,
    required this.tags,
    required this.excludeTags,
    required this.job,
    required this.jobs,
  });

  factory _Options.parse(List<String> args) {
    String? value(String name) {
      for (var i = 0; i < args.length; i++) {
        if (args[i] == name) {
          if (i + 1 >= args.length) _fail('$name needs a value.');
          return args[i + 1];
        }
        if (args[i].startsWith('$name=')) {
          return args[i].substring(name.length + 1);
        }
      }
      return null;
    }

    const flags = {'--packages', '--root', '--list'};
    const valued = {'--only', '--tags', '--exclude-tags', '--job'};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (flags.contains(arg)) continue;
      if (valued.contains(arg)) {
        i++;
        continue;
      }
      if (valued.any((name) => arg.startsWith('$name='))) continue;
      _fail('Unknown argument: $arg');
    }

    final only = value('--only');
    final job = value('--job');
    var (index, total) = (0, 1);
    if (job != null) {
      final match = RegExp(r'^(\d+)/(\d+)$').firstMatch(job);
      index = int.tryParse(match?.group(1) ?? '') ?? 0;
      total = int.tryParse(match?.group(2) ?? '') ?? 0;
      if (total < 1 || index < 1 || index > total) {
        _fail('--job takes <i>/<n> with 1 <= i <= n, e.g. 2/4; not $job.');
      }
      index--;
    }
    return _Options(
      packageRun: !args.contains('--root'),
      rootRun: !args.contains('--packages'),
      only: only == null
          ? null
          : {
              for (final name in only.split(','))
                if (name.trim().isNotEmpty) name.trim(),
            },
      tags: value('--tags'),
      excludeTags: value('--exclude-tags'),
      job: index,
      jobs: total,
    );
  }

  final bool packageRun;
  final bool rootRun;
  final Set<String>? only;
  final String? tags;
  final String? excludeTags;

  /// This part (from 0) and the number of parts (`--job`).
  final int job;
  final int jobs;

  /// The tag whose files alone are loaded: `--tags` naming one tag (not an
  /// expression such as `a || b`).
  String? get tagFiles =>
      tags != null && RegExp(r'^[\w-]+$').hasMatch(tags!) ? tags : null;

  static Never _fail(String message) {
    stderr
      ..writeln(message)
      ..writeln()
      ..writeln(_usage);
    exit(64);
  }
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
  _Run(
    this.title,
    this.directory,
    this.args, {
    required this.failure,
    required this.weight,
    required this.noTestsPass,
  });

  final String title;
  final String directory;
  final List<String> args;

  /// How a failure is named in the summary.
  final String failure;

  /// About how long it takes, relative to the other runs (`--job`).
  final double weight;

  /// Whether "no tests ran" passes (a shard, a tag filter).
  final bool noTestsPass;

  bool passed = false;
  bool started = false;
  bool finished = false;
  String output = '';

  Future<void> start() async {
    started = true;
    stdout.writeln('run  dart test $title');
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
    final code = await process.exitCode;
    passed = code == 0 || (code == _noTestsRan && noTestsPass);
    finished = true;
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
