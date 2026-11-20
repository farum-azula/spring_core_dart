import 'package:dart_spring_language_server/src/config/config_key.dart';

final _documentMarker = RegExp(r'^(---|\.\.\.)(\s|$)');

/// The comment-free part of a YAML line: up to a `#` at the start or after
/// a space, outside quoted scalars. Unquoted, `key: #{...}` is a comment
/// for YAML too, so SpEL is only found in quotes.
String stripYamlComment(String line) {
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quote != null) {
      if (c == quote) {
        quote = null;
      }
    } else if ((c == '"' || c == "'") &&
        (i == 0 || ' \t:[{,-'.contains(line[i - 1]))) {
      quote = c; // a quoted scalar starts here, not an apostrophe
    } else if (c == '#' &&
        (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
      return line.substring(0, i);
    }
  }
  return line;
}

/// The key of the YAML content `key: value`, the offset after its colon
/// and whether the key is quoted; `null` when [content] is no key.
(String, int, bool)? splitYamlKey(String content) {
  if (content.isEmpty) {
    return null;
  }
  final first = content[0];
  if (first == '"' || first == "'") {
    final end = content.indexOf(first, 1);
    if (end < 0) {
      return null;
    }
    final rest = content.substring(end + 1).trimLeft();
    if (!rest.startsWith(':')) {
      return null;
    }
    final colon = content.indexOf(':', end + 1);
    return (content.substring(1, end), colon + 1, true);
  }
  if ('[{&*!|>%@`'.contains(first)) {
    return null;
  }
  for (var i = 0; i < content.length; i++) {
    final c = content[i];
    if (c == ':' && (i + 1 == content.length || content[i + 1] == ' ')) {
      return (content.substring(0, i).trimRight(), i + 1, false);
    }
    if (c == '#' && i > 0 && content[i - 1] == ' ') {
      return null;
    }
  }
  return null;
}

final class _Frame {
  _Frame(this.indent, this.segments, {this.dash = false});

  final int indent;
  final List<String> segments;
  final bool dash;
}

/// Reads the keys of a YAML config text with their places, tolerant of
/// the half-typed text of an open editor: line by line, from the
/// indentation, so a line that does not parse yet leaves the others. List
/// items are a `[0]` segment; flow maps (`{ a: 1 }`) give their keys; block
/// scalars, flow lists, anchors and tags are values not to check.
List<ConfigKey> scanYamlKeys(String text) {
  final lines = text.split('\n');
  final keys = <ConfigKey>[];
  final stack = <_Frame>[];
  int? blockIndent;
  for (var row = 0; row < lines.length; row++) {
    var line = lines[row];
    if (line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }
    if (_documentMarker.hasMatch(line)) {
      stack.clear();
      blockIndent = null;
      continue;
    }
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) {
      continue;
    }
    final indent = line.length - trimmed.length;
    if (blockIndent != null) {
      if (indent > blockIndent) {
        continue;
      }
      blockIndent = null;
    }
    if (trimmed.startsWith('#')) {
      continue;
    }
    var column = indent;
    var content = trimmed;
    while (content == '-' || content.startsWith('- ')) {
      final dash = column;
      while (stack.isNotEmpty &&
          (stack.last.indent > dash ||
              (stack.last.indent == dash && stack.last.dash))) {
        stack.removeLast();
      }
      stack.add(_Frame(dash, ['[0]'], dash: true));
      final rest = content.length == 1 ? '' : content.substring(2);
      final skipped = rest.length - rest.trimLeft().length;
      content = rest.trimLeft();
      column = dash + 2 + skipped;
      if (content.isEmpty) {
        break;
      }
    }
    if (content.isEmpty || content.startsWith('#')) {
      continue;
    }
    final split = splitYamlKey(content);
    if (split == null) {
      continue;
    }
    final (rawKey, afterColon, quoted) = split;
    while (stack.isNotEmpty && stack.last.indent >= column) {
      stack.removeLast();
    }
    final parents = [for (final frame in stack) ...frame.segments];
    final parts = dottedParts(rawKey, column + (quoted ? 1 : 0));
    if (parts.isEmpty) {
      continue;
    }
    final names = [for (final part in parts) part.$1];
    stack.add(_Frame(column, names));
    final key = (
      row: row,
      column: column,
      parents: parents,
      segments: [...parents, ...names],
      spans: [for (final part in parts) (part.$2, part.$3)],
    );
    final rest = stripYamlComment(content.substring(afterColon));
    final valueColumn =
        column + afterColon + (rest.length - rest.trimLeft().length);
    final value = rest.trim();
    if (RegExp(r'^[|>][+\-0-9]*$').hasMatch(value)) {
      blockIndent = column;
    }
    keys.addAll(_keysOf(key, value, valueColumn));
  }
  return keys;
}

typedef _Line = ({
  int row,
  int column,
  List<String> parents,
  List<String> segments,
  List<(int, int)> spans,
});

