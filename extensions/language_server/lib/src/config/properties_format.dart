import 'package:dart_spring_language_server/src/config/config_format.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';
import 'package:dart_spring_language_server/src/schema.dart';

/// Java `.properties` files: one `key=value` per logical line, `#` and `!`
/// comment lines, no nesting. The editor reads an open document the same
/// way as the index ([parseProperties]), which never fails.
final class PropertiesFormat implements ConfigFormat {
  /// The format.
  const PropertiesFormat();

  @override
  bool accepts(String path) => path.endsWith('.properties');

  @override
  bool recognises(String path) => accepts(path);

  @override
  List<PropertyEntry> entries(String path, String text) =>
      parseProperties(path, text);

  @override
  List<ConfigKey> keys(String path, String text) {
    final lines = text.split('\n');
    return [
      for (final entry in parseProperties(path, text))
        _key(lines[entry.line].replaceAll('\r', ''), entry),
    ];
  }

  // The key of [entry], whose line is [line], with the span of each
  // segment and the column of its value.
  static ConfigKey _key(String line, PropertyEntry entry) {
    final segments = splitKey(entry.key);
    final spans = [
      for (final part in dottedParts(
        line.substring(entry.keyStart, entry.keyEnd),
        entry.keyStart,
      ))
        (part.$2, part.$3),
    ];
    final separator = RegExp(
      r'^[ \t]*[=:]?[ \t]*',
    ).firstMatch(line.substring(entry.keyEnd))!;
    return ConfigKey(
      line: entry.line,
      segments: segments,
      parentCount: 0,
      spans: spans.length == segments.length
          ? spans
          : [(entry.keyStart, entry.keyEnd)],
      value: entry.value,
      valueStart: entry.keyEnd + separator.end,
      complex: line.trimRight().endsWith(r'\'),
      indent: entry.keyStart,
    );
  }

  // Comments are whole lines.
  @override
  String content(String line) => inComment(line) ? '' : line;

  @override
  bool inComment(String before) {
    final trimmed = before.trimLeft();
    return trimmed.startsWith('#') || trimmed.startsWith('!');
  }

  @override
  ValueSplit? valueSplit(String before) {
    final match = RegExp(
      r'^(\s*)([^\s=:]+)(\s*[=:]\s*|\s+)(.*)$',
    ).firstMatch(before);
    if (match == null) {
      return null;
    }
    return (
      key: match.group(2)!,
      value: match.group(4)!,
      start:
          match.group(1)!.length +
          match.group(2)!.length +
          match.group(3)!.length,
    );
  }

  @override
  List<String> keyPath(List<String> lines, int line, String keyText) =>
      splitKey(keyText);

  @override
  KeyTyping keyTyping(List<String> lines, int line, String before) {
    final trimmed = before.trimLeft();
    final dots = trimmed.lastIndexOf('.');
    final partial = dots < 0 ? trimmed : trimmed.substring(dots + 1);
    return (
      parents: dots < 0 ? const [] : splitKey(trimmed.substring(0, dots)),
      partial: partial,
      start: before.length - partial.length,
    );
  }

  @override
  String keyInsert(
    String name, {
    required bool group,
    required int indent,
    required bool hasColon,
  }) => name;

  @override
  String nestedInsert(String name, int indent) => '$name.';
}

/// Reads [content] as a Java `.properties` file and returns its entries,
/// each with the position of its key. Never throws.
///
/// It follows the format's rules: `#` and `!` comment lines, `=`, `:` or
/// white space between key and value, backslash escapes in keys, and a
/// trailing backslash that continues the value on the next line.
List<PropertyEntry> parseProperties(String path, String content) {
  final entries = <PropertyEntry>[];
  final lines = content.split('\n');
  var i = 0;
  while (i < lines.length) {
    final lineNumber = i;
    final line = lines[i].replaceAll('\r', '');
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
