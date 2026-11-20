import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/query_editor.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/strings/string_roles.dart';

/// Proposes completions in a part of a Dart file it knows. Asked in order
/// ([dartCompletionSources]); the first that answers wins.
abstract interface class DartCompletionSource {
  /// The completion at [offset] of [file]; `null` when there is none here.
  CompletionResult? complete(DartFile file, int offset);
}

/// The parts of a Dart file with their own completion, in the order they
/// are asked.
List<DartCompletionSource> dartCompletionSources(ProjectModel model) => [
  QueryCompletion(model.query),
  StringCompletion(model.roles),
];

/// The SQL of `@Query` methods: tables, columns, parameters.
final class QueryCompletion implements DartCompletionSource {
  /// Completion through [editor].
  const QueryCompletion(this.editor);

  /// The editor of `@Query` texts.
  final QueryEditor editor;

  @override
  CompletionResult? complete(DartFile file, int offset) =>
      editor.completion(file, file.path, offset);
}

/// Inside a string, on its first line up to the cursor: what the string's
/// role proposes (`${key}`, `#{@bean.member}`, profile names, bean names,
/// property keys, message codes, routes).
final class StringCompletion implements DartCompletionSource {
  /// Completion through [roles].
  const StringCompletion(this.roles);

  /// The roles a string can have.
  final StringRoles roles;

  @override
  CompletionResult? complete(DartFile file, int offset) {
    final node = file.nodeAt(offset);
    if (node is! SimpleStringLiteral ||
        offset < node.contentsOffset ||
        offset > node.contentsEnd) {
      return null;
    }
    final request = CompletionRequest(StringContext.of(file, node), offset);
    if (request.before.contains('\n')) {
      return null;
    }
    return roles.complete(request);
  }
}

/// Completion in Dart files.
final class DartCompletion {
  /// Completion over [model].
  DartCompletion(ProjectModel model)
    : _model = model,
      _sources = dartCompletionSources(model);

  final ProjectModel _model;
  final List<DartCompletionSource> _sources;

  /// The proposals at [offset] of the Dart file [path]; `null` when there
  /// is nothing to propose.
  CompletionResult? completion(String path, int offset) {
    final file = _model.files.dartFile(path);
    if (file == null) {
      return null;
    }
    for (final source in _sources) {
      if (source.complete(file, offset) case final result?) {
        return result;
      }
    }
    return null;
  }
}
