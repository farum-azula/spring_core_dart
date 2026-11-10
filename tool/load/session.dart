// What a run of tool/load.dart holds on to: the bench server it started
// and the oha processes loading it, so that both are always stopped.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'analysis.dart';
import 'bench_server.dart';
import 'oha.dart';
import 'options.dart';
import 'scenarios.dart';

/// One run of the tool: its options, where it writes, its processes.
final class LoadSession {
  /// A session writing into [out], loading with oha [ohaVersion].
  LoadSession(this.options, this.out, this.ohaVersion);

  /// The options of the command line.
  final LoadOptions options;

  /// Where the reports go.
  final Directory out;

  /// oha's version, for the reports.
  final String ohaVersion;

  // The build and the generated files, kept between runs.
  final Directory _work = Directory('build/load_bench').absolute;
  final _ohas = <Process>{};
  String? _executable;

  /// The server running now; `null` between two.
  BenchServer? server;

  /// How often a server was started again because the one before died.
  int restarts = 0;

  /// Put before the names of oha's raw outputs, to tell the runs of an
  /// isolates matrix apart.
  String rawPrefix = '';

  /// Where the server generates its files (`bench.directory`).
  String get data => '${_work.path}/data';

  /// Makes the directories and, unless `--no-compile`, builds the server.
  Future<void> prepare() async {
    out.createSync(recursive: true);
    Directory('${out.path}/raw').createSync(recursive: true);
    Directory(data).createSync(recursive: true);
    if (options.compile) {
      stdout.writeln('Building the bench server (dart build cli)...');
      _executable = await BenchServer.build('${_work.path}/cli');
    }
  }

  /// Stops the server that runs and starts a new one with [arguments]
  /// after the bench's own and the command line's `--server-arg`s. Its
  /// output goes to `<out>/<log>.log`.
  ///
  /// The database is new every time: `db-write` always starts from the
  /// 1000 rows of the migration.
  Future<BenchServer> start({
    List<String> arguments = const [],
    String log = 'server',
  }) async {
    await server?.stop();
    _arguments = arguments;
    _log = log;
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$data/load_bench.db$suffix');
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    return server = await BenchServer.start(
      executable: _executable,
      log: File('${out.path}/$log.log'),
      arguments: [
        '--bench.directory=$data',
        '--bench.files.medium-size=${options.mediumSize}',
        '--bench.files.huge-size=${options.hugeSize}',
        ...options.serverArgs,
        ...arguments,
      ],
    );
  }

  List<String> _arguments = const [];
  String _log = 'server';

  /// Starts the server again as it was started last, after it died; its
  /// output goes to a log of its own.
  Future<BenchServer> restart() {
    restarts++;
    final first = _log.replaceFirst(RegExp(r'-restart-\d+$'), '');
    return start(arguments: _arguments, log: '$first-restart-$restarts');
  }

  /// The scenarios of the sweeps, for the server that runs.
  List<Scenario> catalog() {
    final jsonBodies = File('${out.path}/raw/json-post.bodies')
      ..writeAsStringSync('${jsonPostBodies.join('\n')}\n');
    final dbBody = File('${out.path}/raw/db-write.body')
      ..writeAsStringSync(dbWriteBody);
    return scenarios(
      files: data,
      sizes: server!.files,
      token: server!.token,
      jsonBodies: jsonBodies.path,
      dbBody: dbBody.path,
    );
  }

  /// Runs oha once for [scenario] against the server and reads its
  /// result; its JSON is kept as `raw/<raw>.json` when [raw] is given.
  /// Without a [rate] it sends as fast as [connections] allow.
  Future<OhaResult> oha(
    Scenario scenario, {
    required Duration duration,
    required int connections,
    int? rate,
    String? raw,
    Duration? timeout,
    bool successBreakdown = false,
  }) async {
    final process = await Process.start(
      options.oha,
      ohaArguments(
        scenario,
        baseUrl: server!.baseUrl,
        duration: duration,
        connections: connections,
        rate: rate,
        timeout:
            timeout ??
            (scenario.kind == ScenarioKind.rate
                ? options.timeout
                : options.transferTimeout),
        workerThreads: options.ohaThreads,
        keepAlive: options.keepAlive,
        successBreakdown: successBreakdown,
      ),
    );
    _ohas.add(process);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    _ohas.remove(process);
    final json = await output;
    if (code != 0 || json.trim().isEmpty) {
      throw StateError(
        'oha failed on ${scenario.name} (exit code $code):\n${await errors}',
      );
    }
    if (raw != null) {
      File('${out.path}/raw/$rawPrefix$raw.json').writeAsStringSync(json);
    }
    return OhaResult.parse(json);
  }

  /// How long [recovery] waits for an answer.
  static const recoveryTimeout = Duration(seconds: 15);

  /// After a step that broke the server: asks `GET /bench/info` until it
  /// answers, for at most [recoveryTimeout].
  Future<Recovery> recovery() async {
    final running = server!;
    final watch = Stopwatch()..start();
    while (watch.elapsed < recoveryTimeout && running.running) {
      if (await running.info() != null) {
        return (recovered: true, after: watch.elapsed);
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return (recovered: false, after: null);
  }

  /// Stops oha and the server, waiting for the server.
  Future<void> stop() async {
    for (final process in _ohas.toList()) {
      process.kill();
    }
    await server?.stop();
    server = null;
  }

  /// Stops oha and the server at once (a signal handler cannot wait).
  void kill() {
    for (final process in _ohas) {
      process.kill(ProcessSignal.sigkill);
    }
    server?.kill();
  }
}
