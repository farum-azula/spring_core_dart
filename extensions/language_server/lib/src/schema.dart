// The fields mirror the metadata format (roadmap/spring_metadata.md).
// ignore_for_file: public_member_api_docs
import 'package:dart_spring_language_server/src/metadata.dart';

/// The prefix of the theme keys in `application.yml`.
const themePrefix = ['spring', 'flutter', 'theme'];

/// Lower case without `-` and `_`: the way the framework compares names.
String canonicalName(String name) =>
    name.toLowerCase().replaceAll('-', '').replaceAll('_', '');

/// What the editor knows about one key: from the metadata, or built in for
/// the theme keys the metadata does not list yet.
final class SchemaProp {
  const SchemaProp({
    required this.name,
    required this.type,
    this.description,
    this.defaultValue,
    this.deprecated,
    this.source,
    this.line,
    this.className,
    this.package,
    this.states = false,
    this.values = const [],
    this.flutter,
    this.hint,
    this.theme = false,
    this.fromCode = false,
  });

  /// The full key, or for a theme key the name relative to a theme.
  final String name;
  final String type;
  final String? description;
  final Object? defaultValue;
  final Object? deprecated;
  final String? source;
  final int? line;
  final String? className;
  final String? package;

  /// Theme only: the value may be a map of states.
  final bool states;

  /// Allowed words (a choice), from the theme or from the hint.
  final List<(String, String?)> values;
  final String? flutter;
  final MetaHint? hint;
  final bool theme;

  /// Known only because some code reads it (`@Value`, ...): no description.
  final bool fromCode;

  SchemaProp withHint(MetaHint hint) => SchemaProp(
    name: name,
    type: type,
    description: description,
    defaultValue: defaultValue,
    deprecated: deprecated,
    source: source,
    line: line,
    className: className,
    package: package,
    states: states,
    values: hint.values.isNotEmpty && values.isEmpty ? hint.values : values,
    flutter: flutter,
    hint: hint,
    theme: theme,
    fromCode: fromCode,
  );
}

/// A node of the tree of known keys.
final class SchemaNode {
  SchemaNode(this.name);

  /// The name as written in the metadata (kebab case).
  final String name;
  final children = <String, SchemaNode>{};
  SchemaNode? wildcard;
  SchemaProp? prop;

  /// Everything below is accepted without checks (tokens, styles, ...).
  bool open = false;

  /// Whether a property of the metadata (not only a hint or a key some code
  /// reads) lives at or below this node: only then is an unknown child
  /// reported, since the code may read keys the metadata does not list.
  bool real = false;

  SchemaNode child(String segment) {
    if (segment == '*') {
      return wildcard ??= SchemaNode('*');
    }
    return children.putIfAbsent(
      canonicalName(segment),
      () => SchemaNode(segment),
    );
  }

  /// The named children in the order they were added.
  Iterable<SchemaNode> get named => children.values;
}

/// Where a key landed in the tree.
final class Resolution {
  const Resolution({
    this.node,
    this.rest = const [],
    this.parent,
    this.unknown,
    this.depth = 0,
  });

  /// The node reached; for a leaf with more segments after it, the leaf.
  final SchemaNode? node;

  /// The segments left after a leaf (map keys, list items, color object
  /// parts, states).
  final List<String> rest;

  /// For an unknown key: the node whose children did not have [unknown].
  final SchemaNode? parent;
  final String? unknown;

  /// How many segments were matched before [unknown].
  final int depth;

  bool get isUnknown => unknown != null;
}

/// Splits a flat key like `shop.servers[0].host` into segments, an index as
/// `[0]`.
List<String> splitKey(String key) {
  final result = <String>[];
  for (final part in key.split('.')) {
    final bracket = part.indexOf('[');
    if (bracket <= 0) {
      if (part.isNotEmpty) {
        result.add(part);
      }
      continue;
    }
    result
      ..add(part.substring(0, bracket))
      ..addAll(RegExp(r'\[[^\]]*\]').allMatches(part).map((m) => m[0]!));
  }
  return result;
}

/// The known keys of a package and its dependencies: properties and hints
/// from the metadata, the theme keys, and the keys the code reads.
final class Schema {
  Schema._(this.root);

  /// Builds the tree. [codeKeys] are keys the workspace's code reads that no
  /// metadata describes.
  factory Schema.build(
    MetadataView view, {
    Iterable<String> codeKeys = const [],
  }) {
    final root = SchemaNode('');
    final schema = Schema._(root);
    for (final key in codeKeys) {
      schema._add(
        splitKey(key),
        SchemaProp(name: key, type: 'String', fromCode: true),
        keepExisting: true,
      );
    }
    for (final p in view.properties) {
      schema._add(
        splitKey(p.name.replaceAll('[*]', '.*')),
        SchemaProp(
          name: p.name,
          type: p.type,
          description: p.description,
          defaultValue: p.defaultValue,
          deprecated: p.deprecated,
          source: p.source,
          line: p.line,
          className: p.className,
          package: p.package,
        ),
        real: true,
      );
    }
    for (final hint in view.hints) {
      final node = schema._node(splitKey(hint.name.replaceAll('[*]', '.*')));
      final existing = node.prop;
      node.prop = existing == null
          ? SchemaProp(
              name: hint.name,
              type: 'String',
              hint: hint,
              values: hint.values,
            )
          : existing.withHint(hint);
    }
    schema._addTheme(view);
    return schema;
  }

  final SchemaNode root;

