import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/config/property_hover.dart';
import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/config/theme_loaders.dart';
import 'package:dart_spring_language_server/src/config/theme_names.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// A completion asked where a key of a config file is typed.
final class KeyCompletionRequest {
  /// A completion at [line], [column] of [document], of a key below
  /// [parents] (resolved to [resolution]) whose typed part starts at
  /// [start].
  KeyCompletionRequest(
    this.document,
    this.line,
    this.column,
    this.parents,
    this.start,
    this.resolution,
  ) : indent = keyIndentOf(document.lines[line]),
      hasColon = _hasColonAfter(document.lines[line], column);

  /// The document.
  final ConfigDocument document;

  /// The cursor's line.
  final int line;

  /// The cursor's column.
  final int column;

  /// The segments of the keys the typed key is below.
  final List<String> parents;

  /// The column where the typed segment starts.
  final int start;

  /// Where the schema puts [parents].
  final Resolution resolution;

  /// The column of the key of the line.
  final int indent;

  /// Whether the line already has a `:` after the cursor.
  final bool hasColon;

  /// The path of the document.
  String get path => document.path;

  /// The span a proposal replaces: the typed segment.
  SourceRange get range => document.range(line, start, column);

  /// The text a proposed key inserts.
  String insert(String name, {required bool group}) => document.format
      .keyInsert(name, group: group, indent: indent, hasColon: hasColon);

  static bool _hasColonAfter(String line, int column) {
    final text = line.replaceAll('\r', '');
    return text.substring(column.clamp(0, text.length)).contains(':');
  }
}

/// Proposes the keys that may be typed at a place of a config file.
/// Asked in order ([keyCompletionSources]); the first that handles the
/// place answers.
abstract interface class KeyCompletionSource {
  /// The proposals for [request]; `null` when the place is not this
  /// source's.
  Handled<CompletionResult>? complete(KeyCompletionRequest request);
}

/// The sources of key completion, in the order they are asked.
List<KeyCompletionSource> keyCompletionSources(ProjectModel model) => [
  LoaderKeys(model),
  const ColorKeys(),
  SchemaKeys(model),
];

/// The keys a loader takes, once its `kind` is written: the kind's own,
/// `kind`, `phases` and `web`.
final class LoaderKeys implements KeyCompletionSource {
  /// The keys of the loaders of [model].
  LoaderKeys(this.model) : _loaders = ThemeLoaders(model);

  /// What the workspace knows.
  final ProjectModel model;

  final ThemeLoaders _loaders;

  @override
  Handled<CompletionResult>? complete(KeyCompletionRequest request) {
    final relative = themeRelative(request.parents);
    if (relative == null ||
        relative.rest.length != 2 ||
        canonicalName(relative.rest[0]) != 'loaders') {
      return null;
    }
    final kind = ThemeLoaders.kindsOf(
      request.document.keys,
    )['${relative.theme}|${canonicalName(relative.rest[1])}'];
    final allowed = kind == null
        ? null
        : _loaders.keysOfKind(request.path, kind);
    if (allowed == null) {
      return null;
    }
    final schema = model.schemas.schemaFor(request.path);
    final base = [
      ...themePrefix,
      if (relative.theme != null) ...['themes', relative.theme!],
    ];
    return Handled(
      CompletionResult(request.range, [
        for (final name in [...loaderCommonKeys, ...allowed])
          _proposal(
            request,
            name,
            schema.nodeAt([...base, 'loaders', '*', name]),
          ),
      ]),
    );
  }

  static Completion _proposal(
    KeyCompletionRequest request,
    String name,
    SchemaNode? node,
  ) {
    final prop = node?.prop;
    final group =
        node != null &&
        (node.children.isNotEmpty || node.wildcard != null) &&
        prop == null;
    return Completion(
      name,
      kind: group ? 9 : 10,
      detail: prop == null ? null : propertyDetail(prop),
      documentation: prop == null ? null : propertyHover(name, prop),
      insertText: request.insert(name, group: group),
    );
  }
}

