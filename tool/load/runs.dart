// The scenarios of tool/load.dart as they run: the sweeps (steps of a
// rising rate, or of more connections), the scaling timelines, the `cpu`
// comparison and the overload checks. Each returns its part of
// report.json; what the numbers mean is decided in analysis.dart,
// timeline.dart and checks.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'analysis.dart';
import 'bench_server.dart';
import 'checks.dart';
import 'format.dart';
import 'isolates.dart';
import 'oha.dart';
import 'scenarios.dart';
import 'session.dart';
import 'slow_clients.dart';
import 'timeline.dart';

/// What the server is told so that its pool's steps are in its log, in
/// plain text.
const _isolateLogs = [
  '--logging.level.spring.web.isolates=info',
  '--spring.output.ansi.enabled=never',
];

Future<Map<String, int>?> _requests(BenchServer server) async {
  final state = await server.isolates(timeout: const Duration(seconds: 3));
  return state == null ? null : requestsByIsolate(state);
}

/// Runs the steps of a sweep [scenario] against the session's server:
/// a warm-up, then each rate (or number of connections) until the
/// breaking point.
Future<Json> runSweep(LoadSession session, Scenario scenario) async {
  final options = session.options;
  var server = session.server!;
  if (!server.running) {
    // The scenario before killed it: this one gets a new server.
    stdout.writeln('The bench server is gone: starting a new one.');
    server = await session.restart();
  }
  final rate = scenario.kind == ScenarioKind.rate;
  final loads = rate ? options.rates : options.concurrency;
  stdout
    ..writeln()
    ..writeln('${scenario.name}: ${scenario.title} (${scenario.request})');

  final before = await _requests(server);
  if (options.warmup > Duration.zero) {
    await session.oha(
      scenario,
      duration: options.warmup,
      rate: rate ? loads.first : null,
      connections: rate ? options.connections : loads.first,
    );
  }

  final steps = <StepResult>[];
  Recovery? recovery;
  for (final load in loads) {
    final connections = rate ? options.connections : load;
    final sampler = MemorySampler(server.pid);
    final cpuBefore = await processorTime(server.pid);
    await sampler.start();
    final oha = await session.oha(
      scenario,
      duration: options.duration,
      rate: rate ? load : null,
      connections: connections,
      raw: '${scenario.name}-$load',
    );
    final memory = await sampler.stop();
    final cpuAfter = await processorTime(server.pid);
    final step = StepResult.of(
      oha,
      scenario,
      thresholds: options.thresholds,
      rate: rate ? load : null,
      concurrency: connections,
      memory: memory,
      cpuSeconds: cpuBefore == null || cpuAfter == null
          ? null
          : cpuAfter - cpuBefore,
    );
    steps.add(step);
    stdout.writeln(stepLine(step, megabytes: scenario.transfersData));

    if (step.broken.isNotEmpty && recovery == null) {
      recovery = await session.recovery();
      stdout.writeln(
        recovery.recovered
            ? '    recovered: answered a light request after '
                  '${recovery.after!.inMilliseconds} ms'
            : '    NOT recovered: no answer to a light request in '
                  '${LoadSession.recoveryTimeout.inSeconds} s'
                  '${server.running ? '' : ' (the process is gone)'}',
      );
      if (!options.keepGoing || !server.running) {
        break;
      }
    }
    await Future<void>.delayed(options.pause);
  }

  final state = server.running
      ? await server.isolates(timeout: const Duration(seconds: 3))
      : null;
  final served = isolatesServed(
    before,
    state == null ? null : requestsByIsolate(state),
    count: state?['count'] as int?,
  );
  if (served['served'] case final int answered
      when answered != served['count']) {
    stdout.writeln(
      '    NOTE: ${served['count']} isolates ran, $answered took requests.',
    );
  }
  return {
    'name': scenario.name,
    'title': scenario.title,
    'kind': scenario.kind.name,
    'request': scenario.request,
    'transfersData': scenario.transfersData,
    'isolates': served,
    'steps': [for (final step in steps) step.toJson()],
    'summary': ScenarioSummary.of(steps).toJson(recovery: recovery),
  };
}

