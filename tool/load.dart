// Load tests: how many requests a second a server built on the framework
// sustains, and where it stops answering. The server is the bench
// application (tool/load_bench), one endpoint per scenario; the load comes
// from oha (https://github.com/hatoo/oha), in steps of a rising rate with
// latencies corrected for coordinated omission. docs/load-testing.md
//
//   dart run tool/load.dart                          # every sweep scenario
//   dart run tool/load.dart --scenarios text,json --rates 1000,2000,4000
//   dart run tool/load.dart --start 500 --step 500 --max 4000 --duration 20s
//   dart run tool/load.dart --isolates 1,2,4 --scenarios api
//   dart run tool/load.dart --scenarios scaling,cpu,overload
//   dart run tool/load.dart --compare a/report.json b/report.json
//   dart run tool/load.dart --help
//
// It builds the bench application to a native executable (`--no-compile`:
// `dart run`), starts it on a free port, runs the scenarios and always
// stops it, also on Ctrl+C and on errors. `--out` (default build/load)
// gets report.json (every number, the machine, the commit), report.md
// (tables and charts), the server's logs and oha's raw output of each
// step; with `--isolates`, a report per number of isolates and scaling.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'load/format.dart';
import 'load/isolates.dart';
import 'load/oha.dart';
import 'load/options.dart';
import 'load/report.dart';
import 'load/runs.dart';
import 'load/session.dart';

export 'load/analysis.dart';
export 'load/checks.dart';
export 'load/isolates.dart';
export 'load/oha.dart';
export 'load/options.dart';
export 'load/report.dart';
export 'load/scenarios.dart';
export 'load/timeline.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(usage);
    return;
  }
  final LoadOptions options;
  try {
    options = LoadOptions.parse(args);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln()
      ..writeln(usage);
    exit(64);
  }
  // Report paths are the caller's: resolved before the directory changes
  // to the workspace root (this script is in tool/).
  final out = Directory(options.out).absolute;
  final compare = [for (final path in options.compare) File(path).absolute];
  Directory.current = File.fromUri(Platform.script).parent.parent;

  if (compare.isNotEmpty) {
    final markdown = renderComparison([
      for (final file in compare)
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    ]);
    stdout.write(markdown);
    if (options.outGiven) {
      out.createSync(recursive: true);
      File('${out.path}/comparison.md').writeAsStringSync(markdown);
    }
    return;
  }

  final ohaVersion = await _ohaVersion(options.oha);
  final session = LoadSession(options, out, ohaVersion);
  // Ctrl+C and SIGTERM: the server and oha never outlive the tool.
  for (final signal in [
    ProcessSignal.sigint,
    // Windows has no SIGTERM to watch.
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ]) {
    signal.watch().listen((_) {
      session.kill();
      exit(130);
    });
  }
  try {
    await _run(session);
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    await session.stop();
  }
  // The signal subscriptions would keep the process alive.
  exit(exitCode);
}

/// oha's version (`oha 1.16.0` gives `1.16.0`); stops the tool with how to
/// install it when it is missing.
Future<String> _ohaVersion(String oha) async {
  try {
    final result = await Process.run(oha, ['--version']);
    if (result.exitCode == 0) {
      return (result.stdout as String).trim().split(' ').last;
    }
  } on ProcessException {
    // Reported below.
  }
  stderr.writeln(
    'oha is not installed (no "$oha" to run): the load generator of '
    'tool/load.dart.\n$ohaInstall',
  );
  exit(69);
}

