// report.md and the comparison of several runs, written from report.json
// (the map tool/load.dart builds, or the files `--compare` reads): tables,
// a Mermaid chart of the throughput and a text chart of the p99 latency.
import 'dart:math' as math;

import 'analysis.dart';
import 'checks.dart';
import 'format.dart';
import 'timeline.dart';

/// Why numbers of two machines, or of two days on a shared one, are not
/// compared as they are.
const noiseNote =
    'Numbers depend on the machine, and the load generator runs on it too. '
    'Shared CI runners are noisy: compare ratios between labels of one '
    'run, or a run with the previous one on the same runner type, never '
    'absolute numbers of different machines.';

/// The Markdown of one run: a summary of every scenario, then a table and
/// charts for each.
String renderReport(Map<String, Object?> report) {
  final scenarios = jsonList(report['scenarios']);
  final options = jsonMap(report['options']);
  final thresholds = jsonMap(options['thresholds']);
  final out = StringBuffer()
    ..writeln('# Load report${_labelSuffix(report)}')
    ..writeln()
    ..writeln(machineLine(report))
    ..writeln()
    ..write(_isolatesLine(report))
    ..writeln(
      'Steps of ${number(options['durationSeconds'])} s, '
      '${options['connections']} connections for the rate steps'
      '${options['compiled'] == true ? ', native executable' : ', JIT '
                '(`dart run`: not what a deployed server does)'}.'
      '${_serverArguments(options)}',
    )
    ..writeln()
    ..writeln(
      '**Highest sustainable QPS**: the good answers a second of the last '
      'step, before the first that failed, with a p99 latency of at most '
      '${number(thresholds['p99Ms'])} ms and under '
      '${number((thresholds['errorRate']! as num) * 100)} % of errors. '
      '**Breaking point**: the first step with timeouts, refused or broken '
      'connections, no answer, or a p99 above '
      '${number(thresholds['breakP99Ms'])} ms; "recovered" says whether '
      'the server answered a light request afterwards. Latencies are '
      'corrected for coordinated omission: a request is timed from when '
      'it was due.',
    )
    ..writeln()
    ..writeln('> $noiseNote')
    ..writeln()
    ..writeln('## Summary')
    ..writeln();

  final rates = [
    for (final scenario in scenarios)
      if (scenario['kind'] == 'rate') scenario,
  ];
  final transfers = [
    for (final scenario in scenarios)
      if (scenario['kind'] == 'transfer') scenario,
  ];
  final timelines = [
    for (final scenario in scenarios)
      if (scenario['kind'] == 'timeline') scenario,
  ];
  final checks = [
    for (final scenario in scenarios)
      if (scenario['kind'] == 'check') scenario,
  ];
  if (rates.isNotEmpty) {
    out
      ..writeln(
        '| Scenario | Request | Highest sustainable QPS | Breaking point '
        '| Recovered | Peak RSS |',
      )
      ..writeln('|---|---|---:|---|---|---:|');
    for (final scenario in rates) {
      final summary = jsonMap(scenario['summary']);
      out.writeln(
        '| [${scenario['name']}](#${_anchor(scenario)}) '
        '| `${cell('${scenario['request']}')}` '
        '| ${_sustainable(scenario)} '
        '| ${breakingCell(scenario, '/s')} '
        '| ${recoveredCell(summary)} '
        '| ${megabytes(summary['peakRssBytes'])} |',
      );
    }
    out.writeln();
  }
  if (transfers.isNotEmpty) {
    out
      ..writeln(
        '| Transfer scenario | Request | Peak MB/s | Most connections '
        'without errors | Breaking point | Recovered | Peak RSS |',
      )
      ..writeln('|---|---|---:|---:|---|---|---:|');
    for (final scenario in transfers) {
      final summary = jsonMap(scenario['summary']);
      out.writeln(
        '| [${scenario['name']}](#${_anchor(scenario)}) '
        '| `${cell('${scenario['request']}')}` '
        '| ${number(summary['peakMegabytesPerSecond'])} '
        '| ${summary['sustainableConcurrency'] ?? 'none'} '
        '| ${breakingCell(scenario, ' connections')} '
        '| ${recoveredCell(summary)} '
        '| ${megabytes(summary['peakRssBytes'])} |',
      );
    }
    out.writeln();
  }

  if (checks.isNotEmpty) {
    out
      ..writeln('| Check | Verdict | What failed |')
      ..writeln('|---|---|---|');
    for (final scenario in checks) {
      final failed = [
        for (final expectation in jsonList(scenario['expectations']))
          if (expectation['ok'] == false)
            '${expectation['name']}: ${expectation['actual']}',
      ];
      out.writeln(
        '| [${scenario['name']}](#${_anchor(scenario)}) '
        '| ${scenario['verdict'] == 'pass' ? 'pass' : '**FAIL**'} '
        '| ${cell(failed.join('; '))} |',
      );
    }
    out.writeln();
  }
  if (timelines.isNotEmpty) {
    out
      ..writeln('| Timeline | Rate | Isolates | Errors |')
      ..writeln('|---|---|---|---:|');
    for (final scenario in timelines) {
      final windows = jsonList(scenario['windows']);
      final counts = [
        for (final window in windows) '${window['isolates'] ?? '?'}',
      ];
      final rates = {for (final window in windows) window['rate']};
      out.writeln(
        '| [${scenario['name']}](#${_anchor(scenario)}) '
        '| ${rates.join(', ')}/s '
        '| ${counts.join(' ')} '
        '| ${jsonMap(scenario['summary'])['errors']} |',
      );
    }
    out.writeln();
  }

  for (final scenario in scenarios) {
    out
      ..writeln('## ${scenario['name']}: ${scenario['title']}')
      ..writeln();
    if (scenario['kind'] == 'timeline') {
      out
        ..write(renderTimeline(scenario))
        ..writeln();
      continue;
    }
    if (scenario['kind'] == 'check') {
      out
        ..write(renderCheck(scenario))
        ..writeln();
      continue;
    }
    out
      ..writeln('`${scenario['request']}`${_shares(scenario)}')
      ..writeln()
      ..write(_stepsTable(scenario))
      ..writeln()
      ..write(_throughputChart(scenario))
      ..writeln();
    if (scenario['kind'] == 'rate') {
      out
        ..write(_latencyChart(scenario, thresholds))
        ..writeln();
    }
  }
  return out.toString();
}