/// A step on one line, for the terminal.
String stepLine(StepResult step, {bool megabytes = false, String? label}) {
  final load =
      label ??
      (step.rate != null ? '${step.rate}/s' : '${step.concurrency} conn');
  final memory = step.memory;
  return [
    '  ${load.padLeft(9)}',
    '${step.qps.toStringAsFixed(step.qps < 100 ? 1 : 0)} qps'.padLeft(12),
    if (megabytes)
      '${step.megabytesPerSecond.toStringAsFixed(1)} MB/s'.padLeft(13),
    'p50 ${formatDuration(step.p50)}'.padRight(13),
    'p99 ${formatDuration(step.p99)}'.padRight(13),
    'errors ${(step.errorRate * 100).toStringAsFixed(2)} %',
    if (memory != null) 'rss ${memory.peak ~/ (1024 * 1024)} MB',
    if (step.broken.isNotEmpty)
      'BROKEN: ${step.broken.join(', ')}'
    else if (step.sustained)
      'sustained'
    else
      'not sustained',
  ].join('  ');
}

/// Runs the scenario called [name] that is not a sweep, on a server of
/// its own.
Future<Json> runSpecial(LoadSession session, String name) {
  stdout
    ..writeln()
    ..writeln('$name: ${specialScenarios[name]}');
  return switch (name) {
    'cpu' => _cpu(session),
    'scale-manual' => _scaleManual(session),
    'scale-auto' => _scaleAuto(session),
    'overload-concurrent' => _overloadConcurrent(session),
    'overload-connections' => _overloadConnections(session),
    'slow-headers' => _slowHeaders(session),
    'slow-body' => _slowBody(session),
    'big-body' => _bigBody(session),
    _ => throw ArgumentError.value(name, 'name', 'not a special scenario'),
  };
}

// --- Timelines --------------------------------------------------------------

// What one isolate answers a second when it is full: two seconds as fast
// as the connections go.
Future<double> _capacity(LoadSession session) async {
  final oha = await session.oha(
    timelineScenario,
    duration: const Duration(seconds: 2),
    connections: session.options.connections,
  );
  final capacity = oha.seconds == 0 ? 0.0 : oha.responses / oha.seconds;
  if (capacity < 1) {
    throw StateError('The server answered nothing: no capacity to load.');
  }
  stdout.writeln(
    '  one isolate takes about ${capacity.round()} QPS on '
    '${timelineScenario.request}',
  );
  return capacity;
}

final class _Timeline {
  _Timeline(this.session, this.name);

  final LoadSession session;
  final String name;
  final DateTime started = DateTime.now();
  final _clock = Stopwatch()..start();
  final windows = <TimelineWindow>[];
  final events = <TimelineEvent>[];

  double get now => _clock.elapsedMicroseconds / 1000000;

  void event(String what) {
    events.add((at: now, what: what));
    stdout.writeln('    ${now.toStringAsFixed(1)} s: $what');
  }

  Future<void> window(String phase, int rate) async {
    final options = session.options;
    final start = now;
    final oha = await session.oha(
      timelineScenario,
      duration: options.window,
      connections: options.connections,
      rate: rate,
      raw: '$name-${windows.length}',
    );
    final state = await session.server!.isolates(
      timeout: const Duration(seconds: 1),
    );
    final window = TimelineWindow(
      start: start,
      phase: phase,
      isolates: state?['count'] as int?,
      step: StepResult.of(
        oha,
        timelineScenario,
        thresholds: options.thresholds,
        rate: rate,
        concurrency: options.connections,
      ),
    );
    windows.add(window);
    stdout.writeln(
      '${stepLine(window.step, label: '${start.toStringAsFixed(1)} s')}'
      '  ${window.isolates ?? '?'} isolates  ($phase)',
    );
  }

  // The server's own account of its pool, from its log.
  Future<({List<TimelineEvent> events, List<ScalingStep> steps})> log() async {
    // What the server printed last reaches the file a moment later.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final file = session.server!.log;
    return parseScalingLog(
      file.existsSync() ? file.readAsStringSync() : '',
      started,
    );
  }

  Json json({
    required Json settings,
    required Json summary,
    required List<TimelineEvent> logged,
    required List<ScalingStep> steps,
  }) => {
    'name': name,
    'title': specialScenarios[name],
    'kind': 'timeline',
    'request': timelineScenario.request,
    'settings': settings,
    'windows': [for (final window in windows) window.toJson()],
    'events': [
      for (final event in [
        ...events,
        ...logged,
      ]..sort((a, b) => a.at.compareTo(b.at)))
        {'at': event.at, 'what': event.what},
    ],
    'steps': [
      for (final step in steps)
        {
          'at': step.at,
          'from': step.from,
          'to': step.to,
          'reason': step.reason,
        },
    ],
    'summary': summary,
  };
}

