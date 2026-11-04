// The members are described where they are used; one doc per class suffices.
// ignore_for_file: public_member_api_docs
import 'dart:io';

import 'package:dart_spring_language_server/src/properties_index.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/templates.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

part 'loader_editor.dart';

/// One completion proposal.
final class Completion {
  const Completion(
    this.label, {
    this.kind = 10,
    this.detail,
    this.documentation,
    this.insertText,
    this.sortText,
  });

  final String label;

  /// An LSP `CompletionItemKind`: 10 property, 9 module, 12 value, 18
  /// reference, 6 variable, 2 method, 7 class.
  final int kind;
  final String? detail;
  final String? documentation;
  final String? insertText;
  final String? sortText;
}

/// Proposals with the span of text they replace (on one line).
final class CompletionResult {
  const CompletionResult(this.replace, this.items);
  final SourceRange replace;
  final List<Completion> items;
}

/// A problem found while scanning SpEL: offsets inside the expression.
final class SpelIssue {
  const SpelIssue(this.start, this.end, this.message, {this.error = true});
  final int start;
  final int end;
  final String message;
  final bool error;
}

/// A key of a config file with the place of its parts.
final class _Key {
  _Key({
    required this.line,
    required this.segments,
    required this.parentCount,
    required this.spans,
    this.value,
    this.valueStart = 0,
    this.quoted = false,
    this.complex = false,
    this.indent = 0,
  });

  final int line;

  /// The whole path of the key.
  final List<String> segments;

  /// How many of [segments] come from lines above.
  final int parentCount;

  /// Start and end column of each segment this line adds.
  final List<(int, int)> spans;

  /// The scalar value as text, without quotes; `null` for a group.
  final String? value;
  final int valueStart;
  final bool quoted;

  /// A flow list, an anchor or a tag: the value is not checked.
  final bool complex;
  final int indent;

  int get valueEnd => valueStart + (value?.length ?? 0);
}

class _Frame {
  _Frame(this.indent, this.segments, {this.dash = false});
  final int indent;
  final List<String> segments;
  final bool dash;
}

// The comment-free part of a YAML line.
String _stripComment(String line) {
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quote != null) {
      if (c == quote) {
        quote = null;
      }
    } else if ((c == '"' || c == "'") &&
        (i == 0 || ' \t:[{,-'.contains(line[i - 1]))) {
      quote = c;
    } else if (c == '#' &&
        (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
      return line.substring(0, i);
    }
  }
  return line;
}

