import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/config/config_value_role.dart';
import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/config/theme_references.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// A `$` reference in a theme value (`$colors.primary`, `$brand.cyan`):
/// it shows the values it has in each theme, goes to its declaration (of
/// the key's own theme first), and completes with the sections, tokens,
/// roles and declared keys.
final class ThemeReferenceValue extends ConfigValueRole {
  /// The role over [model].
  const ThemeReferenceValue(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  // The reference at [column] of [key]'s theme value.
  static ThemeReference? _referenceAt(ConfigKey key, int column) {
    if (!isThemeKey(key.segments)) {
      return null;
    }
    final relative = column - key.valueStart;
    for (final reference in themeReferences(key.value!)) {
      if (relative >= reference.start && relative <= reference.end) {
        return reference;
      }
    }
    return null;
  }

  @override
  Handled<String>? hover(ConfigDocument document, ConfigKey key, int column) {
    final reference = _referenceAt(key, column);
    return reference == null
        ? null
        : Handled(
            ThemeReferences(
              model.properties,
              document.path,
            ).hover(reference.path),
          );
  }

  @override
  Handled<List<SourceRange>>? definition(
    ConfigDocument document,
    ConfigKey key,
    int column,
  ) {
    final reference = _referenceAt(key, column);
    return reference == null
        ? null
        : Handled(
            ThemeReferences(
              model.properties,
              document.path,
            ).definitions(reference.path, themeOf(key.segments)),
          );
  }

  @override
  Handled<CompletionResult>? complete(ValueCompletionRequest request) {
    final text = request.valueText;
    final typedReference = RegExp(r'\$([A-Za-z0-9_.\-]*)$').firstMatch(text);
    if (!isThemeKey(request.segments) ||
        typedReference == null ||
        text.endsWith(r'$$')) {
      return null;
    }
    final typed = typedReference.group(1)!;
    final dot = typed.lastIndexOf('.');
    final items = ThemeReferences(model.properties, request.path).complete(
      dot < 0 ? const [] : splitKey(typed.substring(0, dot)),
    );
    final from =
        request.valueStart + typedReference.start + 1 + (dot < 0 ? 0 : dot + 1);
    return Handled(
      items.isEmpty ? null : CompletionResult(request.rangeFrom(from), items),
    );
  }
}
