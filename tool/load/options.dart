// The command line of tool/load.dart: its options and what `--help`
// prints.
import 'analysis.dart';
import 'scenarios.dart';

/// What `--help` prints.
final String usage =
    '''
Measures the bench server (tool/load_bench) with oha: per scenario, the
highest sustainable QPS and the breaking point; how it scales with its
isolates; what it does when it is overloaded.

usage: dart run tool/load.dart [options] [--<server.property>=<value>...]
       dart run tool/load.dart --compare <report.json> <report.json>...

  --scenarios a,b       scenarios to run, or a group: sweep (default: api
                        and files), api, files, scaling, overload, all
  --isolates 1,2,4,auto run the sweep scenarios once per number of server
                        isolates (--server.isolates.count), each with its
                        report, and compare them (scaling.md)
  --rates 500,1000      the rates of the steps, in requests a second
                        (default 500,1000,2000,4000,8000,16000,32000)
  --start N --step N --max N
                        the same as a range: N, N+step, ... up to max
  --concurrency 1,2,4   the connections of the steps of the transfer
                        scenarios: medium and huge files (default 1,2,4,8)
  --duration 10s        how long a step, or the load of a check, lasts
                        (default 10s)
  --warmup 2s           unmeasured load before the first step of a scenario
                        (default 2s; 0 for none)
  --pause 1s            rest between two steps (default 1s)
  --connections 50      connections of the rate steps (default 50)
  --timeout 5s          a request of a rate step unanswered for so long is
                        a timeout (default 5s)
  --transfer-timeout 2m the same for the transfer steps (default 2m)
  --p99 100ms           a sustained step has a p99 latency of at most this
                        (default 100ms)
  --break-p99 1s        a step with a p99 above it broke the server
                        (default 1s)
  --max-errors 0.1      a sustained step has less than this percentage of
                        errors (default 0.1)
  --keep-going          run the steps after the breaking point too
  --no-keepalive        a new connection for every request
  --window 2s           the windows of the scaling scenarios (default 2s)
  --scale-to 3          the isolates scale-manual scales to, and the most
                        scale-auto may start (default 3)
  --medium-size 10MB    the size of the medium file (default 10MB)
  --huge-size 512MB     the size of the huge file (default 512MB)
  --server-arg --k=v    an argument for the server; repeatable. An option
                        with a dot in its name (--server.isolates.count=4)
                        is passed to the server too
  --label isolates=4    names the run in the reports and in --compare
  --out <dir>           where the reports go (default build/load)
  --no-compile          run the server with `dart run` instead of building
                        a native executable
  --oha <path>          the oha executable (default: oha on the PATH)
  --oha-threads N       oha's worker threads (default: oha's, one a core)
  --compare a b...      compare report.json files by label (ratios against
                        the first); with --out, also written to
                        comparison.md
  -h, --help            this help

Sweep scenarios: ${scenarioNames.join(', ')}.
Others: ${specialScenarios.keys.join(', ')}.''';

/// The options of the command line.
final class LoadOptions {
  /// Options with their values; [LoadOptions.parse] reads them.
  const LoadOptions({
    required this.scenarios,
    required this.rates,
    required this.concurrency,
    required this.duration,
    required this.warmup,
    required this.pause,
    required this.connections,
    required this.timeout,
    required this.transferTimeout,
    required this.thresholds,
    required this.keepGoing,
    required this.keepAlive,
    required this.mediumSize,
    required this.hugeSize,
    required this.serverArgs,
    required this.label,
    required this.out,
    required this.outGiven,
    required this.compile,
    required this.oha,
    required this.ohaThreads,
    required this.compare,
    this.isolates = const [],
    this.window = const Duration(seconds: 2),
    this.scaleTo = 3,
  });

