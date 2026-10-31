import 'dart:convert';

import 'package:spring_core_dart/src/core/io/resource.dart';

/// Reads text in the `.properties` format (`key=value` lines) into a map.
///
/// It is the parser behind `@PropertySource` files and message bundles
/// (`messages.properties`), as `java.util.Properties` is in Spring.
/// Config files (`application.properties`) are read as Spring Boot reads
/// them, by `PropertiesPropertySourceLoader`, which also knows `#---`
/// documents and `key[]=a,b` lists. Applications only write such files;
/// call it directly to read a properties text of your own, such as a file
/// uploaded by a user.
///
/// It reads the text exactly as `java.util.Properties.load` does: `=`,
/// `:` or whitespace separate a key from its value, `#` and `!` start a
/// comment line (also after leading whitespace), a line ending in an odd
/// number of backslashes continues on the next one (whose leading
/// whitespace is dropped), and `\t \n \r \f`, `\uXXXX` and `\` before any
/// other character are escapes, in keys too. Whitespace is a space, a tab
/// or a form feed only: other spaces (`U+3000`, a no-break space, a
/// vertical tab) are text. As in Java, a line holding only a backslash
/// joins nothing: the next line starts afresh (a comment stays one, a blank
/// line ends it), and at the end of the text it is an empty key. Keys keep
/// file order; a repeated key keeps its last value; trailing spaces of a
/// value are kept. A byte order mark is text too, so it becomes part of
/// the first key, as in Java.
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
/// The content is a Dart string, already decoded (as UTF-8 unless the
/// caller chose otherwise), not ISO-8859-1 bytes as in
/// `Properties.load(InputStream)`.
abstract final class PropertiesParser {
  /// Parses [content] into keys and values, in file order.
  ///
  /// Throws [FormatException] for a malformed `\uXXXX` escape.
  static Map<String, String> parse(String content) {
    final result = <String, String>{};
    final reader = _LineReader(content);
    for (var line = reader.readLine(); line != null; line = reader.readLine()) {
      final (key, value) = _keyAndValue(line);
      result[key] = value;
    }
    return result;
  }

  static const _space = 0x20;
  static const _tab = 0x09;
  static const _formFeed = 0x0c;
  static const _equals = 0x3d;
  static const _colon = 0x3a;
  static const _backslash = 0x5c;

  static bool _isWhitespace(int c) =>
      c == _space || c == _tab || c == _formFeed;

  // java.util.Properties.load0 for one logical line: the key ends at the
  // first `=`, `:` or whitespace not escaped; whitespace and one `=` or
  // `:` after it are skipped.
  static (String, String) _keyAndValue(String line) {
    final limit = line.length;
    var keyLength = 0;
    var valueStart = limit;
    var hasSeparator = false;
    var precedingBackslash = false;
    while (keyLength < limit) {
      final c = line.codeUnitAt(keyLength);
      if ((c == _equals || c == _colon) && !precedingBackslash) {
        valueStart = keyLength + 1;
        hasSeparator = true;
        break;
      } else if (_isWhitespace(c) && !precedingBackslash) {
        valueStart = keyLength + 1;
        break;
      }
      precedingBackslash = c == _backslash && !precedingBackslash;
      keyLength++;
    }
    while (valueStart < limit) {
      final c = line.codeUnitAt(valueStart);
      if (!_isWhitespace(c)) {
        if (!hasSeparator && (c == _equals || c == _colon)) {
          hasSeparator = true;
        } else {
          break;
        }
      }
      valueStart++;
    }
    return (
      _convert(line, 0, keyLength),
      _convert(line, valueStart, limit),
    );
  }

