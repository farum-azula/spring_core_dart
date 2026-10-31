import 'dart:convert';

import 'package:spring_core_dart/src/core/env/property_source.dart';

/// A reader for one config file format: it turns the text of a file into
/// property sources, one per document in the file.
///
/// The config data loader picks a loader by file extension. `.properties`
/// ([PropertiesPropertySourceLoader]) and `.yml` / `.yaml`
/// (`YamlPropertySourceLoader`) are built in, which covers almost every
/// application. Write one only for another format, such as JSON or TOML
/// config files, and pass it to a `ConfigDataEnvironment` you run
/// yourself; `SpringApplication` always uses the two built-in loaders.
///
/// Unlike Spring Boot, a loader gets the file's content as a string, not a
/// `Resource`, because some resources can only be read asynchronously; the
/// file is decoded with [encoding] first.
///
/// ```dart
/// // `application.json` files next to the YAML ones.
/// class JsonPropertySourceLoader extends PropertySourceLoader {
///   const JsonPropertySourceLoader();
///
///   @override
///   List<String> get fileExtensions => const ['json'];
///
///   @override
///   List<AbstractPropertySource<Object>> load(String name, String content) =>
///       [
///         MapPropertySource(
///           name,
///           YamlPropertySourceLoader.flatten(jsonDecode(content) as Object),
///         ),
///       ];
/// }
///
/// ConfigDataEnvironment(
///   environment,
///   loaders: const [
///     PropertiesPropertySourceLoader(),
///     YamlPropertySourceLoader(),
///     JsonPropertySourceLoader(),
///   ],
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// public class JsonPropertySourceLoader implements PropertySourceLoader {
///   @Override
///   public String[] getFileExtensions() {
///     return new String[] {"json"};
///   }
///
///   @Override
///   public List<PropertySource<?>> load(String name, Resource resource) {
///     return List.of(new MapPropertySource(name, flattenJson(resource)));
///   }
/// }
/// // registered in META-INF/spring.factories
/// ```
abstract class PropertySourceLoader {
  /// Lets subclasses be `const`.
  const PropertySourceLoader();

  /// The file extensions this loader reads, without the dot (`json`).
  /// When several loaders claim one, the first in the list wins.
  List<String> get fileExtensions;

  /// The character encoding the files are decoded with before [load];
  /// UTF-8 unless overridden.
  Encoding get encoding => utf8;

  /// The encoding of a file whose location names one with a Spring Boot
  /// 4.1 file hint (`x.properties[encoding=iso-8859-1]`, `x.conf[.yml]`
  /// `[encoding=utf-8]`): [encoding] unless overridden, so the hint is
  /// ignored, as Boot's YAML loader ignores it (the default of Boot's
  /// `PropertySourceLoader.load(name, resource, encoding)`).
  /// [PropertiesPropertySourceLoader] decodes with [hint].
  Encoding encodingFor(Encoding hint) => encoding;

  /// Parses [content], the text of one file, into one property source per
  /// document, in file order, skipping empty documents. Keys must be
  /// flat (`server.port`), as in a `.properties` file.
  ///
  /// [name] names the file in the sources (and so in error messages); a
  /// file with several documents should make it unique per document, as
  /// in `'$name (document #1)'`. Throw a [FormatException] for invalid
  /// content: the config data loader reports it with the location.
  List<AbstractPropertySource<Object>> load(String name, String content);
}

