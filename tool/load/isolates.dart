// The isolates of the server in the reports of tool/load.dart: which of
// them answered during a scenario, and how the throughput grows with
// their number (`--isolates 1,2,4`). Pure functions.
import 'format.dart';
import 'report.dart';

/// An isolate that took less than this share of the requests did not
/// serve: it answered the tool's own questions at most.
const servedShare = 0.01;

/// The requests each serving isolate has taken, from an answer of the
/// bench server's `GET /bench/isolates` (the rows of the server's
/// isolates; those of the task executor have no requests).
Map<String, int> requestsByIsolate(Json state) => {
  for (final load in jsonList(state['loads']))
    if (jsonMap(load['details'])['requests'] case final num requests)
      load['name']! as String: requests.toInt(),
};

/// Which isolates answered between two answers of `GET /bench/isolates`:
/// the pool's size (`count`), how many took a real share of the requests
/// (`served`) and the share of each (`shares`), for report.json.
///
/// [before] and [after] are [requestsByIsolate] at both ends; `null` when
/// the server did not say (too busy to answer in time).
Json isolatesServed(
  Map<String, int>? before,
  Map<String, int>? after, {
  int? count,
}) {
  if (before == null || after == null) {
    return {'count': count, 'served': null, 'shares': const <String, num>{}};
  }
  final taken = {
    for (final MapEntry(key: name, value: requests) in after.entries)
      name: requests - (before[name] ?? 0),
  };
  final total = taken.values.fold(0, (sum, requests) => sum + requests);
  final shares = {
    for (final MapEntry(key: name, value: requests) in taken.entries)
      name: total == 0 ? 0.0 : requests / total,
  };
  return {
    'count': count,
    'served': shares.values.where((share) => share >= servedShare).length,
    'shares': shares,
  };
}

/// A sustainable QPS that grew by less than this over the run with fewer
/// isolates is no longer scaling.
const scalingGain = 1.1;

/// One run of the isolates matrix for one scenario.
typedef ScalingPoint = ({
  String label,
  int isolates,
  int? served,
  double? sustainable,
  double? peak,
  bool capped,
  String breaking,
});

/// The runs of [reports] that have the scenario [name], by their number
/// of isolates, rising.
///
/// A run is `capped` when its last step was sustained: the rates tried
/// were too low to find what it sustains, so its number is a floor and
/// its efficiency says nothing.
List<ScalingPoint> scalingPoints(List<Json> reports, String name) {
  final points = <ScalingPoint>[];
  for (final (index, report) in reports.indexed) {
    final scenario = jsonList(
      report['scenarios'],
    ).where((scenario) => scenario['name'] == name).firstOrNull;
    if (scenario == null) {
      continue;
    }
    final summary = jsonMap(scenario['summary']);
    final steps = jsonList(scenario['steps']);
    final rate = scenario['kind'] == 'rate';
    final served = jsonMap(scenario['isolates']);
    points.add((
      label: switch (report['label']) {
        final String label when label.isNotEmpty => label,
        _ => 'run ${index + 1}',
      },
      isolates:
          (served['count'] ?? jsonMap(report['isolates'])['count'] ?? 1) as int,
      served: served['served'] as int?,
      sustainable:
          ((rate
                      ? summary['sustainableQps']
                      : summary['peakMegabytesPerSecond'])
                  as num?)
              ?.toDouble(),
      peak:
          ((rate ? summary['peakQps'] : summary['peakMegabytesPerSecond'])
                  as num?)
              ?.toDouble(),
      capped: steps.isNotEmpty && steps.last['sustained'] == true,
      breaking: breakingCell(scenario, rate ? '/s' : ' connections'),
    ));
  }
  return points..sort((a, b) => a.isolates.compareTo(b.isolates));
}

/// How much of the ideal a run with [isolates] isolates reaches:
/// `value / (isolates / baseIsolates * base)`, against the run with the
/// fewest isolates (one as a rule); `null` where a value is missing.
double? efficiency(
  double? value,
  int isolates,
  double? base,
  int baseIsolates,
) => value == null || base == null || base == 0
    ? null
    : value / (isolates / baseIsolates * base);