  // java.util.Properties.loadConvert: the escapes of [line] from [start]
  // to [end] resolved; an unknown one keeps its character (`\=` is `=`).
  static String _convert(String line, int start, int end) {
    final text = line.substring(start, end);
    if (!text.contains(r'\')) {
      return text;
    }
    final out = StringBuffer();
    var i = 0;
    while (i < text.length) {
      var c = text.codeUnitAt(i++);
      if (c != _backslash || i == text.length) {
        // The reader drops a backslash ending a line, so one is always
        // followed by a character here.
        out.writeCharCode(c);
        continue;
      }
      c = text.codeUnitAt(i++);
      if (c == 0x75) {
        // u
        if (i > text.length - 4) {
          throw FormatException(r'Malformed \uxxxx encoding.', text, i);
        }
        var value = 0;
        for (var digit = 0; digit < 4; digit++) {
          final d = text.codeUnitAt(i++);
          final int nibble;
          if (d >= 0x30 && d <= 0x39) {
            nibble = d - 0x30;
          } else if (d >= 0x61 && d <= 0x66) {
            nibble = d - 0x61 + 10;
          } else if (d >= 0x41 && d <= 0x46) {
            nibble = d - 0x41 + 10;
          } else {
            throw FormatException(r'Malformed \uxxxx encoding.', text, i);
          }
          value = (value << 4) + nibble;
        }
        out.writeCharCode(value);
      } else {
        out.writeCharCode(switch (c) {
          0x74 => _tab, // t
          0x72 => 0x0d, // r
          0x6e => 0x0a, // n
          0x66 => _formFeed, // f
          _ => c,
        });
      }
    }
    return out.toString();
  }
}

// java.util.Properties.LineReader, character by character: the logical
// lines of a text, comments and blank lines skipped, a line continued by
// an odd number of trailing backslashes joined to the next one without
// that line's leading whitespace. Line ends are `\n`, `\r` or `\r\n`.
final class _LineReader {
  _LineReader(this._text);

  final String _text;
  int _offset = 0;

  static const _newline = 0x0a;
  static const _return = 0x0d;
  static const _hash = 0x23;
  static const _bang = 0x21;

  // The next logical line; `null` at the end of the text.
  String? readLine() {
    final line = <int>[];
    var skipWhitespace = true;
    var appendedLineBegin = false;
    var precedingBackslash = false;
    String end() => String.fromCharCodes(
      precedingBackslash ? line.take(line.length - 1) : line,
    );

    while (true) {
      if (_offset >= _text.length) {
        return line.isEmpty ? null : end();
      }
      final c = _text.codeUnitAt(_offset++);
      if (skipWhitespace) {
        if (PropertiesParser._isWhitespace(c)) {
          continue;
        }
        if (!appendedLineBegin && (c == _return || c == _newline)) {
          continue;
        }
        skipWhitespace = false;
        appendedLineBegin = false;
      }
      if (line.isEmpty && (c == _hash || c == _bang)) {
        // A comment: the rest of the line.
        while (true) {
          if (_offset >= _text.length) {
            return null;
          }
          final next = _text.codeUnitAt(_offset++);
          if (next == _return || next == _newline) {
            break;
          }
        }
        skipWhitespace = true;
        continue;
      }
      if (c != _newline && c != _return) {
        line.add(c);
        precedingBackslash =
            c == PropertiesParser._backslash && !precedingBackslash;
        continue;
      }
      // The end of a line.
      if (line.isEmpty) {
        skipWhitespace = true;
        continue;
      }
      if (_offset >= _text.length) {
        return end();
      }
      if (!precedingBackslash) {
        return String.fromCharCodes(line);
      }
      // A continued line: the backslash goes, and so does the leading
      // whitespace of the next line.
      line.removeLast();
      skipWhitespace = true;
      appendedLineBegin = true;
      precedingBackslash = false;
      if (c == _return && _text.codeUnitAt(_offset) == _newline) {
        _offset++;
      }
    }
  }
}

/// Reads a `.properties` [Resource] into a map of keys to values in one
/// call.
///
/// Use it when the properties are data for your code rather than
/// configuration, such as a mapping table shipped in `lib/resources/`; for
/// configuration, put the file in the environment instead (a config file,
/// `@PropertySource` or `ResourcePropertySource`).
///
/// ```dart
/// // Country names shipped with the application.
/// final countries = await PropertiesLoaderUtils.loadProperties(
///   resourceLoader.getResource('classpath:countries.properties'),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// Properties countries = PropertiesLoaderUtils.loadProperties(
///     new ClassPathResource("countries.properties"));
/// ```
abstract final class PropertiesLoaderUtils {
  /// Reads [resource], decoded with [encoding] (UTF-8 unless given), and
  /// parses it. Works for every resource, including Flutter assets.
  static Future<Map<String, String>> loadProperties(
    Resource resource, {
    Encoding encoding = utf8,
  }) async =>
      PropertiesParser.parse(await resource.readAsString(encoding: encoding));

  /// Reads [resource] without waiting, decoded with [encoding], and parses
  /// it. Throws [UnsupportedError] for a resource that can only be read
  /// asynchronously.
  static Map<String, String> loadPropertiesSync(
    Resource resource, {
    Encoding encoding = utf8,
  }) => PropertiesParser.parse(resource.readAsStringSync(encoding: encoding));
}