// More than one isolate takes, and less than the pool takes when the
// requests spread unevenly over its isolates.
const _overload = 1.5;

Future<Json> _scaleManual(LoadSession session) async {
  final options = session.options;
  final to = options.scaleTo;
  final arguments = [
    '--server.isolates.count=1',
    '--server.isolates.max=$to',
    // A drain that hangs is cut within the timeline, and seen.
    '--server.isolates.drain-timeout=10s',
    ..._isolateLogs,
  ];
  final server = await session.start(
    arguments: arguments,
    log: 'server-scale-manual',
  );
  final capacity = await _capacity(session);
  final rate = (capacity * _overload).round();
  final timeline = _Timeline(session, 'scale-manual');

  for (var i = 0; i < 3; i++) {
    await timeline.window('one isolate', rate);
  }

  // Asked in the middle of a window, while its connections are open and
  // its requests in flight; the answer comes when the new isolates serve
  // (or the others take no more).
  double? upAsked;
  double? upDone;
  double? downAsked;
  double? downDone;
  var pending = false;
  void scale(int count, String done, void Function(double?, double?) at) {
    pending = true;
    unawaited(() async {
      await Future<void>.delayed(options.window ~/ 2);
      final asked = timeline.now;
      timeline.event('asked for $count isolates');
      at(asked, null);
      final answer = await server.scaleTo(count);
      timeline.event(
        answer == null
            ? 'no answer to the scaling call'
            : '$done ($answer serving)',
      );
      at(asked, answer == null ? null : timeline.now);
      pending = false;
    }());
  }

  scale(to, 'the call returned: the new isolates serve', (asked, done) {
    upAsked = asked;
    upDone = done;
  });
  for (var i = 0; i < 8 && (pending || i < 1); i++) {
    await timeline.window('scaling up', rate);
  }
  for (var i = 0; i < 3; i++) {
    await timeline.window('$to isolates', rate);
  }

  scale(1, 'the call returned: the others take no more', (asked, done) {
    downAsked = asked;
    downDone = done;
  });
  for (var i = 0; i < 8 && (pending || i < 1); i++) {
    await timeline.window('scaling down', rate);
  }
  for (var i = 0; i < 2; i++) {
    await timeline.window('one isolate again', rate);
  }

  final log = await timeline.log();
  return timeline.json(
    settings: {
      'capacityQps': capacity,
      'rate': rate,
      'scaleTo': to,
      'windowSeconds': options.window.inMilliseconds / 1000,
      'serverArgs': arguments,
    },
    summary: summarizeManual(
      timeline.windows,
      upAsked: upAsked ?? timeline.now,
      upDone: upDone,
      downAsked: downAsked ?? timeline.now,
      downDone: downDone,
      thresholds: options.thresholds,
    ),
    logged: log.events,
    steps: log.steps.isEmpty ? scalingSteps(timeline.windows) : log.steps,
  );
}

/// The ramp of `scale-auto`: the rate as a share of what one isolate
/// takes, for how many windows.
const List<({double share, int windows, String phase})> autoRamp = [
  (share: 0.5, windows: 2, phase: 'half of one isolate'),
  (share: _overload, windows: 6, phase: 'overload'),
  (share: 0.3, windows: 12, phase: 'relief'),
];

/// The thresholds `scale-auto` gives the server's scaling policy, short
/// enough for a timeline of under a minute: late for 2 s to grow (the
/// default is 5 s), free for 6 s to shrink (2 min), 4 s between two steps
/// (15 s). The lag that means late stays the default (10 ms).
const autoThresholds = [
  '--server.isolates.scale-up-after=2s',
  '--server.isolates.scale-down-after=6s',
  '--server.isolates.cooldown=4s',
];