  /// Reads [args]; throws a [FormatException] with what is wrong.
  factory LoadOptions.parse(List<String> args) {
    const flags = {'--keep-going', '--no-keepalive', '--no-compile'};
    const valued = {
      '--scenarios',
      '--rates',
      '--start',
      '--step',
      '--max',
      '--concurrency',
      '--duration',
      '--warmup',
      '--pause',
      '--connections',
      '--timeout',
      '--transfer-timeout',
      '--p99',
      '--break-p99',
      '--max-errors',
      '--medium-size',
      '--huge-size',
      '--label',
      '--out',
      '--oha',
      '--oha-threads',
      '--isolates',
      '--window',
      '--scale-to',
    };
    final values = <String, String>{};
    final seen = <String>{};
    final serverArgs = <String>[];
    final compare = <String>[];
    String next(int i, String option) => i + 1 < args.length
        ? args[i + 1]
        : throw FormatException('$option needs a value.');
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      final equals = arg.indexOf('=');
      final name = equals < 0 ? arg : arg.substring(0, equals);
      if (flags.contains(arg)) {
        seen.add(arg);
      } else if (valued.contains(name)) {
        values[name] = equals < 0 ? next(i++, name) : arg.substring(equals + 1);
      } else if (name == '--server-arg') {
        serverArgs.add(
          equals < 0 ? next(i++, name) : arg.substring(equals + 1),
        );
      } else if (arg == '--compare') {
        while (i + 1 < args.length && !args[i + 1].startsWith('--')) {
          compare.add(args[++i]);
        }
        if (compare.length < 2) {
          throw const FormatException('--compare takes two or more files.');
        }
      } else if (arg.startsWith('--') && equals > 0 && name.contains('.')) {
        // A property of the server: --server.isolates.count=4.
        serverArgs.add(arg);
      } else {
        throw FormatException('Unknown argument: $arg');
      }
    }

    int? number(String option) => switch (values[option]) {
      null => null,
      final text => switch (int.tryParse(text)) {
        final value? when value > 0 => value,
        _ => throw FormatException(
          '$option takes a positive number, not "$text".',
        ),
      },
    };
    Duration duration(String option, Duration fallback) =>
        switch (values[option]) {
          null => fallback,
          final text => parseDuration(text, option),
        };

    final ranged = ['--start', '--step', '--max'].any(values.containsKey);
    final rates = values.containsKey('--rates') || ranged
        ? rateSteps(
            rates: values['--rates'],
            start: number('--start'),
            step: number('--step'),
            max: number('--max'),
          )
        : const [500, 1000, 2000, 4000, 8000, 16000, 32000];

    final names = <String>[];
    for (final name in (values['--scenarios'] ?? 'sweep').split(',')) {
      final trimmed = name.trim();
      final expanded =
          scenarioGroups[trimmed] ??
          (scenarioNames.contains(trimmed) ||
                  specialScenarios.containsKey(trimmed)
              ? [trimmed]
              : throw FormatException(
                  'Unknown scenario "$trimmed". Scenarios: '
                  '${scenarioNames.join(', ')}, '
                  '${specialScenarios.keys.join(', ')}; groups: '
                  '${scenarioGroups.keys.join(', ')}.',
                ));
      names.addAll(expanded.where((name) => !names.contains(name)));
    }

    final isolates = [
      for (final value in (values['--isolates'] ?? '').split(','))
        if (value.trim().isNotEmpty) value.trim().toLowerCase(),
    ];
    for (final value in isolates) {
      if (value != 'auto' && (int.tryParse(value) ?? 0) < 1) {
        throw FormatException(
          '--isolates takes numbers of isolates or auto, not "$value".',
        );
      }
    }
    if (isolates.toSet().length != isolates.length) {
      throw FormatException(
        '--isolates names a value twice: "${values['--isolates']}".',
      );
    }

