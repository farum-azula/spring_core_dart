// tool/load.dart: reading oha's JSON, judging a step, the highest
// sustainable rate and the breaking point of a scenario, the command
// line and the reports. The oha outputs in tool/test/load/ are real ones
// (oha 1.16.0 against the bench server): a quiet step, a port nobody
// listens on, a timeout too short for the file, bodies of which a part is
// invalid, a rate the server could not follow, and a server refusing
// what is over its limit. Nothing is started. The isolates matrix, the
// scaling timelines and the checks are in load_special_test.dart.
import 'dart:convert';
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

const text = Scenario('text', 'Plain text', path: '/text');
const jsonPost = Scenario(
  'json-post',
  'JSON POST',
  method: 'POST',
  path: '/json',
  contentType: 'application/json',
  bodyLinesFile: 'bodies.txt',
  expected: {201, 400},
);
const download = Scenario(
  'download-medium',
  'Download',
  kind: ScenarioKind.transfer,
  path: '/files/medium',
  transfersData: true,
);

StepResult judge(
  String name, {
  Scenario scenario = text,
  Thresholds thresholds = const Thresholds(),
  int? rate = 200,
}) => StepResult.of(
  canned(name),
  scenario,
  thresholds: thresholds,
  rate: rate,
  concurrency: 10,
);

/// A step with only what the summary reads.
StepResult step(
  int rate, {
  bool sustained = true,
  List<String> broken = const [],
  int? memory,
}) => StepResult(
  rate: rate,
  concurrency: 50,
  seconds: 10,
  requests: rate * 10,
  ok: rate * 10,
  statusCodes: {200: rate * 10},
  errors: const {},
  timeouts: 0,
  refused: 0,
  connectionErrors: 0,
  unexpected: 0,
  aborted: 0,
  megabytes: rate / 10,
  p50: const Duration(milliseconds: 1),
  p95: const Duration(milliseconds: 2),
  p99: Duration(milliseconds: broken.isEmpty ? 3 : 1500),
  max: const Duration(milliseconds: 5),
  memory: memory == null ? null : (start: memory, peak: memory, end: memory),
  cpuSeconds: 5,
  sustained: sustained,
  broken: broken,
);

