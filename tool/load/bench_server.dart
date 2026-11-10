// The bench server of tool/load.dart (tool/load_bench): built, started on
// a free port, watched (memory and processor time, from `ps`) and stopped.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'analysis.dart';

/// Where the bench application is, from the workspace root.
const benchPackage = 'tool/load_bench';

/// The answer of the bench server's `GET /bench/info`.
typedef BenchInfo = ({
  bool ready,
  int pid,
  Map<String, int> files,
  String token,
});

/// A running bench server.
final class BenchServer {
  BenchServer._(
    this._process,
    this.port,
    this.pid,
    this.files,
    this.token,
    this.log,
  );

  final Process _process;

  /// The port it listens on, on 127.0.0.1.
  final int port;

  /// The process that serves: the one `ps` is asked about. With `dart run`
  /// it is the VM, a child of the process this tool started.
  final int pid;

  /// The size of each file it serves under `/files/`, in bytes.
  final Map<String, int> files;

  /// The bearer token it accepts on `/secure/**`.
  final String token;

  /// Where its output goes.
  final File log;

  var _exited = false;

  /// `http://127.0.0.1:<port>`.
  String get baseUrl => 'http://127.0.0.1:$port';

  /// Whether the process still runs.
  bool get running => !_exited;

  /// Builds the bench application into [output] with `dart build cli` and
  /// returns the executable.
  ///
  /// Not `dart compile exe`: the SQLite driver brings a native library
  /// with a build hook, which only `dart build` runs. The result is the
  /// same ahead-of-time code, in a `bundle/` with the library beside it.
  static Future<String> build(String output) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'build',
      'cli',
      '--target',
      'bin/main.dart',
      '--output',
      output,
    ], workingDirectory: benchPackage);
    final executable = '$output/bundle/bin/main';
    if (result.exitCode != 0 || !File(executable).existsSync()) {
      throw ProcessException(
        'dart',
        ['build', 'cli'],
        'The bench application did not build:\n'
            '${result.stdout}${result.stderr}',
        result.exitCode,
      );
    }
    return executable;
  }

  /// Starts the server on a free port and waits until it is ready: it
  /// answers and its files exist.
  ///
  /// [executable] is what [build] returned; without it the application
  /// runs with `dart run` (JIT). [arguments] are its `--key=value`
  /// properties; its output goes to [log].
  static Future<BenchServer> start({
    required List<String> arguments,
    required File log,
    String? executable,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final port = await _freePort();
    final all = ['--server.port=$port', ...arguments];
    final process = executable != null
        ? await Process.start(executable, all)
        : await Process.start(Platform.resolvedExecutable, [
            'run',
            'bin/main.dart',
            ...all,
          ], workingDirectory: benchPackage);
    final sink = log.openWrite();
    final piped = Future.wait([
      process.stdout.forEach(sink.add),
      process.stderr.forEach(sink.add),
    ]);
    int? exitCode;
    final exited = process.exitCode.then((code) async {
      exitCode = code;
      await piped;
      await sink.close();
    });

    final watch = Stopwatch()..start();
    while (watch.elapsed < timeout) {
      if (exitCode != null) {
        await exited;
        throw StateError(
          'The bench server stopped at startup (exit code $exitCode):\n'
          '${log.readAsStringSync()}',
        );
      }
      final info = await _info(port);
      if (info != null && info.ready) {
        final server = BenchServer._(
          process,
          port,
          info.pid,
          info.files,
          info.token,
          log,
        );
        unawaited(exited.then((_) => server._exited = true));
        return server;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    process.kill(ProcessSignal.sigkill);
    throw StateError(
      'The bench server was not ready after ${timeout.inSeconds} s; its '
      'output is in ${log.path}.',
    );
  }

  /// Asks `GET /bench/info`; `null` when the server does not answer within
  /// [timeout].
  Future<BenchInfo?> info({
    Duration timeout = const Duration(seconds: 2),
  }) => _info(port, timeout: timeout);

  /// The pool of isolates (the bench server's `GET /bench/isolates`): how
  /// many serve and the load of each, whichever isolate answers; `null`
  /// when the server does not say within [timeout].
  Future<Map<String, Object?>?> isolates({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < timeout && running) {
      final answer = await _request(
        'GET',
        '/bench/isolates',
        timeout: timeout - watch.elapsed,
      );
      if (answer != null && answer.status == 200) {
        final state = jsonDecode(answer.body) as Map<String, Object?>;
        if (state['count'] != null) {
          return state;
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    return null;
  }

  /// Asks the server for [count] isolates (`POST /bench/isolates?to=`)
  /// and completes with the pool's size once it has them, or `null` when
  /// the first isolate did not answer within [timeout].
  ///
  /// Only the first isolate takes the call (another one answers 421), and
  /// a connection goes to whichever isolate takes it: the call is made
  /// again on a new connection until the first isolate has it.
  ///
  /// Throws a [StateError] with the server's words when it refuses (409:
  /// it has no pool).
  Future<int?> scaleTo(
    int count, {
    Duration timeout = const Duration(minutes: 1),
  }) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < timeout && running) {
      final answer = await _request(
        'POST',
        '/bench/isolates?to=$count',
        timeout: timeout - watch.elapsed,
      );
      switch (answer?.status) {
        case 200:
          return (jsonDecode(answer!.body) as Map)['count'] as int?;
        case 409:
          throw StateError('The server cannot scale: ${answer!.body}');
        default:
          // 421: an isolate that is not the first; or too busy to answer.
          await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    return null;
  }

  /// The body of the answer to `GET` [path], on a new connection; `null`
  /// without a 200 in [timeout].
  Future<String?> get(
    String path, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final answer = await _request('GET', path, timeout: timeout);
    return answer?.status == 200 ? answer!.body : null;
  }

  /// Sends one `GET` [path] on a new connection and returns the status
  /// and the headers named in [headers]; `null` without an answer in
  /// [timeout].
  Future<({int status, Map<String, String?> headers})?> head(
    String path, {
    List<String> headers = const [],
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final answer = await _request(
      'GET',
      path,
      timeout: timeout,
      headers: headers,
    );
    return answer == null
        ? null
        : (status: answer.status, headers: answer.headers);
  }

  Future<({int status, String body, Map<String, String?> headers})?> _request(
    String method,
    String path, {
    required Duration timeout,
    List<String> headers = const [],
  }) async {
    if (timeout <= Duration.zero) {
      return null;
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .openUrl(method, Uri.parse('$baseUrl$path'))
          .timeout(timeout);
      request.persistentConnection = false;
      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response).timeout(timeout);
      return (
        status: response.statusCode,
        body: body,
        headers: {
          for (final name in headers) name: response.headers.value(name),
        },
      );
    } on Object {
      // Too busy to answer in time, or gone.
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Stops the server: SIGTERM (its shutdown hook closes the context),
  /// then SIGKILL when it is still there after [grace].
  Future<void> stop({Duration grace = const Duration(seconds: 5)}) async {
    if (_exited) {
      return;
    }
    _signal(ProcessSignal.sigterm);
    final watch = Stopwatch()..start();
    while (!_exited && watch.elapsed < grace) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!_exited) {
      _signal(ProcessSignal.sigkill);
      await _process.exitCode;
    }
  }

  /// Kills the server at once, without waiting: for a signal handler.
  void kill() => _signal(ProcessSignal.sigkill);

  void _signal(ProcessSignal signal) {
    _process.kill(signal);
    if (pid != _process.pid) {
      Process.killPid(pid, signal);
    }
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<BenchInfo?> _info(
    int port, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/bench/info'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response).timeout(timeout);
      if (response.statusCode != 200) {
        return null;
      }
      final json = jsonDecode(body) as Map<String, Object?>;
      return (
        ready: json['ready'] == true,
        pid: json['pid']! as int,
        files: (json['files']! as Map).cast<String, int>(),
        token: json['token']! as String,
      );
    } on Object {
      // Not listening yet, too busy to answer, or gone.
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// Reads a process's resident memory while a step runs.
final class MemorySampler {
  /// Samples the process [pid] every [interval] once [start] is called.
  MemorySampler(this.pid, {this.interval = const Duration(milliseconds: 250)});

  /// The process.
  final int pid;

  /// The time between two samples.
  final Duration interval;

  final _samples = <int>[];
  Timer? _timer;
  var _reading = false;

  /// Takes the first sample and starts the timer.
  Future<void> start() async {
    await _sample();
    _timer = Timer.periodic(interval, (_) => unawaited(_sample()));
  }

  /// Takes the last sample and returns the first, the highest and the
  /// last; `null` when `ps` never answered (the process is gone).
  Future<Memory?> stop() async {
    _timer?.cancel();
    await _sample();
    return _samples.isEmpty
        ? null
        : (
            start: _samples.first,
            peak: _samples.reduce(math.max),
            end: _samples.last,
          );
  }

  Future<void> _sample() async {
    if (_reading) {
      return;
    }
    _reading = true;
    try {
      final bytes = await residentMemory(pid);
      if (bytes != null) {
        _samples.add(bytes);
      }
    } finally {
      _reading = false;
    }
  }
}

/// The resident memory of the process [pid] in bytes (`ps -o rss=`, which
/// prints kilobytes); `null` when there is no such process.
Future<int?> residentMemory(int pid) async {
  final kilobytes = int.tryParse(await _ps(pid, 'rss='));
  return kilobytes == null ? null : kilobytes * 1024;
}

/// The processor time the process [pid] has used, in seconds (`ps -o
/// time=`): every thread and isolate together.
Future<double?> processorTime(int pid) async =>
    parseCpuTime(await _ps(pid, 'time='));

Future<String> _ps(int pid, String column) async {
  try {
    final result = await Process.run('ps', ['-o', column, '-p', '$pid']);
    return result.exitCode == 0 ? (result.stdout as String).trim() : '';
  } on ProcessException {
    return '';
  }
}
