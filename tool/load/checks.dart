// The checks of tool/load.dart that are a verdict, not a sweep: what the
// server does when it is asked for more than its limits (`overload-*`),
// by clients that send slowly (`slow-*`) or too much (`big-body`), and
// whether CPU-bound work leaves it responsive (`cpu`). Each check
// measures, then judges the numbers here: pure functions.
import 'analysis.dart';
import 'format.dart';
import 'oha.dart';

/// One thing a check expects, and what it saw.
final class Expectation {
  /// An expectation called [name]; [ok] is `null` for a number that is
  /// reported without being judged.
  const Expectation(
    this.name, {
    required this.ok,
    required this.actual,
    required this.expected,
  });

  /// What is expected, as a short sentence.
  final String name;

  /// Whether it held; `null`: reported only.
  final bool? ok;

  /// What was measured.
  final String actual;

  /// What would pass.
  final String expected;

  /// For report.json.
  Map<String, Object?> toJson() => {
    'name': name,
    'ok': ok,
    'actual': actual,
    'expected': expected,
  };
}

/// `pass` when no expectation failed, else `fail`.
String verdict(List<Expectation> expectations) =>
    expectations.any((expectation) => expectation.ok == false)
    ? 'fail'
    : 'pass';

/// What a slow or oversized request of the tool's own client got.
typedef ClientResult = ({
  /// The status of the answer; `null` when the server sent none.
  int? status,

  /// From the start of the request to the answer's first bytes.
  Duration? answeredAfter,

  /// From the start to the server closing the connection; `null` when it
  /// was still open at the end of the observation.
  Duration? closedAfter,

  /// The bytes of the request the client had written when the answer
  /// came (or at the end, without one).
  int bytesSent,

  /// Whether the client wrote the whole request it meant to.
  bool sentAll,
});

String _time(Duration? duration) => formatDuration(duration);

String _share(int part, int all) =>
    all == 0 ? '0 %' : '${plain(part / all * 100)} %';

int _failures(StepResult step) =>
    step.timeouts + step.refused + step.connectionErrors;

/// The probe beside a check: the server must go on answering it in time.
/// [mayRefuse]: a 503 is an answer too (the server is at a limit that
/// counts the probe's requests as well).
Expectation probeExpectation(
  StepResult probe,
  Thresholds thresholds, {
  bool mayRefuse = false,
}) {
  final p99 = probe.p99;
  final answered = probe.statusCodes.values.fold<int>(0, (a, b) => a + b);
  final ok =
      answered > 0 &&
      _failures(probe) == 0 &&
      p99 != null &&
      p99 <= thresholds.p99 &&
      (mayRefuse || probe.unexpected == 0);
  return Expectation(
    'A light request beside it is answered in time',
    ok: ok,
    actual:
        'p50 ${_time(probe.p50)}, p99 ${_time(p99)}, statuses '
        '${probe.statusCodes}, ${_failures(probe)} timeouts or broken '
        'connections',
    expected:
        'p99 at most ${_time(thresholds.p99)}, no timeout'
        '${mayRefuse ? ' (a 503 counts as an answer here)' : ', only 200'}',
  );
}

/// The probe after a check: the server answers again.
Expectation recoveryExpectation(Recovery recovery) => Expectation(
  'The server answers afterwards',
  ok: recovery.recovered,
  actual: recovery.recovered
      ? 'answered after ${recovery.after!.inMilliseconds} ms'
      : 'no answer',
  expected: 'an answer to a light request',
);

Expectation _refusalHeaders(String? retryAfter, {String? connection}) =>
    Expectation(
      'A 503 says when to come back (Retry-After)',
      ok: retryAfter != null && retryAfter.isNotEmpty,
      actual:
          'Retry-After: ${retryAfter ?? 'absent'}'
          '${connection == null ? '' : ', Connection: $connection'}',
      expected: 'Retry-After present',
    );

