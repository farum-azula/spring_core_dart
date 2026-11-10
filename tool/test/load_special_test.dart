// tool/load.dart beyond the sweeps: which isolates served and how the
// throughput grows with them, what a scaling timeline shows, and the
// verdicts of the overload checks. Pure functions on small fixtures; the
// oha output is a real one (tool/test/load/oha_refusals.json: 600
// requests a second against server.max-concurrent-requests=8).
import 'dart:io';

import 'package:test/test.dart';

import '../load.dart';

OhaResult canned(String name) {
  final file = [
    'tool/test/load/$name.json',
    'test/load/$name.json',
    'load/$name.json',
  ].map(File.new).firstWhere((file) => file.existsSync());
  return OhaResult.parse(file.readAsStringSync());
}

const json = Scenario('json', 'JSON', path: '/json');
const thresholds = Thresholds();

/// A step that answered [qps] of [rate] with the [p99] given.
StepResult step({
  int rate = 1000,
  double? qps,
  Duration p99 = const Duration(milliseconds: 5),
  int failed = 0,
  Map<int, int>? statusCodes,
  double seconds = 2,
}) {
  final ok = ((qps ?? rate) * seconds).round();
  return StepResult(
    rate: rate,
    concurrency: 50,
    seconds: seconds,
    requests: ok + failed,
    ok: ok,
    statusCodes: statusCodes ?? {200: ok},
    errors: {if (failed > 0) 'connection error': failed},
    timeouts: 0,
    refused: 0,
    connectionErrors: failed,
    unexpected: 0,
    aborted: 0,
    megabytes: 0,
    p50: const Duration(milliseconds: 1),
    p99: p99,
    max: p99,
    sustained: failed == 0 && p99 <= const Duration(milliseconds: 100),
    broken: [if (failed > 0) 'connection errors'],
  );
}

const slow = Duration(milliseconds: 600);

TimelineWindow window(
  double start,
  String phase, {
  int rate = 1500,
  double? qps,
  Duration p99 = const Duration(milliseconds: 5),
  int failed = 0,
  int? isolates,
}) => TimelineWindow(
  start: start,
  phase: phase,
  isolates: isolates,
  step: step(rate: rate, qps: qps, p99: p99, failed: failed),
);

ClientResult client({
  int? status,
  Duration? answered,
  Duration? closed,
  int sent = 1024,
  bool sentAll = true,
}) => (
  status: status,
  answeredAfter: answered,
  closedAfter: closed,
  bytesSent: sent,
  sentAll: sentAll,
);

bool? ok(List<Expectation> expectations, String start) => expectations
    .firstWhere((expectation) => expectation.name.startsWith(start))
    .ok;

