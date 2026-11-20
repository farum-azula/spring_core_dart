import 'dart:async';
import 'dart:io';

import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// Diagnostics of the open documents ([SpringWorkspace.problems] and
/// [SpringWorkspace.metadataNotes]), published [delay] after the last
/// change: a change of one file (a config file, a bean) may change the
/// diagnostics of the others, so all open documents are checked again.
final class Diagnostics extends ServerFeature {
  /// Diagnostics of [session].
  Diagnostics(this.session, {this.delay = const Duration(milliseconds: 300)}) {
    session.onChange(_schedule);
  }

  /// The session it serves.
  final SpringSession session;

  /// How long after the last change the diagnostics are published.
  final Duration delay;

  Timer? _timer;

  @override
  void dispose() => _timer?.cancel();

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(delay, _publish);
  }

  void _publish() {
    final workspace = session.workspace..refresh();
    for (final path in session.openDocuments) {
      final List<Problem> problems;
      try {
        problems = [
          ...workspace.problems(path),
          ...workspace.metadataNotes(path),
        ];
      } on Object catch (error, stackTrace) {
        // One broken file must not stop the others' diagnostics.
        stderr.writeln(
          'dart_spring_lsp: diagnostics of $path: $error\n$stackTrace',
        );
        continue;
      }
      session.editor.notify('textDocument/publishDiagnostics', {
        'uri': uriOf(path),
        'diagnostics': [
          for (final problem in problems) diagnosticJson(problem),
        ],
      });
    }
  }
}

/// [problem] as an LSP `Diagnostic`, as it is published and as a quick fix
/// names it.
Map<String, Object?> diagnosticJson(Problem problem) => {
  'range': rangeJson(problem.range),
  'severity': problem.error ? 1 : (problem.info ? 3 : 2),
  'source': 'dart_spring',
  'message': problem.message,
};