/// `overload-concurrent`: [load] asked for more requests at a time than
/// the [limit] of `server.max-concurrent-requests`, on an endpoint that
/// answers after [handler]. [retryAfter] is the header of a 503 the tool
/// asked for itself (`null`: none seen).
List<Expectation> judgeConcurrent(
  StepResult load, {
  required LatencySplit? successful,
  required LatencySplit? notSuccessful,
  required int limit,
  required Duration handler,
  required String? retryAfter,
  required Thresholds thresholds,
}) {
  final answered = load.statusCodes.values.fold<int>(0, (a, b) => a + b);
  final refused = load.statusCodes[503] ?? 0;
  final good = load.statusCodes[200] ?? 0;
  final capacity = limit / (handler.inMicroseconds / 1000000);
  final goodQps = load.seconds == 0 ? 0.0 : good / load.seconds;
  final accepted = handler + thresholds.p99;
  return [
    Expectation(
      'Requests over the limit are refused with 503',
      ok: refused > 0 && answered == refused + good,
      actual:
          '${_share(refused, answered)} answered 503, '
          '${_share(good, answered)} 200, statuses ${load.statusCodes}',
      expected: 'some 503, and nothing but 200 and 503',
    ),
    Expectation(
      'The server goes on answering what its limit allows',
      ok: goodQps >= 0.5 * capacity && goodQps <= 1.3 * capacity,
      actual: '${plain(goodQps)} good answers a second',
      expected:
          'about ${plain(capacity)}: $limit at a time, '
          '${_time(handler)} each',
    ),
    Expectation(
      'A refusal is fast',
      ok: notSuccessful?.p99 != null && notSuccessful!.p99! <= thresholds.p99,
      actual:
          '503: p50 ${_time(notSuccessful?.p50)}, '
          'p99 ${_time(notSuccessful?.p99)}',
      expected: 'p99 at most ${_time(thresholds.p99)}',
    ),
    Expectation(
      'An accepted request does not wait behind the others',
      ok: successful?.p99 != null && successful!.p99! <= accepted,
      actual:
          '200: p50 ${_time(successful?.p50)}, '
          'p99 ${_time(successful?.p99)}',
      expected:
          'p99 at most ${_time(accepted)} (the handler and '
          '${_time(thresholds.p99)})',
    ),
    _refusalHeaders(retryAfter),
    Expectation(
      'No timeout, no broken connection',
      ok: _failures(load) == 0,
      actual:
          '${load.timeouts} timeouts, ${load.refused} refused, '
          '${load.connectionErrors} broken; ${load.errors}',
      expected: 'none',
    ),
  ];
}

/// `overload-connections`: [load] used more connections than the [limit]
/// of `server.max-connections`. [retryAfter] and [connection] are the
/// headers of a 503 the tool asked for itself.
List<Expectation> judgeConnections(
  StepResult load, {
  required LatencySplit? successful,
  required LatencySplit? notSuccessful,
  required int limit,
  required int connections,
  required String? retryAfter,
  required String? connection,
  required Thresholds thresholds,
}) {
  final answered = load.statusCodes.values.fold<int>(0, (a, b) => a + b);
  final refused = load.statusCodes[503] ?? 0;
  final good = load.statusCodes[200] ?? 0;
  return [
    Expectation(
      'Connections over the limit are answered 503',
      ok: refused > 0 && answered == refused + good,
      actual:
          '$connections connections for a limit of $limit: '
          '${_share(refused, answered)} of the answers 503, '
          '${_share(good, answered)} 200',
      expected: 'some 503, and nothing but 200 and 503',
    ),
    Expectation(
      'Connections within the limit are served',
      ok:
          good > 0 &&
          successful?.p99 != null &&
          successful!.p99! <= thresholds.p99,
      actual:
          '$good answers 200, p50 ${_time(successful?.p50)}, '
          'p99 ${_time(successful?.p99)}',
      expected: 'some 200, p99 at most ${_time(thresholds.p99)}',
    ),
    Expectation(
      'A refusal is fast',
      ok: notSuccessful?.p99 != null && notSuccessful!.p99! <= thresholds.p99,
      actual:
          '503: p50 ${_time(notSuccessful?.p50)}, '
          'p99 ${_time(notSuccessful?.p99)}',
      expected: 'p99 at most ${_time(thresholds.p99)}',
    ),
    _refusalHeaders(retryAfter, connection: connection ?? 'absent'),
    Expectation(
      'A refused connection is closed',
      ok: connection?.toLowerCase() == 'close',
      actual: 'Connection: ${connection ?? 'absent'}',
      expected: 'Connection: close',
    ),
    Expectation(
      'No timeout, no connection broken without an answer',
      ok: _failures(load) == 0,
      actual:
          '${load.timeouts} timeouts, ${load.refused} refused, '
          '${load.connectionErrors} broken; ${load.errors}',
      expected: 'none',
    ),
  ];
}

