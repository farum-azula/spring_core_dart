import 'dart:io';

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
  });

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

  /// `application-prod` for `.../application-prod.properties`.
  String get fileName {
    final name = path.split(Platform.pathSeparator).last;
    return name.endsWith('.properties')
        ? name.substring(0, name.length - '.properties'.length)
        : name;
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