/// The reader for `.properties` config files, used for
/// `application.properties` and its profile variants.
///
/// A file can hold several documents, separated by a line `#---` or
/// `!---`; each becomes its own property source, so a later document can
/// be limited to a profile. The config data loader uses it by default, so
/// applications only write the files. Create one only to read
/// `.properties` files in another encoding.
///
/// ```dart
/// final sources = const PropertiesPropertySourceLoader().load(
///   'application.properties',
///   'a=1\n#---\nspring.config.activate.on-profile=dev\na=2\n',
/// );
/// sources.length; // 2
///
/// // Files in ISO-8859-1, as Spring Boot reads them:
/// ConfigDataEnvironment(
///   environment,
///   loaders: const [PropertiesPropertySourceLoader(encoding: latin1)],
/// );
/// ```
///
/// Files are read as Spring Boot's `OriginTrackedPropertiesLoader` reads
/// them, not as `java.util.Properties` (`PropertiesParser`, behind
/// `@PropertySource` and message bundles): a key ending in `[]` is a
/// comma-separated list (`hosts[]=a,b` sets `hosts[0]` and `hosts[1]`),
/// an empty key is skipped, and a separator counts only where a new
/// logical line starts: at the start of a physical line, without leading
/// blanks, three hyphens and nothing but blanks after them, not right
/// after a comment line with the same prefix (`# note` then `#---` is two
/// comments), and not on a line continued from the one before
/// (`a=base\` then `#---` sets `a` to `base#---`). Two differences from
/// Boot, which corrupt a file silently there: a comment right after a
/// separator (before the document's first key) keeps the documents apart
/// (Boot joins the new document to the one before it), and blanks after
/// a separator's hyphens do not change how the next line is read (in
/// Boot, the next line's leading blanks then make it a key without a
/// name, which is dropped, and a separator there is not seen).
///
/// Spring Boot reads `.properties` files as ISO-8859-1; here they are
/// UTF-8 unless [encoding] says otherwise, or the location names an
/// encoding (`x.properties[encoding=iso-8859-1]`, [encodingFor]). A
/// leading byte order mark is skipped. Spring Boot keeps it: read as
/// ISO-8859-1, its default, the first key starts with `ï»¿` there, and
/// its relaxed lookup still finds the key (`a=bom` reads `bom` in both).
///
/// Spring (Java):
/// ```java
/// List<PropertySource<?>> sources = new PropertiesPropertySourceLoader()
///     .load("application.properties",
///         new ClassPathResource("application.properties"));
/// ```
final class PropertiesPropertySourceLoader extends PropertySourceLoader {
  /// Creates a loader that decodes files with [encoding], UTF-8 unless
  /// given.
  const PropertiesPropertySourceLoader({this.encoding = utf8});

  @override
  final Encoding encoding;

  @override
  List<String> get fileExtensions => const ['properties'];

  /// [hint]: a `.properties` file is decoded with the encoding its
  /// location names, as in Spring Boot.
  @override
  Encoding encodingFor(Encoding hint) => hint;

  @override
  List<AbstractPropertySource<Object>> load(String name, String content) {
    final documents = _ConfigPropertiesReader(content).read();
    return [
      for (var i = 0; i < documents.length; i++)
        MapPropertySource(
          documents.length == 1 ? name : '$name (document #$i)',
          documents[i],
        ),
    ];
  }
}

// Spring Boot 4.1's OriginTrackedPropertiesLoader (with its
// CharacterReader), character by character, so that what is a separator,
// a comment, a continuation, a key and a value is decided as there; with
// the two differences the loader's documentation names. Line ends are
// `\n`, `\r\n` or `\r` (Java's LineNumberReader).
final class _ConfigPropertiesReader {
  _ConfigPropertiesReader(String content)
    : _text = (content.startsWith('﻿') ? content.substring(1) : content)
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');

  final String _text;
  int _position = 0;

  // The column of the current character in its line, -1 before the first.
  int _column = -1;
  bool _escaped = false;
  int _character = 0;

  // The prefix of the comment line just read, -1 after any other line.
  int _lastLineCommentPrefix = 0;

  static const _end = -1;
  static const _newline = 0x0a;
  static const _tab = 0x09;
  static const _formFeed = 0x0c;
  static const _space = 0x20;
  static const _hash = 0x23;
  static const _bang = 0x21;
  static const _comma = 0x2c;
  static const _hyphen = 0x2d;
  static const _colon = 0x3a;
  static const _equals = 0x3d;
  static const _backslash = 0x5c;

  // The documents with at least one key, in file order.
  List<Map<String, String>> read() {
    final documents = <Map<String, String>>[];
    var document = <String, String>{};
    final buffer = StringBuffer();
    while (_read()) {
      if (_isCommentPrefix) {
        final prefix = _character;
        if (_isNewDocument()) {
          if (document.isNotEmpty) {
            documents.add(document);
          }
          document = {};
        } else {
          // Boot reopens the previous document here while this one has
          // no key yet, so a comment after a separator joins the two.
          _lastLineCommentPrefix = prefix;
          _skipComment();
        }
      } else {
        _lastLineCommentPrefix = -1;
        _loadKeyAndValue(document, buffer);
      }
    }
    if (document.isNotEmpty) {
      documents.add(document);
    }
    return documents;
  }

  void _loadKeyAndValue(Map<String, String> document, StringBuffer buffer) {
    var key = _trim(_loadKey(buffer));
    if (key.endsWith('[]')) {
      key = key.substring(0, key.length - 2);
      var index = 0;
      do {
        _put(document, '$key[${index++}]', _loadValue(buffer, split: true));
        if (!_isEndOfLine) {
          _read();
        }
      } while (!_isEndOfLine);
    } else {
      _put(document, key, _loadValue(buffer, split: false));
    }
  }

