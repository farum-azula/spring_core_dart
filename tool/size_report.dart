// What the generated code (`*.spring.dart`) costs: its source lines and
// bytes, and the AOT machine code it compiles to in two applications. Run it
// before and after a change of the generator to measure the change.
//
//   dart run tool/size_report.dart                 # sources + AOT sizes
//   dart run tool/size_report.dart --no-compile    # sources only (fast)
//   dart run tool/size_report.dart --json          # machine-readable
//   dart run tool/size_report.dart --budget tool/size_budget.json
//
// With `--budget` it exits with 1 when a measure exceeds its maximum in the
// budget file (`sources.generatedLines`, and for each app
// `apps.<name>.generatedInstructions` and `apps.<name>.snapshotBytes`,
// these with a headroom of 1%: the SDK build and the machine move them by a
// few hundred bytes), and when the budget and the measures do not match
// (see [checkBudget]). A budget with `apps` needs the compilation, so
// `--no-compile` only goes with a budget of the sources.
// The AOT sizes come from `dart compile aot-snapshot` with the VM's
// `--print-instructions-sizes-to`, in a temporary directory under
// `.dart_tool/size_report/` deleted afterwards (also on Ctrl-C).
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The applications compiled to measure the generated code's machine code.
const apps = [
  App(
    'server_guide',
    packageDir: 'example/server_guide',
    entry: 'bin/main.dart',
  ),
  App(
    'data_example',
    packageDir: 'spring_boot_starter_data',
    entry: 'example/example.dart',
  ),
];

/// Directories never searched for generated sources.
const skippedDirectories = {'.dart_tool', 'build', '.worktrees', '.git'};

/// How many libraries the top list of an app shows.
const topLibraryCount = 15;

/// An application compiled ahead of time to measure its machine code.
final class App {
  /// The app [name] used in reports and budgets; [entry] is relative to
  /// [packageDir], itself relative to the repository.
  const App(this.name, {required this.packageDir, required this.entry});

  /// Its name in reports and budget files.
  final String name;

  /// Its package directory, relative to the repository (the compiler's
  /// working directory).
  final String packageDir;

  /// Its `main` file, relative to [packageDir].
  final String entry;
}

/// The size of one generated source file.
final class SourceFile {
  /// The [lines] and [bytes] of the file at [path].
  const SourceFile(this.path, {required this.lines, required this.bytes});

  /// Its path relative to the repository, with `/` separators.
  final String path;

  /// Its number of lines.
  final int lines;

  /// Its size in bytes.
  final int bytes;
}

/// Lines and bytes of the generated sources, in total and per package.
final class SourceReport {
  /// A report of [files] (sorted by path), with the totals of [byPackage].
  const SourceReport(this.files, this.byPackage);

  /// Every generated file, sorted by path.
  final List<SourceFile> files;

  /// Lines and bytes per package directory (relative to the repository,
  /// `.` for the root), sorted by directory.
  final Map<String, ({int lines, int bytes})> byPackage;

  /// Lines of every generated file.
  int get totalLines => files.fold(0, (sum, file) => sum + file.lines);

  /// Bytes of every generated file.
  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);

  /// The report as JSON.
  Map<String, Object?> toJson() => {
    'generatedFiles': files.length,
    'generatedLines': totalLines,
    'generatedBytes': totalBytes,
    'byPackage': {
      for (final MapEntry(:key, :value) in byPackage.entries)
        key: {'lines': value.lines, 'bytes': value.bytes},
    },
    'files': [
      for (final file in files)
        {'path': file.path, 'lines': file.lines, 'bytes': file.bytes},
    ],
  };
}

/// The number of lines of [bytes]: a last line without a newline counts.
int countLines(List<int> bytes) {
  var lines = 0;
  for (final byte in bytes) {
    if (byte == 0x0A) {
      lines++;
    }
  }
  if (bytes.isNotEmpty && bytes.last != 0x0A) {
    lines++;
  }
  return lines;
}

