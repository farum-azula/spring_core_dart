// The scaling scenarios of tool/load.dart (`scale-manual`, `scale-auto`):
// a fixed rate in short windows while the number of isolates changes, and
// what the windows say about it. Pure functions; the runs are in
// special_runs.dart.
import 'dart:math' as math;

import 'analysis.dart';
import 'format.dart';

/// One window of a timeline: a few seconds of load at one rate.
final class TimelineWindow {
  /// A window that started [start] seconds into the timeline.
  const TimelineWindow({
    required this.start,
    required this.phase,
    required this.step,
    this.isolates,
  });

  /// Seconds from the start of the timeline.
  final double start;

  /// What the timeline was doing: `one isolate`, `scaling up`...
  final String phase;

  /// What oha measured in the window.
  final StepResult step;

  /// The isolates serving at the end of the window; `null` when the
  /// server was too busy to say.
  final int? isolates;

  /// When the window ended.
  double get end => start + step.seconds;

  /// The rate asked for.
  int get rate => step.rate ?? 0;

  /// The requests that failed: timeouts, refused or broken connections,
  /// unexpected statuses.
  int get errors => step.requests - step.ok;

  /// Whether the server kept up with the window's rate: it answered at
  /// least 95 % of it, within the p99 of [thresholds], with errors under
  /// its limit.
  bool keptUp(Thresholds thresholds) =>
      step.qps >= 0.95 * rate &&
      step.p99 != null &&
      step.p99! <= thresholds.p99 &&
      step.errorRate < thresholds.errorRate;

  /// For report.json.
  Map<String, Object?> toJson() => {
    'start': start,
    'phase': phase,
    'isolates': isolates,
    ...step.toJson(),
  };
}

/// A change of the pool's size: when (seconds into the timeline), from
/// how many isolates to how many, and why (the server's words).
typedef ScalingStep = ({double at, int from, int to, String reason});

/// Something that happened during a timeline, for the report.
typedef TimelineEvent = ({double at, String what});

/// The lines the server's pool logged (`spring.web.isolates`, at info):
/// every one as an event, and the `Scaling 1 → 2 isolates (reason)` ones
/// as steps. [start] is when the timeline began; lines before it (the
/// start of the server) are left out.
({List<TimelineEvent> events, List<ScalingStep> steps}) parseScalingLog(
  String log,
  DateTime start,
) {
  final line = RegExp(
    r'^(\d{4}-\d\d-\d\dT[\d:.]+(?:Z|[+-]\d\d:\d\d))\s.*?'
    r'spring\.web\.isolates\s*:\s*(.*)$',
    multiLine: true,
  );
  final scaling = RegExp(r'^Scaling (\d+) → (\d+) isolates \((.*)\)$');
  final events = <TimelineEvent>[];
  final steps = <ScalingStep>[];
  for (final match in line.allMatches(log)) {
    final time = DateTime.tryParse(match[1]!);
    if (time == null || time.isBefore(start)) {
      continue;
    }
    final at = time.difference(start).inMilliseconds / 1000;
    final text = match[2]!.trim();
    events.add((at: at, what: text));
    if (scaling.firstMatch(text) case final step?) {
      steps.add((
        at: at,
        from: int.parse(step[1]!),
        to: int.parse(step[2]!),
        reason: step[3]!,
      ));
    }
  }
  return (events: events, steps: steps);
}

/// The steps the windows show when the server's log has none: a step at
/// the end of each window whose number of isolates differs from the one
/// before (to the window's length, so two seconds late at most).
List<ScalingStep> scalingSteps(List<TimelineWindow> windows) {
  final steps = <ScalingStep>[];
  int? before;
  for (final window in windows) {
    final now = window.isolates;
    if (now == null) {
      continue;
    }
    if (before != null && now != before) {
      steps.add((at: window.end, from: before, to: now, reason: 'seen'));
    }
    before = now;
  }
  return steps;
}

/// How often the pool changed direction: growing then shrinking is one
/// change, and what a single peak of load should give. More is flapping.
int directionChanges(List<ScalingStep> steps) {
  var changes = 0;
  int? last;
  for (final step in steps) {
    final direction = (step.to - step.from).sign;
    if (direction == 0) {
      continue;
    }
    if (last != null && direction != last) {
      changes++;
    }
    last = direction;
  }
  return changes;
}