void main() {
  group('the isolates that served', () {
    const state = {
      'count': 3,
      'loads': [
        {
          'name': 'main',
          'kind': 'main',
          'details': {'requests': 1000},
        },
        {
          'name': 'isolate-1',
          'kind': 'server',
          'details': {'requests': 900},
        },
        {
          'name': 'isolate-1-task-1',
          'kind': 'task',
          'details': <String, int>{},
        },
        {
          'name': 'isolate-2',
          'kind': 'server',
          'details': {'requests': 5},
        },
      ],
    };

    test('requestsByIsolate keeps the rows that count requests', () {
      expect(requestsByIsolate(state), {
        'main': 1000,
        'isolate-1': 900,
        'isolate-2': 5,
      });
    });

    test('an isolate with a real share of the requests served', () {
      final served = isolatesServed(
        const {'main': 100, 'isolate-1': 100},
        requestsByIsolate(state),
        count: 3,
      );
      expect(served['count'], 3);
      // isolate-2 took 5 of 1705: it answered the tool at most.
      expect(served['served'], 2);
      expect(
        (served['shares']! as Map)['main'],
        closeTo(900 / 1705, 0.0001),
      );
    });

    test('not known when the server did not say', () {
      expect(
        isolatesServed(null, const {'main': 1}, count: 2)['served'],
        isNull,
      );
    });
  });

  group('the isolates matrix', () {
    Map<String, Object?> run(
      int isolates,
      double sustainable,
      double peak, {
      bool broke = true,
      int? served,
    }) => {
      'label': 'isolates=$isolates',
      'startedAt': '2026-11-10T10:00:00.000Z',
      'machine': {'cores': 10, 'os': 'macos', 'osVersion': '27'},
      'isolates': {'asked': '$isolates', 'count': isolates},
      'scenarios': [
        {
          'name': 'text',
          'kind': 'rate',
          'isolates': {'count': isolates, 'served': served ?? isolates},
          'steps': [
            {'rate': 8000, 'sustained': true, 'broken': <String>[]},
            {
              'rate': 16000,
              'sustained': !broke,
              'broken': [if (broke) 'p99 above 1 s'],
            },
          ],
          'summary': {
            'sustainableQps': sustainable,
            'sustainableRate': 8000,
            'peakQps': peak,
            'breakingRate': broke ? 16000 : null,
            'breakingReasons': [if (broke) 'p99 above 1 s'],
          },
        },
        // A check has no steps: not part of the matrix.
        {'name': 'big-body', 'kind': 'check', 'verdict': 'pass'},
      ],
    };

    final reports = [
      run(4, 30000, 32000),
      run(1, 8000, 10000),
      run(2, 16000, 19000),
    ];

    test('the points are in the order of the isolates', () {
      final points = scalingPoints(reports, 'text');
      expect(points.map((point) => point.isolates), [1, 2, 4]);
      expect(points.map((point) => point.peak), [10000, 19000, 32000]);
      expect(points.first.breaking, '16000/s: p99 above 1 s');
      expect(points.every((point) => !point.capped), isTrue);
    });

    test('efficiency is the gain over the isolates added', () {
      expect(efficiency(19000, 2, 10000, 1), closeTo(0.95, 0.0001));
      expect(efficiency(32000, 4, 10000, 1), closeTo(0.8, 0.0001));
      // Against a run with two isolates: twice the isolates.
      expect(efficiency(32000, 4, 19000, 2), closeTo(0.842, 0.001));
      expect(efficiency(null, 2, 10000, 1), isNull);
      expect(efficiency(1, 2, 0, 1), isNull);
    });

    test('it stops scaling where the peak gains under 10 %', () {
      expect(stopsScalingAt(scalingPoints(reports, 'text')), isNull);
      final flat = [...reports, run(8, 30000, 33000)];
      expect(stopsScalingAt(scalingPoints(flat, 'text'))?.isolates, 8);
    });

    test('scaling.md has the ratios, the efficiency and the verdict', () {
      final markdown = renderScaling([...reports, run(8, 30000, 33000)]);
      expect(markdown, startsWith('# Load by isolates\n'));
      expect(markdown, contains('## text'));
      expect(
        markdown,
        contains('| 1 | 1 | 8000 | 1.00× | 100 % | 10000 | 1.00× | 100 % |'),
      );
      expect(
        markdown,
        contains('| 2 | 2 | 16000 | 2.00× | 100 % | 19000 | 1.90× | 95 % |'),
      );
      expect(
        markdown,
        contains('| 4 | 4 | 30000 | 3.75× | 93.8 % | 32000 | 3.20× | 80 % |'),
      );
      expect(markdown, contains('| text | Stops scaling at 8 isolates'));
      expect(markdown, isNot(contains('big-body')));
    });

    test('a run whose last step was sustained is a floor', () {
      final markdown = renderScaling([
        run(1, 8000, 10000),
        run(2, 16000, 16000, broke: false),
      ]);
      expect(markdown, contains('| 2 | 2 | ≥ 16000 |'));
      expect(markdown, contains('not reached (up to 16000/s)'));
      expect(markdown, contains('its sustainable value is a floor'));
      expect(markdown, contains('Still scaling at 2 isolates'));
    });

    test('a run that did not use its isolates says so', () {
      final markdown = renderScaling([
        run(1, 8000, 10000),
        run(4, 8000, 10500, served: 1),
      ]);
      expect(markdown, contains('**4 isolates ran but 1 served**'));
      expect(markdown, contains('Stops scaling at 4 isolates'));
    });
  });

  group('the scaling log', () {
    final start = DateTime.parse('2026-11-10T13:21:50.000+02:00');
    const log = '''
2026-11-10T13:21:48.100+02:00  INFO 1 --- [load-bench] [main] spring.web.isolates : Scaling 1 → 1 isolates (before the timeline)
2026-11-10T13:21:54.500+02:00  INFO 1 --- [load-bench] [           main] spring.web.isolates                      : Scaling 1 → 3 isolates (auto: lag 14.2 ms, 40 in flight)
2026-11-10T13:21:54.638+02:00  INFO 1 --- [load-bench] [           main] spring.web.isolates                      : Isolate isolate-2 ready in 0.094 seconds
2026-11-10T13:21:55.000+02:00  INFO 1 --- [load-bench] [           main] spring.web.server                        : not the pool
2026-11-10T13:22:02.000+02:00  INFO 1 --- [load-bench] [           main] spring.web.isolates                      : Scaling 3 → 2 isolates (auto: lag 0.4 ms, 1 in flight)
''';

    test('its lines are events, the scaling ones steps', () {
      final parsed = parseScalingLog(log, start);
      expect(parsed.events, hasLength(3));
      expect(parsed.events[1].at, closeTo(4.638, 0.0001));
      expect(parsed.events[1].what, 'Isolate isolate-2 ready in 0.094 seconds');
      expect(parsed.steps, [
        (at: 4.5, from: 1, to: 3, reason: 'auto: lag 14.2 ms, 40 in flight'),
        (at: 12.0, from: 3, to: 2, reason: 'auto: lag 0.4 ms, 1 in flight'),
      ]);
    });

    test('without a log the windows show the steps', () {
      final steps = scalingSteps([
        window(0, 'a', isolates: 1),
        // The server was too busy to say: no step from that.
        window(2, 'a'),
        window(4, 'a', isolates: 2),
        window(6, 'a', isolates: 2),
        window(8, 'a', isolates: 1),
      ]);
      expect(steps.map((step) => (step.at, step.from, step.to)), [
        (6.0, 1, 2),
        (10.0, 2, 1),
      ]);
    });

    test('directionChanges counts the turns', () {
      ScalingStep to(int from, int to) =>
          (at: 0, from: from, to: to, reason: '');
      expect(directionChanges([]), 0);
      expect(directionChanges([to(1, 2), to(2, 3)]), 0);
      expect(directionChanges([to(1, 2), to(2, 3), to(3, 2), to(2, 1)]), 1);
      expect(directionChanges([to(1, 2), to(2, 1), to(1, 2), to(2, 1)]), 3);
    });
  });

  group('scale-manual', () {
    // One isolate answers 1000 of 1500 a second; three keep up.
    final windows = [
      window(0, 'one isolate', qps: 1000, p99: slow, isolates: 1),
      window(2, 'one isolate', qps: 1020, p99: slow, isolates: 1),
      // Asked at 5.0, done at 5.2: this window is half before, half after.
      window(4, 'scaling up', qps: 900, p99: slow, isolates: 3),
      window(6, '3 isolates', isolates: 3),
      window(8, '3 isolates', isolates: 3),
      // Asked at 11.0, done at 11.1.
      window(10, 'scaling down', qps: 1100, p99: slow, failed: 4, isolates: 1),
      window(12, 'one isolate again', qps: 990, p99: slow, isolates: 1),
    ];
    final summary = summarizeManual(
      windows,
      upAsked: 5,
      upDone: 5.2,
      downAsked: 11,
      downDone: 11.1,
      thresholds: thresholds,
    );

    test('the parts of the timeline', () {
      expect((summary['before']! as Map)['qps'], 1010);
      expect((summary['before']! as Map)['windows'], 2);
      expect((summary['scaled']! as Map)['qps'], 1500);
      expect((summary['scaled']! as Map)['p99Ms'], 5);
      expect((summary['after']! as Map)['windows'], 1);
    });

    test('the dip, and when the new isolates helped', () {
      expect(summary['scaleUpSeconds'], closeTo(0.2, 0.0001));
      // 900 against 1010 before.
      expect(summary['dipPercent'], closeTo(10.89, 0.01));
      // The first window that kept up starts at 6, one second after.
      expect(summary['helpedAfterSeconds'], 1);
    });

    test('the errors of the drain', () {
      expect(summary['scaleDownSeconds'], closeTo(0.1, 0.0001));
      expect(summary['drainErrors'], 4);
      expect(summary['errors'], 4);
    });

    test('isolates that never help', () {
      final never = summarizeManual(
        [
          window(0, 'one isolate', qps: 1000, p99: slow),
          window(2, 'scaling up', qps: 1000, p99: slow),
          window(4, '3 isolates', qps: 1000, p99: slow),
        ],
        upAsked: 3,
        upDone: null,
        downAsked: 6,
        downDone: null,
        thresholds: thresholds,
      );
      expect(never['helpedAfterSeconds'], isNull);
      expect(never['scaleUpSeconds'], isNull);
      expect(never['dipPercent'], 0);
    });

    test('keptUp needs the rate, the p99 and no errors', () {
      expect(window(0, 'a').keptUp(thresholds), isTrue);
      expect(window(0, 'a', qps: 1400).keptUp(thresholds), isFalse);
      expect(window(0, 'a', p99: slow).keptUp(thresholds), isFalse);
      expect(window(0, 'a', failed: 30).keptUp(thresholds), isFalse);
    });
  });

  group('scale-auto', () {
    // One isolate takes 1000 a second.
    final windows = [
      window(0, 'half', rate: 500, isolates: 1),
      window(2, 'overload', qps: 1000, p99: slow, isolates: 1),
      window(4, 'overload', qps: 1100, p99: slow, isolates: 2),
      window(6, 'overload', isolates: 2),
      window(8, 'relief', rate: 300, isolates: 2),
      window(10, 'relief', rate: 300, isolates: 2),
      window(12, 'relief', rate: 300, isolates: 1),
    ];
    const steps = [
      (at: 5.5, from: 1, to: 2, reason: 'auto'),
      (at: 13.0, from: 2, to: 1, reason: 'auto'),
    ];
    final summary = summarizeAuto(
      windows,
      steps,
      capacity: 1000,
      thresholds: thresholds,
    );

    test('when it grew, relative to the overload', () {
      expect(summary['overloadAtSeconds'], 2);
      expect(summary['firstScaleUpAfterSeconds'], 3.5);
      expect(summary['keptUpAfterSeconds'], 4);
      expect(summary['overloadedWindows'], 3);
      expect(summary['overloadedWindowsKeptUp'], 1);
      expect(summary['mostIsolates'], 2);
    });

    test('when it shrank, relative to the relief', () {
      expect(summary['relievedAtSeconds'], 8);
      expect(summary['firstScaleDownAfterSeconds'], 5);
      expect(summary['backToStartAfterSeconds'], 5);
    });

    test('one peak, one change of direction: no flapping', () {
      expect(summary['scaleUps'], 1);
      expect(summary['scaleDowns'], 1);
      expect(summary['directionChanges'], 1);
      expect(summary['flapped'], isFalse);
    });

    test('a pool that goes up and down twice flapped', () {
      final flapping = summarizeAuto(
        windows,
        const [
          (at: 5.5, from: 1, to: 2, reason: 'auto'),
          (at: 7.0, from: 2, to: 1, reason: 'auto'),
          (at: 9.0, from: 1, to: 2, reason: 'auto'),
        ],
        capacity: 1000,
        thresholds: thresholds,
      );
      expect(flapping['directionChanges'], 2);
      expect(flapping['flapped'], isTrue);
    });

    test('a pool that never grew', () {
      final stuck = summarizeAuto(
        windows.take(4).toList(),
        const [],
        capacity: 1000,
        thresholds: thresholds,
      );
      expect(stuck['firstScaleUpAfterSeconds'], isNull);
      expect(stuck['relievedAtSeconds'], isNull);
      expect(stuck['scaleUps'], 0);
    });

    test('the report says what happened', () {
      final markdown = renderTimeline({
        'name': 'scale-auto',
        'settings': {
          'capacityQps': 1000,
          'windowSeconds': 2,
          'serverArgs': ['--server.isolates.scaling=auto'],
        },
        'windows': [for (final window in windows) window.toJson()],
        'events': [
          {'at': 5.5, 'what': 'Scaling 1 → 2 isolates (auto)'},
        ],
        'summary': summary,
      });
      expect(markdown, contains('`--server.isolates.scaling=auto`'));
      expect(markdown, contains('first step up 3.5 s later'));
      expect(markdown, contains('1 of 3 overloaded windows kept up'));
      expect(markdown, contains('**1 steps up, 1 down, 1 changes'));
      expect(markdown, contains('no flapping'));
      expect(
        markdown,
        contains('| 2 | overload | 1500 | 1000 | 1.00 ms | 600.0 ms | 0 '),
      );
      expect(markdown, contains('- 5.5 s: Scaling 1 → 2 isolates (auto)'));
      expect(markdown, contains('    line [500, 1500, 1500, 1500, 300, 300'));
    });
  });

  group('overload-concurrent', () {
    final oha = canned('oha_refusals');
    const slowEndpoint = Scenario(
      'slow',
      'Slow',
      path: '/slow?ms=50',
      expected: {200, 503},
    );
    final load = StepResult.of(
      oha,
      slowEndpoint,
      thresholds: thresholds,
      rate: 600,
      concurrency: 64,
    );
    List<Expectation> judge({
      int limit = 8,
      String? retryAfter = '1',
      LatencySplit? notSuccessful,
    }) => judgeConcurrent(
      load,
      successful: oha.successful,
      notSuccessful: notSuccessful ?? oha.notSuccessful,
      limit: limit,
      handler: const Duration(milliseconds: 50),
      retryAfter: retryAfter,
      thresholds: thresholds,
    );

    test('oha tells the latency of the refusals from the answers', () {
      expect(oha.statusCodes, {200: 610, 503: 1782});
      expect(oha.successful?.p99, const Duration(microseconds: 52806));
      expect(oha.notSuccessful?.p99, const Duration(microseconds: 1509));
      expect(canned('oha_ok').successful, isNull);
    });

    test('a server that refuses fast and serves its limit passes', () {
      final expectations = judge();
      expect(verdict(expectations), 'pass');
      expect(expectations.map((e) => e.ok), everyElement(isTrue));
      expect(
        expectations.first.actual,
        startsWith('74.5 % answered 503, 25.5 % 200'),
      );
    });

    test('a slow refusal fails', () {
      final expectations = judge(
        notSuccessful: (
          p50: const Duration(milliseconds: 300),
          p99: const Duration(milliseconds: 900),
        ),
      );
      expect(ok(expectations, 'A refusal is fast'), isFalse);
      expect(verdict(expectations), 'fail');
    });

    test('a 503 without Retry-After fails', () {
      expect(ok(judge(retryAfter: null), 'A 503 says'), isFalse);
    });

    test('answering far from what the limit allows fails', () {
      // 151 good answers a second is not what 64 at a time would give.
      expect(ok(judge(limit: 64), 'The server goes on'), isFalse);
    });
  });

  group('overload-connections', () {
    final oha = canned('oha_refusals');
    const text = Scenario('text', 'Text', path: '/text', expected: {200, 503});
    final load = StepResult.of(
      oha,
      text,
      thresholds: thresholds,
      rate: 400,
      concurrency: 64,
    );
    List<Expectation> judge({String? connection = 'close'}) => judgeConnections(
      load,
      // On /text an answer is as fast as a refusal.
      successful: oha.notSuccessful,
      notSuccessful: oha.notSuccessful,
      limit: 16,
      connections: 64,
      retryAfter: '1',
      connection: connection,
      thresholds: thresholds,
    );

    test('refused over the limit, served within it', () {
      expect(verdict(judge()), 'pass');
    });

    test('a refused connection that stays open fails', () {
      final expectations = judge(connection: null);
      expect(ok(expectations, 'A refused connection is closed'), isFalse);
      expect(verdict(expectations), 'fail');
    });
  });

  group('the slow clients', () {
    const timeout = Duration(seconds: 2);

    test('slow headers: all dropped within twice the timeout', () {
      final expectations = judgeSlowHeaders(
        [
          for (var i = 0; i < 10; i++)
            client(closed: const Duration(milliseconds: 3870)),
        ],
        timeout: timeout,
        memoryGrowth: 1 << 20,
      );
      expect(verdict(expectations), 'pass');
      expect(expectations.first.actual, startsWith('10 of 10 dropped'));
    });

    test('slow headers: one kept open, or dropped late, fails', () {
      final kept = judgeSlowHeaders(
        [client(closed: const Duration(seconds: 3)), client()],
        timeout: timeout,
        memoryGrowth: null,
      );
      expect(ok(kept, 'Every connection'), isFalse);
      // Not measured: reported, not judged.
      expect(ok(kept, 'They cost little memory'), isNull);
      final late = judgeSlowHeaders(
        [client(closed: const Duration(seconds: 6))],
        timeout: timeout,
        memoryGrowth: 0,
      );
      expect(ok(late, 'Within twice'), isFalse);
      expect(
        ok(
          judgeSlowHeaders(
            [client(closed: const Duration(seconds: 3))],
            timeout: timeout,
            memoryGrowth: 64 << 20,
          ),
          'They cost little memory',
        ),
        isFalse,
      );
    });

    List<Expectation> body({
      int? status = 408,
      Duration answered = const Duration(milliseconds: 2030),
      Duration? closed = const Duration(milliseconds: 7030),
      ClientResult? trickled,
    }) => judgeSlowBody(
      stalled: [client(status: status, answered: answered, closed: closed)],
      trickled: [trickled ?? client()],
      timeout: timeout,
      watched: const Duration(seconds: 11),
    );

    test('slow body: a stalled one gets its 408 and is closed', () {
      final expectations = body();
      expect(verdict(expectations), 'pass');
      // The trickle is reported, not judged.
      expect(ok(expectations, 'A body that trickles'), isNull);
      expect(
        expectations.last.actual,
        '1 of 1 still open and unanswered after 11 s',
      );
    });

    test('slow body: another status, a late answer or no close fail', () {
      expect(ok(body(status: 500), 'A body that stalls'), isFalse);
      expect(
        ok(body(answered: const Duration(seconds: 9)), 'Within twice'),
        isFalse,
      );
      expect(ok(body(closed: null), 'Its connection is closed'), isFalse);
    });

    test('slow body: a trickle that is cut says how', () {
      final expectations = body(
        trickled: client(
          status: 408,
          answered: const Duration(seconds: 4),
        ),
      );
      expect(
        expectations.last.actual,
        'cut: statuses {408}, the last after 4 s',
      );
    });
  });

  group('big-body', () {
    const megabyte = 1024 * 1024;
    final refused = client(
      status: 413,
      answered: const Duration(milliseconds: 20),
      closed: const Duration(milliseconds: 30),
    );
    List<Expectation> judge({ClientResult? announced, ClientResult? flood}) =>
        judgeBigBody(
          announced: announced ?? refused,
          chunked: refused,
          flood:
              flood ??
              client(
                closed: const Duration(milliseconds: 8),
                sent: 2 * megabyte,
                sentAll: false,
              ),
          limit: megabyte,
          floodBytes: 256 * megabyte,
          memoryGrowth: 5 * megabyte,
        );

    test('refused from the headers and not read to the end', () {
      final expectations = judge();
      expect(verdict(expectations), 'pass');
      // The client that kept sending read no answer: reported only.
      expect(ok(expectations, 'What a client that keeps sending'), isNull);
    });

    test('a server that reads it all fails', () {
      final expectations = judge(
        flood: client(status: 413, sent: 256 * megabyte),
      );
      expect(ok(expectations, 'A body that keeps coming'), isFalse);
      expect(verdict(expectations), 'fail');
    });

    test('a late or missing 413 fails', () {
      expect(
        ok(
          judge(
            announced: client(
              status: 413,
              answered: const Duration(seconds: 3),
            ),
          ),
          'A body announced',
        ),
        isFalse,
      );
      expect(ok(judge(announced: client()), 'A body announced'), isFalse);
    });
  });

  group('cpu and the probes', () {
    test('the probe must be answered in time', () {
      expect(probeExpectation(step(), thresholds).ok, isTrue);
      expect(probeExpectation(step(p99: slow), thresholds).ok, isFalse);
      expect(probeExpectation(step(failed: 1), thresholds).ok, isFalse);
    });

    test('a refusal is an answer only where the check says so', () {
      final refused = StepResult.of(
        const OhaResult(
          seconds: 4,
          statusCodes: {200: 13, 503: 67},
          errors: {},
          bytes: 0,
          p50: Duration(milliseconds: 1),
          p95: Duration(milliseconds: 1),
          p99: Duration(milliseconds: 2),
          max: Duration(milliseconds: 2),
        ),
        probeScenario,
        thresholds: thresholds,
        rate: 20,
        concurrency: 2,
      );
      expect(probeExpectation(refused, thresholds).ok, isFalse);
      expect(
        probeExpectation(refused, thresholds, mayRefuse: true).ok,
        isTrue,
      );
    });

    test('recovery', () {
      expect(
        recoveryExpectation((recovered: false, after: null)).ok,
        isFalse,
      );
      expect(
        recoveryExpectation((
          recovered: true,
          after: const Duration(milliseconds: 3),
        )).actual,
        'answered after 3 ms',
      );
    });

    List<Expectation> cpu(Duration inline, Duration task) => judgeCpu(
      inlineProbe: step(p99: inline),
      taskProbe: step(p99: task),
      inlineWork: step(rate: 20),
      taskWork: step(rate: 20),
      inlineThroughput: 30,
      taskThroughput: 85,
      thresholds: thresholds,
    );

    test('tasks keep the probe fast', () {
      final expectations = cpu(
        const Duration(milliseconds: 46),
        const Duration(milliseconds: 1),
      );
      expect(verdict(expectations), 'pass');
      expect(expectations[1].actual, contains('(46 times)'));
      expect(expectations.last.actual, 'inline 30 QPS, tasks 85 QPS');
    });

    test('a probe as slow with tasks as inline fails', () {
      final expectations = cpu(
        const Duration(milliseconds: 46),
        const Duration(milliseconds: 46),
      );
      expect(ok(expectations, 'They wait less'), isFalse);
      expect(verdict(expectations), 'fail');
    });
  });

  group('the report', () {
    final failing = [
      const Expectation(
        'A refusal is fast',
        ok: false,
        actual: '503: p99 900 ms',
        expected: 'p99 at most 100 ms',
      ),
      const Expectation('A number', ok: null, actual: '42', expected: '-'),
    ];
    final report = {
      'label': 'special',
      'startedAt': '2026-11-10T10:00:00.000Z',
      'machine': {'cores': 10, 'os': 'macos', 'osVersion': '27'},
      'options': {
        'durationSeconds': 5,
        'connections': 50,
        'compiled': true,
        'thresholds': thresholds.toJson(),
      },
      'isolates': {'asked': '4', 'count': 1, 'mismatch': true},
      'scenarios': [
        {
          'name': 'overload-concurrent',
          'title': 'More requests at a time',
          'kind': 'check',
          'verdict': verdict(failing),
          'settings': {'server': '--server.max-concurrent-requests=8'},
          'expectations': [for (final e in failing) e.toJson()],
        },
        {
          'name': 'scale-manual',
          'title': 'Scaling by hand',
          'kind': 'timeline',
          'settings': {'capacityQps': 1000, 'rate': 1500, 'scaleTo': 3},
          'windows': [
            window(0, 'one isolate', qps: 1000, isolates: 1).toJson(),
            window(2, '3 isolates', isolates: 3).toJson(),
          ],
          'summary': summarizeManual(
            const [],
            upAsked: 1,
            upDone: 1.2,
            downAsked: 3,
            downDone: 3.1,
            thresholds: thresholds,
          ),
        },
      ],
    };

    test('a check has its verdict in the summary and its rows below', () {
      final markdown = renderReport(report);
      expect(
        markdown,
        contains(
          '| **FAIL** | A refusal is fast: 503: p99 900 ms |',
        ),
      );
      expect(markdown, contains('**FAIL.** server: '));
      expect(
        markdown,
        contains(
          '| **FAIL** | A refusal is fast | 503: p99 900 ms '
          '| p99 at most 100 ms |',
        ),
      );
      expect(markdown, contains('| info | A number | 42 | - |'));
    });

    test('a timeline has its isolates in the summary', () {
      final markdown = renderReport(report);
      expect(markdown, contains('| 1500/s | 1 3 | 0 |'));
      expect(markdown, contains('- **Scaling to 3** took 0.2 s'));
    });

    test('a run that did not get its isolates says so at the top', () {
      expect(
        renderReport(report),
        contains(
          '**1 isolates** served the sweeps (`server.isolates.count=4`). '
          '**This is not the number asked for',
        ),
      );
    });

    test('the comparison leaves the checks and timelines out', () {
      final markdown = renderComparison([report, report]);
      expect(markdown, isNot(contains('overload-concurrent')));
      expect(markdown, isNot(contains('scale-manual')));
    });
  });
}