/// Counts the generated [files] (contents by repository-relative path,
/// `/` separators); each belongs to the deepest of [packageDirs] containing
/// it (`.` when none does).
SourceReport countSources(
  Map<String, List<int>> files, {
  required Set<String> packageDirs,
}) {
  final sources = [
    for (final MapEntry(:key, :value) in files.entries)
      SourceFile(key, lines: countLines(value), bytes: value.length),
  ]..sort((a, b) => a.path.compareTo(b.path));
  final byPackage = <String, ({int lines, int bytes})>{};
  for (final file in sources) {
    final package = packageOf(file.path, packageDirs);
    final sum = byPackage[package] ?? (lines: 0, bytes: 0);
    byPackage[package] = (
      lines: sum.lines + file.lines,
      bytes: sum.bytes + file.bytes,
    );
  }
  return SourceReport(sources, {
    for (final key in byPackage.keys.toList()..sort()) key: byPackage[key]!,
  });
}

/// The deepest of [packageDirs] that contains [path] (`.` when none does).
String packageOf(String path, Set<String> packageDirs) {
  var best = '.';
  for (final dir in packageDirs) {
    if (dir != '.' &&
        path.startsWith('$dir/') &&
        (best == '.' || dir.length > best.length)) {
      best = dir;
    }
  }
  return best;
}

/// Machine code of an app by library, from the VM's
/// `--print-instructions-sizes-to` output.
final class InstructionReport {
  /// A report; the maps are sorted by size, largest first.
  const InstructionReport({
    required this.totalInstructions,
    required this.generatedByLibrary,
    required this.proxyInstructions,
    required this.topLibraries,
  });

  /// Bytes of instructions of every function.
  final int totalInstructions;

  /// Bytes of instructions per `.spring.dart` library.
  final Map<String, int> generatedByLibrary;

  /// Bytes of instructions of the classes named `...Proxy` in
  /// `.spring.dart` libraries.
  final int proxyInstructions;

  /// The [topLibraryCount] largest libraries or packages (see [groupOf]).
  final Map<String, int> topLibraries;

  /// Bytes of instructions of the `.spring.dart` libraries.
  int get generatedInstructions =>
      generatedByLibrary.values.fold(0, (sum, size) => sum + size);
}

/// Aggregates the entries of `--print-instructions-sizes-to` (`l`: library
/// URI, `c`: class, `n`: function, `s`: size in bytes); `file:` URIs are
/// shown relative to [repoRoot].
InstructionReport aggregateInstructions(
  List<Map<String, Object?>> entries, {
  required String repoRoot,
}) {
  var total = 0;
  var proxies = 0;
  final generated = <String, int>{};
  final groups = <String, int>{};
  for (final entry in entries) {
    final size = (entry['s'] as num?)?.toInt() ?? 0;
    final library = entry['l'] as String? ?? '';
    total += size;
    final group = groupOf(library, repoRoot: repoRoot);
    groups[group] = (groups[group] ?? 0) + size;
    if (library.contains('.spring.dart')) {
      final name = displayLibrary(library, repoRoot: repoRoot);
      generated[name] = (generated[name] ?? 0) + size;
      final className = entry['c'] as String?;
      if (className != null && className.endsWith('Proxy')) {
        proxies += size;
      }
    }
  }
  return InstructionReport(
    totalInstructions: total,
    generatedByLibrary: sortedBySize(generated),
    proxyInstructions: proxies,
    topLibraries: sortedBySize(groups, limit: topLibraryCount),
  );
}

/// [sizes] sorted largest first (then by name), keeping at most [limit].
Map<String, int> sortedBySize(Map<String, int> sizes, {int? limit}) {
  final entries = sizes.entries.toList()
    ..sort((a, b) {
      final bySize = b.value.compareTo(a.value);
      return bySize != 0 ? bySize : a.key.compareTo(b.key);
    });
  return Map.fromEntries(limit == null ? entries : entries.take(limit));
}

/// The group of [library] in the top list: `package:foo` for
/// `package:foo/...`, `dart:x` as is, a `file:` URI as its path relative to
/// [repoRoot].
String groupOf(String library, {required String repoRoot}) {
  if (library.startsWith('package:')) {
    final slash = library.indexOf('/');
    return slash < 0 ? library : library.substring(0, slash);
  }
  return displayLibrary(library, repoRoot: repoRoot);
}

/// [library] for display: a `file:` URI as its path relative to [repoRoot]
/// (`/` separators), anything else as is (`<unknown>` when empty).
String displayLibrary(String library, {required String repoRoot}) {
  if (library.isEmpty) {
    return '<unknown>';
  }
  if (library.startsWith('file:')) {
    final path = Uri.parse(library).toFilePath();
    return p.isWithin(repoRoot, path)
        ? p.posix.joinAll(p.split(p.relative(path, from: repoRoot)))
        : path;
  }
  return library;
}

