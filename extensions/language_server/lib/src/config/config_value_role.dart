import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// What a value of a config file means, and what the editor does with
/// it: a `${key}` or `#{...}`, a path of the navigation, a `$` reference
/// of the theme, the name of a loader, a value the schema describes.
///
/// Like the roles of Dart strings, a role implements what applies and the
/// roles are registered once, in order (`configValueRoles`); the first
/// that handles a value answers.
abstract class ConfigValueRole {
  /// A role.
  const ConfigValueRole();

  /// The hover at [column] of [key]'s value in [document]; `null` when the
  /// value is not this role's there.
  Handled<String>? hover(ConfigDocument document, ConfigKey key, int column) =>
      null;

  /// Where go to definition leads from [column] of [key]'s value; `null`
  /// when the value is not this role's there.
  Handled<List<SourceRange>>? definition(
    ConfigDocument document,
    ConfigKey key,
    int column,
  ) => null;

  /// The completion of the value of [request]; `null` when the value is
  /// not this role's.
  Handled<CompletionResult>? complete(ValueCompletionRequest request) => null;
}

/// A completion asked in a value of a config file.
final class ValueCompletionRequest {
  /// A completion at [line], [column] of [document], in the value of the
  /// key [segments], typed so far as [valueText] from [valueStart].
  const ValueCompletionRequest(
    this.document,
    this.line,
    this.column,
    this.segments,
    this.valueText,
    this.valueStart,
  );

  /// The document.
  final ConfigDocument document;

  /// The cursor's line.
  final int line;

  /// The cursor's column.
  final int column;

  /// The whole path of the key whose value is typed.
  final List<String> segments;

  /// The value from its start to the cursor.
  final String valueText;

  /// The column where the value starts.
  final int valueStart;

  /// The path of the document.
  String get path => document.path;

  /// The span from column [from] to the cursor.
  SourceRange rangeFrom(int from) => document.range(line, from, column);
}
