// What tool/load.dart concludes from oha's numbers: whether a step was
// sustained or broke the server, and from the steps of a scenario its
// highest sustainable rate and its breaking point. Pure functions, tested
// in tool/test/load_test.dart.
import 'dart:math' as math;

import 'oha.dart';
import 'scenarios.dart';

/// The limits a step is judged by.
final class Thresholds {
  /// The defaults of tool/load.dart: a step is sustained with a p99 of at
  /// most 100 ms and less than 0.1 % of errors, and broken with a p99
  /// above 1 s.
  const Thresholds({
    this.p99 = const Duration(milliseconds: 100),
    this.breakP99 = const Duration(seconds: 1),
    this.errorRate = 0.001,
  });

  /// The highest p99 latency of a sustained step (`--p99`).
  final Duration p99;

  /// A step with a p99 latency above it broke the server (`--break-p99`).
  final Duration breakP99;

  /// A sustained step has a smaller share of errors (`--max-errors`).
  final double errorRate;

  /// For report.json.
  Map<String, Object?> toJson() => {
    'p99Ms': p99.inMicroseconds / 1000,
    'breakP99Ms': breakP99.inMicroseconds / 1000,
    'errorRate': errorRate,
  };
}

/// The server's memory during a step, from `ps`, in bytes.
typedef Memory = ({int start, int peak, int end});

/// One step of a scenario: the load asked for and what came back.
final class StepResult {
  /// A step with its numbers; [StepResult.of] works them out from oha's.
  const StepResult({
    required this.seconds,
    required this.requests,
    required this.ok,
    required this.statusCodes,
    required this.errors,
    required this.timeouts,
    required this.refused,
    required this.connectionErrors,
    required this.unexpected,
    required this.aborted,
    required this.megabytes,
    required this.sustained,
    required this.broken,
    this.rate,
    this.concurrency,
    this.p50,
    this.p95,
    this.p99,
    this.max,
    this.memory,
    this.cpuSeconds,
  });

  /// Judges what oha measured for one step of [scenario] by [thresholds].
  ///
  /// [rate] is the request rate asked for (a rate step), [concurrency] the
  /// connections used. Requests cut when the step's time was up
  /// ([abortedAtDeadline]) are neither answers nor errors.
  factory StepResult.of(
    OhaResult oha,
    Scenario scenario, {
    required Thresholds thresholds,
    required int concurrency,
    int? rate,
    Memory? memory,
    double? cpuSeconds,
  }) {
    var timeouts = 0;
    var refused = 0;
    var connectionErrors = 0;
    var aborted = 0;
    for (final MapEntry(key: message, value: count) in oha.errors.entries) {
      final text = message.toLowerCase();
      if (message == abortedAtDeadline) {
        aborted += count;
      } else if (text.contains('timeout') || text.contains('timed out')) {
        timeouts += count;
      } else if (text.contains('refused')) {
        refused += count;
      } else {
        connectionErrors += count;
      }
    }
    var ok = 0;
    var unexpected = 0;
    for (final MapEntry(key: status, value: count) in oha.statusCodes.entries) {
      if (scenario.expected.contains(status)) {
        ok += count;
      } else {
        unexpected += count;
      }
    }
    final failed = timeouts + refused + connectionErrors + unexpected;
    final requests = ok + failed;
    final errorRate = requests == 0 ? 1.0 : failed / requests;
    final p99 = oha.p99;
    final rateStep = scenario.kind == ScenarioKind.rate;

    // A transfer takes as long as its bytes: only errors judge it.
    final broken = [
      if (timeouts > 0) 'timeouts',
      if (refused > 0) 'refused connections',
      if (connectionErrors > 0) 'connection errors',
      if (requests == 0 || p99 == null)
        'no answer'
      else if (rateStep && p99 > thresholds.breakP99)
        'p99 above ${formatDuration(thresholds.breakP99)}',
    ];
    final sustained =
        ok > 0 &&
        errorRate < thresholds.errorRate &&
        p99 != null &&
        (!rateStep || p99 <= thresholds.p99);

    final megabytes = switch (scenario.uploadBytes) {
      final bytes? => ok * bytes / _megabyte,
      null => oha.bytes / _megabyte,
    };
    return StepResult(
      rate: rate,
      concurrency: concurrency,
      seconds: oha.seconds,
      requests: requests,
      ok: ok,
      statusCodes: oha.statusCodes,
      errors: oha.errors,
      timeouts: timeouts,
      refused: refused,
      connectionErrors: connectionErrors,
      unexpected: unexpected,
      aborted: aborted,
      megabytes: megabytes,
      p50: oha.p50,
      p95: oha.p95,
      p99: p99,
      max: oha.max,
      memory: memory,
      cpuSeconds: cpuSeconds,
      sustained: sustained,
      broken: broken,
    );
  }

  static const int _megabyte = 1024 * 1024;