/// The measures of one compiled app.
final class AppReport {
  /// The [snapshotBytes] and [instructions] of [app].
  const AppReport(
    this.app, {
    required this.snapshotBytes,
    required this.instructions,
  });

  /// The app measured.
  final App app;

  /// Size of its AOT snapshot file.
  final int snapshotBytes;

  /// Its machine code by library.
  final InstructionReport instructions;

  /// The report as JSON.
  Map<String, Object?> toJson() => {
    'entry': p.posix.join(app.packageDir, app.entry),
    'snapshotBytes': snapshotBytes,
    'totalInstructions': instructions.totalInstructions,
    'generatedInstructions': instructions.generatedInstructions,
    'proxyInstructions': instructions.proxyInstructions,
    'generatedByLibrary': instructions.generatedByLibrary,
    'topLibraries': instructions.topLibraries,
  };
}

/// How much the AOT measures may exceed their budget: they vary by a few
/// hundred bytes from one machine (or SDK build) to another, unlike the
/// source lines, which are checked exactly.
const aotHeadroom = 1.01;

/// The measures budgeted for each app.
const appMeasures = ['generatedInstructions', 'snapshotBytes'];

/// What fails [budget] in [report] (the JSON of a full report: `sources`
/// and `apps`); empty when nothing does. The AOT measures have
/// [aotHeadroom].
///
/// The check is strict, so that a mistake in the budget or a run that
/// measured less cannot pass it: `sources.generatedLines` and, for each
/// budgeted app, every one of [appMeasures] must be a finite non-negative
/// number; unknown keys, a budgeted measure that was not measured, and a
/// measured app absent from the budget all fail.
List<String> checkBudget(
  Map<String, Object?> report,
  Map<String, Object?> budget,
) {
  final problems = <String>[];
  Map<String, Object?>? section(String name, Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    problems.add(
      value == null
          ? '$name: missing from the budget'
          : '$name: expected an object in the budget, got ${_describe(value)}',
    );
    return null;
  }

  void known(String name, Map<String, Object?> value, List<String> keys) {
    for (final key in value.keys) {
      if (!keys.contains(key)) {
        problems.add(
          '${name.isEmpty ? '' : '$name.'}$key: unknown budget key '
          '(expected ${keys.join(' or ')})',
        );
      }
    }
  }

  void check(String name, Object? actual, Object? max, {num headroom = 1}) {
    if (max is! num || !max.isFinite || max < 0) {
      problems.add(
        max == null
            ? '$name: missing from the budget'
            : '$name: invalid budget ${_describe(max)} '
                  '(expected a non-negative number)',
      );
    } else if (actual is! num) {
      problems.add('$name: budgeted but not measured');
    } else if (actual > (max * headroom).round()) {
      problems.add('$name: $actual > $max (+${actual - max})');
    }
  }

  known('', budget, const ['sources', 'apps']);
  final sources = report['sources'] as Map<String, Object?>? ?? const {};
  final sourceBudget = section('sources', budget['sources']);
  if (sourceBudget != null) {
    known('sources', sourceBudget, const ['generatedLines']);
    check(
      'sources.generatedLines',
      sources['generatedLines'],
      sourceBudget['generatedLines'],
    );
  }
  final reportApps = report['apps'] as Map<String, Object?>? ?? const {};
  final budgetApps = budget.containsKey('apps')
      ? section('apps', budget['apps'])
      : const <String, Object?>{};
  if (budgetApps == null) {
    return problems;
  }
  for (final MapEntry(key: name, :value) in budgetApps.entries) {
    final max = section('apps.$name', value);
    if (max == null) {
      continue;
    }
    known('apps.$name', max, appMeasures);
    final actual = reportApps[name] as Map<String, Object?>? ?? const {};
    for (final measure in appMeasures) {
      check(
        'apps.$name.$measure',
        actual[measure],
        max[measure],
        headroom: aotHeadroom,
      );
    }
  }
  for (final name in reportApps.keys) {
    if (!budgetApps.containsKey(name)) {
      problems.add('apps.$name: measured but not in the budget');
    }
  }
  return problems;
}

// A budget value as written in JSON (or as Dart writes it, for a value
// JSON cannot hold).
String _describe(Object? value) {
  try {
    return jsonEncode(value);
  } on JsonUnsupportedObjectError {
    return '$value';
  }
}

