// Mutation testing of the security packages (roadmap/security_verification.md,
// section 5): changes the code one small way at a time (a flipped
// condition, a swapped boolean, a bound off by one) and runs the package's
// tests; a change the tests do not notice (a surviving mutant) is a missing
// test. Mutants that do not compile are skipped.
//
//   dart run tool/mutation_test.dart <package> <lib file>... [--max N] [--report file.md]
//
//   dart run tool/mutation_test.dart spring_boot_starter_security \
//       lib/src/web/firewall.dart lib/src/web/access.dart
//
// The original file is restored after every mutant, also on Ctrl+C.
import 'dart:async';
import 'dart:io';

/// A textual mutation of one line.
final class Mutation {
  const Mutation(this.name, this.pattern, this.replacement);

  final String name;
  final RegExp pattern;
  final String replacement;
}

final mutations = [
  Mutation('== → !=', RegExp('(?<![=!<>])==(?!=)'), '!='),
  Mutation('!= → ==', RegExp('!=(?!=)'), '=='),
  Mutation('&& → ||', RegExp('&&'), '||'),
  Mutation('|| → &&', RegExp(r'\|\|'), '&&'),
  Mutation(' < → <=', RegExp(' < (?!=)'), ' <= '),
  Mutation(' <= → <', RegExp(' <= '), ' < '),
  Mutation(' > → >=', RegExp(' > (?!=)'), ' >= '),
  Mutation(' >= → >', RegExp(' >= '), ' > '),
  Mutation('true → false', RegExp(r'\btrue\b'), 'false'),
  Mutation('false → true', RegExp(r'\bfalse\b'), 'true'),
  Mutation('!x → x', RegExp(r'(?<=[(\s])!(?=[a-zA-Z_(])'), ''),
  Mutation('isEmpty → isNotEmpty', RegExp(r'\.isEmpty\b'), '.isNotEmpty'),
  Mutation('isNotEmpty → isEmpty', RegExp(r'\.isNotEmpty\b'), '.isEmpty'),
  Mutation('any → every', RegExp(r'\.any\('), '.every('),
  Mutation('every → any', RegExp(r'\.every\('), '.any('),
  Mutation(
    'contains → !contains',
    RegExp(r'(?<![!\w])(\w+)\.contains\('),
    r'!$1.contains(',
  ),
  Mutation('+ 1 → - 1', RegExp(r' \+ 1\b'), ' - 1'),
  Mutation('- 1 → + 1', RegExp(r' - 1\b'), ' + 1'),
];

/// One mutant: [mutation] applied at [line] (1-based), [index]-th match.
final class Mutant {
  Mutant(
    this.file,
    this.line,
    this.index,
    this.mutation,
    this.original,
    this.mutated,
  );

  final String file;
  final int line;
  final int index;
  final Mutation mutation;
  final String original;
  final String mutated;
}

bool _skippable(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('//') ||
      trimmed.startsWith('///') ||
      trimmed.startsWith('*') ||
      trimmed.startsWith('import ') ||
      trimmed.startsWith('export ') ||
      trimmed.startsWith('@') ||
      trimmed.contains("'") && !trimmed.contains('(') && !trimmed.contains('=');
}

List<Mutant> mutantsOf(String file, List<String> lines) {
  final result = <Mutant>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_skippable(line)) {
      continue;
    }
    // Only the code, not a trailing comment or string literals' insides.
    final code = line.split(' // ').first;
    for (final mutation in mutations) {
      var index = 0;
      for (final match in mutation.pattern.allMatches(code)) {
        // Inside a string literal: skip (counts quotes before the match).
        final before = code.substring(0, match.start);
        if ("'".allMatches(before).length.isOdd) {
          index++;
          continue;
        }
        // The replacement in place of the match (`$1`: its first group),
        // not the pattern again on the match alone, where lookarounds see
        // nothing around it and nothing would change.
        final replacement = mutation.replacement.replaceAllMapped(
          RegExp(r'\$(\d)'),
          (group) => match.group(int.parse(group[1]!)) ?? '',
        );
        final mutated =
            code.substring(0, match.start) +
            replacement +
            code.substring(match.end) +
            line.substring(code.length);
        if (mutated == line) {
          index++;
          continue; // not a change
        }
        result.add(Mutant(file, i + 1, index++, mutation, line, mutated));
      }
    }
  }
  return result;
}

void _write(String path, String text) => File(path).writeAsStringSync(text);

/// How long one test run of a mutant may take (a mutant may loop forever).
const _timeout = Duration(minutes: 5);

