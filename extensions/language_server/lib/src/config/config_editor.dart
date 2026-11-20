import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/config/config_problems.dart';
import 'package:dart_spring_language_server/src/config/config_tokens.dart';
import 'package:dart_spring_language_server/src/config/config_values.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';

/// The editing features of config files: completion, hover, definition,
/// highlighting and diagnostics for keys, values, `${}`, `#{}` and the
/// theme, each done by its own part ([ConfigNavigation],
/// [ConfigProblems], [configTokens]) on the file's current text.
final class ConfigEditor {
  /// The features over [model].
  ConfigEditor(this.model)
    : _navigation = ConfigNavigation(model),
      _problems = ConfigProblems(model);

  /// What the workspace knows.
  final ProjectModel model;

  final ConfigNavigation _navigation;
  final ConfigProblems _problems;

  ConfigDocument? _document(String path) {
    final text = model.files.textOf(path);
    return text == null ? null : ConfigDocument(path, text);
  }

  /// The proposals at [offset] of the config file [path].
  CompletionResult? completion(String path, int offset) {
    final document = _document(path);
    return document == null ? null : _navigation.completion(document, offset);
  }

  /// The hover at [offset] of the config file [path].
  String? hover(String path, int offset) {
    final document = _document(path);
    return document == null ? null : _navigation.hover(document, offset);
  }

  /// Where go to definition leads from [offset] of the config file [path].
  List<SourceRange> definition(String path, int offset) {
    final document = _document(path);
    return document == null
        ? const []
        : _navigation.definition(document, offset);
  }

  /// The problems of the config file [path].
  List<Problem> problems(String path) {
    final document = _document(path);
    return document == null ? const [] : _problems.problems(document);
  }

  /// The semantic tokens of the config file [path].
  List<SemanticToken> tokens(String path) {
    final document = _document(path);
    return document == null ? const [] : configTokens(document);
  }
}