/// The budget in [text] (the content of a `--budget` file), checked
/// against the run's options: a run that does not [compile] measures no
/// app, so its budget may not have `apps`. Throws a [FormatException]
/// otherwise.
Map<String, Object?> readBudget(String text, {required bool compile}) {
  final budget = jsonDecode(text);
  if (budget is! Map<String, Object?>) {
    throw const FormatException('the budget must be a JSON object');
  }
  if (!compile && budget.containsKey('apps')) {
    throw const FormatException(
      '--no-compile measures no app, but the budget has apps: '
      'run with the compilation, or with a budget of the sources only',
    );
  }
  return budget;
}

/// A failure that ends the report (exit code 2) once the temporary files
/// are deleted.
final class _Failure implements Exception {
  const _Failure(this.message);

  final String message;
}

Future<void> main(List<String> args) async {
  var compile = true;
  var json = false;
  String? budgetPath;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--no-compile') {
      compile = false;
    } else if (arg == '--json') {
      json = true;
    } else if (arg == '--budget' && i + 1 < args.length) {
      budgetPath = args[++i];
    } else if (arg.startsWith('--budget=')) {
      budgetPath = arg.substring('--budget='.length);
    } else {
      stderr.writeln(
        'Usage: dart run tool/size_report.dart '
        '[--no-compile] [--json] [--budget <file>]',
      );
      exit(64);
    }
  }
  Map<String, Object?>? budget;
  if (budgetPath != null) {
    try {
      budget = readBudget(
        File(budgetPath).readAsStringSync(),
        compile: compile,
      );
    } on FormatException catch (error) {
      stderr.writeln('Invalid budget $budgetPath: ${error.message}');
      exit(64);
    } on FileSystemException catch (error) {
      stderr.writeln('Cannot read the budget $budgetPath: ${error.message}');
      exit(64);
    }
  }

  final root = p.normalize(
    p.absolute(File.fromUri(Platform.script).parent.parent.path),
  );
  final sources = _scanSources(root);
  final appReports = <AppReport>[];
  if (compile) {
    try {
      appReports.addAll(await _measureApps(root));
    } on _Failure catch (failure) {
      stderr.write(failure.message);
      exit(2);
    }
  }

  final report = <String, Object?>{
    'sources': sources.toJson(),
    'apps': {for (final app in appReports) app.app.name: app.toJson()},
  };
  if (json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } else {
    _printSources(sources);
    appReports.forEach(_printApp);
  }

  if (budget != null) {
    final problems = checkBudget(report, budget);
    if (problems.isNotEmpty) {
      stderr
        ..writeln('Size budget failed ($budgetPath):')
        ..writeln(problems.map((line) => '  - $line').join('\n'));
      exit(1);
    }
    (json ? stderr : stdout).writeln('Size budget ok ($budgetPath).');
  }
}

/// Reads every `*.spring.dart` under [root] (outside [skippedDirectories]).
SourceReport _scanSources(String root) {
  final files = <String, List<int>>{};
  final packageDirs = <String>{};
  void walk(Directory directory) {
    for (final entity in directory.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      final relative = p.posix.joinAll(
        p.split(p.relative(entity.path, from: root)),
      );
      if (entity is Directory) {
        if (!skippedDirectories.contains(name)) {
          walk(entity);
        }
      } else if (entity is File) {
        if (name.endsWith('.spring.dart')) {
          files[relative] = entity.readAsBytesSync();
        } else if (name == 'pubspec.yaml') {
          packageDirs.add(p.posix.dirname(relative));
        }
      }
    }
  }

  walk(Directory(root));
  return countSources(files, packageDirs: packageDirs);
}

/// Compiles every app of [apps] in a temporary directory under
/// `<root>/.dart_tool/size_report/`, deleted afterwards, also when a
/// compilation fails or on Ctrl-C.
///
/// Not the system temporary directory: the sizes path goes through
/// `--extra-gen-snapshot-options`, which splits on commas.
Future<List<AppReport>> _measureApps(String root) async {
  final parent = Directory(p.join(root, '.dart_tool', 'size_report'));
  if (parent.path.contains(',')) {
    throw _Failure(
      'The repository path has a comma, which '
      '--extra-gen-snapshot-options cannot pass: ${parent.path}\n',
    );
  }
  await parent.create(recursive: true);
  final temp = await parent.createTemp('run_');
  final interrupt = ProcessSignal.sigint.watch().listen((_) {
    try {
      temp.deleteSync(recursive: true);
    } on FileSystemException {
      // Exiting anyway.
    }
    exit(130);
  });
  try {
    return [
      for (final app in apps) await _measure(app, root: root, temp: temp.path),
    ];
  } finally {
    await interrupt.cancel();
    await temp.delete(recursive: true);
  }
}