  static void _put(Map<String, String> document, String key, String value) {
    if (key.isNotEmpty) {
      document[key] = value;
    }
  }

  String _loadKey(StringBuffer buffer) {
    buffer.clear();
    var previousWhitespace = false;
    while (!_isEndOfLine) {
      if (_isPropertyDelimiter) {
        _read();
        return buffer.toString();
      }
      if (!_isWhitespace && previousWhitespace) {
        return buffer.toString();
      }
      previousWhitespace = _isWhitespace;
      buffer.writeCharCode(_character);
      _read();
    }
    return buffer.toString();
  }

  String _loadValue(StringBuffer buffer, {required bool split}) {
    buffer.clear();
    while (_isWhitespace && !_isEndOfLine) {
      _read();
    }
    while (!_isEndOfLine && !(split && _isListDelimiter)) {
      buffer.writeCharCode(_character);
      _read();
    }
    return buffer.toString();
  }

  // Whether the comment prefix just read starts a separator line,
  // reading on to the end of the line when it does.
  bool _isNewDocument() {
    if (_lastLineCommentPrefix == _character) {
      return false;
    }
    var result = _column == 0;
    for (var i = 0; i < 3 && result; i++) {
      _read();
      result = _character == _hyphen;
    }
    if (!_isEndOfLine) {
      _read();
      _skipWhitespace();
      // Boot counts the newline those blanks end in as a column of this
      // line, so it does not see the next line start (the difference the
      // loader's documentation names).
      if (_character == _newline) {
        _column = -1;
      }
    }
    return result && _isEndOfLine;
  }

  // Java's LineNumberReader.read() (line ends already `\n`).
  int _next() =>
      _position < _text.length ? _text.codeUnitAt(_position++) : _end;

  // Boot's CharacterReader.read(), with its recursion into a continued
  // line (read(true) from readEscaped) made a loop, so any number of
  // lines holding only `\` is read.
  bool _read() {
    while (true) {
      _escaped = false;
      _character = _next();
      _column++;
      if (_column == 0) {
        _skipWhitespace();
      }
      if (_character == _backslash) {
        _escaped = true;
        if (_readEscaped()) {
          continue; // a continued line: read on from the next one
        }
      } else if (_character == _newline) {
        _column = -1;
      }
      return _character != _end;
    }
  }

  void _skipWhitespace() {
    while (_isWhitespace) {
      _character = _next();
      _column++;
    }
  }

  void _skipComment() {
    while (_character != _newline && _character != _end) {
      _character = _next();
    }
    _column = -1;
  }

  // The character after a `\`; whether it is a line end (a continued
  // line, read on by [_read]).
  bool _readEscaped() {
    _character = _next();
    switch (_character) {
      case 0x74: // t
        _character = _tab;
      case 0x72: // r
        _character = 0x0d;
      case 0x6e: // n
        _character = _newline;
      case 0x66: // f
        _character = _formFeed;
      case _newline: // a continued line
        _column = -1;
        return true;
      case 0x75: // u
        _readUnicode();
    }
    return false;
  }

  void _readUnicode() {
    _character = 0;
    for (var i = 0; i < 4; i++) {
      final digit = _next();
      final int value;
      if (digit >= 0x30 && digit <= 0x39) {
        value = digit - 0x30;
      } else if (digit >= 0x61 && digit <= 0x66) {
        value = digit - 0x61 + 10;
      } else if (digit >= 0x41 && digit <= 0x46) {
        value = digit - 0x41 + 10;
      } else {
        throw FormatException(r'Malformed \uxxxx encoding.', _text, _position);
      }
      _character = (_character << 4) + value;
    }
  }

  bool get _isWhitespace =>
      !_escaped &&
      (_character == _space || _character == _tab || _character == _formFeed);

  bool get _isEndOfLine =>
      _character == _end || !_escaped && _character == _newline;

  bool get _isListDelimiter => !_escaped && _character == _comma;

  bool get _isPropertyDelimiter =>
      !_escaped && (_character == _equals || _character == _colon);

  bool get _isCommentPrefix =>
      !_escaped && (_character == _hash || _character == _bang);

  // Java's String.trim(): code units up to a space off both ends.
  static String _trim(String text) {
    var start = 0;
    var end = text.length;
    while (start < end && text.codeUnitAt(start) <= _space) {
      start++;
    }
    while (end > start && text.codeUnitAt(end - 1) <= _space) {
      end--;
    }
    return text.substring(start, end);
  }
}