  /// The requests a second asked for; `null` for a transfer step.
  final int? rate;

  /// The connections oha used.
  final int? concurrency;

  /// How long the step took.
  final double seconds;

  /// The requests that ended: answered, or failed (those cut at the end
  /// of the step are left out).
  final int requests;

  /// The answers with a status the scenario expects.
  final int ok;

  /// The answers by status code.
  final Map<int, int> statusCodes;

  /// oha's errors by message, as it reports them.
  final Map<String, int> errors;

  /// Requests the server did not answer in time.
  final int timeouts;

  /// Connections the server refused.
  final int refused;

  /// Other failures of a connection (reset, closed before the answer).
  final int connectionErrors;

  /// Answers with a status the scenario does not expect (a 500, a 503).
  final int unexpected;

  /// Requests cut when the step's time was up.
  final int aborted;

  /// The megabytes of the bodies moved: downloaded, or uploaded and
  /// answered well.
  final double megabytes;

  /// The latency of the answered requests.
  final Duration? p50;

  /// See [p50].
  final Duration? p95;

  /// See [p50].
  final Duration? p99;

  /// See [p50].
  final Duration? max;

  /// The server's resident memory at the start of the step, at its
  /// highest and at the end.
  final Memory? memory;

  /// The processor time the server used during the step, in seconds.
  final double? cpuSeconds;

  /// Whether the server kept up: a p99 within the threshold (rate steps)
  /// and errors under the limit.
  final bool sustained;

  /// Why the step broke the server; empty when it did not.
  final List<String> broken;

  /// The good answers a second.
  double get qps => seconds == 0 ? 0 : ok / seconds;

  /// The megabytes a second.
  double get megabytesPerSecond => seconds == 0 ? 0 : megabytes / seconds;

  /// The share of requests that failed, from 0 to 1.
  double get errorRate => requests == 0 ? 1 : (requests - ok) / requests;

  /// The processor cores the server kept busy: 1 is one core all the
  /// time.
  double? get cores =>
      cpuSeconds == null || seconds == 0 ? null : cpuSeconds! / seconds;

  /// The load asked for: the rate of a rate step, else the connections.
  int get load => rate ?? concurrency ?? 0;

  /// For report.json.
  Map<String, Object?> toJson() => {
    'rate': ?rate,
    'concurrency': ?concurrency,
    'seconds': seconds,
    'requests': requests,
    'ok': ok,
    'qps': qps,
    'megabytesPerSecond': megabytesPerSecond,
    'latencyMs': {
      'p50': _milliseconds(p50),
      'p95': _milliseconds(p95),
      'p99': _milliseconds(p99),
      'max': _milliseconds(max),
    },
    'statusCodes': {
      for (final MapEntry(:key, :value) in statusCodes.entries) '$key': value,
    },
    'errors': errors,
    'timeouts': timeouts,
    'refused': refused,
    'connectionErrors': connectionErrors,
    'unexpectedStatuses': unexpected,
    'abortedAtDeadline': aborted,
    'errorRate': errorRate,
    if (memory case final memory?)
      'rssBytes': {
        'start': memory.start,
        'peak': memory.peak,
        'end': memory.end,
      },
    'cpuSeconds': ?cpuSeconds,
    'cores': ?cores,
    'sustained': sustained,
    'broken': broken,
  };

  static double? _milliseconds(Duration? duration) =>
      duration == null ? null : duration.inMicroseconds / 1000;
}

/// Whether the server answered a light request after the step that broke
/// it, and how long after.
typedef Recovery = ({bool recovered, Duration? after});

/// What the steps of a scenario say together.
final class ScenarioSummary {
  /// A summary; [ScenarioSummary.of] derives it from the steps.
  const ScenarioSummary({
    this.sustainable,
    this.breaking,
    this.peakQps,
    this.peakMegabytesPerSecond,
    this.peakMemory,
  });

  /// The highest sustainable step and the breaking point of [steps], in
  /// the order they ran (rising load).
  ///
  /// The highest sustainable step is the last sustained one before the
  /// first that was not: a sustained step after a failed one is luck, not
  /// capacity. The breaking point is the first broken step.
  factory ScenarioSummary.of(List<StepResult> steps) {
    StepResult? sustainable;
    for (final step in steps) {
      if (!step.sustained) {
        break;
      }
      sustainable = step;
    }
    final memory = [
      for (final step in steps)
        if (step.memory case final memory?) memory.peak,
    ];
    return ScenarioSummary(
      sustainable: sustainable,
      breaking: steps.where((step) => step.broken.isNotEmpty).firstOrNull,
      peakQps: steps.isEmpty
          ? null
          : steps.map((step) => step.qps).reduce(math.max),
      peakMegabytesPerSecond: steps.isEmpty
          ? null
          : steps.map((step) => step.megabytesPerSecond).reduce(math.max),
      peakMemory: memory.isEmpty ? null : memory.reduce(math.max),
    );
  }