/// The Markdown comparing several runs by their labels: the highest
/// sustainable QPS, the breaking point, the peak MB/s and the peak memory
/// of each scenario, with the ratio to the first run.
String renderComparison(List<Map<String, Object?>> reports) {
  final labels = _labels(reports);
  final names = <String>[];
  for (final report in reports) {
    for (final scenario in jsonList(report['scenarios'])) {
      final name = scenario['name']! as String;
      // The sweeps only: a timeline or a check has no steps to compare.
      if (scenario.containsKey('steps') && !names.contains(name)) {
        names.add(name);
      }
    }
  }
  Json? scenarioOf(Json report, String name) => jsonList(
    report['scenarios'],
  ).where((scenario) => scenario['name'] == name).firstOrNull;

  final out = StringBuffer()
    ..writeln('# Load comparison: ${labels.join(', ')}')
    ..writeln()
    ..writeln('Ratios (×) are against ${labels.first}.')
    ..writeln()
    ..writeln('> $noiseNote')
    ..writeln()
    ..writeln('| Run | Machine |')
    ..writeln('|---|---|');
  for (final (index, report) in reports.indexed) {
    out.writeln('| ${labels[index]} | ${machineLine(report)} |');
  }
  out.writeln();

  /// A table of one number of each scenario's summary, with ratios.
  void table(
    String title,
    String key, {
    required bool Function(Json scenario) where,
    num scale = 1,
  }) {
    final rows = <String>[];
    for (final name in names) {
      final found = [for (final report in reports) scenarioOf(report, name)];
      if (!found.nonNulls.any(where)) {
        continue;
      }
      final values = [
        for (final scenario in found)
          switch (scenario == null ? null : jsonMap(scenario['summary'])[key]) {
            final num value => value / scale,
            _ => null,
          },
      ];
      final cells = StringBuffer('| $name | ${number(values.first)} |');
      for (final value in values.skip(1)) {
        cells.write(' ${number(value)} | ${ratio(value, values.first)} |');
      }
      rows.add(cells.toString());
    }
    if (rows.isEmpty) {
      return;
    }
    out
      ..writeln('## $title')
      ..writeln()
      ..writeln(
        '| Scenario | ${labels.first} |'
        '${labels.skip(1).map((label) => ' $label | × |').join()}',
      )
      ..writeln('|---|---:|${'---:|---:|' * (labels.length - 1)}')
      ..writeln(rows.join('\n'))
      ..writeln();
  }

  bool isRate(Json scenario) => scenario['kind'] == 'rate';
  bool movesData(Json scenario) => scenario['transfersData'] == true;

  table('Highest sustainable QPS', 'sustainableQps', where: isRate);

  final breaking = <String>[];
  for (final name in names) {
    final cells = StringBuffer('| $name |');
    for (final report in reports) {
      final scenario = scenarioOf(report, name);
      final cell = scenario == null
          ? '-'
          : breakingCell(scenario, isRate(scenario) ? '/s' : ' connections');
      cells.write(' $cell |');
    }
    breaking.add(cells.toString());
  }
  out
    ..writeln('## Breaking point')
    ..writeln()
    ..writeln('| Scenario | ${labels.join(' | ')} |')
    ..writeln('|---|${'---|' * labels.length}')
    ..writeln(breaking.join('\n'))
    ..writeln();

  table('Peak throughput (MB/s)', 'peakMegabytesPerSecond', where: movesData);
  table(
    'Peak server memory (RSS, MB)',
    'peakRssBytes',
    where: (_) => true,
    scale: 1024 * 1024,
  );
  return out.toString();
}