Future<Json> _scaleAuto(LoadSession session) async {
  final options = session.options;
  final arguments = [
    '--server.isolates.scaling=auto',
    '--server.isolates.count=1',
    '--server.isolates.max=${options.scaleTo}',
    ...autoThresholds,
    '--server.isolates.drain-timeout=10s',
    ..._isolateLogs,
  ];
  await session.start(arguments: arguments, log: 'server-scale-auto');
  final capacity = await _capacity(session);
  // The measure itself loaded the isolate: the policy may have grown
  // the pool already. Let it settle before the ramp.
  await Future<void>.delayed(const Duration(seconds: 2));
  final timeline = _Timeline(session, 'scale-auto');
  for (final level in autoRamp) {
    for (var i = 0; i < level.windows; i++) {
      await timeline.window(level.phase, (capacity * level.share).round());
    }
  }
  final log = await timeline.log();
  final steps = log.steps.isEmpty ? scalingSteps(timeline.windows) : log.steps;
  return timeline.json(
    settings: {
      'capacityQps': capacity,
      'ramp': [
        for (final level in autoRamp)
          '${level.windows} windows at ${plain(level.share * 100)} %',
      ],
      'windowSeconds': options.window.inMilliseconds / 1000,
      'serverArgs': arguments,
    },
    summary: summarizeAuto(
      timeline.windows,
      steps,
      capacity: capacity,
      thresholds: options.thresholds,
    ),
    logged: log.events,
    steps: steps,
  );
}

// --- CPU --------------------------------------------------------------------

Future<Json> _cpu(LoadSession session) async {
  final options = session.options;
  final server = await session.start(log: 'server-cpu');
  // How many rounds take about 25 ms on this machine.
  const target = Duration(milliseconds: 25);
  const sample = 400;
  var fastest = 1 << 62;
  for (var i = 0; i < 4; i++) {
    final answer = await server.get('/cpu/inline?rounds=$sample');
    if (answer != null) {
      final micros = (jsonDecode(answer) as Map)['micros']! as int;
      fastest = micros < fastest ? micros : fastest;
    }
  }
  if (fastest == 1 << 62) {
    throw StateError('The server did not answer GET /cpu/inline.');
  }
  final rounds = (sample * target.inMicroseconds / fastest).round().clamp(
    10,
    1000000,
  );
  // Half of one core: the isolate is busy, not overloaded.
  const rate = 20;
  const probeRate = 100;
  stdout.writeln(
    '  $rounds rounds of SHA-256 take about ${target.inMilliseconds} ms; '
    '$rate requests a second, a probe of $probeRate a second beside them',
  );

  final variants = <Json>[];
  final steps = <String, ({StepResult work, StepResult probe})>{};
  final most = <String, double>{};
  for (final variant in ['inline', 'task']) {
    final work = Scenario(
      'cpu-$variant',
      'CPU work',
      path: '/cpu/$variant?rounds=$rounds',
    );
    final results = await Future.wait([
      session.oha(
        work,
        duration: options.duration,
        connections: 8,
        rate: rate,
        raw: 'cpu-$variant',
      ),
      session.oha(
        probeScenario,
        duration: options.duration,
        connections: 4,
        rate: probeRate,
        raw: 'cpu-$variant-probe',
      ),
    ]);
    StepResult step(OhaResult oha, Scenario scenario, int rate) =>
        StepResult.of(
          oha,
          scenario,
          thresholds: options.thresholds,
          rate: rate,
          concurrency: 8,
        );
    final workStep = step(results[0], work, rate);
    final probeStep = step(results[1], probeScenario, probeRate);
    final throughput = await session.oha(
      work,
      duration: const Duration(seconds: 3),
      connections: 4,
      raw: 'cpu-$variant-most',
    );
    final mostStep = StepResult.of(
      throughput,
      work,
      thresholds: options.thresholds,
      concurrency: 4,
    );
    steps[variant] = (work: workStep, probe: probeStep);
    most[variant] = mostStep.qps;
    stdout
      ..writeln(stepLine(workStep, label: variant))
      ..writeln(stepLine(probeStep, label: 'probe'))
      ..writeln(
        '       most  ${mostStep.qps.toStringAsFixed(1)} qps on 4 '
        'connections',
      );
    variants.add({
      'name': variant,
      'work': workStep.toJson(),
      'probe': probeStep.toJson(),
      'throughput': mostStep.toJson(),
    });
  }
  final expectations = judgeCpu(
    inlineProbe: steps['inline']!.probe,
    taskProbe: steps['task']!.probe,
    inlineWork: steps['inline']!.work,
    taskWork: steps['task']!.work,
    inlineThroughput: most['inline'],
    taskThroughput: most['task'],
    thresholds: options.thresholds,
  );
  return _checked(
    'cpu',
    expectations,
    {
      'rounds': rounds,
      'work': 'about ${target.inMilliseconds} ms of SHA-256 a request',
      'rate': '$rate/s',
      'probe': '${probeScenario.request} at $probeRate/s',
    },
    {'variants': variants},
  );
}