/// Where the throughput of [points] stops growing with the isolates: the
/// first run whose peak is less than [scalingGain] times the one before.
/// `null` when every run gained (or there is nothing to compare).
ScalingPoint? stopsScalingAt(List<ScalingPoint> points) {
  for (var i = 1; i < points.length; i++) {
    final before = points[i - 1].peak;
    final now = points[i].peak;
    if (before != null && now != null && now < scalingGain * before) {
      return points[i];
    }
  }
  return null;
}

/// The Markdown of the isolates matrix: for each scenario its throughput
/// by number of isolates, the ratio to the run with the fewest, the
/// scaling efficiency and where it stops scaling.
String renderScaling(List<Map<String, Object?>> reports) {
  final names = <String>[];
  for (final report in reports) {
    for (final scenario in jsonList(report['scenarios'])) {
      final name = scenario['name']! as String;
      if (scenario.containsKey('steps') && !names.contains(name)) {
        names.add(name);
      }
    }
  }
  final out = StringBuffer()
    ..writeln('# Load by isolates')
    ..writeln()
    ..writeln(
      '**Sustainable** is the highest sustainable QPS (for a transfer '
      'scenario, the peak MB/s); it moves in the steps of the rates '
      'tried. **Peak** is the most good answers a second of any step, the '
      'overloaded one included: what the server puts out when it is '
      'full. **×** is the ratio to the run with the fewest isolates, and '
      '**efficiency** that ratio over the ratio of the isolates: 100 % is '
      'twice the throughput for twice the isolates. **Served** is how '
      'many isolates took at least ${plain(servedShare * 100)} % of the '
      'requests. A value with ≥ was sustained at the highest rate tried: '
      'raise the rates to find its limit.',
    )
    ..writeln()
    ..writeln('> $noiseNote')
    ..writeln()
    ..writeln('| Run | Machine |')
    ..writeln('|---|---|');
  for (final (index, report) in reports.indexed) {
    final label = switch (report['label']) {
      final String label when label.isNotEmpty => label,
      _ => 'run ${index + 1}',
    };
    out.writeln('| $label | ${machineLine(report)} |');
  }
  out.writeln();

  final stops = <String>[];
  for (final name in names) {
    final points = scalingPoints(reports, name);
    if (points.isEmpty) {
      continue;
    }
    final base = points.first;
    out
      ..writeln('## $name')
      ..writeln()
      ..writeln(
        '| Isolates | Served | Sustainable | × | Efficiency | Peak | × '
        '| Efficiency | Breaking point |',
      )
      ..writeln('|---:|---:|---:|---:|---:|---:|---:|---:|---|');
    for (final point in points) {
      String cells(double? value, double? from) {
        final share = efficiency(value, point.isolates, from, base.isolates);
        return '${value == null ? 'none' : plain(value)} '
            '| ${ratio(value, from)} | ${percent(share)}';
      }

      out.writeln(
        '| ${point.isolates} '
        '| ${point.served ?? '-'} '
        '| ${point.capped ? '≥ ' : ''}'
        '${cells(point.sustainable, base.sustainable)} '
        '| ${cells(point.peak, base.peak)} '
        '| ${point.breaking} |',
      );
    }
    out.writeln();
    final notes = <String>[
      for (final point in points)
        if (point.served != null && point.served != point.isolates)
          _notServed(point),
      if (points.any((point) => point.capped)) _cappedNote,
    ];
    final stop = stopsScalingAt(points);
    final line = points.length < 2
        ? 'One run: nothing to compare.'
        : stop == null
        ? 'Still scaling at ${points.last.isolates} isolates, the most '
              'tried.'
        : 'Stops scaling at ${stop.isolates} isolates: the peak is less '
              'than ${plain((scalingGain - 1) * 100)} % above the run '
              'before.';
    stops.add('| $name | $line |');
    out
      ..writeln([line, ...notes].join(' '))
      ..writeln();
  }
  out
    ..writeln('## Where it stops scaling')
    ..writeln()
    ..writeln('| Scenario | |')
    ..writeln('|---|---|')
    ..writeln(stops.join('\n'));
  return out.toString();
}

const _cappedNote =
    'A row with ≥ never failed a step: its sustainable value is a floor, '
    'and the efficiency after it means little.';

String _notServed(ScalingPoint point) =>
    '**${point.isolates} isolates ran but ${point.served} served**: this '
    'row does not measure ${point.isolates} isolates.';