// The label of each run; runs without one are numbered, and runs with
// the same label (a run and the previous one) get their commit, then a
// number, so every column has its own name.
List<String> _labels(List<Json> reports) {
  var labels = [
    for (final (index, report) in reports.indexed)
      switch (report['label']) {
        final String label when label.isNotEmpty => label,
        _ => 'run ${index + 1}',
      },
  ];
  bool repeated(String label) =>
      labels.where((other) => other == label).length > 1;
  labels = [
    for (final (index, label) in labels.indexed)
      if (repeated(label))
        '$label @ ${jsonMap(reports[index]['machine'])['gitCommit'] ?? '?'}'
      else
        label,
  ];
  return [
    for (final (index, label) in labels.indexed)
      if (repeated(label)) '$label (${index + 1})' else label,
  ];
}

// How many isolates served, when the run asked the server.
String _isolatesLine(Json report) {
  final isolates = jsonMap(report['isolates']);
  final count = isolates['count'];
  if (count == null && isolates['asked'] == null) {
    return '';
  }
  final asked = isolates['asked'] == null
      ? ''
      : ' (`server.isolates.count=${isolates['asked']}`)';
  final warning = isolates['mismatch'] == true
      ? ' **This is not the number asked for: the run does not measure '
            'it.**'
      : '';
  return '**${count ?? 'An unknown number of'} isolates** served the '
      'sweeps$asked.$warning\n\n';
}

// Which isolates answered a scenario, when there are several.
String _shares(Json scenario) {
  final isolates = jsonMap(scenario['isolates']);
  final shares = jsonMap(isolates['shares']);
  if (shares.length < 2) {
    return '';
  }
  final served = isolates['served'];
  final warning = served != null && served != isolates['count']
      ? ' **Only $served of ${isolates['count']} isolates took requests.**'
      : '';
  return ' · requests by isolate: '
      '${shares.entries.map((e) => '${e.key} ${percent(e.value)}').join(', ')}'
      '.$warning';
}