// --- Checks -----------------------------------------------------------------

Json _checked(
  String name,
  List<Expectation> expectations,
  Json settings,
  Json measures,
) {
  final result = verdict(expectations);
  for (final expectation in expectations) {
    final mark = switch (expectation.ok) {
      true => 'ok  ',
      false => 'FAIL',
      _ => 'info',
    };
    stdout.writeln('  $mark  ${expectation.name}: ${expectation.actual}');
  }
  stdout.writeln('  => ${result.toUpperCase()}');
  return {
    'name': name,
    'title': specialScenarios[name],
    'kind': 'check',
    'verdict': result,
    'settings': settings,
    'expectations': [for (final e in expectations) e.toJson()],
    ...measures,
  };
}

// A probe may be refused where the server is at a limit that counts its
// requests too.
const _refusableProbe = Scenario(
  'probe',
  'Probe',
  path: '/text',
  expected: {200, 503},
);

StepResult _probeStep(LoadSession session, OhaResult oha, Scenario scenario) =>
    StepResult.of(
      oha,
      scenario,
      thresholds: session.options.thresholds,
      rate: _probeRate,
      concurrency: 2,
    );

const _probeRate = 20;

Future<OhaResult> _probe(
  LoadSession session,
  Scenario scenario,
  Duration duration,
  String raw,
) => session.oha(
  scenario,
  duration: duration,
  connections: 2,
  rate: _probeRate,
  raw: raw,
);