int _errors(Iterable<TimelineWindow> windows) =>
    windows.fold<int>(0, (sum, window) => sum + window.errors);

double? _mean(Iterable<double> values) =>
    values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

double? _worstP99(Iterable<TimelineWindow> windows) {
  final all = [
    for (final window in windows)
      if (window.step.p99 case final p99?) p99.inMicroseconds / 1000,
  ];
  return all.isEmpty ? null : all.reduce(math.max);
}

/// What `scale-manual` shows: the pool is asked to grow at [upAsked]
/// (seconds into the timeline; the call returned at [upDone]) and to
/// shrink back at [downAsked] (returned at [downDone]), all under the
/// same rate.
///
/// - `before`, `scaled`, `after`: the mean QPS and the worst p99 of the
///   windows with one isolate, with all of them, and with one again;
/// - `dipPercent`: how far the QPS of the worst window during the scaling
///   call fell under `before`;
/// - `helpedAfterSeconds`: from the call to the start of the first window
///   that kept up with the rate ([TimelineWindow.keptUp]);
/// - `drainErrors`: the requests that failed in the windows touched by
///   the scaling down.
Map<String, Object?> summarizeManual(
  List<TimelineWindow> windows, {
  required double upAsked,
  required double? upDone,
  required double downAsked,
  required double? downDone,
  required Thresholds thresholds,
}) {
  final last = windows.isEmpty ? 0.0 : windows.last.end;
  final upEnd = upDone ?? downAsked;
  final downEnd = downDone ?? last;
  bool touches(TimelineWindow window, double from, double to) =>
      window.end > from && window.start < to;

  final before = windows.where((window) => window.end <= upAsked);
  final during = windows.where((window) => touches(window, upAsked, upEnd));
  final scaled = windows.where(
    (window) => window.start >= upEnd && window.end <= downAsked,
  );
  final draining = windows.where(
    (window) => touches(window, downAsked, downEnd),
  );
  final after = windows.where((window) => window.start >= downEnd);

  Map<String, Object?> part(Iterable<TimelineWindow> windows) => {
    'windows': windows.length,
    'qps': _mean(windows.map((window) => window.step.qps)),
    'p99Ms': _worstP99(windows),
    'errors': _errors(windows),
  };

  final beforeQps = _mean(before.map((window) => window.step.qps));
  final lowest = during.isEmpty
      ? null
      : during.map((window) => window.step.qps).reduce(math.min);
  final helped = windows
      .where((window) => window.end > upAsked && window.start < downAsked)
      .where((window) => window.keptUp(thresholds))
      .firstOrNull;
  return {
    'before': part(before),
    'scalingUp': part(during),
    'scaled': part(scaled),
    'scalingDown': part(draining),
    'after': part(after),
    'scaleUpSeconds': upDone == null ? null : upDone - upAsked,
    'scaleDownSeconds': downDone == null ? null : downDone - downAsked,
    'dipPercent': beforeQps == null || lowest == null || beforeQps == 0
        ? null
        : math.max(0, (1 - lowest / beforeQps) * 100),
    'helpedAfterSeconds': helped == null
        ? null
        : math.max(0, helped.start - upAsked),
    'drainErrors': _errors(draining),
    'errors': _errors(windows),
  };
}