String _labelSuffix(Json report) => switch (report['label']) {
  final String label when label.isNotEmpty => ': $label',
  _ => '',
};

/// When and where [report] was measured, on one line.
String machineLine(Json report) {
  final machine = jsonMap(report['machine']);
  final changes = machine['gitDirty'] == true ? ' (with local changes)' : '';
  return [
    '${report['startedAt']}',
    'commit ${machine['gitCommit'] ?? 'unknown'}$changes',
    '${machine['cores']} cores',
    if (machine['cpu'] case final String cpu) cpu,
    '${machine['os']} ${machine['osVersion']}',
    'Dart ${machine['dart']}',
    'oha ${machine['oha']}',
  ].join(' · ');
}

String _serverArguments(Json options) {
  final arguments = (options['serverArgs'] as List?) ?? const [];
  return arguments.isEmpty
      ? ''
      : ' Server arguments: ${arguments.map((a) => '`$a`').join(' ')}.';
}

String _anchor(Json scenario) => '${scenario['name']}: ${scenario['title']}'
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9 _-]'), '')
    .replaceAll(' ', '-');

String _sustainable(Json scenario) {
  final summary = jsonMap(scenario['summary']);
  final qps = summary['sustainableQps'];
  if (qps == null) {
    return 'none (the first step failed)';
  }
  return '**${number(qps)}** (at ${summary['sustainableRate']}/s)';
}

/// The breaking point of [scenario] for a table: the load and why, or
/// up to where it went without one.
String breakingCell(Json scenario, String unit) {
  final summary = jsonMap(scenario['summary']);
  final load = summary['breakingRate'] ?? summary['breakingConcurrency'];
  final steps = jsonList(scenario['steps']);
  if (load == null || summary['breakingReasons'] == null) {
    final last = steps.isEmpty
        ? null
        : steps.last['rate'] ?? steps.last['concurrency'];
    return 'not reached${last == null ? '' : ' (up to $last$unit)'}';
  }
  final reasons = (summary['breakingReasons']! as List).join(', ');
  if (reasons.isEmpty) {
    return 'not reached';
  }
  return '$load$unit: $reasons';
}

/// Whether the server answered after the breaking step, and how soon.
String recoveredCell(Json summary) => switch (summary['recovered']) {
  true => switch (summary['recoveredAfterMs']! as num) {
    < 1000 && final time => 'yes, after ${time.round()} ms',
    final time => 'yes, after ${plain(time / 1000)} s',
  },
  false => '**no**',
  _ => '-',
};

String _stepsTable(Json scenario) {
  final rate = scenario['kind'] == 'rate';
  final steps = jsonList(scenario['steps']);
  final data = scenario['transfersData'] == true;
  final out = StringBuffer()
    ..writeln(
      '| ${rate ? 'Rate (/s)' : 'Connections'} | QPS |${data ? ' MB/s |' : ''}'
      ' p50 | p95 | p99 | max | Errors | Timeouts | Refused | Statuses '
      '| RSS peak / end (MB) | Cores | Result |',
    )
    ..writeln(
      '|---:|---:|${data ? '---:|' : ''}---:|---:|---:|---:|---:|---:|---:|'
      '---|---:|---:|---|',
    );
  for (final step in steps) {
    final latency = jsonMap(step['latencyMs']);
    final memory = step['rssBytes'] == null ? null : jsonMap(step['rssBytes']);
    final broken = (step['broken']! as List).join(', ');
    String time(String key) => formatDuration(switch (latency[key]) {
      final num value => milliseconds(value),
      _ => null,
    });
    out.writeln(
      '| ${step['rate'] ?? step['concurrency']} '
      '| ${number(step['qps'])} '
      '${data ? '| ${number(step['megabytesPerSecond'])} ' : ''}'
      '| ${time('p50')} | ${time('p95')} | ${time('p99')} | ${time('max')} '
      '| ${percent(step['errorRate'])} '
      '| ${step['timeouts']} | ${step['refused']} '
      '| ${_statuses(jsonMap(step['statusCodes']))} '
      '| ${memory == null ? '-' : '${megabytes(memory['peak'], unit: '')} / '
                '${megabytes(memory['end'], unit: '')}'} '
      '| ${number(step['cores'])} '
      '| ${broken.isNotEmpty
          ? '**broken**: $broken'
          : step['sustained'] == true
          ? 'sustained'
          : 'not sustained'} |',
    );
  }
  return out.toString();
}

