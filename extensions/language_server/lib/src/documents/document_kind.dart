import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/config_editor.dart';
import 'package:dart_spring_language_server/src/config/config_format.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/documents/dart_completion.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';

/// A kind of document the server answers for: what it does with each of
/// the editor's questions about such a document.
///
/// The kinds are registered once ([documentKinds]); the first that
/// accepts a path answers for it, and a path no kind accepts gets empty
/// answers.
abstract interface class DocumentKind {
  /// Whether [path] is a document of this kind.
  bool accepts(String path);

  /// The targets of go to definition at [offset] of [path].
  List<SourceRange> definition(String path, int offset);

  /// The hover at [offset] of [path].
  String? hover(String path, int offset);

  /// The proposals at [offset] of [path].
  CompletionResult? completion(String path, int offset);

  /// The semantic tokens of [path], sorted by position.
  List<SemanticToken> tokens(String path);

  /// The problems of [path].
  List<Problem> problems(String path);
}

/// The kinds of documents, in the order they are asked.
List<DocumentKind> documentKinds(ProjectModel model) => [
  ConfigDocuments(model.config),
  DartDocuments(model),
];

/// Config files (`.properties`, `application*.yaml`, YAML under
/// `resources/`).
final class ConfigDocuments implements DocumentKind {
  /// Config files, answered by [editor].
  const ConfigDocuments(this.editor);

  /// The editing features of config files.
  final ConfigEditor editor;

  @override
  bool accepts(String path) => ConfigFormat.isConfigFile(path);

  @override
  List<SourceRange> definition(String path, int offset) =>
      editor.definition(path, offset);

  @override
  String? hover(String path, int offset) => editor.hover(path, offset);

  @override
  CompletionResult? completion(String path, int offset) =>
      editor.completion(path, offset);

  @override
  List<SemanticToken> tokens(String path) => editor.tokens(path);

  @override
  List<Problem> problems(String path) => editor.problems(path);
}

/// Dart files.
final class DartDocuments implements DocumentKind {
  /// Dart files of [model].
  DartDocuments(this.model) : _completion = DartCompletion(model);

  /// What the workspace knows.
  final ProjectModel model;

  final DartCompletion _completion;

  @override
  bool accepts(String path) => path.endsWith('.dart');

  @override
  List<SourceRange> definition(String path, int offset) =>
      model.symbols.definition(path, offset);

  @override
  String? hover(String path, int offset) => model.symbols.hover(path, offset);

  @override
  CompletionResult? completion(String path, int offset) =>
      _completion.completion(path, offset);

  @override
  List<SemanticToken> tokens(String path) {
    final file = model.files.dartFile(path);
    return file == null ? const [] : model.tokens.of(file);
  }

  @override
  List<Problem> problems(String path) => model.problems.problems(path);
}
