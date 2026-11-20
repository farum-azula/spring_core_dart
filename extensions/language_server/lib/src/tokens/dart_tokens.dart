import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/query_editor.dart';
import 'package:dart_spring_language_server/src/strings/string_roles.dart';
import 'package:dart_spring_language_server/src/tokens/closure_parameters.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';

/// Finds semantic tokens of one kind in a Dart file.
abstract interface class DartTokenSource {
  /// Calls [add] with the offsets and type of each token of [file].
  void tokens(DartFile file, AddToken add);
}

/// What is highlighted in a Dart file: a new kind of token is a new
/// [DartTokenSource] and one entry here.
List<DartTokenSource> dartTokenSources(ProjectModel model) => [
  StringTokens(model.roles),
  QueryTokens(model.query),
  const ClosureParameterTokens(),
];

/// The tokens the string roles find: placeholders and SpEL of annotation
/// strings, the SpEL arguments of the cache annotations, pointcuts.
final class StringTokens implements DartTokenSource {
  /// Tokens of the strings, as [roles] read them.
  const StringTokens(this.roles);

  /// The roles a string can have.
  final StringRoles roles;

  @override
  void tokens(DartFile file, AddToken add) =>
      roles.tokens(DartFileFacts.of(file).strings, add);
}

/// The SQL of `@Query` methods.
final class QueryTokens implements DartTokenSource {
  /// Tokens of the queries, as [editor] reads them.
  const QueryTokens(this.editor);

  /// The editor of `@Query` texts.
  final QueryEditor editor;

  @override
  void tokens(DartFile file, AddToken add) => editor.tokens(file, add);
}

/// The parameters of closures, where they are declared and used.
final class ClosureParameterTokens implements DartTokenSource {
  /// The closure parameters' tokens.
  const ClosureParameterTokens();

  @override
  void tokens(DartFile file, AddToken add) => file.unit.accept(
    ClosureParameterFinder(
      (start, end) => add(start, end, TokenType.closureParameter),
    ),
  );
}

/// The semantic tokens of Dart files.
final class DartTokens {
  /// Tokens over [model].
  DartTokens(ProjectModel model) : _sources = dartTokenSources(model);

  final List<DartTokenSource> _sources;

  /// The tokens of [file], sorted by position. A token that would span
  /// lines is left out.
  List<SemanticToken> of(DartFile file) {
    final tokens = <SemanticToken>[];
    void add(int start, int end, TokenType type, [int modifiers = 0]) {
      if (end <= start) {
        return;
      }
      final from = file.lineInfo.getLocation(start);
      final to = file.lineInfo.getLocation(end);
      if (from.lineNumber != to.lineNumber) {
        return; // tokens must not span lines
      }
      tokens.add(
        SemanticToken(
          from.lineNumber - 1,
          from.columnNumber - 1,
          end - start,
          type,
          modifiers: modifiers,
        ),
      );
    }

    for (final source in _sources) {
      source.tokens(file, add);
    }
    return tokens..sort(
      (a, b) => a.line != b.line ? a.line - b.line : a.column - b.column,
    );
  }
}