/// Compiles [app] into [temp] and reads its sizes.
Future<AppReport> _measure(
  App app, {
  required String root,
  required String temp,
}) async {
  final snapshot = p.join(temp, '${app.name}.aot');
  final sizes = p.join(temp, '${app.name}.sizes.json');
  stderr.writeln('Compiling ${p.posix.join(app.packageDir, app.entry)}...');
  final result = await Process.run(Platform.resolvedExecutable, [
    '--suppress-analytics',
    'compile',
    'aot-snapshot',
    app.entry,
    '-o',
    snapshot,
    '--extra-gen-snapshot-options=--print-instructions-sizes-to=$sizes',
  ], workingDirectory: p.join(root, app.packageDir));
  if (result.exitCode != 0) {
    throw _Failure(
      'dart compile aot-snapshot failed for ${app.name}:\n'
      '${result.stdout}${result.stderr}',
    );
  }
  final entries = (jsonDecode(File(sizes).readAsStringSync()) as List)
      .cast<Map<String, Object?>>();
  return AppReport(
    app,
    snapshotBytes: File(snapshot).lengthSync(),
    instructions: aggregateInstructions(entries, repoRoot: root),
  );
}

/// [value] with thousands separators.
String _n(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

String _percent(int part, int whole) =>
    whole == 0 ? '-' : '${(100 * part / whole).toStringAsFixed(1)}%';

void _table(Map<String, int> rows, {int? whole}) {
  final width = rows.keys.fold(0, (w, key) => key.length > w ? key.length : w);
  for (final MapEntry(:key, :value) in rows.entries) {
    final share = whole == null ? '' : '  ${_percent(value, whole)}';
    stdout.writeln('  ${key.padRight(width)}  ${_n(value).padLeft(12)}$share');
  }
}

void _printSources(SourceReport sources) {
  stdout
    ..writeln('Generated sources (*.spring.dart)')
    ..writeln(
      '  ${_n(sources.files.length)} files, ${_n(sources.totalLines)} lines, '
      '${_n(sources.totalBytes)} bytes',
    )
    ..writeln()
    ..writeln('  By package (lines / bytes):');
  final width = sources.byPackage.keys.fold(
    0,
    (w, key) => key.length > w ? key.length : w,
  );
  for (final MapEntry(:key, :value) in sources.byPackage.entries) {
    stdout.writeln(
      '    ${key.padRight(width)}  ${_n(value.lines).padLeft(8)}  '
      '${_n(value.bytes).padLeft(10)}',
    );
  }
  stdout
    ..writeln()
    ..writeln('  Files (lines / bytes):');
  final fileWidth = sources.files.fold(
    0,
    (w, file) => file.path.length > w ? file.path.length : w,
  );
  for (final file in sources.files) {
    stdout.writeln(
      '    ${file.path.padRight(fileWidth)}  ${_n(file.lines).padLeft(8)}  '
      '${_n(file.bytes).padLeft(10)}',
    );
  }
}

void _printApp(AppReport report) {
  final i = report.instructions;
  stdout
    ..writeln()
    ..writeln(
      'AOT ${report.app.name} '
      '(${p.posix.join(report.app.packageDir, report.app.entry)})',
    )
    ..writeln('  snapshot file          ${_n(report.snapshotBytes)} bytes')
    ..writeln('  instructions           ${_n(i.totalInstructions)} bytes')
    ..writeln(
      '  generated instructions ${_n(i.generatedInstructions)} bytes '
      '(${_percent(i.generatedInstructions, i.totalInstructions)})',
    )
    ..writeln(
      '  ...Proxy classes       ${_n(i.proxyInstructions)} bytes '
      '(${_percent(i.proxyInstructions, i.generatedInstructions)} '
      'of generated)',
    )
    ..writeln()
    ..writeln('  Generated libraries:');
  _table(i.generatedByLibrary, whole: i.totalInstructions);
  stdout
    ..writeln()
    ..writeln('  Top $topLibraryCount libraries / packages:');
  _table(i.topLibraries, whole: i.totalInstructions);
}