/// Everything the options ask for: the sweeps (once, or once per number
/// of isolates), then the scenarios that start a server of their own.
Future<void> _run(LoadSession session) async {
  final options = session.options;
  final out = session.out;
  await session.prepare();
  final machine = await _machine(session.ohaVersion);

  Json report(
    String label,
    DateTime started,
    List<Json> scenarios, {
    Json? isolates,
    Map<String, int>? files,
  }) => {
    'schema': 2,
    'label': label,
    'startedAt': started.toIso8601String(),
    'machine': machine,
    'options': {
      'durationSeconds': options.duration.inMilliseconds / 1000,
      'connections': options.connections,
      'rates': options.rates,
      'concurrency': options.concurrency,
      'timeoutMs': options.timeout.inMilliseconds,
      'transferTimeoutMs': options.transferTimeout.inMilliseconds,
      'keepAlive': options.keepAlive,
      'thresholds': options.thresholds.toJson(),
      'compiled': options.compile,
      'ohaThreads': options.ohaThreads,
      'serverArgs': options.serverArgs,
      'fileBytes': ?files,
      'serverRestarts': session.restarts,
    },
    'isolates': ?isolates,
    'scenarios': scenarios,
  };

  void write(Directory directory, Json report) {
    directory.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    File(
      '${directory.path}/report.json',
    ).writeAsStringSync('${encoder.convert(report)}\n');
    File('${directory.path}/report.md').writeAsStringSync(renderReport(report));
    stdout
      ..writeln()
      ..writeln('Reports: ${directory.path}/report.md and report.json');
  }

  // The sweeps on one server; [isolates] is the --isolates value, if any.
  Future<Json> sweeps(String label, {String? isolates}) async {
    final started = DateTime.now().toUtc();
    final suffix = isolates == null ? '' : '-isolates-$isolates';
    session.rawPrefix = isolates == null ? '' : 'isolates-$isolates-';
    final server = await session.start(
      arguments: [if (isolates != null) '--server.isolates.count=$isolates'],
      log: 'server$suffix',
    );
    final state = await server.isolates(timeout: const Duration(seconds: 5));
    final count = state?['count'] as int?;
    stdout
      ..writeln()
      ..writeln(
        'Bench server on ${server.baseUrl} (pid ${server.pid}), '
        '${count ?? '?'} isolates serving'
        '${isolates == null ? '' : ' (asked for $isolates)'}, '
        'oha ${session.ohaVersion}.',
      );
    // A run must not measure one isolate under the name of four.
    final wanted = int.tryParse(isolates ?? '');
    final mismatch = wanted != null && count != wanted;
    if (mismatch) {
      stderr.writeln(
        'WARNING: $isolates isolates were asked for and ${count ?? 'an '
                'unknown number'} serve: this run does not measure '
        '$isolates isolates.',
      );
    }
    final catalog = session.catalog();
    final scenarios = <Json>[
      for (final name in options.sweeps)
        await runSweep(
          session,
          catalog.firstWhere((scenario) => scenario.name == name),
        ),
    ];
    session.rawPrefix = '';
    return report(
      label,
      started,
      scenarios,
      files: server.files,
      isolates: {
        'asked': isolates,
        'count': count,
        if (mismatch) 'mismatch': true,
      },
    );
  }

  Future<List<Json>> specials() async => [
    for (final name in options.specials) await runSpecial(session, name),
  ];

  if (options.isolates.isEmpty) {
    final started = DateTime.now().toUtc();
    final swept = options.sweeps.isEmpty ? null : await sweeps(options.label);
    final others = await specials();
    write(
      out,
      swept == null
          ? report(options.label, started, others)
          : {
              ...swept,
              'scenarios': [...jsonList(swept['scenarios']), ...others],
            },
    );
    return;
  }

  final reports = <Json>[];
  for (final isolates in options.isolates) {
    final label = [
      if (options.label.isNotEmpty) options.label,
      'isolates=$isolates',
    ].join(', ');
    final swept = await sweeps(label, isolates: isolates);
    write(Directory('${out.path}/isolates-$isolates'), swept);
    reports.add(swept);
  }
  final scaling = renderScaling(reports);
  File('${out.path}/scaling.md').writeAsStringSync(scaling);
  stdout
    ..writeln()
    ..write(scaling)
    ..writeln()
    ..writeln('Scaling: ${out.path}/scaling.md');
  if (options.specials.isNotEmpty) {
    final started = DateTime.now().toUtc();
    write(out, report(options.label, started, await specials()));
  }
}

Future<Map<String, Object?>> _machine(String ohaVersion) async {
  Future<String?> output(String command, List<String> arguments) async {
    try {
      final result = await Process.run(command, arguments);
      final text = (result.stdout as String).trim();
      return result.exitCode == 0 && text.isNotEmpty ? text : null;
    } on ProcessException {
      return null;
    }
  }

  String? cpu;
  if (Platform.isMacOS) {
    cpu = await output('sysctl', ['-n', 'machdep.cpu.brand_string']);
  } else if (File('/proc/cpuinfo').existsSync()) {
    cpu = RegExp(
      r'^model name\s*:\s*(.+)$',
      multiLine: true,
    ).firstMatch(File('/proc/cpuinfo').readAsStringSync())?.group(1);
  }
  return {
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'cores': Platform.numberOfProcessors,
    'cpu': cpu,
    'dart': Platform.version.split(' ').first,
    'oha': ohaVersion,
    'gitCommit': await output('git', ['rev-parse', '--short', 'HEAD']),
    'gitDirty': await output('git', ['status', '--porcelain']) != null,
  };
}