  SchemaNode _node(List<String> segments, {bool real = false}) {
    var node = root;
    for (final segment in segments) {
      node = node.child(segment.startsWith('[') ? '*' : segment);
      if (real) {
        node.real = true;
      }
    }
    return node;
  }

  void _add(
    List<String> segments,
    SchemaProp prop, {
    bool keepExisting = false,
    bool real = false,
  }) {
    final node = _node(segments, real: real);
    if (keepExisting && node.prop != null) {
      return;
    }
    node.prop = prop;
  }

  // The theme: `theme.properties` of the metadata. A key lives at the root
  // of `spring.flutter.theme` and under `themes.<name>`, unless its scope
  // says otherwise.
  void _addTheme(MetadataView view) {
    final themeRoot = _node(themePrefix, real: true);
    final themes = (themeRoot.child('themes')..real = true).child('*')
      ..real = true;
    if (view.themeProperties.isEmpty) {
      // Without the starter's theme metadata nothing is known: accept any
      // key (the editor then shows the note to run build_runner).
      themeRoot.open = true;
      themes.open = true;
      return;
    }
    final kinds = [for (final k in view.loaderKinds) k.name];
    for (final property in view.themeProperties) {
      var key = _ThemeKey.from(property);
      // A kind of the app's own is a kind too.
      if (key.path.join('.') == 'loaders.*.kind') {
        key = key.withValues([...key.values, ...kinds]);
      }
      if (property.scope != 'theme') {
        _addThemeKey(themeRoot, key);
      }
      if (property.scope != 'root') {
        _addThemeKey(themes, key);
      }
    }
  }

  void _addThemeKey(SchemaNode base, _ThemeKey key) {
    var node = base..real = true;
    for (final segment in key.path) {
      node = node.child(segment)..real = true;
    }
    node
      ..open = key.open
      ..prop = SchemaProp(
        name: key.path.join('.'),
        type: key.type,
        description: key.description,
        defaultValue: key.defaultValue,
        states: key.states,
        values: [for (final v in key.values) (v, null)],
        flutter: key.flutter,
        theme: true,
      );
  }

  /// Walks [segments] down the tree.
  Resolution resolve(List<String> segments) {
    var node = root;
    for (var i = 0; i < segments.length; i++) {
      if (node.open) {
        return Resolution(node: node, rest: segments.sublist(i));
      }
      final segment = segments[i];
      final next =
          node.children[canonicalName(segment)] ??
          (segment.startsWith('[') ? node.wildcard : null) ??
          node.wildcard;
      if (next == null) {
        if (node.prop != null && node.children.isEmpty) {
          return Resolution(node: node, rest: segments.sublist(i));
        }
        return Resolution(
          parent: node,
          unknown: segment,
          depth: i,
          node: node,
        );
      }
      node = next;
    }
    return Resolution(node: node);
  }

  /// The node for [segments] when it exists, with no wildcard guessing.
  SchemaNode? nodeAt(List<String> segments) {
    var node = root;
    for (final segment in segments) {
      final next =
          node.children[canonicalName(segment)] ??
          (segment.startsWith('[') ? node.wildcard : null) ??
          node.wildcard;
      if (next == null) {
        return null;
      }
      node = next;
    }
    return node;
  }
}

class _ThemeKey {
  const _ThemeKey(
    this.path,
    this.type, {
    this.values = const [],
    this.description,
    this.states = false,
    this.open = false,
    this.flutter,
    this.defaultValue,
  });

  factory _ThemeKey.from(MetaThemeProperty p) => _ThemeKey(
    [
      for (final s in p.name.split('.'))
        if (s.startsWith('<') && s.endsWith('>')) '*' else s,
    ],
    p.type,
    values: p.values,
    description: p.description,
    states: p.states,
    flutter: p.flutter,
    defaultValue: p.defaultValue,
    open: p.open,
  );

  _ThemeKey withValues(List<String> more) => _ThemeKey(
    path,
    type,
    values: more,
    description: description,
    states: states,
    open: open,
    flutter: flutter,
    defaultValue: defaultValue,
  );

  final List<String> path;
  final String type;
  final List<String> values;
  final String? description;
  final bool states;
  final bool open;
  final String? flutter;
  final Object? defaultValue;
}

/// The names of the 46 Material 3 color roles.
const colorRoles = [
  'primary',
  'on-primary',
  'primary-container',
  'on-primary-container',
  'primary-fixed',
  'primary-fixed-dim',
  'on-primary-fixed',
  'on-primary-fixed-variant',
  'secondary',
  'on-secondary',
  'secondary-container',
  'on-secondary-container',
  'secondary-fixed',
  'secondary-fixed-dim',
  'on-secondary-fixed',
  'on-secondary-fixed-variant',
  'tertiary',
  'on-tertiary',
  'tertiary-container',
  'on-tertiary-container',
  'tertiary-fixed',
  'tertiary-fixed-dim',
  'on-tertiary-fixed',
  'on-tertiary-fixed-variant',
  'error',
  'on-error',
  'error-container',
  'on-error-container',
  'surface',
  'on-surface',
  'on-surface-variant',
  'surface-dim',
  'surface-bright',
  'surface-container-lowest',
  'surface-container-low',
  'surface-container',
  'surface-container-high',
  'surface-container-highest',
  'surface-tint',
  'inverse-surface',
  'on-inverse-surface',
  'inverse-primary',
  'outline',
  'outline-variant',
  'shadow',
  'scrim',
];

/// Corner and elevation names that exist without being written.
const defaultShapeNames = [
  'none',
  'extra-small',
  'small',
  'medium',
  'large',
  'extra-large',
  'full',
];