/// What `scale-auto` shows, from the windows of a ramp and the [steps]
/// of the pool. [capacity] is the QPS one isolate takes: a window that
/// asks for more is overload.
///
/// - `overloadAtSeconds`: the start of the first window above [capacity];
/// - `firstScaleUpAfterSeconds`: from there to the first step up;
/// - `keptUpAfterSeconds`: from there to the start of the first
///   overloaded window the pool kept up with; `null` when it never did;
/// - `relievedAtSeconds`, `firstScaleDownAfterSeconds`,
///   `backToStartAfterSeconds`: the same for the way down;
/// - `directionChanges` and `flapped` (more than one change).
Map<String, Object?> summarizeAuto(
  List<TimelineWindow> windows,
  List<ScalingStep> steps, {
  required double capacity,
  required Thresholds thresholds,
}) {
  final overloaded = windows.where((window) => window.rate > capacity);
  final overloadAt = overloaded.firstOrNull?.start;
  final relievedAt = overloadAt == null
      ? null
      : windows
            .where(
              (window) => window.start > overloadAt && window.rate <= capacity,
            )
            .firstOrNull
            ?.start;
  final ups = steps.where((step) => step.to > step.from);
  final downs = steps.where((step) => step.to < step.from);
  final firstUp = overloadAt == null
      ? null
      : ups.where((step) => step.at >= overloadAt).firstOrNull;
  final keptUp = overloaded
      .where((window) => window.keptUp(thresholds))
      .firstOrNull;
  final firstDown = relievedAt == null
      ? null
      : downs.where((step) => step.at >= relievedAt).firstOrNull;
  final counts = [
    for (final window in windows) ?window.isolates,
    for (final step in steps) ...[step.from, step.to],
  ];
  final start = steps.firstOrNull?.from ?? counts.firstOrNull;
  final back = relievedAt == null || start == null
      ? null
      : downs
            .where((step) => step.at >= relievedAt && step.to <= start)
            .firstOrNull;
  final changes = directionChanges(steps);
  return {
    'overloadAtSeconds': overloadAt,
    'firstScaleUpAfterSeconds': firstUp == null || overloadAt == null
        ? null
        : firstUp.at - overloadAt,
    'keptUpAfterSeconds': keptUp == null || overloadAt == null
        ? null
        : keptUp.start - overloadAt,
    'overloadedWindows': overloaded.length,
    'overloadedWindowsKeptUp': overloaded
        .where((window) => window.keptUp(thresholds))
        .length,
    'mostIsolates': counts.isEmpty ? null : counts.reduce(math.max),
    'relievedAtSeconds': relievedAt,
    'firstScaleDownAfterSeconds': firstDown == null || relievedAt == null
        ? null
        : firstDown.at - relievedAt,
    'backToStartAfterSeconds': back == null || relievedAt == null
        ? null
        : back.at - relievedAt,
    'scaleUps': ups.length,
    'scaleDowns': downs.length,
    'directionChanges': changes,
    'flapped': changes > 1,
    'errors': _errors(windows),
  };
}