// The key of `key: value` and the offset after the colon, or null.
(String, int, bool)? _splitKey(String content) {
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

List<(String, int, int)> _dotted(String key, int column) {
  final result = <(String, int, int)>[];
  var start = 0;
  for (var i = 0; i <= key.length; i++) {
    if (i == key.length || key[i] == '.') {
      if (i > start) {
        result.add((key.substring(start, i), column + start, column + i));
      }
      start = i + 1;
    }
  }
  return result;
}

// Parses the flow map `{ a: 1, b: { c: 2 } }` starting at [source] (which
// begins with `{`) into keys; [base] is the column of `{`.
void _flowMap(
  String source,
  int base,
  int line,
  List<String> prefix,
  List<_Key> out,
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
    final name = source
        .substring(i, colon)
        .trim()
        .replaceAll(RegExp('^["\']|["\']\$'), '');
    final nameStart =
        base +
        i +
        (source.substring(i, colon).length -
            source.substring(i, colon).trimLeft().length);
    var j = colon + 1;
    while (j < source.length && source[j] == ' ') {
      j++;
    }
    final segments = [...prefix, name];
    final spans = [(nameStart, nameStart + name.length)];
    if (j < source.length && source[j] == '{') {
      out.add(
        _Key(
          line: line,
          segments: segments,
          parentCount: prefix.length,
          spans: spans,
        ),
      );
      var depth = 0;
      var k = j;
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
    var k = j;
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
      _Key(
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

/// Reads the keys of a YAML config text with their places, tolerant of the
/// half-typed text of an open editor.
List<_Key> _scanYaml(String text) {
  final lines = text.split('\n');
  final keys = <_Key>[];
  final stack = <_Frame>[];
  int? blockIndent;
  for (var row = 0; row < lines.length; row++) {
    var line = lines[row];
    if (line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }
    if (RegExp(r'^(---|\.\.\.)(\s|$)').hasMatch(line)) {
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
    final split = _splitKey(content);
    if (split == null) {
      continue;
    }
    final (rawKey, afterColon, quoted) = split;
    while (stack.isNotEmpty && stack.last.indent >= column) {
      stack.removeLast();
    }
    final parents = [for (final frame in stack) ...frame.segments];
    final parts = _dotted(rawKey, column + (quoted ? 1 : 0));
    if (parts.isEmpty) {
      continue;
    }
    final names = [for (final part in parts) part.$1];
    stack.add(_Frame(column, names));
    final rest = _stripComment(content.substring(afterColon));
    final trimmedRest = rest.trim();
    final valueColumn =
        column + afterColon + (rest.length - rest.trimLeft().length);
    final spans = [for (final part in parts) (part.$2, part.$3)];
    final segments = [...parents, ...names];
    if (trimmedRest.isEmpty) {
      keys.add(
        _Key(
          line: row,
          segments: segments,
          parentCount: parents.length,
          spans: spans,
          indent: column,
        ),
      );
      continue;
    }
    if (RegExp(r'^[|>][+\-0-9]*$').hasMatch(trimmedRest)) {
      blockIndent = column;
      keys.add(
        _Key(
          line: row,
          segments: segments,
          parentCount: parents.length,
          spans: spans,
          value: '',
          complex: true,
          indent: column,
        ),
      );
      continue;
    }
    if (trimmedRest.startsWith('{')) {
      keys.add(
        _Key(
          line: row,
          segments: segments,
          parentCount: parents.length,
          spans: spans,
          indent: column,
        ),
      );
      _flowMap(trimmedRest, valueColumn, row, segments, keys);
      continue;
    }
    var value = trimmedRest;
    var start = valueColumn;
    var isQuoted = false;
    if (value.length >= 2 &&
        (value[0] == '"' || value[0] == "'") &&
        value.endsWith(value[0])) {
      value = value.substring(1, value.length - 1);
      start++;
      isQuoted = true;
    }
    keys.add(
      _Key(
        line: row,
        segments: segments,
        parentCount: parents.length,
        spans: spans,
        value: value,
        valueStart: start,
        quoted: isQuoted,
        complex: !isQuoted && RegExp(r'^([\[&*!]|<<)').hasMatch(trimmedRest),
        indent: column,
      ),
    );
  }
  return keys;
}

List<_Key> _scanProperties(String text, List<PropertyEntry> entries) {
  final lines = text.split('\n');
  final keys = <_Key>[];
  for (final entry in entries) {
    final line = lines[entry.line].replaceAll('\r', '');
    final segments = splitKey(entry.key);
    final spans = <(int, int)>[];
    var column = entry.keyStart;
    final rawSegments = _dotted(
      line.substring(entry.keyStart, entry.keyEnd),
      entry.keyStart,
    );
    for (final part in rawSegments) {
      column = part.$3;
      spans.add((part.$2, part.$3));
    }
    var valueStart = column;
    final afterKey = line.substring(entry.keyEnd);
    final match = RegExp(r'^[ \t]*[=:]?[ \t]*').firstMatch(afterKey)!;
    valueStart = entry.keyEnd + match.end;
    final value = entry.value;
    keys.add(
      _Key(
        line: entry.line,
        segments: segments,
        parentCount: 0,
        spans: spans.length == segments.length
            ? spans
            : [(entry.keyStart, entry.keyEnd)],
        value: value,
        valueStart: valueStart,
        complex: line.trimRight().endsWith(r'\'),
        indent: entry.keyStart,
      ),
    );
  }
  return keys;
}

/// The editing features of config files: completion, hover, definition and
/// diagnostics for keys, values, `${}`, `#{}` and the theme.
final class ConfigEditor {
  ConfigEditor(this.workspace);

  final SpringWorkspace workspace;

  static bool _isYaml(String path) =>
      path.endsWith('.yml') || path.endsWith('.yaml');

  List<_Key> _keys(String path, String text) {
    if (_isYaml(path)) {
      return _scanYaml(text);
    }
    return _scanProperties(text, parseProperties(path, text));
  }

  // -------------------------------------------------------------------
  // Positions
  // -------------------------------------------------------------------

  static (int, int) _lineColumn(String text, int offset) {
    var line = 0;
    var start = 0;
    for (var i = 0; i < offset && i < text.length; i++) {
      if (text[i] == '\n') {
        line++;
        start = i + 1;
      }
    }
    return (line, offset - start);
  }

  static SourceRange _range(String path, int line, int from, int to) =>
      SourceRange(path, line, from, line, to);

  // The key line at ([line], [column]) when the cursor is in its key part,
  // with the index of the segment under the cursor.
  (_Key, int)? _keyAt(List<_Key> keys, int line, int column) {
    for (final key in keys) {
      if (key.line != line || key.spans.isEmpty) {
        continue;
      }
      for (var i = 0; i < key.spans.length; i++) {
        if (column >= key.spans[i].$1 && column <= key.spans[i].$2) {
          return (key, key.parentCount + i);
        }
      }
    }
    return null;
  }

  _Key? _valueAt(List<_Key> keys, int line, int column) {
    for (final key in keys) {
      if (key.line == line &&
          key.value != null &&
          column >= key.valueStart &&
          column <= key.valueEnd) {
        return key;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------
  // Diagnostics
  // -------------------------------------------------------------------

  List<Problem> problems(String path, String text) {
    final keys = _keys(path, text);
    final schema = workspace.schemaFor(path);
    final problems = <Problem>[];
    final reported = <List<String>>[];
    final refs = _RefIndex(workspace, path);
    // A dependency without metadata may define any key: then only the
    // theme, which the editor knows by itself, is checked for unknown keys.
    final complete = workspace.metadataFor(path).complete;
    final objects = <String, Set<String>>{};
    final objectKeys = <String, _Key>{};
    for (final key in keys) {
      if (reported.any((p) => _startsWith(key.segments, p))) {
        continue;
      }
      final resolution = schema.resolve(key.segments);
      final isTheme = _isTheme(key.segments);
      if (resolution.isUnknown) {
        if (resolution.depth >= key.parentCount && (complete || isTheme)) {
          final parent = resolution.parent!;
          if (parent.real) {
            final index = resolution.depth - key.parentCount;
            final (from, to) = key.spans[index.clamp(0, key.spans.length - 1)];
            problems.add(
              Problem(
                _range(path, key.line, from, to),
                _unknownMessage(key, resolution, isTheme),
                error: isTheme,
              ),
            );
            reported.add(key.segments.sublist(0, resolution.depth + 1));
          }
        }
        if (key.value != null && !key.complex) {
          _checkTemplate(path, key, problems);
        }
        continue;
      }
      final node = resolution.node;
      final prop = node?.prop;
      if (isTheme && prop != null && prop.type == 'color') {
        final base = key.segments.length - resolution.rest.length;
        final objectPath = key.segments.sublist(0, base).join('.');
        objects.putIfAbsent(objectPath, () => {});
        objectKeys.putIfAbsent(objectPath, () => key);
        if (resolution.rest.isNotEmpty) {
          objects[objectPath]!.add(resolution.rest.join('.'));
        }
      }
      if (key.value != null && !key.complex) {
        if (prop != null) {
          _checkValue(path, key, prop, resolution.rest, problems);
        }
        if (isTheme) {
          _checkReferences(path, key, refs, problems);
        }
        _checkTemplate(path, key, problems);
      }
    }
    _checkLoaders(path, keys, problems);
    for (final MapEntry(key: objectPath, value: parts) in objects.entries) {
      if (parts.isEmpty) {
        continue;
      }
      final key = objectKeys[objectPath]!;
      final hasColor = parts.any((p) => p == 'color' || p.endsWith('.color'));
      // A per-state map: `{ default: ..., hovered: ... }` written in one
      // line has the states as plain parts, a nested one has dotted parts.
      const stateNames = {
        'default',
        'hovered',
        'focused',
        'pressed',
        'dragged',
        'selected',
        'scrolled-under',
        'disabled',
        'error',
      };
      final states = {
        for (final part in parts)
          if (part.contains('.') || stateNames.contains(part))
            part.split('.').first,
      };
      if (!hasColor && states.isEmpty && !parts.contains('color')) {
        problems.add(
          Problem(
            _range(
              path,
              key.line,
              key.spans.first.$1,
              key.spans.last.$2,
            ),
            'A color object needs a `color:` (the color alpha or mix is '
            'applied to)',
            error: true,
          ),
        );
      }
      if (parts.contains('mix') ||
          parts.any((p) => p.endsWith('mix') || p.contains('mix.'))) {
        final hasWith = parts.any((p) => p.endsWith('mix.with'));
        final hasAmount = parts.any((p) => p.endsWith('mix.amount'));
        if (!(hasWith && hasAmount) && !parts.contains('mix')) {
          problems.add(
            Problem(
              _range(path, key.line, key.spans.first.$1, key.spans.last.$2),
              '`mix` needs both `with:` and `amount:`',
              error: true,
            ),
          );
        }
      }
    }
    return problems;
  }

  static bool _startsWith(List<String> segments, List<String> prefix) {
    if (segments.length < prefix.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (segments[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _isTheme(List<String> segments) {
    if (segments.length < themePrefix.length) {
      return false;
    }
    for (var i = 0; i < themePrefix.length; i++) {
      if (canonicalName(segments[i]) != themePrefix[i]) {
        return false;
      }
    }
    return true;
  }

  String _unknownMessage(_Key key, Resolution resolution, bool theme) {
    final name = resolution.unknown!;
    final parent = resolution.parent!;
    final path = key.segments.sublist(0, resolution.depth).join('.');
    final choices = [for (final node in parent.named) node.name];
    final guess = didYouMean(name, choices);
    final where = path.isEmpty ? '' : " in '$path'";
    final hint = guess == null ? '' : ". Did you mean '$guess'?";
    final kind = theme ? 'theme key' : 'property';
    final extra = theme && guess == null && choices.length <= 12
        ? '. Valid: ${choices.join(', ')}'
        : '';
    return "Unknown $kind '$name'$where$hint$extra";
  }

  // Wrong type, out of range, a value to avoid.
  void _checkValue(
    String path,
    _Key key,
    SchemaProp prop,
    List<String> rest,
    List<Problem> problems,
  ) {
    final value = key.value!;
    if (value.isEmpty || value.contains(r'${') || value.contains('#{')) {
      return;
    }
    final range = _range(path, key.line, key.valueStart, key.valueEnd);
    void error(String message) =>
        problems.add(Problem(range, message, error: true));
    final type = prop.type;
    if (prop.theme && type == 'color') {
      _checkColorValue(key, prop, rest, range, problems);
      return;
    }
    if (rest.isNotEmpty) {
      return;
    }
    // A `$` reference stands for any value; its target is checked by
    // _checkReferences.
    if (prop.theme && value.trimLeft().startsWith(r'$')) {
      return;
    }
    final base = type.replaceAll('?', '').trim();
    final hint = prop.hint;
    switch (base) {
      case 'int' || 'whole number':
        if (!RegExp(r'^[+-]?\d+$').hasMatch(value)) {
          error("Expected a whole number, got '$value'");
          return;
        }
      case 'double' || 'num' || 'number' || 'elevation':
        final level = RegExp(r'^level\d$').hasMatch(value);
        if (num.tryParse(value) == null &&
            !level &&
            value.toLowerCase() != 'infinity') {
          error("Expected a number, got '$value'");
          return;
        }
      case 'bool' || 'true / false':
        if (!{'true', 'false'}.contains(value.toLowerCase())) {
          error("Expected true or false, got '$value'");
          return;
        }
      case 'choice':
        final allowed = [for (final v in prop.values) v.$1];
        if (allowed.isNotEmpty &&
            !allowed.any((v) => canonicalName(v) == canonicalName(value))) {
          final guess = didYouMean(value, allowed);
          error(
            "'$value' is not allowed here. Expected one of: "
            '${allowed.join(', ')}'
            "${guess == null ? '' : ". Did you mean '$guess'?"}",
          );
          return;
        }
    }
    if (hint == null) {
      return;
    }
    final isEnum =
        hint.values.isNotEmpty &&
        hint.provider == null &&
        !const {
          'String',
          'int',
          'double',
          'num',
          'bool',
          'Object',
          'dynamic',
        }.contains(base) &&
        !base.startsWith('List') &&
        !base.startsWith('Map');
    if (isEnum &&
        !hint.values.any((v) => canonicalName(v.$1) == canonicalName(value))) {
      error(
        "'$value' is not allowed here. Expected one of: "
        '${[for (final v in hint.values) v.$1].join(', ')}',
      );
      return;
    }
    if (hint.range case (final low, final high)?) {
      final number = num.tryParse(value);
      if (number != null && (number < low || number > high)) {
        error('$value is out of range: $low to $high');
        return;
      }
    }
    for (final (values, message) in hint.warn) {
      if (values.contains(value)) {
        problems.add(Problem(range, '$value: $message'));
      }
    }
  }

  // A color: a plain string, or the parts of the object form.
  void _checkColorValue(
    _Key key,
    SchemaProp prop,
    List<String> rest,
    SourceRange range,
    List<Problem> problems,
  ) {
    final value = key.value!;
    var parts = rest;
    if (parts.isNotEmpty &&
        prop.states &&
        !_colorObjectKeys.contains(parts[0])) {
      parts = parts.sublist(1); // a state name
    }
    void error(String message) =>
        problems.add(Problem(range, message, error: true));
    if (parts.isEmpty || parts.length == 1 && parts[0] == 'color') {
      final problem = colorProblem(value);
      if (problem != null) {
        error(problem);
      }
      return;
    }
    final joined = parts.join('.');
    switch (joined) {
      case 'alpha' || 'mix.amount':
        if (!_isPercent(value)) {
          error(
            "Expected a percentage from 0% to 100% (or 0 to 1), got '$value'",
          );
        }
      case 'mix.with':
        final problem = colorProblem(value);
        if (problem != null) {
          error(problem);
        }
      default:
        error(
          "'$joined' is not a part of a color. A color object has "
          '`color`, `alpha` and `mix: { with, amount }`',
        );
    }
  }

  static const _colorObjectKeys = {'color', 'alpha', 'mix'};

  static bool _isPercent(String value) {
    // `12%` (0% to 100%) or a fraction from 0 to 1.
    final match = RegExp(r'^(\d+(?:\.\d+)?)(%?)$').firstMatch(value.trim());
    if (match == null) {
      return value.startsWith(r'$');
    }
    final number = double.parse(match[1]!);
    return number >= 0 && number <= (match[2] == '%' ? 100 : 1);
  }

  // `$ref` checks in theme values.
  void _checkReferences(
    String path,
    _Key key,
    _RefIndex refs,
    List<Problem> problems,
  ) {
    if (_noReferences(key.segments)) {
      return;
    }
    for (final ref in _references(key.value!)) {
      if (refs.exists(ref.path)) {
        continue;
      }
      final guess = refs.closest(ref.path);
      problems.add(
        Problem(
          _range(
            path,
            key.line,
            key.valueStart + ref.start,
            key.valueStart + ref.end,
          ),
          'Unknown reference \$${ref.path.join('.')}'
          "${guess == null ? '' : ". Did you mean \$$guess?"}",
          error: true,
        ),
      );
    }
  }

  // Values never resolved: headers and the image keys.
  static bool _noReferences(List<String> segments) =>
      segments.any((s) => canonicalName(s) == 'headers') ||
      const {'source', 'fallback', 'sourcesha256'}.contains(
        canonicalName(segments.last),
      );

  // `${key}` without a default and `#{...}` in a value.
  void _checkTemplate(String path, _Key key, List<Problem> problems) {
    final value = key.value!;
    if (!value.contains(r'${') && !value.contains('#{')) {
      return;
    }
    for (final part in scanTemplate(value)) {
      final start = key.valueStart + part.start;
      final end = key.valueStart + part.end;
      if (part.unclosed) {
        problems.add(
          Problem(
            _range(path, key.line, start, end),
            part.kind == TemplatePartKind.placeholder
                ? "Unclosed placeholder: missing '}'"
                : "Unclosed SpEL expression: missing '}'",
            error: true,
          ),
        );
        continue;
      }
      if (part.kind == TemplatePartKind.placeholder) {
        final name = part.inner(value);
        final hasDefault = part.keyEnd! < part.innerEnd;
        if (!hasDefault &&
            name.isNotEmpty &&
            !RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(name) &&
            !workspace.declaredByMetadata(path, name) &&
            workspace.property(name).isEmpty) {
          problems.add(
            Problem(
              _range(
                path,
                key.line,
                key.valueStart + part.innerStart,
                key.valueStart + part.keyEnd!,
              ),
              "Cannot resolve property '$name' in any properties file",
            ),
          );
        }
        continue;
      }
      final expression = value.substring(part.innerStart, part.innerEnd);
      if (expression.contains(r'${')) {
        continue;
      }
      for (final issue in workspace.spelIssues(path, expression)) {
        problems.add(
          Problem(
            _range(
              path,
              key.line,
              key.valueStart + part.innerStart + issue.start,
              key.valueStart + part.innerStart + issue.end,
            ),
            issue.message,
            error: issue.error,
          ),
        );
      }
    }
  }

  // -------------------------------------------------------------------
  // Hover
  // -------------------------------------------------------------------

  String? hover(String path, String text, int offset) {
    final (line, column) = _lineColumn(text, offset);
    final keys = _keys(path, text);
    final schema = workspace.schemaFor(path);
    final valueKey = _valueAt(keys, line, column);
    if (valueKey != null) {
      final inside = _templateAt(valueKey, column);
      if (inside != null) {
        final (part, source) = inside;
        final relative = column - valueKey.valueStart;
        if (part.kind == TemplatePartKind.placeholder) {
          return _placeholderHover(path, part.inner(source));
        }
        return workspace.spelHover(
          path,
          source.substring(part.innerStart, part.innerEnd),
          relative - part.innerStart,
        );
      }
      if (_isTheme(valueKey.segments)) {
        final relative = column - valueKey.valueStart;
        for (final ref in _references(valueKey.value!)) {
          if (relative >= ref.start && relative <= ref.end) {
            return _RefIndex(workspace, path).hover(ref.path);
          }
        }
      }
    }
    final at = _keyAt(keys, line, column);
    if (at == null) {
      return null;
    }
    final (key, index) = at;
    final resolution = schema.resolve(key.segments.sublist(0, index + 1));
    final node = resolution.node;
    if (resolution.isUnknown || node == null) {
      return null;
    }
    final prop = node.prop;
    if (prop == null) {
      return '**${key.segments.sublist(0, index + 1).join('.')}**';
    }
    return propertyHover(
      key.segments.sublist(0, index + 1).join('.'),
      prop,
      value: index == key.segments.length - 1 ? key.value : null,
    );
  }

  (TemplatePart, String)? _templateAt(_Key key, int column) {
    final value = key.value!;
    if (!value.contains(r'${') && !value.contains('#{')) {
      return null;
    }
    final relative = column - key.valueStart;
    for (final part in scanTemplate(value).reversed) {
      if (relative >= part.start && relative <= part.end) {
        return (part, value);
      }
    }
    return null;
  }

  String _placeholderHover(String path, String key) {
    final entries = workspace.property(key);
    final known = workspace.schemaFor(path);
    final prop = known.nodeAt(splitKey(key))?.prop;
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

  String propertyHover(String key, SchemaProp prop, {String? value}) {
    final lines = <String>['**`$key`**'];
    final type = prop.theme ? _themeTypeText(prop) : prop.type;
    lines
      ..add('')
      ..add('Type: `$type`${prop.states ? ' (a value per state)' : ''}');
    if (prop.description case final text?) {
      lines
        ..add('')
        ..add(text);
    }
    if (prop.defaultValue != null) {
      lines
        ..add('')
        ..add('Default: `${prop.defaultValue}`');
    }
    if (prop.deprecated != null && prop.deprecated != false) {
      lines
        ..add('')
        ..add(
          '**Deprecated**: ${prop.deprecated == true ? '' : prop.deprecated}',
        );
    }
    final hint = prop.hint;
    if (hint != null) {
      if (hint.range case (final low, final high)?) {
        lines
          ..add('')
          ..add('Range: $low to $high');
      }
      if (hint.values.isNotEmpty) {
        lines
          ..add('')
          ..add('Values:');
        for (final (v, description) in hint.values) {
          lines.add('- `$v`${description == null ? '' : ': $description'}');
        }
      }
    } else if (prop.values.isNotEmpty) {
      lines
        ..add('')
        ..add(
          'Values: ${[for (final v in prop.values) '`${v.$1}`'].join(', ')}',
        );
    }
    if (prop.flutter case final field?) {
      lines
        ..add('')
        ..add('Sets: `$field`');
    }
    if (prop.source != null) {
      lines
        ..add('')
        ..add(
          'Source: ${prop.className == null ? '' : '`${prop.className}` in '}'
          '`${prop.source}`${prop.line == null ? '' : ':${prop.line}'}',
        );
    }
    if (prop.fromCode) {
      lines
        ..add('')
        ..add('Read by code (`@Value`, `@ConditionalOnProperty`, ...)');
    }
    return lines.join('\n');
  }

  String _themeTypeText(SchemaProp prop) =>
      prop.type == 'choice' && prop.values.isNotEmpty
      ? 'one of ${[for (final v in prop.values) v.$1].join(' | ')}'
      : prop.type;

  // -------------------------------------------------------------------
  // Definition
  // -------------------------------------------------------------------

  List<SourceRange> definition(String path, String text, int offset) {
    final (line, column) = _lineColumn(text, offset);
    final keys = _keys(path, text);
    final valueKey = _valueAt(keys, line, column);
    if (valueKey == null) {
      return const [];
    }
    final inside = _templateAt(valueKey, column);
    if (inside != null) {
      final (part, source) = inside;
      if (part.kind == TemplatePartKind.placeholder) {
        return [
          for (final entry in workspace.property(part.inner(source)))
            SourceRange(
              entry.path,
              entry.line,
              entry.keyStart,
              entry.line,
              entry.keyEnd,
            ),
        ];
      }
      return workspace.spelDefinition(
        path,
        source.substring(part.innerStart, part.innerEnd),
        column - valueKey.valueStart - part.innerStart,
      );
    }
    if (_isTheme(valueKey.segments)) {
      final relative = column - valueKey.valueStart;
      final theme = _themeOf(valueKey.segments);
      final named = _loaderDefinition(path, valueKey);
      if (named.isNotEmpty) {
        return named;
      }
      for (final ref in _references(valueKey.value!)) {
        if (relative >= ref.start && relative <= ref.end) {
          return _RefIndex(workspace, path).definitions(ref.path, theme);
        }
      }
    }
    return const [];
  }

  // The name of the theme a key belongs to; `null` for the root.
  static String? _themeOf(List<String> segments) {
    final rest = segments.length > themePrefix.length
        ? segments.sublist(themePrefix.length)
        : const <String>[];
    if (rest.length >= 2 && canonicalName(rest[0]) == 'themes') {
      return rest[1];
    }
    return null;
  }

  // -------------------------------------------------------------------
  // Completion
  // -------------------------------------------------------------------

  CompletionResult? completion(String path, String text, int offset) {
    final (line, column) = _lineColumn(text, offset);
    final lines = text.split('\n');
    if (line >= lines.length) {
      return null;
    }
    final current = lines[line].replaceAll('\r', '');
    final before = current.substring(0, column.clamp(0, current.length));
    final yaml = _isYaml(path);
    if (yaml
        ? _stripComment(before).length != before.length
        : _propComment(before)) {
      return null;
    }
    final keys = _keys(path, text);
    // Where is the value of this line? After the colon (YAML) or the
    // separator (properties).
    final split = yaml
        ? _yamlValueSplit(before)
        : _propertiesValueSplit(before);
    if (split == null) {
      return _keyCompletion(
        path,
        text,
        lines,
        line,
        column,
        before,
        yaml,
        keys,
      );
    }
    final (keyText, valueText, valueStart) = split;
    final segments = _valueKeySegments(path, text, lines, line, keyText, yaml);
    return _valueCompletion(
      path,
      line,
      column,
      segments,
      valueText,
      valueStart,
    );
  }

  static bool _propComment(String before) {
    final trimmed = before.trimLeft();
    return trimmed.startsWith('#') || trimmed.startsWith('!');
  }

  // `key: value` up to the cursor: (key text, value so far, value column).
  (String, String, int)? _yamlValueSplit(String before) {
    var content = before;
    var offset = 0;
    while (true) {
      final trimmed = content.trimLeft();
      if (trimmed == '-' || trimmed.startsWith('- ')) {
        final skip = content.length - trimmed.length + (trimmed == '-' ? 1 : 2);
        offset += skip;
        content = content.substring(skip);
      } else {
        break;
      }
    }
    final body = content.trimLeft();
    offset += content.length - body.length;
    var from = 0;
    if (body.isNotEmpty && (body[0] == '"' || body[0] == "'")) {
      final close = body.indexOf(body[0], 1);
      if (close < 0) {
        return null;
      }
      from = close + 1;
    }
    for (var i = from; i < body.length; i++) {
      if (body[i] == ':' && (i + 1 == body.length || body[i + 1] == ' ')) {
        final rest = body.substring(i + 1);
        final value = rest.trimLeft();
        return (
          body.substring(0, i).trim(),
          value,
          offset + i + 1 + (rest.length - value.length),
        );
      }
      if (body[i] == ' ' && i + 1 < body.length && body[i + 1] == '#') {
        return null;
      }
    }
    return null;
  }

  (String, String, int)? _propertiesValueSplit(String before) {
    final match = RegExp(r'^(\s*)([^\s=:]+)(\s*[=:]\s*|\s+)(.*)$')
        .firstMatch(before);
    if (match == null) {
      return null;
    }
    final start =
        match.group(1)!.length +
        match.group(2)!.length +
        match.group(3)!.length;
    return (match.group(2)!, match.group(4)!, start);
  }

  // The full path of the key of the line [line] whose key text is
  // [keyText]: the parent keys above it (YAML) plus the text.
  List<String> _valueKeySegments(
    String path,
    String text,
    List<String> lines,
    int line,
    String keyText,
    bool yaml,
  ) {
    final own = [
      for (final part in _dotted(
        keyText.replaceAll(RegExp('^["\']|["\']\$'), ''),
        0,
      ))
        part.$1,
    ];
    if (!yaml) {
      return splitKey(keyText);
    }
    final parents = _parentSegments(lines, line);
    return [...parents, ...own];
  }

  // The path of the keys that enclose the YAML line [line], found from the
  // indentation of the lines above it (the text may not parse yet).
  List<String> _parentSegments(List<String> lines, int line) {
    final current = lines[line];
    var limit = _keyIndent(current);
    final result = <List<String>>[];
    for (var row = line - 1; row >= 0 && limit > 0; row--) {
      final text = lines[row].replaceAll('\r', '');
      if (text.trim().isEmpty || text.trimLeft().startsWith('#')) {
        continue;
      }
      if (RegExp(r'^(---|\.\.\.)(\s|$)').hasMatch(text)) {
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
      final split = _splitKey(content);
      if (dashIndent >= 0 && keyIndent >= limit && dashIndent < limit) {
        // An earlier item of the same list: the item boundary.
        result.add(['[0]']);
        limit = dashIndent;
        continue;
      }
      if (split == null || keyIndent >= limit) {
        continue;
      }
      result.add([for (final part in _dotted(split.$1, 0)) part.$1]);
      limit = dashIndent >= 0 ? dashIndent : keyIndent;
      if (dashIndent >= 0) {
        result.add(['[0]']);
      }
    }
    return [for (final part in result.reversed) ...part];
  }

  static int _keyIndent(String line) {
    var content = line.replaceAll('\r', '');
    var indent = content.length - content.trimLeft().length;
    content = content.trimLeft();
    while (content == '-' || content.startsWith('- ')) {
      final rest = content.length == 1 ? '' : content.substring(2);
      indent += 2 + (rest.length - rest.trimLeft().length);
      content = rest.trimLeft();
    }
    return indent;
  }

  CompletionResult? _keyCompletion(
    String path,
    String text,
    List<String> lines,
    int line,
    int column,
    String before,
    bool yaml,
    List<_Key> keys,
  ) {
    final schema = workspace.schemaFor(path);
    final List<String> parents;
    String partial;
    int start;
    if (yaml) {
      var content = before;
      var offset = 0;
      while (content.trimLeft() == '-' || content.trimLeft().startsWith('- ')) {
        final trimmed = content.trimLeft();
        final skip = content.length - trimmed.length + (trimmed == '-' ? 1 : 2);
        offset += skip;
        content = content.substring(skip);
      }
      final trimmed = content.trimLeft();
      start = offset + content.length - trimmed.length;
      if (!RegExp(r'^[A-Za-z0-9_.\-\[\]*"]*$').hasMatch(trimmed)) {
        return null;
      }
      final dots = trimmed.lastIndexOf('.');
      final typed = dots < 0
          ? <String>[]
          : [
              for (final part in _dotted(trimmed.substring(0, dots), 0))
                part.$1,
            ];
      partial = dots < 0 ? trimmed : trimmed.substring(dots + 1);
      start += dots < 0 ? 0 : dots + 1;
      parents = [..._parentSegments(lines, line), ...typed];
    } else {
      final trimmed = before.trimLeft();
      final dots = trimmed.lastIndexOf('.');
      parents = dots < 0 ? const [] : splitKey(trimmed.substring(0, dots));
      partial = dots < 0 ? trimmed : trimmed.substring(dots + 1);
      start = before.length - partial.length;
    }
    final resolution = schema.resolve(parents);
    if (resolution.isUnknown) {
      return null;
    }
    final loaderKeys = _loaderKeyCompletion(
      path,
      line,
      start,
      column,
      parents,
      keys,
      yaml,
      _keyIndent(lines[line]),
      lines[line]
          .replaceAll('\r', '')
          .substring(column.clamp(0, lines[line].length))
          .contains(':'),
    );
    if (loaderKeys != null) {
      return loaderKeys;
    }
    final node = resolution.node;
    if (node != null &&
        resolution.rest.isEmpty &&
        node.children.isEmpty &&
        node.wildcard == null &&
        (node.prop?.theme ?? false) &&
        node.prop!.type == 'color') {
      // A color may be a plain value or an object: offer its parts.
      final indent = _keyIndent(lines[line]);
      return CompletionResult(_range(path, line, start, column), [
        const Completion('color', detail: 'color', insertText: 'color: '),
        const Completion('alpha', detail: 'percent', insertText: 'alpha: '),
        Completion(
          'mix',
          detail: 'with, amount',
          insertText: yaml ? 'mix:\n${' ' * (indent + 2)}' : 'mix.',
        ),
      ]);
    }
    if (node == null || node.open || resolution.rest.isNotEmpty) {
      if (node != null &&
          resolution.rest.isNotEmpty &&
          node.prop?.type == 'color') {
        return _colorPartsCompletion(
          path,
          line,
          start,
          column,
          node.prop!,
          resolution.rest,
        );
      }
      return null;
    }
    final items = <Completion>[];
    final rest = lines[line].replaceAll('\r', '');
    final hasColon = rest.substring(column.clamp(0, rest.length)).contains(':');
    final indent = _keyIndent(lines[line]);
    var order = 0;
    for (final child in node.named) {
      final prop = child.prop;
      final isGroup = child.children.isNotEmpty || child.wildcard != null;
      final leaf =
          !isGroup ||
          (prop != null && child.children.isEmpty && child.wildcard == null);
      items.add(
        Completion(
          child.name,
          kind: leaf ? 10 : 9,
          detail: prop == null ? null : _detail(prop),
          documentation: prop == null ? null : propertyHover(child.name, prop),
          insertText: !yaml || hasColon
              ? child.name
              : leaf
              ? '${child.name}: '
              : '${child.name}:\n${' ' * (indent + 2)}',
          sortText: (1000 + order++).toString(),
        ),
      );
    }
    final wildcard = node.wildcard;
    if (wildcard != null) {
      items.addAll(
        _wildcardKeys(path, parents, wildcard, yaml, hasColon, indent),
      );
    }
    if (items.isEmpty) {
      return null;
    }
    return CompletionResult(_range(path, line, start, column), items);
  }

  String _detail(SchemaProp prop) {
    final type = prop.theme ? _themeTypeText(prop) : prop.type;
    return prop.defaultValue == null ? type : '$type = ${prop.defaultValue}';
  }

  // Names for a map key: themes, color roles and so on.
  List<Completion> _wildcardKeys(
    String path,
    List<String> parents,
    SchemaNode wildcard,
    bool yaml,
    bool hasColon,
    int indent,
  ) {
    final last = parents.isEmpty ? '' : canonicalName(parents.last);
    var names = const <String>[];
    if (_isTheme(parents) || parents.length >= themePrefix.length) {
      names = switch (last) {
        'themes' => _themeNames(path),
        'colors' => colorRoles,
        'shape' => defaultShapeNames,
        'elevation' => [for (var i = 0; i < 6; i++) 'level$i'],
        'spacing' => const ['xs', 's', 'm', 'l', 'xl'],
        'durations' => const ['short', 'medium', 'long'],
        _ => const [],
      };
    }
    final leaf = wildcard.children.isEmpty && wildcard.wildcard == null;
    return [
      for (final name in names)
        Completion(
          name,
          kind: 12,
          detail: wildcard.prop?.type,
          insertText: !yaml || hasColon
              ? name
              : leaf
              ? '$name: '
              : '$name:\n${' ' * (indent + 2)}',
        ),
    ];
  }

  List<String> _themeNames(String path) {
    final names = <String>{'light', 'dark'};
    for (final entry in workspace.configEntries(path)) {
      final segments = splitKey(entry.key);
      if (_isTheme(segments) && _themeOf(segments) != null) {
        names.add(_themeOf(segments)!);
      }
    }
    return names.toList()..sort();
  }

  CompletionResult? _colorPartsCompletion(
    String path,
    int line,
    int start,
    int column,
    SchemaProp prop,
    List<String> rest,
  ) {
    if (rest.length > 1 && rest.first == 'mix' ||
        rest.length == 1 && rest.first == 'mix') {
      return CompletionResult(_range(path, line, start, column), const [
        Completion('with', detail: 'color', insertText: 'with: '),
        Completion(
          'amount',
          detail: 'percent',
          insertText: 'amount: ',
        ),
      ]);
    }
    return null;
  }

  CompletionResult? _valueCompletion(
    String path,
    int line,
    int column,
    List<String> segments,
    String valueText,
    int valueStart,
  ) {
    final schema = workspace.schemaFor(path);
    // Inside `${...}`: property keys.
    final placeholder = RegExp(r'\$\{([^}:]*)$').firstMatch(valueText);
    if (placeholder != null) {
      final typed = placeholder.group(1)!;
      final from = valueStart + placeholder.end - typed.length;
      return CompletionResult(_range(path, line, from, column), [
        for (final key in workspace.knownKeys(path))
          Completion(key, detail: 'property'),
      ]);
    }
    // Inside `#{...}`: beans and members.
    final spel = RegExp(r'#\{([^}]*)$').firstMatch(valueText);
    if (spel != null) {
      final result = workspace.spelComplete(path, spel.group(1)!);
      if (result == null) {
        return null;
      }
      final from = valueStart + spel.start + 2 + result.$1;
      return CompletionResult(_range(path, line, from, column), result.$2);
    }
    if (_isTheme(segments)) {
      final ref = RegExp(r'\$([A-Za-z0-9_.\-]*)$').firstMatch(valueText);
      if (ref != null && !valueText.endsWith(r'$$')) {
        final typed = ref.group(1)!;
        final dot = typed.lastIndexOf('.');
        final from = valueStart + ref.start + 1 + (dot < 0 ? 0 : dot + 1);
        final items = _RefIndex(workspace, path).complete(
          dot < 0 ? const [] : splitKey(typed.substring(0, dot)),
        );
        return items.isEmpty
            ? null
            : CompletionResult(_range(path, line, from, column), items);
      }
    }
    final named = _loaderValueCompletion(
      path,
      line,
      column,
      segments,
      valueText,
      valueStart,
    );
    if (named != null) {
      return named;
    }
    final resolution = schema.resolve(segments);
    final prop = resolution.isUnknown ? null : resolution.node?.prop;
    if (prop == null || resolution.rest.isNotEmpty && prop.type != 'color') {
      return null;
    }
    final items = <Completion>[];
    final word = RegExp(r'[A-Za-z0-9_.\-$]*$').firstMatch(valueText)!;
    final from = valueStart + word.start;
    final hint = prop.hint;
    if (prop.type == 'bool' || prop.type == 'true / false') {
      items.addAll([
        const Completion('true', kind: 12),
        const Completion('false', kind: 12),
      ]);
    }
    for (final (value, description) in prop.values) {
      items.add(Completion(value, kind: 20, documentation: description));
    }
    if (hint != null && hint.provider == 'profiles') {
      for (final profile in workspace.knownProfiles(path).toList()..sort()) {
        items.add(Completion(profile, kind: 20, detail: 'profile'));
      }
    }
    if (prop.theme) {
      final name = segments.isEmpty ? '' : canonicalName(segments.last);
      if (const {
        'active',
        'systemlight',
        'systemdark',
        'extends',
      }.contains(name)) {
        for (final theme in _themeNames(path)) {
          items.add(Completion(theme, kind: 20, detail: 'theme'));
        }
        if (name == 'active') {
          items.add(
            const Completion('system', kind: 20, detail: 'follow the device'),
          );
        }
      }
      if (prop.type == 'color' && resolution.rest.isEmpty ||
          prop.type == 'color' &&
              const {'color', 'with'}.contains(resolution.rest.lastOrNull)) {
        items.add(
          const Completion(r'$colors.', kind: 18, detail: 'a color role'),
        );
      }
    }
    return items.isEmpty
        ? null
        : CompletionResult(_range(path, line, from, column), items);
  }
}

/// The percent, hex and name forms of a color: a message when [value] is
/// not a color, `null` when it is (or may be: a reference).
String? colorProblem(String value) {
  final text = value.trim();
  if (RegExp(r'\s(alpha|mix)\s').hasMatch(text) ||
      RegExp(r'[A-Za-z0-9\-]@\d').hasMatch(text)) {
    return 'The one-line color forms are gone: write an object, '
        '`color: …` with `alpha: 12%` and/or `mix: { with: …, amount: 14% }`';
  }
  if (text.startsWith(r'$')) {
    return null;
  }
  if (RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$')
          .hasMatch(text) ||
      RegExp(r'^0[xX]([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(text)) {
    return null;
  }
  if (_colorNames.contains(text) || _isShade(text)) {
    return null;
  }
  if (colorRoles.contains(text)) {
    return "'$text' is a color role, no bare role names: write \$colors.$text";
  }
  final guess = didYouMean(text, _colorNames.toList());
  return "'$text' is not a color: use '#RRGGBB', '0xAARRGGBB', a Colors name "
      "or a \$reference${guess == null ? '' : ". Did you mean '$guess'?"}";
}

bool _isShade(String text) {
  final match = RegExp(r'^([A-Za-z]+)\.shade(\d+)$').firstMatch(text);
  if (match == null) {
    return false;
  }
  final name = match[1]!;
  final shade = int.parse(match[2]!);
  if (name.endsWith('Accent')) {
    return _accents.contains(name.substring(0, name.length - 6)) &&
        const {100, 200, 400, 700}.contains(shade);
  }
  return _primaries.contains(name) &&
      const {50, 100, 200, 300, 400, 500, 600, 700, 800, 900}.contains(shade);
}

const _primaries = {
  'red', 'pink', 'purple', 'deepPurple', 'indigo', 'blue', 'lightBlue', //
  'cyan', 'teal', 'green', 'lightGreen', 'lime', 'yellow', 'amber',
  'orange', 'deepOrange', 'brown', 'grey', 'blueGrey',
};

const _accents = {
  'red', 'pink', 'purple', 'deepPurple', 'indigo', 'blue', 'lightBlue', //
  'cyan', 'teal', 'green', 'lightGreen', 'lime', 'yellow', 'amber',
  'orange', 'deepOrange',
};

final Set<String> _colorNames = {
  ..._primaries,
  for (final name in _accents) '${name}Accent',
  'transparent',
  'black',
  'white',
  'black12',
  'black26',
  'black38',
  'black45',
  'black54',
  'black87',
  'white10',
  'white12',
  'white24',
  'white30',
  'white38',
  'white54',
  'white60',
  'white70',
};

/// The closest of [choices] to [name] when it is near enough to be a typo.
String? didYouMean(String name, List<String> choices) {
  String? best;
  var bestDistance = 1 << 30;
  final target = canonicalName(name);
  for (final choice in choices) {
    final candidate = canonicalName(choice);
    var distance = _distance(target, candidate);
    if (candidate.startsWith(target) || target.startsWith(candidate)) {
      distance = distance.clamp(0, 1);
    }
    if (distance < bestDistance) {
      bestDistance = distance;
      best = choice;
    }
  }
  final limit = target.length <= 4 ? 1 : (target.length <= 8 ? 2 : 3);
  return best != null && bestDistance <= limit ? best : null;
}

int _distance(String a, String b) {
  if (a == b) {
    return 0;
  }
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var twoBack = previous;
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      // Two letters swapped (hots for host) is one slip.
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        current[j] = current[j] < twoBack[j - 2] + 1
            ? current[j]
            : twoBack[j - 2] + 1;
      }
    }
    twoBack = previous;
    previous = current;
  }
  return previous[b.length];
}

/// A `$path` in a value: the segments and the span of the whole `$path`.
final class _Reference {
  const _Reference(this.path, this.start, this.end);
  final List<String> path;
  final int start;
  final int end;
}

List<_Reference> _references(String value) {
  final result = <_Reference>[];
  for (final match in RegExp(
    r'\$\$|\$([A-Za-z_][A-Za-z0-9_.\-]*)',
  ).allMatches(value)) {
    final path = match.group(1);
    if (path == null) {
      continue;
    }
    var text = path;
    while (text.endsWith('.') || text.endsWith('-')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isEmpty) {
      continue;
    }
    result.add(
      _Reference(text.split('.'), match.start, match.start + 1 + text.length),
    );
  }
  return result;
}

/// The declared values of the themes of a package and its dependencies, for
/// `$` references.
final class _RefIndex {
  _RefIndex(this.workspace, this.path) {
    for (final entry in workspace.configEntries(path)) {
      final segments = splitKey(entry.key);
      if (!ConfigEditor._isTheme(segments)) {
        continue;
      }
      var rest = segments.sublist(themePrefix.length);
      String? theme;
      if (rest.length >= 2 && canonicalName(rest[0]) == 'themes') {
        theme = rest[1];
        rest = rest.sublist(2);
      }
      if (rest.isEmpty) {
        continue;
      }
      declarations.add((entry, theme, rest));
      for (var i = 1; i <= rest.length; i++) {
        final key = rest.sublist(0, i).map(canonicalName).join('.');
        declared.putIfAbsent(key, () => rest.sublist(0, i));
      }
    }
  }

  final SpringWorkspace workspace;
  final String path;
  final declarations = <(PropertyEntry, String?, List<String>)>[];

  /// Canonical dotted path to the path as written.
  final declared = <String, List<String>>{};

  static const _sections = {
    'brightness', 'seedcolor', 'schemevariant', 'contrast', 'colors', //
    'typography', 'shape', 'elevation', 'spacing', 'visualdensity',
    'taptargetsize', 'splash', 'motion', 'components', 'tokens',
    'cupertino', 'styles', 'animations', 'background', 'loaders',
  };

  // The built-in names a reference may use without writing them.
  Iterable<List<String>> get _builtin sync* {
    for (final role in colorRoles) {
      yield ['colors', role];
    }
    for (final name in defaultShapeNames) {
      yield ['shape', name];
    }
    for (var i = 0; i < 6; i++) {
      yield ['elevation', 'level$i'];
    }
    for (final name in const ['xs', 's', 'm', 'l', 'xl']) {
      yield ['spacing', name];
    }
    for (final name in const ['short', 'medium', 'long']) {
      yield ['motion', 'durations', name];
    }
  }

  List<List<String>> _candidates(List<String> reference) => [
    reference,
    if (!_sections.contains(canonicalName(reference.first)))
      ['tokens', ...reference],
  ];

  String _key(List<String> segments) => segments.map(canonicalName).join('.');

  late final Set<String> _builtinKeys = {
    for (final path in _builtin)
      for (var i = 1; i <= path.length; i++) _key(path.sublist(0, i)),
  };

  bool exists(List<String> reference) {
    for (final candidate in _candidates(reference)) {
      final key = _key(candidate);
      if (declared.containsKey(key) || _builtinKeys.contains(key)) {
        return true;
      }
    }
    return false;
  }

  String? closest(List<String> reference) {
    final all = <String>{
      for (final path in declared.values)
        if (_isTokenPath(path)) path.skip(1).join('.') else path.join('.'),
      for (final path in _builtin) path.join('.'),
    }.toList();
    // A leaf for a leaf: `neon.cyna` means `neon.cyan`, not the group.
    final same = [
      for (final name in all)
        if (name.split('.').length == reference.length) name,
    ];
    return didYouMean(reference.join('.'), same) ??
        didYouMean(reference.join('.'), all);
  }

  static bool _isTokenPath(List<String> path) =>
      path.first.toLowerCase() == 'tokens' && path.length > 1;

  /// Where the reference is declared: the entries of its own theme, else of
  /// the root, else of any theme.
  List<SourceRange> definitions(List<String> reference, String? theme) {
    final wanted = {for (final c in _candidates(reference)) _key(c)};
    final matches = [
      for (final (entry, entryTheme, rest) in declarations)
        for (var i = 1; i <= rest.length; i++)
          if (wanted.contains(_key(rest.sublist(0, i))))
            (entry, entryTheme, i == rest.length),
    ];
    // Prefer the exact key; a group only when nothing is exact.
    var exact = [
      for (final m in matches)
        if (m.$3) m,
    ];
    if (exact.isEmpty) {
      exact = matches;
    }
    List<(PropertyEntry, String?, bool)> pick(bool Function(String?) test) => [
      for (final m in exact)
        if (test(m.$2)) m,
    ];
    var chosen = pick(
      (t) =>
          t != null &&
          theme != null &&
          canonicalName(t) == canonicalName(theme),
    );
    if (chosen.isEmpty) {
      chosen = pick((t) => t == null);
    }
    if (chosen.isEmpty) {
      chosen = exact;
    }
    final seen = <String>{};
    return [
      for (final (entry, _, _) in chosen)
        if (seen.add('${entry.path}:${entry.line}'))
          SourceRange(
            entry.path,
            entry.line,
            entry.keyStart,
            entry.line,
            entry.keyEnd,
          ),
    ];
  }

  String hover(List<String> reference) {
    final name = reference.join('.');
    final sites = definitions(reference, null);
    final lines = <String>['**`\$$name`**'];
    if (sites.isEmpty) {
      final builtin = exists(reference);
      lines.add(
        builtin
            ? 'A Material role or default of the palette (made from the seed).'
            : 'Not declared in any theme of this package or its dependencies.',
      );
      return lines.join('\n');
    }
    lines.add('');
    final wanted = {for (final c in _candidates(reference)) _key(c)};
    for (final (entry, theme, rest) in declarations) {
      if (wanted.contains(_key(rest))) {
        lines.add(
          '- `${entry.fileName}`'
          "${theme == null ? '' : ' (theme `$theme`)'}: `${entry.value}`",
        );
      }
    }
    return lines.join('\n');
  }

  /// Names below [parent] (a path without the `$`): the sections, tokens,
  /// roles and declared keys.
  List<Completion> complete(List<String> parent) {
    final names = <String, (int, String)>{};
    void add(String name, int kind, String detail) =>
        names.putIfAbsent(name, () => (kind, detail));
    final candidates = parent.isEmpty ? [<String>[]] : _candidates(parent);
    for (final base in candidates) {
      final baseKey = base.map(canonicalName).toList();
      void visit(List<String> path, String detail) {
        if (path.length <= base.length) {
          return;
        }
        for (var i = 0; i < base.length; i++) {
          if (canonicalName(path[i]) != baseKey[i]) {
            return;
          }
        }
        final isLeaf = path.length == base.length + 1;
        add(path[base.length], isLeaf ? 12 : 9, detail);
      }

      for (final path in declared.values) {
        visit(path, 'declared');
      }
      for (final path in _builtin) {
        visit(path, 'built in');
      }
    }
    if (parent.isEmpty) {
      // `$brand.`: the groups of tokens may drop the `tokens.`.
      for (final path in declared.values) {
        if (path.length > 2 && path.first.toLowerCase() == 'tokens') {
          add(path[1], 9, 'token group');
        }
      }
    }
    return [
      for (final MapEntry(key: name, value: (kind, detail)) in names.entries)
        Completion(name, kind: kind, detail: detail),
    ];
  }
}