/// Runs the package's tests, the integration ones too (a local server
/// checks what a mock cannot), stopping at the first failure; not the
/// differential ones (they need the Spring application).
Future<({int exitCode, String output, bool timedOut})> _runTests(
  String package,
) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'test',
    '--fail-fast',
    '--reporter=compact',
    '-x',
    'differential',
  ], workingDirectory: package);
  final output = StringBuffer();
  final done = Future.wait([
    process.stdout
        .transform(const SystemEncoding().decoder)
        .forEach(output.write),
    process.stderr
        .transform(const SystemEncoding().decoder)
        .forEach(output.write),
  ]);
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    _timeout,
    onTimeout: () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  await done;
  return (exitCode: exitCode, output: '$output', timedOut: timedOut);
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run tool/mutation_test.dart <package> <lib file>... '
      '[--max N] [--report file.md]',
    );
    exit(64);
  }
  final package = args.first;
  final maxIndex = args.indexOf('--max');
  final max = maxIndex < 0 ? 1 << 30 : int.parse(args[maxIndex + 1]);
  final reportIndex = args.indexOf('--report');
  final reportFile = reportIndex < 0 ? null : args[reportIndex + 1];
  final files = [
    for (var i = 1; i < args.length; i++)
      if (!args[i].startsWith('--') &&
          (i == 0 || !const {'--max', '--report'}.contains(args[i - 1])))
        args[i],
  ];
  final originals = <String, String>{};
  void restoreAll() {
    for (final MapEntry(key: path, value: text) in originals.entries) {
      _write(path, text);
    }
  }

  final interrupt = ProcessSignal.sigint.watch().listen((_) {
    restoreAll();
    exit(130);
  });

  final mutants = <Mutant>[];
  for (final file in files) {
    final path = '$package/$file';
    final text = File(path).readAsStringSync();
    originals[path] = text;
    mutants.addAll(mutantsOf(path, text.split('\n')));
  }
  final selected = mutants.take(max).toList();

  // Without a passing baseline every mutant would count as killed.
  final baseline = await _runTests(package);
  if (baseline.exitCode != 0 || baseline.timedOut) {
    stderr.writeln(
      'The tests of $package fail without any mutation; fix them first.\n'
      '${baseline.output}',
    );
    await interrupt.cancel();
    exit(1);
  }
  stdout.writeln('${mutants.length} mutants, running ${selected.length}');

  final survived = <Mutant>[];
  var killed = 0;
  var invalid = 0;
  final watch = Stopwatch()..start();
  try {
    for (final (n, mutant) in selected.indexed) {
      final lines = originals[mutant.file]!.split('\n');
      lines[mutant.line - 1] = mutant.mutated;
      _write(mutant.file, lines.join('\n'));
      final result = await _runTests(package);
      _write(mutant.file, originals[mutant.file]!);
      final String outcome;
      if (result.timedOut) {
        killed++; // an endless loop: noticed
        outcome = 'killed (timeout)';
      } else if (result.output.contains('Error: ') &&
          result.output.contains('loading')) {
        invalid++;
        outcome = 'invalid';
      } else if (result.exitCode == 0) {
        survived.add(mutant);
        outcome = 'SURVIVED';
      } else {
        killed++;
        outcome = 'killed';
      }
      stdout.writeln(
        '[${n + 1}/${selected.length}] $outcome '
        '${mutant.file.split('/').last}:${mutant.line} ${mutant.mutation.name}',
      );
    }
  } finally {
    restoreAll();
  }
  final valid = killed + survived.length;
  final score = valid == 0 ? 100.0 : killed * 100 / valid;
  final report = StringBuffer()
    ..writeln('# Mutation report: $package')
    ..writeln()
    ..writeln(
      'Mutants: ${selected.length} (killed $killed, survived '
      '${survived.length}, did not compile $invalid). Score: '
      '${score.toStringAsFixed(1)} %. Time: ${watch.elapsed.inMinutes} min.',
    )
    ..writeln();
  if (survived.isNotEmpty) {
    report
      ..writeln('| Where | Mutation | Line |')
      ..writeln('|---|---|---|');
    for (final mutant in survived) {
      report.writeln(
        '| ${mutant.file}:${mutant.line} | ${mutant.mutation.name} | '
        '`${mutant.original.trim().replaceAll('|', r'\|')}` |',
      );
    }
  }
  stdout.write(report);
  if (reportFile != null) {
    File(reportFile).writeAsStringSync('$report');
  }
  await interrupt.cancel();
  exit(survived.isEmpty ? 0 : 1);
}