/// The Markdown of a timeline scenario of report.json: what was set, the
/// summary, a row per window, the pool's steps and a chart.
String renderTimeline(Json scenario) {
  final settings = jsonMap(scenario['settings']);
  final summary = jsonMap(scenario['summary']);
  final windows = jsonList(scenario['windows']);
  final manual = scenario['name'] == 'scale-manual';
  String seconds(Object? value) => value is num ? '${plain(value)} s' : '-';
  String part(String key) {
    final part = jsonMap(summary[key]);
    return '${number(part['qps'])} QPS, worst p99 '
        '${formatDuration(_duration(part['p99Ms']))}, '
        '${part['errors'] ?? 0} errors (${part['windows'] ?? 0} windows)';
  }

  final arguments = (settings['serverArgs'] as List? ?? const [])
      .map((argument) => '`$argument`')
      .join(' ');
  final out = StringBuffer()
    ..writeln(
      'One isolate takes about ${number(settings['capacityQps'])} QPS '
      'here (measured first, as fast as it goes). Windows of '
      '${number(settings['windowSeconds'])} s, each on new connections, '
      'as new clients would arrive. Server arguments: $arguments.',
    )
    ..writeln();
  if (manual) {
    final helped = summary['helpedAfterSeconds'] == null
        ? '**never**: no window kept up with the rate'
        : 'after ${seconds(summary['helpedAfterSeconds'])} (the start of '
              'the first window that kept up)';
    out
      ..writeln(
        '- **One isolate** at ${number(settings['rate'])}/s: '
        '${part('before')}.',
      )
      ..writeln(
        '- **Scaling to ${settings['scaleTo']}** took '
        '${seconds(summary['scaleUpSeconds'])}; the windows it touched: '
        '${part('scalingUp')}; dip of '
        '${number(summary['dipPercent'])} % under the QPS before.',
      )
      ..writeln('- **The new isolates helped** $helped.')
      ..writeln('- **${settings['scaleTo']} isolates**: ${part('scaled')}.')
      ..writeln(
        '- **Scaling back to one** took '
        '${seconds(summary['scaleDownSeconds'])}: '
        '**${summary['drainErrors']} errors** in the windows it touched '
        '(${part('scalingDown')}).',
      )
      ..writeln('- **One isolate again**: ${part('after')}.');
  } else {
    final keptUp = summary['keptUpAfterSeconds'] == null
        ? '**never kept up** with an overloaded window'
        : 'kept up ${seconds(summary['keptUpAfterSeconds'])} after the '
              'overload began';
    final back = summary['backToStartAfterSeconds'] == null
        ? '**not within the timeline**'
        : '${seconds(summary['backToStartAfterSeconds'])} later';
    final flapped = summary['flapped'] == true
        ? '**it flapped**'
        : 'no flapping';
    out
      ..writeln(
        '- **Overload** (more than one isolate takes) from '
        '${seconds(summary['overloadAtSeconds'])}; first step up '
        '${seconds(summary['firstScaleUpAfterSeconds'])} later; the pool '
        '$keptUp (${summary['overloadedWindowsKeptUp']} of '
        '${summary['overloadedWindows']} overloaded windows kept up), at '
        'most ${summary['mostIsolates'] ?? '-'} isolates.',
      )
      ..writeln(
        '- **Relief** from ${seconds(summary['relievedAtSeconds'])}; first '
        'step down ${seconds(summary['firstScaleDownAfterSeconds'])} '
        'later; back to the start $back.',
      )
      ..writeln(
        '- **${summary['scaleUps']} steps up, ${summary['scaleDowns']} '
        'down, ${summary['directionChanges']} changes of direction**: '
        '$flapped. ${summary['errors']} errors in all.',
      );
  }
  out
    ..writeln()
    ..writeln(
      '| Start (s) | Phase | Rate (/s) | QPS | p50 | p99 | Errors '
      '| Statuses | Isolates |',
    )
    ..writeln('|---:|---|---:|---:|---:|---:|---:|---|---:|');
  for (final window in windows) {
    final latency = jsonMap(window['latencyMs']);
    final codes = jsonMap(window['statusCodes']);
    out.writeln(
      '| ${plain(window['start']! as num)} '
      '| ${window['phase']} '
      '| ${window['rate']} '
      '| ${number(window['qps'])} '
      '| ${formatDuration(_duration(latency['p50']))} '
      '| ${formatDuration(_duration(latency['p99']))} '
      '| ${(window['requests']! as int) - (window['ok']! as int)} '
      '| ${codes.entries.map((e) => '${e.key}: ${e.value}').join(', ')} '
      '| ${window['isolates'] ?? '?'} |',
    );
  }
  final events = jsonList(scenario['events']);
  if (events.isNotEmpty) {
    out
      ..writeln()
      ..writeln('What happened, in seconds from the start:')
      ..writeln();
    for (final event in events) {
      out.writeln('- ${plain(event['at']! as num)} s: ${event['what']}');
    }
  }
  if (windows.isNotEmpty) {
    final top = [
      for (final window in windows) ...[
        (window['qps']! as num).toDouble(),
        (window['rate']! as num).toDouble(),
      ],
    ].reduce(math.max);
    out
      ..writeln()
      ..writeln('```mermaid')
      ..writeln('xychart-beta')
      ..writeln(
        '    title "${scenario['name']}: good answers a second (bars) and '
        'the rate asked for (line), by window"',
      )
      ..writeln(
        '    x-axis "start of the window (s)" '
        '[${windows.map((w) => plain(w['start']! as num)).join(', ')}]',
      )
      ..writeln(
        '    y-axis "requests/s" 0 --> ${math.max(1, (top * 1.1).ceil())}',
      )
      ..writeln(
        '    bar [${windows.map((w) => plain(w['qps']! as num)).join(', ')}]',
      )
      ..writeln('    line [${windows.map((w) => w['rate']).join(', ')}]')
      ..writeln('```');
  }
  return out.toString();
}

Duration? _duration(Object? ms) => ms is num ? milliseconds(ms) : null;
