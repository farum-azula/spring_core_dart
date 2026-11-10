// What tool/load.dart asks of oha (https://github.com/hatoo/oha, 1.16) and
// what it reads back: the command line of a step and the JSON oha prints
// with `--output-format json`. Nothing here starts a process.
import 'dart:convert';

import 'scenarios.dart';

/// How to install oha, for the message when it is missing.
const ohaInstall =
    'Install it with `brew install oha` (macOS), `cargo install oha '
    '--locked` (any system with Rust) or from a release binary: '
    'https://github.com/hatoo/oha#installation';

/// The error oha counts for a request still running when the step's time
/// is up: not a failure of the server, so never counted as one.
const abortedAtDeadline = 'aborted due to deadline';

/// The median and the 99th percentile of a part of the answers.
typedef LatencySplit = ({Duration? p50, Duration? p99});

/// What oha measured in one run (its JSON output).
final class OhaResult {
  /// A result with the numbers read from oha's JSON.
  const OhaResult({
    required this.seconds,
    required this.statusCodes,
    required this.errors,
    required this.bytes,
    required this.p50,
    required this.p95,
    required this.p99,
    required this.max,
    this.successful,
    this.notSuccessful,
  });

  /// Reads the JSON oha prints with `--output-format json`.
  ///
  /// The latencies are `null` there when no request was answered (every
  /// connection refused, every request timed out).
  factory OhaResult.parse(String json) {
    final root = jsonDecode(json) as Map<String, Object?>;
    final summary = root['summary']! as Map<String, Object?>;
    final percentiles =
        (root['latencyPercentiles'] as Map<String, Object?>?) ?? const {};
    Duration? latency(Object? seconds) => seconds is num
        ? Duration(microseconds: (seconds * 1000000).round())
        : null;
    LatencySplit? split(Object? map) => map is Map
        ? (p50: latency(map['p50']), p99: latency(map['p99']))
        : null;
    Map<String, int> counts(Object? map) => {
      for (final MapEntry(:key, :value)
          in ((map as Map<String, Object?>?) ?? const {}).entries)
        key: (value! as num).toInt(),
    };
    return OhaResult(
      seconds: (summary['total']! as num).toDouble(),
      statusCodes: {
        for (final MapEntry(:key, :value) in counts(
          root['statusCodeDistribution'],
        ).entries)
          int.parse(key): value,
      },
      errors: counts(root['errorDistribution']),
      bytes: (summary['totalData'] as num?)?.toInt() ?? 0,
      p50: latency(percentiles['p50']),
      p95: latency(percentiles['p95']),
      p99: latency(percentiles['p99']),
      max: latency(summary['slowest']),
      successful: split(root['latencyPercentilesSuccessful']),
      notSuccessful: split(root['latencyPercentilesNotSuccessful']),
    );
  }

  /// How long the run took, in seconds.
  final double seconds;

  /// How many responses had each status code.
  final Map<int, int> statusCodes;

  /// How many requests ended with each error instead of a response, by
  /// oha's message (`timeout`, `Connection refused (os error 61)`,
  /// [abortedAtDeadline]...).
  final Map<String, int> errors;

  /// The bytes of the response bodies.
  final int bytes;

  /// The latency of the answered requests: the median, the 95th and 99th
  /// percentiles and the slowest. With `--latency-correction` a request's
  /// time starts when it was due, not when it was sent.
  final Duration? p50;

  /// See [p50].
  final Duration? p95;

  /// See [p50].
  final Duration? p99;

  /// See [p50].
  final Duration? max;

  /// The latency of the 2xx answers alone, and of the others, when oha
  /// was asked for them (`--stats-success-breakdown`): what tells a fast
  /// refusal (503) from a slow answer.
  final LatencySplit? successful;

  /// See [successful].
  final LatencySplit? notSuccessful;

  /// The requests that got a response, whatever its status.
  int get responses => statusCodes.values.fold(0, (sum, count) => sum + count);
}

/// The arguments of oha for one step of [scenario] against the server at
/// [baseUrl].
///
/// A rate step ([rate] requests a second for [duration]) is sent with
/// `--latency-correction`, so a server that falls behind is charged the
/// wait of the requests it delayed. A transfer step (no [rate]) sends as
/// fast as its [connections] allow and lets the transfers under way at the
/// end finish (`-w`), as a cut transfer says nothing about the server.
List<String> ohaArguments(
  Scenario scenario, {
  required String baseUrl,
  required Duration duration,
  required int connections,
  required Duration timeout,
  int? rate,
  int? workerThreads,
  bool keepAlive = true,
  bool successBreakdown = false,
}) => [
  '--no-tui',
  '--output-format',
  'json',
  '-z',
  '${duration.inMilliseconds}ms',
  '-c',
  '$connections',
  '-t',
  '${timeout.inMilliseconds}ms',
  if (rate != null) ...['-q', '$rate', '--latency-correction'] else '-w',
  if (workerThreads != null) ...['--worker-threads', '$workerThreads'],
  if (!keepAlive) '--disable-keepalive',
  if (successBreakdown) '--stats-success-breakdown',
  // The server's bytes as they are: no gzip asked for.
  '--disable-compression',
  '-m',
  scenario.method,
  for (final MapEntry(:key, :value) in scenario.headers.entries) ...[
    '-H',
    '$key: $value',
  ],
  if (scenario.contentType case final type?) ...['-T', type],
  if (scenario.bodyFile case final file?) ...['-D', file],
  if (scenario.bodyLinesFile case final file?) ...['-Z', file],
  if (scenario.formFile case final file?) ...['-F', 'file=@$file'],
  if (scenario.randomPath) '--rand-regex-url',
  '$baseUrl${scenario.path}',
];
