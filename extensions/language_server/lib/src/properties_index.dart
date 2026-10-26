import 'dart:io';

import 'package:yaml/yaml.dart';

/// One `key=value` entry of a properties file, with its position.
final class PropertyEntry {
  /// Creates an entry.
  const PropertyEntry({
    required this.path,
    required this.key,
    required this.value,
    required this.line,
    required this.keyStart,
    required this.keyEnd,
    this.environment = false,
  });

  /// Whether [key] is an environment variable (`SHOP_MAX_BASKET_SIZE`, from
  /// a test's `@TestEnvironment`), matched the way Spring maps property
  /// names to variables.
  final bool environment;

  /// File path.
  final String path;

  /// The key.
  final String key;

  /// The value (continuation lines joined).
  final String value;

  /// Zero-based line of the key.
  final int line;

  /// Zero-based column range of the key (UTF-16 units).
  final int keyStart;

  /// End column of the key.
  final int keyEnd;

  /// `application-prod` for `.../application-prod.properties` (or `.yml`).
  String get fileName {
    final name = path.split(Platform.pathSeparator).last;
    for (final extension in ['.properties', '.yml', '.yaml']) {
      if (name.endsWith(extension)) {
        return name.substring(0, name.length - extension.length);
      }
    }
    return name;
  }
}

/// Parses [content] (Java properties syntax) keeping key positions.
List<PropertyEntry> parseProperties(String path, String content) {
  final entries = <PropertyEntry>[];
  final lines = content.split('\n');
  var i = 0;
  while (i < lines.length) {
    final lineNumber = i;
    var line = lines[i].replaceAll('\r', '');
    i++;
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('!')) {
      continue;
    }
    final indent = line.length - trimmed.length;
    // Logical line: a trailing unescaped backslash continues it.
    var logical = trimmed;
    while (_continues(logical) && i < lines.length) {
      logical =
          logical.substring(0, logical.length - 1) +
          lines[i].replaceAll('\r', '').trimLeft();
      i++;
    }
    var k = 0;
    final key = StringBuffer();
    while (k < logical.length) {
      final c = logical[k];
      if (c == r'\' && k + 1 < logical.length) {
        key.write(logical[k + 1]);
        k += 2;
        continue;
      }
      if (c == '=' || c == ':' || c == ' ' || c == '\t') {
        break;
      }
      key.write(c);
      k++;
    }
    final keyEndInLine = indent + k;
    while (k < logical.length && (logical[k] == ' ' || logical[k] == '\t')) {
      k++;
    }
    if (k < logical.length && (logical[k] == '=' || logical[k] == ':')) {
      k++;
    }
    final value = logical.substring(k).trim();
    if (key.isNotEmpty) {
      entries.add(
        PropertyEntry(
          path: path,
          key: key.toString(),
          value: value,
          line: lineNumber,
          keyStart: indent,
          keyEnd: keyEndInLine,
        ),
      );
    }
  }
  return entries;
}

bool _continues(String line) {
  var slashes = 0;
  for (var i = line.length - 1; i >= 0 && line[i] == r'\'; i--) {
    slashes++;
  }
  return slashes.isOdd;
}

/// Parses a YAML config file ([content], one or more `---` documents) into
/// flat entries exactly as the framework's `YamlPropertySourceLoader` does:
/// `shop.payment.provider`, `shop.servers[0].host`, merge keys (`<<: *d`)
/// applied, non-string keys as `[1]`, an empty map, list or `null` as `''`.
/// A list of scalars gives only its indexed keys (`${shop.currencies}`
/// does not resolve at run time either, as in Spring). Each entry points
/// at its key in the file. Each document is parsed on its own, so a
/// broken one leaves the others' keys.
List<PropertyEntry> parseYamlProperties(String path, String content) {
  final entries = <PropertyEntry>[];

  void add(String key, YamlNode at, String value) {
    final span = at.span;
    entries.add(
      PropertyEntry(
        path: path,
        key: key,
        value: value,
        line: span.start.line,
        keyStart: span.start.column,
        keyEnd: span.start.line == span.end.line
            ? span.end.column
            : span.start.column + key.length,
      ),
    );
  }

  // [at]: the node the entry points at (its key, or the list element).
  void walk(YamlNode node, String path, YamlNode at) {
    switch (node) {
      case YamlMap():
        final members = _members(node);
        if (members.isEmpty) {
          if (path.isNotEmpty) {
            add(path, at, '');
          }
          return;
        }
        for (final (key, keyNode, child) in members) {
          final name = path.isEmpty
              ? key
              : key.startsWith('[')
              ? '$path$key'
              : '$path.$key';
          walk(child, name, keyNode);
        }
      case YamlList(:final nodes):
        if (nodes.isEmpty) {
          add(path, at, '');
        }
        for (var i = 0; i < nodes.length; i++) {
          final child = nodes[i];
          walk(child, '$path[$i]', child is YamlScalar ? child : at);
        }
      case YamlScalar(:final value):
        if (path.isNotEmpty) {
          add(path, at, value == null ? '' : '$value');
        }
    }
  }

  for (final (start, text) in _documents(content)) {
    final YamlNode root;
    try {
      // Blank lines in front keep the spans' line numbers those of the file.
      root = loadYamlNode('${'\n' * start}$text');
    } on YamlException {
      continue;
    }
    walk(root, '', root);
  }
  return entries;
}

// The documents of a YAML stream with the line each starts on (split at
// `---` and `...` lines, as a loader would).
List<(int, String)> _documents(String content) {
  final lines = content.split('\n');
  final result = <(int, String)>[];
  var start = 0;
  for (var i = 0; i <= lines.length; i++) {
    final end =
        i == lines.length ||
        RegExp(r'^(---|\.\.\.)(\s.*)?\r?$').hasMatch(lines[i]);
    if (end) {
      if (i > start) {
        result.add((start, lines.sublist(start, i).join('\n')));
      }
      start = i + 1;
    }
  }
  return result;
}

// The members of a mapping as the loader sees them: merge keys (`<<`)
// applied — the mapping's own keys win, then earlier merged mappings —
// and non-string keys written as `[key]`.
List<(String, YamlNode, YamlNode)> _members(YamlMap map) {
  final own = <String, (YamlNode, YamlNode)>{};
  final merged = <String, (YamlNode, YamlNode)>{};
  for (final MapEntry(:key, :value) in map.nodes.entries) {
    final keyNode = key is YamlNode ? key : value;
    final keyValue = key is YamlNode ? key.value : key;
    if (keyValue == '<<' &&
        keyNode is YamlScalar &&
        keyNode.style == ScalarStyle.PLAIN) {
      final sources = value is YamlList ? value.nodes : [value];
      for (final source in sources) {
        if (source is YamlMap) {
          for (final (name, node, child) in _members(source)) {
            merged.putIfAbsent(name, () => (node, child));
          }
        }
      }
      continue;
    }
    own[keyValue is String ? keyValue : '[$keyValue]'] = (keyNode, value);
  }
  for (final entry in merged.entries) {
    own.putIfAbsent(entry.key, () => entry.value);
  }
  return [
    for (final MapEntry(key: name, value: (node, child)) in own.entries)
      (name, node, child),
  ];
}