/// The parts of a theme color: a plain color key may become an object of
/// `color`, `alpha` and `mix`; below `mix`, `with` and `amount`.
final class ColorKeys implements KeyCompletionSource {
  /// The parts of colors.
  const ColorKeys();

  @override
  Handled<CompletionResult>? complete(KeyCompletionRequest request) {
    final node = request.resolution.node;
    final rest = request.resolution.rest;
    if (node == null) {
      return null;
    }
    final prop = node.prop;
    if (rest.isEmpty &&
        node.children.isEmpty &&
        node.wildcard == null &&
        (prop?.theme ?? false) &&
        prop!.type == 'color') {
      // A color may be a plain value or an object: offer its parts.
      return Handled(
        CompletionResult(request.range, [
          const Completion('color', detail: 'color', insertText: 'color: '),
          const Completion('alpha', detail: 'percent', insertText: 'alpha: '),
          Completion(
            'mix',
            detail: 'with, amount',
            insertText: request.document.format.nestedInsert(
              'mix',
              request.indent,
            ),
          ),
        ]),
      );
    }
    if (rest.isEmpty || prop?.type != 'color') {
      return null;
    }
    return Handled(
      rest.first == 'mix'
          ? CompletionResult(request.range, const [
              Completion('with', detail: 'color', insertText: 'with: '),
              Completion('amount', detail: 'percent', insertText: 'amount: '),
            ])
          : null,
    );
  }
}

/// The keys the schema has below the typed parents, and for a map the
/// names its keys usually have (the themes, the color roles, the shape
/// and elevation names, ...).
final class SchemaKeys implements KeyCompletionSource {
  /// The keys of the schema of [model].
  SchemaKeys(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<CompletionResult>? complete(KeyCompletionRequest request) {
    final node = request.resolution.node;
    if (node == null || node.open || request.resolution.rest.isNotEmpty) {
      return const Handled(null);
    }
    var order = 0;
    final items = [
      for (final child in node.named)
        _proposal(request, child, (1000 + order++).toString()),
      if (node.wildcard case final wildcard?) ..._mapKeys(request, wildcard),
    ];
    return Handled(
      items.isEmpty ? null : CompletionResult(request.range, items),
    );
  }

  static Completion _proposal(
    KeyCompletionRequest request,
    SchemaNode child,
    String sortText,
  ) {
    final prop = child.prop;
    final group = child.children.isNotEmpty || child.wildcard != null;
    return Completion(
      child.name,
      kind: group ? 9 : 10,
      detail: prop == null ? null : propertyDetail(prop),
      documentation: prop == null ? null : propertyHover(child.name, prop),
      insertText: request.insert(child.name, group: group),
      sortText: sortText,
    );
  }

  // Names for a map key of the theme: themes, color roles and so on.
  Iterable<Completion> _mapKeys(
    KeyCompletionRequest request,
    SchemaNode wildcard,
  ) {
    final parents = request.parents;
    final last = parents.isEmpty ? '' : canonicalName(parents.last);
    final names = isThemeKey(parents) || parents.length >= themePrefix.length
        ? _mapKeyNames(request.path, last)
        : const <String>[];
    final group = wildcard.children.isNotEmpty || wildcard.wildcard != null;
    return [
      for (final name in names)
        Completion(
          name,
          kind: 12,
          detail: wildcard.prop?.type,
          insertText: request.insert(name, group: group),
        ),
    ];
  }

  List<String> _mapKeyNames(String path, String map) => switch (map) {
    'themes' => ThemeNames(model).of(path),
    'colors' => colorRoles,
    'shape' => defaultShapeNames,
    'elevation' => [for (var i = 0; i < 6; i++) 'level$i'],
    'spacing' => const ['xs', 's', 'm', 'l', 'xl'],
    'durations' => const ['short', 'medium', 'long'],
    _ => const [],
  };
}