Duration? _slowest(Iterable<Duration?> times) {
  final all = times.nonNulls.toList()..sort();
  return all.isEmpty ? null : all.last;
}

/// `slow-headers`: [clients] connections sent their headers a line at a
/// time and never finished them, against a `server.connection-timeout` of
/// [timeout]. [memoryGrowth] is how much the server's memory rose, in
/// bytes.
List<Expectation> judgeSlowHeaders(
  List<ClientResult> clients, {
  required Duration timeout,
  required int? memoryGrowth,
}) {
  final dropped = clients.where((client) => client.closedAfter != null);
  final slowest = _slowest(clients.map((client) => client.closedAfter));
  final fastest = dropped.isEmpty
      ? null
      : (dropped.map((client) => client.closedAfter!).toList()..sort()).first;
  // dart:io drops an idle connection between one and two timeouts.
  final limit = timeout * 2 + const Duration(seconds: 1);
  final statuses = {for (final client in clients) client.status};
  const perConnection = 256 * 1024;
  return [
    Expectation(
      'Every connection that never finishes its headers is dropped',
      ok: dropped.length == clients.length,
      actual:
          '${dropped.length} of ${clients.length} dropped; answers: '
          '${statuses.map((s) => s ?? 'none').join(', ')}',
      expected: 'all of them',
    ),
    Expectation(
      'Within twice server.connection-timeout',
      ok:
          slowest != null &&
          dropped.length == clients.length &&
          slowest <= limit,
      actual: 'first after ${_time(fastest)}, last after ${_time(slowest)}',
      expected: 'at most ${_time(limit)} (the timeout is ${_time(timeout)})',
    ),
    Expectation(
      'They cost little memory',
      ok: memoryGrowth == null
          ? null
          : memoryGrowth <= clients.length * perConnection,
      actual: memoryGrowth == null
          ? 'not measured'
          : 'the RSS rose by ${megabytes(memoryGrowth)}',
      expected:
          'at most ${megabytes(clients.length * perConnection)} '
          '(256 KB a connection)',
    ),
  ];
}

/// `slow-body`: requests with a `Content-Length` whose body [stalled]
/// (nothing after the first bytes) or [trickled] (a byte now and then),
/// against a `server.connection-timeout` of [timeout], watched for
/// [watched].
List<Expectation> judgeSlowBody({
  required List<ClientResult> stalled,
  required List<ClientResult> trickled,
  required Duration timeout,
  required Duration watched,
}) {
  final limit = timeout * 2 + const Duration(seconds: 1);
  // What the web starter gives the rest of a body after an early answer.
  const swallow = Duration(seconds: 5);
  final slowest = _slowest(stalled.map((client) => client.answeredAfter));
  final cut = trickled.where(
    (client) => client.status != null || client.closedAfter != null,
  );
  final lastCut = _slowest(
    trickled.map((client) => client.answeredAfter ?? client.closedAfter),
  );
  return [
    Expectation(
      'A body that stalls is answered 408',
      ok: stalled.isNotEmpty && stalled.every((client) => client.status == 408),
      actual:
          'statuses ${stalled.map((c) => c.status ?? 'none').toSet()} '
          'of ${stalled.length} requests',
      expected: '408',
    ),
    Expectation(
      'Within twice server.connection-timeout',
      ok: slowest != null && slowest <= limit,
      actual: 'the slowest answer after ${_time(slowest)}',
      expected: 'at most ${_time(limit)} (the timeout is ${_time(timeout)})',
    ),
    Expectation(
      'Its connection is closed',
      ok: stalled.every(
        (client) =>
            client.closedAfter != null &&
            client.closedAfter! <= limit + swallow,
      ),
      actual:
          '${stalled.where((c) => c.closedAfter != null).length} of '
          '${stalled.length} closed, the last after '
          '${_time(_slowest(stalled.map((c) => c.closedAfter)))}',
      expected:
          'all closed within ${_time(limit + swallow)}: after its answer '
          'the server reads on for up to ${_time(swallow)}, for a body '
          'that ends late',
    ),
    Expectation(
      'A body that trickles (a byte every half second)',
      // Not judged: server.connection-timeout is about a body that sends
      // nothing. Reported, as such a request holds its connection.
      ok: null,
      actual: cut.length == trickled.length
          ? 'cut: statuses '
                '${trickled.map((c) => c.status ?? 'none').toSet()}, the '
                'last after ${_time(lastCut)}'
          : '${trickled.length - cut.length} of ${trickled.length} still '
                'open and unanswered after ${_time(watched)}',
      expected:
          'reported only: the timeout counts silence, and a trickle is '
          'not silent',
    ),
  ];
}