    final maxErrors = double.tryParse(values['--max-errors'] ?? '0.1');
    if (maxErrors == null || maxErrors <= 0 || maxErrors > 100) {
      throw FormatException(
        '--max-errors takes a percentage above 0, not '
        '"${values['--max-errors']}".',
      );
    }
    return LoadOptions(
      scenarios: names,
      rates: rates,
      concurrency: positiveNumbers(
        values['--concurrency'] ?? '1,2,4,8',
        '--concurrency',
      ),
      duration: duration('--duration', const Duration(seconds: 10)),
      warmup: duration('--warmup', const Duration(seconds: 2)),
      pause: duration('--pause', const Duration(seconds: 1)),
      connections: number('--connections') ?? 50,
      timeout: duration('--timeout', const Duration(seconds: 5)),
      transferTimeout: duration(
        '--transfer-timeout',
        const Duration(minutes: 2),
      ),
      thresholds: Thresholds(
        p99: duration('--p99', const Duration(milliseconds: 100)),
        breakP99: duration('--break-p99', const Duration(seconds: 1)),
        errorRate: maxErrors / 100,
      ),
      keepGoing: seen.contains('--keep-going'),
      keepAlive: !seen.contains('--no-keepalive'),
      mediumSize: values['--medium-size'] ?? '10MB',
      hugeSize: values['--huge-size'] ?? '512MB',
      serverArgs: serverArgs,
      label: values['--label'] ?? '',
      out: values['--out'] ?? 'build/load',
      outGiven: values.containsKey('--out'),
      compile: !seen.contains('--no-compile'),
      oha: values['--oha'] ?? 'oha',
      ohaThreads: number('--oha-threads'),
      isolates: isolates,
      window: duration('--window', const Duration(seconds: 2)),
      scaleTo: number('--scale-to') ?? 3,
      compare: compare,
    );
  }

  /// The names of the scenarios to run, sweeps and others.
  final List<String> scenarios;

  /// The rates of the rate steps, rising.
  final List<int> rates;

  /// The connections of the transfer steps, rising.
  final List<int> concurrency;

  /// How long a step lasts.
  final Duration duration;

  /// The unmeasured load before a scenario's first step.
  final Duration warmup;

  /// The rest between two steps.
  final Duration pause;

  /// The connections of the rate steps.
  final int connections;

  /// The timeout of a request of a rate step.
  final Duration timeout;

  /// The timeout of a transfer.
  final Duration transferTimeout;

  /// What a sustained and a broken step are.
  final Thresholds thresholds;

  /// Whether the steps after the breaking point run too.
  final bool keepGoing;

  /// Whether connections are reused.
  final bool keepAlive;

  /// The sizes of the generated files, as the server's `DataSize`
  /// properties read them (`10MB`).
  final String mediumSize;

  /// See [mediumSize].
  final String hugeSize;

  /// Arguments passed to the server as they are.
  final List<String> serverArgs;

  /// The name of the run.
  final String label;

  /// The directory of the reports, and whether `--out` named it.
  final String out;

  /// See [out].
  final bool outGiven;

  /// A native executable (`true`) or `dart run`.
  final bool compile;

  /// The oha executable.
  final String oha;

  /// oha's worker threads; `null` for its default.
  final int? ohaThreads;

  /// The report.json files to compare; empty to run the load.
  final List<String> compare;

  /// The numbers of server isolates to run the sweep scenarios with, one
  /// run each (`auto` among them: a core each); empty for one run as the
  /// server is.
  final List<String> isolates;

  /// The length of a window of the scaling scenarios.
  final Duration window;

  /// The isolates `scale-manual` scales to, and the most `scale-auto` may
  /// start.
  final int scaleTo;

  /// The sweep scenarios chosen, in the order of the report.
  List<String> get sweeps => [
    for (final name in scenarios)
      if (scenarioNames.contains(name)) name,
  ];

  /// The other scenarios chosen.
  List<String> get specials => [
    for (final name in scenarios)
      if (specialScenarios.containsKey(name)) name,
  ];
}
