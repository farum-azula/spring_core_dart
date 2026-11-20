import 'package:dart_spring_language_server/src/diagnostics/fix.dart';
import 'package:dart_spring_language_server/src/features/diagnostics.dart';
import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// Quick fixes: the [Problem.fixes] of the problems in the range the editor
/// asks about (a misspelt name changed to the one it was probably meant to
/// be, a key nothing defines added to the package's config file).
final class CodeActions extends ServerFeature {
  /// Quick fixes in [session].
  CodeActions(this.session);

  /// The session it serves.
  final SpringSession session;

  @override
  Map<String, Object?> get capabilities => const {
    'codeActionProvider': {
      'codeActionKinds': ['quickfix'],
    },
  };

  @override
  Map<String, RequestHandler> get requests => {
    'textDocument/codeAction': (params) {
      final path = pathOf((params['textDocument']! as Map)['uri'] as String);
      final asked = params['range']! as Map;
      final workspace = session.workspace..refresh();
      return [
        for (final problem in workspace.problems(path))
          if (_overlaps(problem.range, asked))
            for (final (index, fix) in problem.fixes.indexed)
              {
                'title': fix.title,
                'kind': 'quickfix',
                'diagnostics': [diagnosticJson(problem)],
                'isPreferred': index == 0,
                'edit': {'changes': _changes(fix)},
              },
      ];
    },
  };

  /// The edits of [fix] by the URI of their file.
  static Map<String, List<Map<String, Object?>>> _changes(Fix fix) {
    final changes = <String, List<Map<String, Object?>>>{};
    for (final edit in fix.edits) {
      changes.putIfAbsent(uriOf(edit.range.path), () => []).add({
        'range': rangeJson(edit.range),
        'newText': edit.newText,
      });
    }
    return changes;
  }

  /// Whether [range] and the protocol range [asked] share a position.
  static bool _overlaps(SourceRange range, Map<Object?, Object?> asked) {
    int compare(int line, int column, Map<Object?, Object?> position) {
      final otherLine = (position['line']! as num).toInt();
      return line != otherLine
          ? line.compareTo(otherLine)
          : column.compareTo((position['character']! as num).toInt());
    }

    final start = asked['start']! as Map;
    final end = asked['end']! as Map;
    return compare(range.startLine, range.startColumn, end) <= 0 &&
        compare(range.endLine, range.endColumn, start) >= 0;
  }
}