/// `big-body`, against a `server.max-http-request-body-size` of [limit]
/// bytes:
///
/// - [announced]: the headers of a body of [floodBytes], and nothing
///   more: the `Content-Length` alone is too much;
/// - [chunked]: a body without a length that grows past the limit, then
///   stops;
/// - [flood]: the announced body sent as fast as the socket takes it, to
///   see how much of it the server takes.
List<Expectation> judgeBigBody({
  required ClientResult announced,
  required ClientResult chunked,
  required ClientResult flood,
  required int limit,
  required int floodBytes,
  required int? memoryGrowth,
}) {
  // What the sockets of both ends hold without the server reading it,
  // and the 2 MB the web starter reads and drops after an early answer.
  const buffers = 16 * 1024 * 1024;
  const fast = Duration(seconds: 1);
  Expectation refused(String name, ClientResult result) => Expectation(
    name,
    ok:
        result.status == 413 &&
        result.answeredAfter != null &&
        result.answeredAfter! <= fast,
    actual:
        'status ${result.status ?? 'none'} after '
        '${_time(result.answeredAfter)}',
    expected: '413 within ${_time(fast)}',
  );
  return [
    refused(
      'A body announced as too large is refused from its headers (413)',
      announced,
    ),
    refused('A chunked body is refused once it is too large (413)', chunked),
    Expectation(
      'A body that keeps coming is not read to its end',
      ok: !flood.sentAll && flood.bytesSent <= limit + buffers,
      actual:
          'the client could write ${megabytes(flood.bytesSent)} of '
          '${megabytes(floodBytes)}; the connection closed after '
          '${_time(flood.closedAfter)}',
      expected:
          'not all of it, and at most the limit (${megabytes(limit)}) '
          'with what the sockets hold (${megabytes(buffers)})',
    ),
    Expectation(
      'What a client that keeps sending reads',
      // Not judged: the 413 is sent, then the connection is closed with
      // the rest of the body unread, which resets it. Whether the answer
      // is still read then depends on the client.
      ok: null,
      actual: flood.status == null
          ? 'no answer: its write failed (the connection was reset) '
                'before it read one'
          : 'status ${flood.status} after ${_time(flood.answeredAfter)}',
      expected:
          'reported only: 413, or a reset connection for a client that '
          'reads late',
    ),
    Expectation(
      'The server does not keep the bodies in memory',
      ok: memoryGrowth == null ? null : memoryGrowth <= 2 * buffers,
      actual: memoryGrowth == null
          ? 'not measured'
          : 'the RSS rose by ${megabytes(memoryGrowth)}',
      expected: 'at most ${megabytes(2 * buffers)}',
    ),
  ];
}