// The headers of a refusal, asked for while the load runs: a request of
// the tool's own until one is answered 503.
Future<Map<String, String?>?> _refusal(
  BenchServer server,
  String path,
  Duration during,
) async {
  final watch = Stopwatch()..start();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  while (watch.elapsed < during - const Duration(milliseconds: 500)) {
    final answer = await server.head(
      path,
      headers: const ['retry-after', 'connection'],
    );
    if (answer?.status == 503) {
      return answer!.headers;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return null;
}

Json _split(LatencySplit? split) => {
  'p50': split?.p50 == null ? null : split!.p50!.inMicroseconds / 1000,
  'p99': split?.p99 == null ? null : split!.p99!.inMicroseconds / 1000,
};

Future<Json> _overloadConcurrent(LoadSession session) async {
  final options = session.options;
  const limit = 8;
  const handler = Duration(milliseconds: 50);
  const rate = 600;
  const connections = 64;
  final arguments = ['--server.max-concurrent-requests=$limit'];
  final server = await session.start(
    arguments: arguments,
    log: 'server-overload-concurrent',
  );
  final slow = Scenario(
    'slow',
    'Slow',
    path: '/slow?ms=${handler.inMilliseconds}',
    expected: const {200, 503},
  );
  final load = session.oha(
    slow,
    duration: options.duration,
    connections: connections,
    rate: rate,
    raw: 'overload-concurrent',
    successBreakdown: true,
  );
  final probe = _probe(
    session,
    _refusableProbe,
    options.duration,
    'overload-concurrent-probe',
  );
  final refusal = await _refusal(server, slow.path, options.duration);
  final oha = await load;
  final step = StepResult.of(
    oha,
    slow,
    thresholds: options.thresholds,
    rate: rate,
    concurrency: connections,
  );
  final probeStep = _probeStep(session, await probe, _refusableProbe);
  final recovery = await session.recovery();
  return _checked(
    'overload-concurrent',
    [
      ...judgeConcurrent(
        step,
        successful: oha.successful,
        notSuccessful: oha.notSuccessful,
        limit: limit,
        handler: handler,
        retryAfter: refusal?['retry-after'],
        thresholds: options.thresholds,
      ),
      probeExpectation(probeStep, options.thresholds, mayRefuse: true),
      recoveryExpectation(recovery),
    ],
    {
      'server': arguments.join(' '),
      'load': '${slow.request} at $rate/s on $connections connections',
    },
    {
      'load': {
        ...step.toJson(),
        'successfulMs': _split(oha.successful),
        'notSuccessfulMs': _split(oha.notSuccessful),
      },
      'probe': probeStep.toJson(),
    },
  );
}

Future<Json> _overloadConnections(LoadSession session) async {
  final options = session.options;
  const limit = 16;
  const rate = 400;
  const connections = 64;
  final arguments = ['--server.max-connections=$limit'];
  final server = await session.start(
    arguments: arguments,
    log: 'server-overload-connections',
  );
  const text = Scenario('text', 'Text', path: '/text', expected: {200, 503});
  final load = session.oha(
    text,
    duration: options.duration,
    connections: connections,
    rate: rate,
    raw: 'overload-connections',
    successBreakdown: true,
  );
  final probe = _probe(
    session,
    _refusableProbe,
    options.duration,
    'overload-connections-probe',
  );
  final refusal = await _refusal(server, text.path, options.duration);
  final oha = await load;
  final step = StepResult.of(
    oha,
    text,
    thresholds: options.thresholds,
    rate: rate,
    concurrency: connections,
  );
  final probeStep = _probeStep(session, await probe, _refusableProbe);
  final recovery = await session.recovery();
  return _checked(
    'overload-connections',
    [
      ...judgeConnections(
        step,
        successful: oha.successful,
        notSuccessful: oha.notSuccessful,
        limit: limit,
        connections: connections,
        retryAfter: refusal?['retry-after'],
        connection: refusal?['connection'],
        thresholds: options.thresholds,
      ),
      probeExpectation(probeStep, options.thresholds, mayRefuse: true),
      recoveryExpectation(recovery),
    ],
    {
      'server': arguments.join(' '),
      'load': '${text.request} at $rate/s on $connections connections',
    },
    {
      'load': {
        ...step.toJson(),
        'successfulMs': _split(oha.successful),
        'notSuccessfulMs': _split(oha.notSuccessful),
      },
      'probe': probeStep.toJson(),
    },
  );
}

// The connection timeout of the slow checks, and how long they watch: a
// connection dart:io calls idle goes between one and two timeouts.
const _slowTimeout = Duration(seconds: 2);
const _slowWatch = Duration(seconds: 7);

// A stalled body is answered after the timeout, and its connection kept
// for up to 5 s more (the web starter reads on for a body that ends
// late): watched longer.
const _bodyWatch = Duration(seconds: 11);

Json _client(ClientResult result) => {
  'status': result.status,
  'answeredAfterMs': result.answeredAfter?.inMilliseconds,
  'closedAfterMs': result.closedAfter?.inMilliseconds,
  'bytesSent': result.bytesSent,
  'sentAll': result.sentAll,
};

Future<Json> _slowHeaders(LoadSession session) async {
  const clients = 200;
  final arguments = [
    '--server.connection-timeout=${_slowTimeout.inSeconds}s',
  ];
  final server = await session.start(
    arguments: arguments,
    log: 'server-slow-headers',
  );
  final sampler = MemorySampler(server.pid);
  await sampler.start();
  final probe = _probe(
    session,
    probeScenario,
    _slowWatch,
    'slow-headers-probe',
  );
  final results = await Future.wait([
    for (var i = 0; i < clients; i++)
      slowRequest(
        server.port,
        head: 'GET /text HTTP/1.1\r\nHost: bench\r\n',
        pace: Pace.trickle,
        drip: 'X-Slow-$i: a\r\n',
        watch: _slowWatch,
      ),
  ]);
  final memory = await sampler.stop();
  final probeStep = _probeStep(session, await probe, probeScenario);
  final recovery = await session.recovery();
  return _checked(
    'slow-headers',
    [
      ...judgeSlowHeaders(
        results,
        timeout: _slowTimeout,
        memoryGrowth: memory == null ? null : memory.peak - memory.start,
      ),
      probeExpectation(probeStep, session.options.thresholds),
      recoveryExpectation(recovery),
    ],
    {
      'server': arguments.join(' '),
      'clients':
          '$clients connections, a header line every half second, '
          'watched for ${_slowWatch.inSeconds} s',
    },
    {
      'clients': [for (final result in results) _client(result)],
      'rssBytes': memory == null
          ? null
          : {'start': memory.start, 'peak': memory.peak, 'end': memory.end},
      'probe': probeStep.toJson(),
    },
  );
}

Future<Json> _slowBody(LoadSession session) async {
  const each = 4;
  const declared = 1024 * 1024;
  final arguments = [
    '--server.connection-timeout=${_slowTimeout.inSeconds}s',
  ];
  final server = await session.start(
    arguments: arguments,
    log: 'server-slow-body',
  );
  final head =
      'PUT /upload/raw HTTP/1.1\r\nHost: bench\r\n'
      'Content-Type: application/octet-stream\r\n'
      'Content-Length: $declared\r\n\r\n${'x' * 1024}';
  final probe = _probe(session, probeScenario, _bodyWatch, 'slow-body-probe');
  Future<List<ClientResult>> send(Pace pace) => Future.wait([
    for (var i = 0; i < each; i++)
      slowRequest(
        server.port,
        head: head,
        pace: pace,
        drip: 'x',
        watch: _bodyWatch,
      ),
  ]);
  final results = await Future.wait([send(Pace.stall), send(Pace.trickle)]);
  final probeStep = _probeStep(session, await probe, probeScenario);
  final recovery = await session.recovery();
  return _checked(
    'slow-body',
    [
      ...judgeSlowBody(
        stalled: results[0],
        trickled: results[1],
        timeout: _slowTimeout,
        watched: _bodyWatch,
      ),
      probeExpectation(probeStep, session.options.thresholds),
      recoveryExpectation(recovery),
    ],
    {
      'server': arguments.join(' '),
      'clients':
          '$each requests whose body stalls after 1 KB of '
          '${declared ~/ 1024} KB, $each that send a byte every half '
          'second, watched for ${_bodyWatch.inSeconds} s',
    },
    {
      'stalled': [for (final result in results[0]) _client(result)],
      'trickled': [for (final result in results[1]) _client(result)],
      'probe': probeStep.toJson(),
    },
  );
}

Future<Json> _bigBody(LoadSession session) async {
  const limit = 1024 * 1024;
  const floodBytes = 256 * 1024 * 1024;
  const watch = Duration(seconds: 3);
  final arguments = ['--server.max-http-request-body-size=1MB'];
  final server = await session.start(
    arguments: arguments,
    log: 'server-big-body',
  );
  final sampler = MemorySampler(server.pid);
  await sampler.start();
  final probe = _probe(session, probeScenario, watch * 3, 'big-body-probe');
  const head =
      'POST /json HTTP/1.1\r\nHost: bench\r\n'
      'Content-Type: application/json\r\n';
  const announcedHead = '${head}Content-Length: $floodBytes\r\n\r\n';
  final announced = await slowRequest(
    server.port,
    head: announcedHead,
    pace: Pace.stall,
    watch: watch,
  );
  final chunked = await slowRequest(
    server.port,
    head: '${head}Transfer-Encoding: chunked\r\n\r\n',
    pace: Pace.flood,
    body: 2 * limit,
    chunked: true,
    endChunks: false,
    watch: watch,
  );
  final flood = await slowRequest(
    server.port,
    head: announcedHead,
    pace: Pace.flood,
    body: floodBytes,
    watch: watch,
  );
  final probeStep = _probeStep(session, await probe, probeScenario);
  final memory = await sampler.stop();
  final recovery = await session.recovery();
  return _checked(
    'big-body',
    [
      ...judgeBigBody(
        announced: announced,
        chunked: chunked,
        flood: flood,
        limit: limit,
        floodBytes: floodBytes,
        memoryGrowth: memory == null ? null : memory.peak - memory.start,
      ),
      probeExpectation(probeStep, session.options.thresholds),
      recoveryExpectation(recovery),
    ],
    {
      'server': arguments.join(' '),
      'clients':
          'POST /json: the headers of ${floodBytes ~/ limit} MB; '
          '${2 * limit ~/ limit} MB in chunks; ${floodBytes ~/ limit} MB '
          'sent as fast as it goes',
    },
    {
      'announced': _client(announced),
      'chunked': _client(chunked),
      'flood': _client(flood),
      'rssBytes': memory == null
          ? null
          : {'start': memory.start, 'peak': memory.peak, 'end': memory.end},
      'probe': probeStep.toJson(),
    },
  );
}