// The keys of the line [key] whose value (comment-free, trimmed) is
// [value], starting at [valueColumn].
List<ConfigKey> _keysOf(_Line key, String value, int valueColumn) {
  ConfigKey keyWith({String? value, int start = 0, bool quoted = false}) =>
      ConfigKey(
        line: key.row,
        segments: key.segments,
        parentCount: key.parents.length,
        spans: key.spans,
        value: value,
        valueStart: start,
        quoted: quoted,
        indent: key.column,
      );
  if (value.isEmpty) {
    return [keyWith()];
  }
  if (RegExp(r'^[|>][+\-0-9]*$').hasMatch(value)) {
    // A block scalar: its lines are its value, not keys.
    return [
      ConfigKey(
        line: key.row,
        segments: key.segments,
        parentCount: key.parents.length,
        spans: key.spans,
        value: '',
        complex: true,
        indent: key.column,
      ),
    ];
  }
  if (value.startsWith('{')) {
    final keys = [keyWith()];
    _flowMap(value, valueColumn, key.row, key.segments, keys);
    return keys;
  }
  var text = value;
  var start = valueColumn;
  var quoted = false;
  if (text.length >= 2 &&
      (text[0] == '"' || text[0] == "'") &&
      text.endsWith(text[0])) {
    text = text.substring(1, text.length - 1);
    start++;
    quoted = true;
  }
  return [
    ConfigKey(
      line: key.row,
      segments: key.segments,
      parentCount: key.parents.length,
      spans: key.spans,
      value: text,
      valueStart: start,
      quoted: quoted,
      complex: !quoted && RegExp(r'^([\[&*!]|<<)').hasMatch(value),
      indent: key.column,
    ),
  ];
}

// Parses the flow map `{ a: 1, b: { c: 2 } }` starting at [source] (which
// begins with `{`) into keys; [base] is the column of `{`.
void _flowMap(
  String source,
  int base,
  int line,
  List<String> prefix,
  List<ConfigKey> out,
) {
  var i = 1;
  while (i < source.length) {
    while (i < source.length && ' ,'.contains(source[i])) {
      i++;
    }
    if (i >= source.length || source[i] == '}') {
      return;
    }
    final colon = source.indexOf(':', i);
    if (colon < 0) {
      return;
    }
    final raw = source.substring(i, colon);
    final name = raw.trim().replaceAll(RegExp('^["\']|["\']\$'), '');
    final nameStart = base + i + (raw.length - raw.trimLeft().length);
    var j = colon + 1;
    while (j < source.length && source[j] == ' ') {
      j++;
    }
    final segments = [...prefix, name];
    final spans = [(nameStart, nameStart + name.length)];
    if (j < source.length && source[j] == '{') {
      out.add(
        ConfigKey(
          line: line,
          segments: segments,
          parentCount: prefix.length,
          spans: spans,
        ),
      );
      final k = _closingBrace(source, j);
      _flowMap(
        source.substring(j, k < source.length ? k + 1 : source.length),
        base + j,
        line,
        segments,
        out,
      );
      i = k + 1;
      continue;
    }
    final k = _valueEnd(source, j);
    var text = source.substring(j, k).trimRight();
    var start = base + j;
    var quoted = false;
    if (text.length >= 2 &&
        (text[0] == '"' || text[0] == "'") &&
        text.endsWith(text[0])) {
      text = text.substring(1, text.length - 1);
      start++;
      quoted = true;
    }
    out.add(
      ConfigKey(
        line: line,
        segments: segments,
        parentCount: prefix.length,
        spans: spans,
        value: text,
        valueStart: start,
        quoted: quoted,
        complex: text.startsWith('['),
      ),
    );
    i = k;
  }
}

// The index of the `}` that closes the `{` at [from] of [source], or the
// length of [source].
int _closingBrace(String source, int from) {
  var depth = 0;
  var k = from;
  for (; k < source.length; k++) {
    if (source[k] == '{') {
      depth++;
    } else if (source[k] == '}') {
      depth--;
      if (depth == 0) {
        break;
      }
    }
  }
  return k;
}

// The end of the flow value that starts at [from] of [source]: a comma or
// `}` outside quotes and lists.
int _valueEnd(String source, int from) {
  var k = from;
  String? quote;
  var depth = 0;
  for (; k < source.length; k++) {
    final c = source[k];
    if (quote != null) {
      if (c == quote) {
        quote = null;
      }
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '[') {
      depth++;
    } else if (c == ']') {
      depth--;
    } else if ((c == ',' && depth == 0) || c == '}') {
      break;
    }
  }
  return k;
}

/// The path of the keys that enclose the YAML line [line] of [lines],
/// found from the indentation of the lines above it (the text may not
/// parse yet). A list item is a `[0]` segment.
List<String> yamlParentSegments(List<String> lines, int line) {
  var limit = keyIndentOf(lines[line]);
  final result = <List<String>>[];
  for (var row = line - 1; row >= 0 && limit > 0; row--) {
    final text = lines[row].replaceAll('\r', '');
    if (text.trim().isEmpty || text.trimLeft().startsWith('#')) {
      continue;
    }
    if (_documentMarker.hasMatch(text)) {
      break;
    }
    final indent = text.length - text.trimLeft().length;
    var content = text.trimLeft();
    var dashIndent = -1;
    var keyIndent = indent;
    while (content == '-' || content.startsWith('- ')) {
      if (dashIndent < 0) {
        dashIndent = keyIndent;
      }
      final rest = content.length == 1 ? '' : content.substring(2);
      keyIndent += 2 + (rest.length - rest.trimLeft().length);
      content = rest.trimLeft();
    }
    final split = splitYamlKey(content);
    if (dashIndent >= 0 && keyIndent >= limit && dashIndent < limit) {
      // An earlier item of the same list: the item boundary.
      result.add(['[0]']);
      limit = dashIndent;
      continue;
    }
    if (split == null || keyIndent >= limit) {
      continue;
    }
    result.add([for (final part in dottedParts(split.$1, 0)) part.$1]);
    limit = dashIndent >= 0 ? dashIndent : keyIndent;
    if (dashIndent >= 0) {
      result.add(['[0]']);
    }
  }
  return [for (final part in result.reversed) ...part];
}