/// `cpu`: the same CPU-bound requests answered in the request's isolate
/// ([inlineProbe] is the probe beside them) and through the task executor
/// ([taskProbe]).
List<Expectation> judgeCpu({
  required StepResult inlineProbe,
  required StepResult taskProbe,
  required StepResult inlineWork,
  required StepResult taskWork,
  required double? inlineThroughput,
  required double? taskThroughput,
  required Thresholds thresholds,
}) {
  final inline = inlineProbe.p99;
  final task = taskProbe.p99;
  final times = task == null || inline == null || task.inMicroseconds == 0
      ? ''
      : ' (${plain(inline.inMicroseconds / task.inMicroseconds)} times)';
  return [
    Expectation(
      'With the work in a task isolate, other requests are not held up',
      ok: task != null && _failures(taskProbe) == 0 && task <= thresholds.p99,
      actual: 'probe p50 ${_time(taskProbe.p50)}, p99 ${_time(task)}',
      expected: 'p99 at most ${_time(thresholds.p99)}',
    ),
    Expectation(
      "They wait less than with the work in the request's isolate",
      ok: task != null && inline != null && task < inline,
      actual:
          'probe p99 ${_time(task)} with tasks, ${_time(inline)} inline'
          '$times',
      expected: 'less with tasks',
    ),
    Expectation(
      'The work itself, at the same rate',
      ok: null,
      actual:
          'inline: ${plain(inlineWork.qps)} QPS, p50 '
          '${_time(inlineWork.p50)}, p99 ${_time(inlineWork.p99)}; tasks: '
          '${plain(taskWork.qps)} QPS, p50 ${_time(taskWork.p50)}, p99 '
          '${_time(taskWork.p99)}',
      expected: 'reported only',
    ),
    Expectation(
      'The most work a second, four connections as fast as they go',
      ok: null,
      actual:
          'inline ${inlineThroughput == null ? '-' : plain(inlineThroughput)}'
          ' QPS, tasks '
          '${taskThroughput == null ? '-' : plain(taskThroughput)} QPS',
      expected: 'reported only: tasks use several cores, inline one',
    ),
  ];
}

/// The Markdown of a check (or of `cpu`) of report.json: the verdict,
/// what was set, and a row per expectation.
String renderCheck(Json scenario) {
  final expectations = jsonList(scenario['expectations']);
  final settings = jsonMap(scenario['settings']);
  final out = StringBuffer()
    ..writeln(
      '**${scenario['verdict'] == 'pass' ? 'Pass' : 'FAIL'}.** '
      '${settings.entries.map((e) => '${e.key}: `${e.value}`').join(', ')}.',
    )
    ..writeln()
    ..writeln('| | Expectation | Measured | Expected |')
    ..writeln('|---|---|---|---|');
  for (final expectation in expectations) {
    final mark = switch (expectation['ok']) {
      true => 'ok',
      false => '**FAIL**',
      _ => 'info',
    };
    out.writeln(
      '| $mark | ${expectation['name']} '
      '| ${cell('${expectation['actual']}')} '
      '| ${cell('${expectation['expected']}')} |',
    );
  }
  final variants = jsonList(scenario['variants']);
  if (variants.isNotEmpty) {
    out
      ..writeln()
      ..writeln(
        '| Work | Rate (/s) | QPS | p50 | p99 | Probe p50 | Probe p99 '
        '| Probe max | Most QPS |',
      )
      ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|');
    for (final variant in variants) {
      final work = jsonMap(variant['work']);
      final probe = jsonMap(variant['probe']);
      String time(Json step, String key) => formatDuration(
        switch (jsonMap(step['latencyMs'])[key]) {
          final num value => milliseconds(value),
          _ => null,
        },
      );
      out.writeln(
        '| ${variant['name']} | ${work['rate']} | ${number(work['qps'])} '
        '| ${time(work, 'p50')} | ${time(work, 'p99')} '
        '| ${time(probe, 'p50')} | ${time(probe, 'p99')} '
        '| ${time(probe, 'max')} '
        '| ${number(jsonMap(variant['throughput'])['qps'])} |',
      );
    }
  }
  return out.toString();
}
