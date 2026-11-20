import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/config/config_value_role.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/templates.dart';

/// A `${key}` placeholder or a `#{...}` SpEL expression in a value: the
/// key goes to its definitions in the package's config files and shows
/// them with its description; the expression's beans and members are read
/// by the SpEL editor. An open `${` completes with the known keys, an open
/// `#{` with SpEL.
final class TemplateValue extends ConfigValueRole {
  /// The role over [model].
  const TemplateValue(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<String>? hover(ConfigDocument document, ConfigKey key, int column) {
    final inside = ConfigDocument.templateAt(key, column);
    if (inside == null) {
      return null;
    }
    final (part, source) = inside;
    if (part.kind == TemplatePartKind.placeholder) {
      return Handled(_placeholderHover(document.path, part.inner(source)));
    }
    return Handled(
      model.spel.hover(
        source.substring(part.innerStart, part.innerEnd),
        column - key.valueStart - part.innerStart,
      ),
    );
  }

  String _placeholderHover(String path, String key) {
    final entries = model.properties.property(key, from: path);
    final prop = model.schemas.schemaFor(path).nodeAt(splitKey(key))?.prop;
    return [
      '**`$key`**',
      if (prop?.description case final text?) ...['', text],
      '',
      if (entries.isEmpty)
        'not defined in any properties file'
      else
        for (final entry in entries)
          if (entry.provider case final provider?)
            '- provided by `$provider` (`@ServiceConnection`)'
          else
            '- `${entry.fileName}`: `${entry.value}`',
    ].join('\n');
  }

  @override
  Handled<List<SourceRange>>? definition(
    ConfigDocument document,
    ConfigKey key,
    int column,
  ) {
    final inside = ConfigDocument.templateAt(key, column);
    if (inside == null) {
      return null;
    }
    final (part, source) = inside;
    if (part.kind == TemplatePartKind.placeholder) {
      return Handled([
        for (final entry in model.properties.property(
          part.inner(source),
          from: document.path,
        ))
          SourceRange(
            entry.path,
            entry.line,
            entry.keyStart,
            entry.line,
            entry.keyEnd,
          ),
      ]);
    }
    return Handled([
      for (final bean in model.spel.definition(
        source.substring(part.innerStart, part.innerEnd),
        column - key.valueStart - part.innerStart,
      ))
        if (bean.path.isNotEmpty) model.locations.beanRange(bean),
    ]);
  }

  @override
  Handled<CompletionResult>? complete(ValueCompletionRequest request) {
    final placeholder = RegExp(r'\$\{([^}:]*)$').firstMatch(request.valueText);
    if (placeholder != null) {
      final typed = placeholder.group(1)!;
      return Handled(
        CompletionResult(
          request.rangeFrom(
            request.valueStart + placeholder.end - typed.length,
          ),
          [
            for (final key in model.schemas.knownKeys(request.path))
              Completion(key, detail: 'property'),
          ],
        ),
      );
    }
    final spel = RegExp(r'#\{([^}]*)$').firstMatch(request.valueText);
    if (spel == null) {
      return null;
    }
    final result = model.spel.complete(spel.group(1)!);
    return Handled(
      result == null
          ? null
          : CompletionResult(
              request.rangeFrom(
                request.valueStart + spel.start + 2 + result.$1,
              ),
              result.$2,
            ),
    );
  }
}