  /// The last step the server sustained; `null` when not even the first.
  final StepResult? sustainable;

  /// The first step that broke the server; `null` when none did (raise
  /// the rates to find it).
  final StepResult? breaking;

  /// The most good answers a second of any step, the overloaded ones
  /// included: what the server puts out when it is full.
  final double? peakQps;

  /// The most megabytes a second of any step.
  final double? peakMegabytesPerSecond;

  /// The server's highest resident memory over the steps, in bytes.
  final int? peakMemory;

  /// For report.json. [recovery] is the probe after the breaking step.
  Map<String, Object?> toJson({Recovery? recovery}) => {
    'sustainableQps': sustainable?.qps,
    'sustainableRate': sustainable?.rate,
    'sustainableConcurrency': sustainable?.concurrency,
    'breakingRate': breaking?.rate,
    'breakingConcurrency': breaking?.concurrency,
    'breakingReasons': breaking?.broken ?? const <String>[],
    'recovered': recovery?.recovered,
    'recoveredAfterMs': recovery?.after?.inMilliseconds,
    'peakQps': peakQps,
    'peakMegabytesPerSecond': peakMegabytesPerSecond,
    'peakRssBytes': peakMemory,
  };
}

/// The rates of `--rates 500,1000,2000`, or those from [start] to [max]
/// in steps of [step] (`--start 500 --step 500 --max 3000`), rising.
///
/// Throws a [FormatException] for a rate that is not a positive number,
/// rates that do not rise, or a range that is not complete.
List<int> rateSteps({String? rates, int? start, int? step, int? max}) {
  if (rates != null) {
    if (start != null || step != null || max != null) {
      throw const FormatException(
        '--rates and --start/--step/--max are two ways to say the same: '
        'give one.',
      );
    }
    return positiveNumbers(rates, '--rates');
  }
  if (start == null || step == null || max == null) {
    throw const FormatException('--start, --step and --max go together.');
  }
  if (start < 1 || step < 1 || max < start) {
    throw FormatException(
      '--start $start --step $step --max $max is not a rising range.',
    );
  }
  return [for (var rate = start; rate <= max; rate += step) rate];
}

/// The rising positive numbers of a comma list given to [option]
/// (`--rates`, `--concurrency`).
List<int> positiveNumbers(String list, String option) {
  final numbers = [
    for (final text in list.split(','))
      if (text.trim().isNotEmpty) int.tryParse(text.trim()),
  ];
  if (numbers.isEmpty ||
      numbers.any((number) => number == null || number < 1)) {
    throw FormatException('$option takes positive numbers, not "$list".');
  }
  final result = numbers.cast<int>();
  for (var i = 1; i < result.length; i++) {
    if (result[i] <= result[i - 1]) {
      throw FormatException('$option must rise, not "$list".');
    }
  }
  return result;
}

/// A duration of the command line: `10s`, `500ms`, `2m`, or a number of
/// seconds.
Duration parseDuration(String text, String option) {
  final match = RegExp(r'^(\d+(?:\.\d+)?)(ms|s|m)?$').firstMatch(text.trim());
  if (match == null) {
    throw FormatException(
      '$option takes a duration such as 10s, 500ms or 2m, not "$text".',
    );
  }
  final value = double.parse(match[1]!);
  final milliseconds = switch (match[2]) {
    'ms' => value,
    'm' => value * 60000,
    _ => value * 1000,
  };
  return Duration(microseconds: (milliseconds * 1000).round());
}

/// The processor time `ps -o time=` prints, in seconds: `0:01.52` on
/// macOS, `00:00:01` on Linux, `1-02:03:04` with days. `null` when the
/// text is not one.
double? parseCpuTime(String text) {
  final match = RegExp(
    r'^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+(?:\.\d+)?)$',
  ).firstMatch(text.trim());
  if (match == null) {
    return null;
  }
  final days = int.parse(match[1] ?? '0');
  final hours = int.parse(match[2] ?? '0');
  final minutes = int.parse(match[3]!);
  final seconds = double.parse(match[4]!);
  return ((days * 24 + hours) * 60 + minutes) * 60 + seconds;
}

/// A latency for people: `0.42 ms`, `12.3 ms`, `1.74 s`.
String formatDuration(Duration? duration) {
  if (duration == null) {
    return '-';
  }
  final milliseconds = duration.inMicroseconds / 1000;
  if (milliseconds >= 1000) {
    final seconds = milliseconds / 1000;
    return '${_trim(seconds.toStringAsFixed(2))} s';
  }
  return '${milliseconds.toStringAsFixed(milliseconds < 10 ? 2 : 1)} ms';
}

String _trim(String number) =>
    number.contains('.') ? number.replaceFirst(RegExp(r'\.?0+$'), '') : number;
