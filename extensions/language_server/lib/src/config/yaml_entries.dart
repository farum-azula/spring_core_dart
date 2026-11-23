import 'package:dart_spring_language_server/src/properties/property_entry.dart';
import 'package:yaml/yaml.dart';

/// Reads a YAML config file ([content], one or more `---` documents) into
/// flat entries, exactly as the framework's `YamlPropertySourceLoader`
/// does, each pointing at its key in the file.
///
/// Nested keys are joined with dots (`shop.payment.provider`) and list
/// elements indexed (`shop.servers[0].host`); merge keys (`<<: *d`) are
/// applied; non-string keys are written `[1]`; an empty map, an empty list
/// or `null` gives `''`. A list of scalars gives only its indexed keys:
/// `${shop.currencies}` does not resolve at run time either, as in Spring.
/// Each document is parsed on its own, so a broken one leaves the others'
/// keys.
///
/// A file cannot make the server run out of time, memory or stack: aliases
/// are expanded as the loader does, but a document stops being read once
/// it has visited [maxNodes] nodes (an alias bomb visits billions) or is
/// nested deeper than [maxDepth]; and whatever a document throws (a stack
/// overflow of the parser on thousands of `[`) leaves only that document
/// out.
List<PropertyEntry> parseYamlProperties(
  String path,
  String content, {
  int maxNodes = 100000,
  int maxDepth = 100,
}) {
  final entries = <PropertyEntry>[];
  var document = <PropertyEntry>[];
  var visited = 0;

  void add(String key, YamlNode at, String value) {
    final span = at.span;
    document.add(
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
  void walk(YamlNode node, String path, YamlNode at, int depth) {
    if (++visited > maxNodes || depth > maxDepth) {
      throw const _TooLarge();
    }
    switch (node) {
      case YamlMap():
        final members = _members(node, () {
          if (++visited > maxNodes) {
            throw const _TooLarge();
          }
        });
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
          walk(child, name, keyNode, depth + 1);
        }
      case YamlList(:final nodes):
        if (nodes.isEmpty) {
          add(path, at, '');
        }
        for (var i = 0; i < nodes.length; i++) {
          final child = nodes[i];
          walk(
            child,
            '$path[$i]',
            child is YamlScalar ? child : at,
            depth + 1,
          );
        }
      case YamlScalar(:final value):
        if (path.isNotEmpty) {
          add(path, at, value == null ? '' : '$value');
        }
    }
  }

  for (final (start, text) in _documents(content)) {
    document = [];
    visited = 0;
    if (_flowDepth(text) > maxDepth) {
      // The parser's time grows with the square of the nesting.
      continue;
    }
    try {
      // Blank lines in front keep the spans' line numbers those of the file.
      final root = loadYamlNode('${'\n' * start}$text');
      walk(root, '', root, 0);
    } on Object {
      // Invalid, too large or too deep: the document gives no keys.
      continue;
    }
    final profile = _activationProfile(document);
    entries.addAll(
      profile == null
          ? document
          : [for (final entry in document) entry.withProfile(profile)],
    );
  }
  return entries;
}

/// The profile expression a YAML document is read under: the value of its
/// `spring.config.activate.on-profile` (or the older `spring.profiles`).
String? _activationProfile(List<PropertyEntry> document) {
  for (final key in const [
    'spring.config.activate.on-profile',
    'spring.profiles',
  ]) {
    for (final entry in document) {
      if (entry.key == key && entry.value.trim().isNotEmpty) {
        return entry.value.trim();
      }
    }
  }
  return null;
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
List<(String, YamlNode, YamlNode)> _members(
  YamlMap map,
  void Function() visit,
) {
  final own = <String, (YamlNode, YamlNode)>{};
  final merged = <String, (YamlNode, YamlNode)>{};
  for (final MapEntry(:key, :value) in map.nodes.entries) {
    visit();
    final keyNode = key is YamlNode ? key : value;
    final keyValue = key is YamlNode ? key.value : key;
    if (keyValue == '<<' &&
        keyNode is YamlScalar &&
        keyNode.style == ScalarStyle.PLAIN) {
      final sources = value is YamlList ? value.nodes : [value];
      for (final source in sources) {
        if (source is YamlMap) {
          for (final (name, node, child) in _members(source, visit)) {
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

/// [loadYaml] of [text], or null when its flow collections (`[`, `{`) nest
/// deeper than [maxDepth]: the parser's time grows with the square of the
/// nesting (seconds for 20 000 `[`), and its stack overflows.
Object? loadYamlBounded(String text, {int maxDepth = 100}) =>
    _flowDepth(text) > maxDepth ? null : loadYaml(text);

// How deep the flow collections (`[`, `{`) of [text] nest, quoted text and
// comments left out.
int _flowDepth(String text) {
  var depth = 0;
  var deepest = 0;
  String? quote;
  var comment = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '\n') {
      quote = null;
      comment = false;
    } else if (comment) {
      continue;
    } else if (quote != null) {
      if (char == quote) {
        quote = null;
      }
    } else if (char == "'" || char == '"') {
      quote = char;
    } else if (char == '#' && (i == 0 || text[i - 1] == ' ')) {
      comment = true;
    } else if (char == '[' || char == '{') {
      if (++depth > deepest) {
        deepest = depth;
      }
    } else if ((char == ']' || char == '}') && depth > 0) {
      depth--;
    }
  }
  return deepest;
}

/// Thrown when a document is too large or too deep to read.
final class _TooLarge implements Exception {
  const _TooLarge();
}
