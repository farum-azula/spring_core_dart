import 'package:spring_core_dart/src/core/io/resource.dart';

/// Parses the `.properties` format Spring uses for config and message files.
///
/// Supports `=`, `:` and whitespace separators, `#` and `!` comments,
/// line continuations with a trailing backslash, the escapes `\t \n \r \f`,
/// `\uXXXX`, and escaped separators in keys. Keys keep file order; a
/// repeated key keeps the last value.
///
/// ```dart
/// final map = PropertiesParser.parse('''
/// # comment
/// app.name = Demo
/// app.greeting: Hello \\
///     world
/// ''');
/// map['app.greeting']; // 'Hello world'
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring delegates to java.util.Properties:
/// Properties props = new Properties();
/// props.load(new StringReader(content));
/// ```
///
/// Content is a Dart string (decoded as UTF-8 by the resource), not
/// ISO-8859-1 bytes as in `Properties.load(InputStream)`.
abstract final class PropertiesParser {
  /// Parses [content] into key/value pairs in file order.
  ///
  /// Throws [FormatException] for a malformed `\uXXXX` escape.
  static Map<String, String> parse(String content) {
    final result = <String, String>{};
    for (final line in _logicalLines(content)) {
      final (key, value) = _splitLine(line);
      result[key] = value;
    }
    return result;
  }

  // Logical lines: comments and blank lines dropped, continuations joined
  // (leading whitespace of continuation lines is dropped, as in Java).
  static Iterable<String> _logicalLines(String content) sync* {
    final lines = content.split(RegExp(r'\r\n|\r|\n'));
    var buffer = StringBuffer();
    var continuing = false;
    for (final raw in lines) {
      final line = raw.trimLeft();
      if (!continuing && (line.isEmpty || line[0] == '#' || line[0] == '!')) {
        continue;
      }
      if (_endsWithContinuation(line)) {
        buffer.write(line.substring(0, line.length - 1));
        continuing = true;
        continue;
      }
      buffer.write(line);
      continuing = false;
      yield buffer.toString();
      buffer = StringBuffer();
    }
    if (continuing && buffer.isNotEmpty) {
      yield buffer.toString();
    }
  }

  // An odd number of trailing backslashes continues the line; an even
  // number is a sequence of escaped backslashes.
  static bool _endsWithContinuation(String line) {
    var backslashes = 0;
    for (var i = line.length - 1; i >= 0 && line[i] == r'\'; i--) {
      backslashes++;
    }
    return backslashes.isOdd;
  }

  // Splits at the first unescaped `=`, `:` or whitespace (escapes are
  // skipped two characters at a time).
  static (String, String) _splitLine(String line) {
    var keyEnd = line.length;
    var valueStart = line.length;
    var hasSeparator = false;
    var i = 0;
    while (i < line.length) {
      final c = line[i];
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == '=' || c == ':') {
        keyEnd = i;
        valueStart = i + 1;
        hasSeparator = true;
        break;
      }
      if (c == ' ' || c == '\t' || c == '\f') {
        keyEnd = i;
        valueStart = i + 1;
        break;
      }
      i++;
    }
    // Whitespace, then an optional single '=' or ':' after a space.
    while (valueStart < line.length && _isWhitespace(line[valueStart])) {
      valueStart++;
    }
    if (!hasSeparator &&
        valueStart < line.length &&
        (line[valueStart] == '=' || line[valueStart] == ':')) {
      valueStart++;
      while (valueStart < line.length && _isWhitespace(line[valueStart])) {
        valueStart++;
      }
    }
    return (
      _unescape(line.substring(0, keyEnd)),
      _unescape(line.substring(valueStart.clamp(0, line.length))),
    );
  }

  static bool _isWhitespace(String c) => c == ' ' || c == '\t' || c == '\f';

  static final _hex4 = RegExp(r'^[0-9a-fA-F]{4}$');

  // Resolves escapes; an unknown escape keeps the character (`\=` → `=`)
  // and a trailing lone backslash is kept.
  static String _unescape(String text) {
    if (!text.contains(r'\')) {
      return text;
    }
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c != r'\' || i == text.length - 1) {
        out.write(c);
        continue;
      }
      final next = text[++i];
      switch (next) {
        case 't':
          out.write('\t');
        case 'n':
          out.write('\n');
        case 'r':
          out.write('\r');
        case 'f':
          out.write('\f');
        case 'u':
          final hex = i + 4 < text.length ? text.substring(i + 1, i + 5) : '';
          if (!_hex4.hasMatch(hex)) {
            throw FormatException(r'Malformed \uxxxx encoding', text, i);
          }
          out.writeCharCode(int.parse(hex, radix: 16));
          i += 4;
        default:
          out.write(next);
      }
    }
    return out.toString();
  }
}

/// Loads properties from resources, like Spring's `PropertiesLoaderUtils`.
///
/// ```dart
/// final props = await PropertiesLoaderUtils.loadProperties(
///   FileSystemResource('config/app.properties'),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// Properties props = PropertiesLoaderUtils.loadProperties(
///     new FileSystemResource("config/app.properties"));
/// ```
abstract final class PropertiesLoaderUtils {
  /// Reads and parses [resource] asynchronously.
  static Future<Map<String, String>> loadProperties(Resource resource) async =>
      PropertiesParser.parse(await resource.readAsString());

  /// Reads and parses [resource] synchronously; throws [UnsupportedError]
  /// for async-only resources.
  static Map<String, String> loadPropertiesSync(Resource resource) =>
      PropertiesParser.parse(resource.readAsStringSync());
}