void main() {
  group('OhaResult.parse', () {
    test('reads the time, the statuses, the errors and the latencies', () {
      final oha = canned('oha_ok');
      expect(oha.seconds, closeTo(3.001, 0.001));
      expect(oha.statusCodes, {200: 600});
      expect(oha.errors, {abortedAtDeadline: 2});
      expect(oha.responses, 600);
      expect(oha.bytes, 7200);
      expect(oha.p50, const Duration(microseconds: 425));
      expect(oha.p95, const Duration(microseconds: 780));
      expect(oha.p99, const Duration(microseconds: 1114));
      expect(oha.max, const Duration(microseconds: 3493));
    });

    test('has no latency when nothing was answered', () {
      final oha = canned('oha_refused');
      expect(oha.statusCodes, isEmpty);
      expect(oha.responses, 0);
      expect(oha.p50, isNull);
      expect(oha.p99, isNull);
      expect(oha.max, isNull);
      expect(oha.errors.keys, contains(startsWith('Connection refused')));
    });

    test('counts every status code', () {
      expect(canned('oha_mixed').statusCodes, {201: 148, 400: 52});
    });
  });

  group('StepResult.of', () {
    test('a quiet step is sustained', () {
      final result = judge('oha_ok');
      expect(result.sustained, isTrue);
      expect(result.broken, isEmpty);
      expect(result.ok, 600);
      expect(result.qps, closeTo(199.9, 0.1));
      expect(result.errorRate, 0);
    });

    test('requests cut at the end of the step are not errors', () {
      final result = judge('oha_ok');
      expect(result.aborted, 2);
      expect(result.requests, 600);
      expect(result.timeouts + result.refused + result.connectionErrors, 0);
    });

    test('refused connections break the server', () {
      final result = judge('oha_refused');
      expect(result.refused, 100);
      expect(result.errorRate, 1);
      expect(result.sustained, isFalse);
      expect(result.broken, ['refused connections', 'no answer']);
    });

    test('timeouts break the server', () {
      final result = judge('oha_timeout');
      expect(result.timeouts, 100);
      expect(result.sustained, isFalse);
      expect(result.broken, ['timeouts', 'no answer']);
    });

    test('a status the scenario expects is a good answer', () {
      final result = judge('oha_mixed', scenario: jsonPost);
      expect(result.ok, 200);
      expect(result.unexpected, 0);
      expect(result.sustained, isTrue);
    });

    test('other statuses are errors, but the server still answers', () {
      // The same answers judged as `text`, which expects 200 only.
      final result = judge('oha_mixed');
      expect(result.ok, 0);
      expect(result.unexpected, 200);
      expect(result.errorRate, 1);
      expect(result.sustained, isFalse);
      expect(result.broken, isEmpty);
    });

    test('a p99 between the two thresholds is neither', () {
      // p99 of oha_ok: 1.114 ms.
      final result = judge(
        'oha_ok',
        thresholds: const Thresholds(
          p99: Duration(milliseconds: 1),
          breakP99: Duration(milliseconds: 2),
        ),
      );
      expect(result.sustained, isFalse);
      expect(result.broken, isEmpty);
    });

    test('a rate the server cannot follow breaks it by its p99', () {
      // 40 000 asked for, 4 861 answered a second: the corrected p99 is
      // 1.74 s although no request failed.
      final result = judge('oha_overload', rate: 40000);
      expect(result.errorRate, 0);
      expect(result.qps, closeTo(4861, 1));
      expect(result.p99, const Duration(microseconds: 1739090));
      expect(result.sustained, isFalse);
      expect(result.broken, ['p99 above 1 s']);
    });

    test('the errors threshold is a share of the requests', () {
      const oha = OhaResult(
        seconds: 10,
        statusCodes: {200: 9990, 500: 10},
        errors: {},
        bytes: 0,
        p50: Duration(milliseconds: 1),
        p95: Duration(milliseconds: 1),
        p99: Duration(milliseconds: 1),
        max: Duration(milliseconds: 1),
      );
      StepResult of(double errorRate) => StepResult.of(
        oha,
        text,
        thresholds: Thresholds(errorRate: errorRate),
        rate: 1000,
        concurrency: 50,
      );
      // 10 of 10 000 is 0.1 %: not under 0.1 %, under 0.2 %.
      expect(of(0.001).sustained, isFalse);
      expect(of(0.002).sustained, isTrue);
      expect(of(0.001).broken, isEmpty);
    });

    test('a transfer is not judged by its latency', () {
      final result = judge(
        'oha_overload',
        scenario: download,
        rate: null,
      );
      expect(result.sustained, isTrue);
      expect(result.broken, isEmpty);
      expect(result.megabytesPerSecond, closeTo(45, 0.1));
    });

    test('an upload moves the bytes of its good answers', () {
      const upload = Scenario(
        'upload-small-raw',
        'Upload',
        method: 'PUT',
        path: '/upload/raw',
        uploadBytes: 1024 * 1024,
      );
      final result = judge('oha_ok', scenario: upload);
      expect(result.megabytes, 600);
      expect(result.megabytesPerSecond, closeTo(199.9, 0.1));
    });

    test('other failures of a connection break the server too', () {
      final result = StepResult.of(
        const OhaResult(
          seconds: 10,
          statusCodes: {200: 100},
          errors: {'connection closed before message completed': 3},
          bytes: 0,
          p50: Duration(milliseconds: 1),
          p95: Duration(milliseconds: 1),
          p99: Duration(milliseconds: 1),
          max: Duration(milliseconds: 1),
        ),
        text,
        thresholds: const Thresholds(),
        rate: 10,
        concurrency: 50,
      );
      expect(result.connectionErrors, 3);
      expect(result.broken, ['connection errors']);
    });

    test('toJson has the raw numbers', () {
      final json = judge('oha_mixed', scenario: jsonPost).toJson();
      expect(json['rate'], 200);
      expect(json['statusCodes'], {'201': 148, '400': 52});
      expect(json['abortedAtDeadline'], 1);
      expect((json['latencyMs']! as Map)['p99'], closeTo(1.633, 0.001));
      expect(jsonEncode(json), isNotEmpty);
    });
  });

  group('ScenarioSummary.of', () {
    test('the highest sustainable step is the last before a failure', () {
      final summary = ScenarioSummary.of([
        step(500),
        step(1000),
        step(2000, sustained: false),
        // Luck, not capacity: a sustained step after a failed one.
        step(4000),
        step(8000, sustained: false, broken: ['timeouts']),
      ]);
      expect(summary.sustainable?.rate, 1000);
      expect(summary.breaking?.rate, 8000);
    });

    test('no step sustained, none broken', () {
      final summary = ScenarioSummary.of([step(500, sustained: false)]);
      expect(summary.sustainable, isNull);
      expect(summary.breaking, isNull);
      expect(summary.toJson()['sustainableQps'], isNull);
      expect(summary.toJson()['breakingReasons'], isEmpty);
    });

    test('the breaking point is the first broken step', () {
      final summary = ScenarioSummary.of([
        step(500),
        step(1000, sustained: false, broken: ['p99 above 1 s']),
        step(2000, sustained: false, broken: ['timeouts']),
      ]);
      expect(summary.sustainable?.rate, 500);
      expect(summary.breaking?.rate, 1000);
      final json = summary.toJson(
        recovery: (recovered: true, after: const Duration(milliseconds: 40)),
      );
      expect(json['sustainableQps'], 500);
      expect(json['breakingRate'], 1000);
      expect(json['breakingReasons'], ['p99 above 1 s']);
      expect(json['recovered'], isTrue);
      expect(json['recoveredAfterMs'], 40);
    });

    test('keeps the peaks of the steps', () {
      final summary = ScenarioSummary.of([
        step(500, memory: 40 << 20),
        step(1000, memory: 64 << 20),
        step(2000, memory: 48 << 20),
      ]);
      expect(summary.peakMemory, 64 << 20);
      expect(summary.peakMegabytesPerSecond, 20);
    });
  });

  group('the command line', () {
    test('rateSteps reads a list or a range', () {
      expect(rateSteps(rates: '500, 1000,2000'), [500, 1000, 2000]);
      expect(rateSteps(start: 500, step: 500, max: 2000), [
        500,
        1000,
        1500,
        2000,
      ]);
      expect(rateSteps(start: 500, step: 400, max: 1000), [500, 900]);
    });

    test('rateSteps refuses what is not a rising list of rates', () {
      expect(() => rateSteps(rates: '500,x'), throwsFormatException);
      expect(() => rateSteps(rates: '0,10'), throwsFormatException);
      expect(() => rateSteps(rates: '1000,500'), throwsFormatException);
      expect(() => rateSteps(rates: '500', start: 1), throwsFormatException);
      expect(() => rateSteps(start: 500, max: 1000), throwsFormatException);
      expect(
        () => rateSteps(start: 500, step: 100, max: 100),
        throwsFormatException,
      );
    });

    test('parseDuration reads seconds, milliseconds and minutes', () {
      expect(parseDuration('10s', '--duration'), const Duration(seconds: 10));
      expect(parseDuration('10', '--duration'), const Duration(seconds: 10));
      expect(
        parseDuration('250ms', '--p99'),
        const Duration(milliseconds: 250),
      );
      expect(
        parseDuration('1.5s', '--p99'),
        const Duration(milliseconds: 1500),
      );
      expect(parseDuration('2m', '--timeout'), const Duration(minutes: 2));
      expect(() => parseDuration('soon', '--p99'), throwsFormatException);
    });

    test('parseCpuTime reads what ps prints on macOS and Linux', () {
      expect(parseCpuTime('0:01.52'), closeTo(1.52, 0.001));
      expect(parseCpuTime('  12:03.40\n'), closeTo(723.4, 0.001));
      expect(parseCpuTime('00:00:07'), 7);
      expect(parseCpuTime('01:02:03'), 3723);
      expect(parseCpuTime('2-01:02:03'), 2 * 86400 + 3723);
      expect(parseCpuTime(''), isNull);
    });

    test('formatDuration picks the unit', () {
      expect(formatDuration(const Duration(microseconds: 425)), '0.42 ms');
      expect(formatDuration(const Duration(microseconds: 12340)), '12.3 ms');
      expect(formatDuration(const Duration(milliseconds: 1739)), '1.74 s');
      expect(formatDuration(const Duration(seconds: 1)), '1 s');
      expect(formatDuration(null), '-');
    });

    test('the defaults', () {
      final options = LoadOptions.parse(const []);
      expect(options.scenarios, scenarioNames);
      expect(options.rates, [500, 1000, 2000, 4000, 8000, 16000, 32000]);
      expect(options.concurrency, [1, 2, 4, 8]);
      expect(options.duration, const Duration(seconds: 10));
      expect(options.connections, 50);
      expect(options.thresholds.p99, const Duration(milliseconds: 100));
      expect(options.thresholds.breakP99, const Duration(seconds: 1));
      expect(options.thresholds.errorRate, 0.001);
      expect(options.compile, isTrue);
      expect(options.serverArgs, isEmpty);
      expect(options.compare, isEmpty);
    });

    test('options, with a space or an equals sign', () {
      final options = LoadOptions.parse(const [
        '--scenarios',
        'text,json',
        '--rates=100,200',
        '--duration',
        '3s',
        '--p99',
        '50ms',
        '--max-errors=1',
        '--label',
        'isolates=4',
        '--no-compile',
        '--keep-going',
        '--oha-threads',
        '2',
      ]);
      expect(options.scenarios, ['text', 'json']);
      expect(options.rates, [100, 200]);
      expect(options.duration, const Duration(seconds: 3));
      expect(options.thresholds.p99, const Duration(milliseconds: 50));
      expect(options.thresholds.errorRate, 0.01);
      expect(options.label, 'isolates=4');
      expect(options.compile, isFalse);
      expect(options.keepGoing, isTrue);
      expect(options.ohaThreads, 2);
    });

    test('groups of scenarios, without repeating one', () {
      final options = LoadOptions.parse(const ['--scenarios', 'json,api']);
      expect(options.scenarios, [
        'json',
        'text',
        'json-post',
        'secure',
        'db-read',
        'db-write',
        'static',
      ]);
      expect(
        LoadOptions.parse(const ['--scenarios=files']).scenarios,
        everyElement(anyOf(startsWith('download-'), startsWith('upload-'))),
      );
    });

    test('sweeps and the scenarios with a server of their own', () {
      final options = LoadOptions.parse(const [
        '--scenarios',
        'text,scaling,cpu,overload',
        '--isolates',
        '1,2,AUTO',
        '--window=1s',
        '--scale-to',
        '4',
      ]);
      expect(options.sweeps, ['text']);
      expect(options.specials, [
        'scale-manual',
        'scale-auto',
        'cpu',
        'overload-concurrent',
        'overload-connections',
        'slow-headers',
        'slow-body',
        'big-body',
      ]);
      expect(options.isolates, ['1', '2', 'auto']);
      expect(options.window, const Duration(seconds: 1));
      expect(options.scaleTo, 4);
      final all = LoadOptions.parse(const ['--scenarios', 'all']);
      expect(all.sweeps, scenarioNames);
      expect(all.specials, specialScenarios.keys);
      expect(LoadOptions.parse(const []).specials, isEmpty);
      expect(LoadOptions.parse(const []).isolates, isEmpty);
    });

    test('server properties and --server-arg go to the server', () {
      final options = LoadOptions.parse(const [
        '--server.isolates.count=4',
        '--server-arg',
        '--debug',
        '--server-arg=--spring.profiles.active=prod',
        '--rates',
        '100',
      ]);
      expect(options.serverArgs, [
        '--server.isolates.count=4',
        '--debug',
        '--spring.profiles.active=prod',
      ]);
      expect(options.rates, [100]);
    });

    test('--compare takes the files that follow', () {
      final options = LoadOptions.parse(const [
        '--compare',
        'a/report.json',
        'b/report.json',
        '--out',
        'cmp',
      ]);
      expect(options.compare, ['a/report.json', 'b/report.json']);
      expect(options.out, 'cmp');
      expect(options.outGiven, isTrue);
    });

    test('what it refuses', () {
      for (final args in [
        ['--scenarios', 'nope'],
        ['--isolates', '1,zero'],
        ['--isolates', '2,2'],
        ['--scale-to', '0'],
        ['--frobnicate'],
        ['--rates'],
        ['--rates', '200,100'],
        ['--connections', '0'],
        ['--duration', 'long'],
        ['--max-errors', '0'],
        ['--compare', 'only-one.json'],
        // A typo of an option is not a server property: no dot.
        ['--lable=x'],
      ]) {
        expect(
          () => LoadOptions.parse(args),
          throwsFormatException,
          reason: '$args',
        );
      }
    });
  });

  group('ohaArguments', () {
    List<String> arguments(Scenario scenario, {int? rate}) => ohaArguments(
      scenario,
      baseUrl: 'http://127.0.0.1:18080',
      duration: const Duration(seconds: 10),
      connections: 50,
      timeout: const Duration(seconds: 5),
      rate: rate,
      workerThreads: 2,
    );

    test('a rate step is rate-limited and latency-corrected', () {
      final args = arguments(text, rate: 2000);
      expect(args.join(' '), contains('-q 2000 --latency-correction'));
      expect(args.join(' '), contains('-z 10000ms -c 50 -t 5000ms'));
      expect(args, containsAll(['--no-tui', '--worker-threads']));
      expect(args, isNot(contains('-w')));
      expect(args.last, 'http://127.0.0.1:18080/text');
    });

    test('a transfer step goes as fast as it can and finishes', () {
      final args = arguments(download);
      expect(args, contains('-w'));
      expect(args, isNot(contains('-q')));
      expect(args, isNot(contains('--latency-correction')));
    });

    test('the request of the scenario', () {
      final all = scenarios(
        files: '/data',
        sizes: const {'small': 4096, 'medium': 10 << 20, 'huge': 512 << 20},
        token: 'abc.def.ghi',
        jsonBodies: '/out/bodies',
        dbBody: '/out/body',
      );
      expect(all.map((scenario) => scenario.name), scenarioNames);
      String of(String name) => arguments(
        all.firstWhere((scenario) => scenario.name == name),
        rate: 100,
      ).join(' ');

      expect(
        of('json-post'),
        contains('-m POST -T application/json -Z /out/bodies'),
      );
      expect(of('secure'), contains('-H Authorization: Bearer abc.def.ghi'));
      expect(
        of('db-read'),
        endsWith(
          '--rand-regex-url '
          'http://127.0.0.1:18080/db/items/[1-9][0-9]{0,2}',
        ),
      );
      expect(of('db-write'), contains('-m POST -T application/json -D'));
      expect(of('download-range'), contains('-H Range: $rangeHeader'));
      expect(
        of('upload-huge-multipart'),
        contains('-m POST -F file=@/data/huge.bin'),
      );
      expect(
        of('upload-medium-raw'),
        contains('-m PUT -T application/octet-stream -D /data/medium.bin'),
      );
      final huge = all.firstWhere((s) => s.name == 'upload-huge-raw');
      expect(huge.kind, ScenarioKind.transfer);
      expect(huge.uploadBytes, 512 << 20);
      expect(
        all.firstWhere((s) => s.name == 'upload-small-raw').kind,
        ScenarioKind.rate,
      );
    });

    test('one body in ten of json-post is invalid', () {
      expect(jsonPostBodies, hasLength(10));
      final blank = [
        for (final body in jsonPostBodies)
          if ((jsonDecode(body) as Map)['name'] == '') body,
      ];
      expect(blank, hasLength(1));
    });
  });

  group('the reports', () {
    Map<String, Object?> report(String label, List<StepResult> steps) {
      final summary = ScenarioSummary.of(steps);
      final broke = summary.breaking != null;
      return {
        'schema': 1,
        'label': label,
        'startedAt': '2026-11-10T10:00:00.000Z',
        'machine': {
          'os': 'linux',
          'osVersion': '6.8',
          'cores': 4,
          'cpu': 'Some CPU',
          'dart': '3.13.7',
          'oha': '1.16.0',
          'gitCommit': 'abc1234',
          'gitDirty': false,
        },
        'options': {
          'durationSeconds': 10,
          'connections': 50,
          'compiled': true,
          'serverArgs': ['--server.isolates.count=2'],
          'thresholds': const Thresholds().toJson(),
        },
        'scenarios': [
          {
            'name': 'text',
            'title': 'Plain text',
            'kind': 'rate',
            'request': 'GET /text',
            'transfersData': false,
            'steps': [for (final step in steps) step.toJson()],
            'summary': summary.toJson(
              recovery: broke
                  ? (
                      recovered: true,
                      after: const Duration(milliseconds: 250),
                    )
                  : null,
            ),
          },
        ],
      };
    }

    final one = report('isolates=1', [
      step(1000, memory: 40 << 20),
      step(2000, memory: 42 << 20),
      step(4000, sustained: false, broken: ['p99 above 1 s'], memory: 50 << 20),
    ]);
    final two = report('isolates=2', [
      step(1000, memory: 70 << 20),
      step(2000, memory: 72 << 20),
      step(4000, memory: 80 << 20),
    ]);

    test('report.md has the summary, a table and the charts', () {
      final markdown = renderReport(one);
      expect(markdown, startsWith('# Load report: isolates=1\n'));
      expect(markdown, contains('commit abc1234 · 4 cores · Some CPU'));
      expect(markdown, contains('`--server.isolates.count=2`'));
      expect(
        markdown,
        contains(
          '| [text](#text-plain-text) | `GET /text` | **2000** (at 2000/s) '
          '| 4000/s: p99 above 1 s | yes, after 250 ms | 50 MB |',
        ),
      );
      expect(markdown, contains('## text: Plain text'));
      expect(markdown, contains('| 1000 | 1000 | 1.00 ms | 2.00 ms |'));
      expect(markdown, contains('| **broken**: p99 above 1 s |'));
      expect(markdown, contains('```mermaid\nxychart-beta\n'));
      expect(
        markdown,
        contains(
          '    x-axis "rate asked for (requests/s)" '
          '[1000, 2000, 4000]',
        ),
      );
      expect(markdown, contains('    bar [1000, 2000, 4000]'));
      expect(markdown, contains('p99 latency, log scale'));
      expect(markdown, contains(noiseNote));
    });

    test('the p99 chart marks the threshold', () {
      final chart = renderReport(one)
          .split('```text\n')[1]
          .split('```')
          .first
          .split('\n');
      // 3 ms stops before the 100 ms mark; 1.5 s goes through it.
      expect(chart[1], matches(r'^1000/s  #+ +: +3\.00 ms$'));
      expect(chart[3], matches(r'^4000/s  #+\|#+ +1\.5 s$'));
    });

    test('a scenario that never broke says up to where it went', () {
      expect(renderReport(two), contains('| not reached (up to 4000/s) | - |'));
    });

    test('the comparison has ratios against the first run', () {
      final markdown = renderComparison([one, two]);
      expect(
        markdown,
        startsWith('# Load comparison: isolates=1, isolates=2\n'),
      );
      expect(markdown, contains('| Scenario | isolates=1 | isolates=2 | × |'));
      expect(markdown, contains('| text | 2000 | 4000 | 2.00× |'));
      expect(
        markdown,
        contains(
          '| text | 4000/s: p99 above 1 s | not reached (up to 4000/s) |',
        ),
      );
      expect(markdown, contains('## Peak server memory (RSS, MB)'));
      expect(markdown, contains('| text | 50 | 80 | 1.60× |'));
    });

    test('runs without a label are numbered', () {
      final markdown = renderComparison([
        {...one, 'label': ''},
        {...two, 'label': ''},
      ]);
      expect(markdown, startsWith('# Load comparison: run 1, run 2\n'));
    });

    test('runs with the same label get their commit, then a number', () {
      final later = {
        ...one,
        'machine': {...one['machine']! as Map, 'gitCommit': 'def5678'},
      };
      expect(
        renderComparison([one, later]),
        startsWith(
          '# Load comparison: isolates=1 @ abc1234, isolates=1 @ def5678\n',
        ),
      );
      expect(
        renderComparison([one, one]),
        startsWith(
          '# Load comparison: isolates=1 @ abc1234 (1), '
          'isolates=1 @ abc1234 (2)\n',
        ),
      );
    });

    test('a transfer scenario shows MB/s by connections', () {
      StepResult transfer(int connections, double megabytes) => StepResult(
        concurrency: connections,
        seconds: 10,
        requests: 40,
        ok: 40,
        statusCodes: const {200: 40},
        errors: const {},
        timeouts: 0,
        refused: 0,
        connectionErrors: 0,
        unexpected: 0,
        aborted: 0,
        megabytes: megabytes,
        p99: const Duration(seconds: 2),
        sustained: true,
        broken: const [],
      );
      final steps = [transfer(1, 9000), transfer(2, 15000)];
      final run = {
        ...one,
        'scenarios': [
          {
            'name': 'download-huge',
            'title': 'Download, huge file',
            'kind': 'transfer',
            'request': 'GET /files/huge',
            'transfersData': true,
            'steps': [for (final step in steps) step.toJson()],
            'summary': ScenarioSummary.of(steps).toJson(),
          },
        ],
      };
      final markdown = renderReport(run);
      expect(
        markdown,
        contains(
          '| `GET /files/huge` | 1500 | 2 '
          '| not reached (up to 2 connections) | - | - |',
        ),
      );
      expect(markdown, contains('| Connections | QPS | MB/s | p50 |'));
      expect(markdown, contains('| 2 | 4 | 1500 | - | - | 2 s |'));
      expect(markdown, contains('    x-axis "connections" [1, 2]'));
      expect(markdown, contains('    bar [900, 1500]'));
      // No latency chart: a transfer takes as long as its bytes.
      expect(markdown, isNot(contains('p99 latency, log scale')));
      expect(
        renderComparison([run, run]),
        contains(
          '## Peak throughput (MB/s)\n\n'
          '| Scenario | isolates=1 @ abc1234 (1) | isolates=1 @ abc1234 (2) '
          '| × |\n'
          '|---|---:|---:|---:|\n'
          '| download-huge | 1500 | 1500 | 1.00× |',
        ),
      );
    });

    test('a scenario one run lacks is a dash', () {
      final markdown = renderComparison([
        one,
        {...two, 'scenarios': <Object?>[]},
      ]);
      expect(markdown, contains('| text | 2000 | - | - |'));
    });
  });
}