String _statuses(Json codes) => codes.isEmpty
    ? '-'
    : (codes.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(', ');

// The good answers a second (bars) against the rate asked for (line), or
// the MB/s of a transfer scenario by its connections.
String _throughputChart(Json scenario) {
  final steps = jsonList(scenario['steps']);
  if (steps.isEmpty) {
    return '';
  }
  final rate = scenario['kind'] == 'rate';
  final loads = [for (final step in steps) step['rate'] ?? step['concurrency']];
  final values = [
    for (final step in steps)
      ((rate ? step['qps'] : step['megabytesPerSecond'])! as num).toDouble(),
  ];
  final top = [
    ...values,
    if (rate)
      for (final load in loads) (load! as num).toDouble(),
  ].reduce(math.max);
  return (StringBuffer()
        ..writeln('```mermaid')
        ..writeln('xychart-beta')
        ..writeln(
          '    title "${scenario['name']}: ${rate ? 'good answers a second '
                    '(bars) and the rate asked for (line)' : 'MB/s by '
                    'connections'}"',
        )
        ..writeln(
          '    x-axis "${rate ? 'rate asked for (requests/s)' : 'connections'}"'
          ' [${loads.join(', ')}]',
        )
        ..writeln(
          '    y-axis "${rate ? 'requests/s' : 'MB/s'}" 0 --> '
          '${math.max(1, (top * 1.1).ceil())}',
        )
        ..writeln('    bar [${values.map(plain).join(', ')}]')
        ..write(rate ? '    line [${loads.join(', ')}]\n' : '')
        ..writeln('```'))
      .toString();
}

// Mermaid's charts have no logarithmic axis, and the p99 goes from a
// fraction of a millisecond to seconds: a text chart shows both ends.
String _latencyChart(Json scenario, Json thresholds) {
  const width = 48;
  const low = 0.1; // ms
  final steps = jsonList(scenario['steps']);
  final latencies = [
    for (final step in steps) jsonMap(step['latencyMs'])['p99'] as num?,
  ];
  final limit = (thresholds['p99Ms']! as num).toDouble();
  final high = [
    10000.0,
    limit,
    ...latencies.nonNulls.map((value) => value.toDouble()),
  ].reduce(math.max);
  int column(num milliseconds) =>
      ((math.log(math.max(milliseconds, low) / low) / math.log(high / low)) *
              width)
          .round()
          .clamp(0, width);
  final mark = column(limit);
  final labels = [for (final step in steps) '${step['rate']}/s'];
  final pad = labels.fold(
    0,
    (longest, label) => math.max(longest, label.length),
  );
  final out = StringBuffer()
    ..writeln('```text')
    ..writeln(
      'p99 latency, log scale from ${plain(low)} ms to '
      '${plain(high / 1000)} s; the mark is the ${plain(limit)} ms '
      'threshold',
    );
  for (final (index, latency) in latencies.indexed) {
    final bar = latency == null ? 0 : column(latency);
    String cell(int i) {
      if (i == mark) {
        return i < bar ? '|' : ':';
      }
      return i < bar ? '#' : ' ';
    }

    final cells = [for (var i = 0; i <= width; i++) cell(i)].join();
    final value = latency == null
        ? 'no answer'
        : formatDuration(milliseconds(latency));
    out.writeln('${labels[index].padLeft(pad)}  $cells  $value');
  }
  out.writeln('```');
  return out.toString();
}
