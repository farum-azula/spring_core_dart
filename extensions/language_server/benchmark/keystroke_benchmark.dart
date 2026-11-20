// Measures what a keystroke costs the language server: the editor sends
// the whole document after each key (`setOverlay`), then asks for the
// diagnostics (`problems`) and the semantic tokens of the file.
//
//   dart run benchmark/keystroke_benchmark.dart \
//     [--root <workspace folder>] [--file <Dart file>] [--keys <count>]
//
// Defaults: the whole repository as the workspace; two files of the server
// guide: OrderService (its placeholders have defaults) and the supplier's
// configuration (a placeholder without a default, which asks the schema
// of known keys); 12 keystrokes typed into a method body, then 4 edits of
// a class annotation (those change what the bean index reads).
import 'dart:io';

import 'package:dart_spring_language_server/src/workspace.dart';

void main(List<String> arguments) {
  String option(String name, String fallback) {
    final index = arguments.indexOf('--$name');
    return index >= 0 && index + 1 < arguments.length
        ? arguments[index + 1]
        : fallback;
  }

  final repository = _repositoryRoot();
  final root = option('root', repository);
  final guide = '$repository/example/server_guide/lib/src';
  final paths = arguments.contains('--file')
      ? [option('file', '')]
      : [
          '$guide/orders/order_service.dart',
          '$guide/supplier/supplier_config.dart',
        ];
  final keys = int.parse(option('keys', '12'));

  final workspace = SpringWorkspace([root]);
  final scan = Stopwatch()..start();
  workspace.refresh(force: true);
  scan.stop();
  final rescan = Stopwatch()..start();
  workspace.refresh(force: true);
  rescan.stop();

  stdout
    ..writeln('workspace: $root')
    ..writeln('first scan:              ${_ms(scan.elapsedMicroseconds)}')
    ..writeln('rescan, nothing changed: ${_ms(rescan.elapsedMicroseconds)}');
  for (final path in paths) {
    _benchmark(workspace, path, keys);
  }
}

void _benchmark(SpringWorkspace workspace, String path, int keys) {
  final original = File(path).readAsStringSync();
  final cold = Stopwatch()..start();
  workspace
    ..setOverlay(path, original)
    ..problems(path)
    ..semanticTokens(path);
  cold.stop();
  stdout
    ..writeln()
    ..writeln('file: $path')
    ..writeln('first problems + tokens: ${_ms(cold.elapsedMicroseconds)}');

  // Typing a statement into the first method body, one key at a time.
  final body = original.indexOf(') {\n');
  final at = original.indexOf('\n', body) + 1;
  const typed = '    final typedByTheBenchmark = 1;\n';
  final bodyTimes = _type(
    workspace,
    path,
    [
      for (var i = 1; i <= keys; i++)
        original.replaceRange(
          at,
          at,
          typed.substring(0, i.clamp(0, typed.length)),
        ),
    ],
  );
  _report('keystroke in a method body', bodyTimes);

  // Adding and removing an annotation of the first class: the bean index
  // must be built again.
  final declaration = original.indexOf('\nclass ') + 1;
  final annotated = original.replaceRange(
    declaration,
    declaration,
    '@Lazy()\n',
  );
  final annotationTimes = _type(workspace, path, [
    for (var i = 0; i < 4; i++)
      if (i.isEven) annotated else original,
  ]);
  _report('edit of a class annotation', annotationTimes);
  workspace.setOverlay(path, null);
}

typedef _Times = ({List<int> overlay, List<int> problems, List<int> tokens});

_Times _type(SpringWorkspace workspace, String path, List<String> texts) {
  final times = (overlay: <int>[], problems: <int>[], tokens: <int>[]);
  for (final text in texts) {
    final watch = Stopwatch()..start();
    workspace.setOverlay(path, text);
    times.overlay.add(watch.elapsedMicroseconds);
    watch.reset();
    workspace.problems(path);
    times.problems.add(watch.elapsedMicroseconds);
    watch.reset();
    workspace.semanticTokens(path);
    times.tokens.add(watch.elapsedMicroseconds);
  }
  return times;
}

void _report(String title, _Times times) {
  final total = [
    for (var i = 0; i < times.overlay.length; i++)
      times.overlay[i] + times.problems[i] + times.tokens[i],
  ];
  stdout
    ..writeln('$title (${total.length} edits), median / mean:')
    ..writeln('  setOverlay      ${_stats(times.overlay)}')
    ..writeln('  problems        ${_stats(times.problems)}')
    ..writeln('  semanticTokens  ${_stats(times.tokens)}')
    ..writeln('  total           ${_stats(total)}');
}

String _stats(List<int> micros) {
  final sorted = [...micros]..sort();
  final median = sorted[sorted.length ~/ 2];
  final mean = micros.reduce((a, b) => a + b) ~/ micros.length;
  return '${_ms(median)} / ${_ms(mean)}';
}

String _ms(int micros) => '${(micros / 1000).toStringAsFixed(1)} ms';

// The repository: three levels above this package's benchmark folder.
String _repositoryRoot() {
  final script = File.fromUri(Platform.script).absolute.path;
  final package = File(script).parent.parent.path;
  return Directory(package).parent.parent.path;
}
