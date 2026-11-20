import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/config/config_value_role.dart';
import 'package:dart_spring_language_server/src/config/key_completion.dart';
import 'package:dart_spring_language_server/src/config/property_hover.dart';
import 'package:dart_spring_language_server/src/config/values/loader_value.dart';
import 'package:dart_spring_language_server/src/config/values/navigation_value.dart';
import 'package:dart_spring_language_server/src/config/values/schema_value.dart';
import 'package:dart_spring_language_server/src/config/values/template_value.dart';
import 'package:dart_spring_language_server/src/config/values/theme_reference_value.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// The roles a value of a config file can have, in the order they are
/// asked: a new kind of value is a new [ConfigValueRole] and one entry
/// here.
List<ConfigValueRole> configValueRoles(ProjectModel model) => [
  TemplateValue(model),
  NavigationValue(model),
  ThemeReferenceValue(model),
  LoaderValue(model),
  SchemaValue(model),
];

/// Hovers, definitions and completion in config files: the value roles
/// for values, the schema for keys.
final class ConfigNavigation {
  /// Navigation over [model].
  ConfigNavigation(this.model)
    : _roles = configValueRoles(model),
      _keySources = keyCompletionSources(model);

  /// What the workspace knows.
  final ProjectModel model;

  final List<ConfigValueRole> _roles;
  final List<KeyCompletionSource> _keySources;

  /// The hover at [offset] of [document]: about the value there, else
  /// about the key (its type, description, default, values).
  String? hover(ConfigDocument document, int offset) {
    final (line, column) = document.lineColumn(offset);
    if (document.valueAt(line, column) case final key?) {
      for (final role in _roles) {
        if (role.hover(document, key, column) case final handled?) {
          return handled.value;
        }
      }
    }
    final at = document.keyAt(line, column);
    if (at == null) {
      return null;
    }
    final (key, index) = at;
    final segments = key.segments.sublist(0, index + 1);
    final resolution = model.schemas.schemaFor(document.path).resolve(segments);
    final node = resolution.node;
    if (resolution.isUnknown || node == null) {
      return null;
    }
    final prop = node.prop;
    if (prop == null) {
      return '**${segments.join('.')}**';
    }
    return propertyHover(
      segments.join('.'),
      prop,
      value: index == key.segments.length - 1 ? key.value : null,
    );
  }

  /// Where go to definition leads from the value at [offset] of
  /// [document].
  List<SourceRange> definition(ConfigDocument document, int offset) {
    final (line, column) = document.lineColumn(offset);
    final key = document.valueAt(line, column);
    if (key == null) {
      return const [];
    }
    for (final role in _roles) {
      if (role.definition(document, key, column) case final handled?) {
        return handled.value ?? const [];
      }
    }
    return const [];
  }

  /// The proposals at [offset] of [document]: keys where a key is typed,
  /// what the value roles propose in a value.
  CompletionResult? completion(ConfigDocument document, int offset) {
    final (line, column) = document.lineColumn(offset);
    final lines = document.lines;
    if (line >= lines.length) {
      return null;
    }
    final current = lines[line].replaceAll('\r', '');
    final before = current.substring(0, column.clamp(0, current.length));
    final format = document.format;
    if (format.inComment(before)) {
      return null;
    }
    final split = format.valueSplit(before);
    if (split == null) {
      return _keyCompletion(document, line, column, before);
    }
    final request = ValueCompletionRequest(
      document,
      line,
      column,
      format.keyPath(lines, line, split.key),
      split.value,
      split.start,
    );
    for (final role in _roles) {
      if (role.complete(request) case final handled?) {
        return handled.value;
      }
    }
    return null;
  }

  CompletionResult? _keyCompletion(
    ConfigDocument document,
    int line,
    int column,
    String before,
  ) {
    final typing = document.format.keyTyping(document.lines, line, before);
    if (typing == null) {
      return null;
    }
    final resolution = model.schemas
        .schemaFor(document.path)
        .resolve(typing.parents);
    if (resolution.isUnknown) {
      return null;
    }
    final request = KeyCompletionRequest(
      document,
      line,
      column,
      typing.parents,
      typing.start,
      resolution,
    );
    for (final source in _keySources) {
      if (source.complete(request) case final handled?) {
        return handled.value;
      }
    }
    return null;
  }
}
