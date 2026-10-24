/// A property name made of dot-separated elements, compared the relaxed
/// way, like Spring Boot's `ConfigurationPropertyName`.
///
/// Canonical names ([ConfigurationPropertyName.of]) are lower-case with
/// `-` between words and `[index]` for list elements and map keys:
/// `app.read-timeout`, `app.hosts[0].name`, `app.headers[X-Shop]`. Names
/// as they appear in property sources are adapted with
/// [ConfigurationPropertyName.adapt], so `app.readTimeout`,
/// `app.read_timeout` and `app.READ-TIMEOUT` are all equal to
/// `app.read-timeout`: outside `[...]`, comparison ignores case and every
/// character that is not a letter or digit. `[...]` elements compare
/// exactly, and `a.b.0` equals `a.b[0]`.
///
/// ```dart
/// final name = ConfigurationPropertyName.of('app.read-timeout');
/// name == ConfigurationPropertyName.adapt('app.readTimeout', '.'); // true
/// ConfigurationPropertyName.of('app').isParentOf(name); // true
/// ConfigurationPropertyName.isValid('app.readTimeout'); // false
/// ```
///
/// Spring (Java):
/// ```java
/// var name = ConfigurationPropertyName.of("app.read-timeout");
/// name.equals(ConfigurationPropertyName.adapt("app.readTimeout", '.'));
/// ConfigurationPropertyName.of("app").isParentOf(name);
/// ConfigurationPropertyName.isValid("app.readTimeout"); // false
/// ```
final class ConfigurationPropertyName {
  ConfigurationPropertyName._(List<_Element> elements)
    : _elements = List.unmodifiable(elements);

  /// Parses a canonical [name]; throws
  /// [InvalidConfigurationPropertyNameException] if it is not one
  /// (upper-case letters, `_`, a leading or trailing `.`, unbalanced
  /// brackets, ...). The empty string is the [empty] name.
  ///
  /// ```dart
  /// ConfigurationPropertyName.of('spring.profiles.include[0]');
  /// ```
  factory ConfigurationPropertyName.of(String name) =>
      _parse(name) ??
      (throw InvalidConfigurationPropertyNameException(
        name,
        _invalidCharacters(name),
      ));

  /// Like [ConfigurationPropertyName.of], but `null` for an invalid name.
  static ConfigurationPropertyName? ofIfValid(String name) => _parse(name);

  /// Whether [name] is a valid canonical name.
  static bool isValid(String name) => _parse(name) != null;

  /// Splits [name] at [separator] (and `[...]`), accepting any case and
  /// characters; elements without letters or digits are dropped.
  ///
  /// ```dart
  /// ConfigurationPropertyName.adapt('Server.Read_Timeout', '.').toString();
  /// // 'server.readtimeout'
  /// ```
  factory ConfigurationPropertyName.adapt(String name, String separator) {
    final elements = <_Element>[];
    final buffer = StringBuffer();
    var depth = 0;
    void add({required bool indexed}) {
      final value = buffer.toString();
      buffer.clear();
      if (value.isEmpty) {
        return;
      }
      final element = _Element(value, indexed: indexed);
      if (indexed || element.key.isNotEmpty) {
        elements.add(element);
      }
    }

    for (var i = 0; i < name.length; i++) {
      final char = name[i];
      if (char == '[') {
        if (depth == 0) {
          add(indexed: false);
        } else {
          buffer.write(char);
        }
        depth++;
      } else if (char == ']' && depth > 0) {
        depth--;
        if (depth == 0) {
          add(indexed: true);
        } else {
          buffer.write(char);
        }
      } else if (depth == 0 && name.startsWith(separator, i)) {
        add(indexed: false);
        i += separator.length - 1;
      } else {
        buffer.write(char);
      }
    }
    add(indexed: depth > 0);
    return ConfigurationPropertyName._(elements);
  }

  /// The name without elements.
  static final empty = ConfigurationPropertyName._(const []);

  final List<_Element> _elements;

  /// Number of elements (`app.hosts[0]` has three).
  int get numberOfElements => _elements.length;

  /// Whether the name has no elements.
  bool get isEmpty => _elements.isEmpty;

  /// Element [index] in the given [form]; `[...]` elements are returned
  /// without brackets.
  ///
  /// ```dart
  /// final name = ConfigurationPropertyName.adapt('app.readTimeout', '.');
  /// name.getElement(1); // 'readTimeout'
  /// name.getElement(1, form: ConfigurationPropertyNameForm.uniform);
  /// // 'readtimeout'
  /// ```
  String getElement(
    int index, {
    ConfigurationPropertyNameForm form = ConfigurationPropertyNameForm.original,
  }) {
    final element = _elements[index];
    if (element.indexed) {
      return element.value;
    }
    return switch (form) {
      ConfigurationPropertyNameForm.original => element.value,
      ConfigurationPropertyNameForm.dashed => element.dashed,
      ConfigurationPropertyNameForm.uniform => element.key,
    };
  }

  /// Whether element [index] is a `[...]` element.
  bool isIndexed(int index) => _elements[index].indexed;

  /// Whether element [index] is a `[...]` element of digits only.
  bool isNumericIndex(int index) =>
      _elements[index].indexed && _digits.hasMatch(_elements[index].value);

  /// Whether the last element is a `[...]` element.
  bool get isLastElementIndexed =>
      _elements.isNotEmpty && _elements.last.indexed;

  /// This name followed by [suffix] (a canonical name or `[index]`).
  ///
  /// ```dart
  /// ConfigurationPropertyName.of('spring.profiles.include').append('[0]');
  /// ```
  ConfigurationPropertyName append(String suffix) {
    if (suffix.isEmpty) {
      return this;
    }
    final other = ConfigurationPropertyName.of(
      suffix.startsWith('[') ? 'x$suffix' : suffix,
    );
    return ConfigurationPropertyName._([
      ..._elements,
      ...suffix.startsWith('[') ? other._elements.skip(1) : other._elements,
    ]);
  }

  /// The first [size] elements.
  ConfigurationPropertyName chop(int size) => size >= _elements.length
      ? this
      : ConfigurationPropertyName._(_elements.sublist(0, size));

  /// The name without its last element ([empty] for a single element).
  ConfigurationPropertyName get parent =>
      isEmpty ? this : chop(_elements.length - 1);

  /// Whether [name] is this name plus exactly one element.
  bool isParentOf(ConfigurationPropertyName name) =>
      name.numberOfElements == numberOfElements + 1 && _isPrefixOf(name);

  /// Whether [name] starts with this name and has more elements.
  bool isAncestorOf(ConfigurationPropertyName name) =>
      name.numberOfElements > numberOfElements && _isPrefixOf(name);

  bool _isPrefixOf(ConfigurationPropertyName name) {
    for (var i = 0; i < _elements.length; i++) {
      if (_elements[i].key != name._elements[i].key) {
        return false;
      }
    }
    return true;
  }

  /// Relaxed equality: see the class documentation.
  @override
  bool operator ==(Object other) {
    if (other is! ConfigurationPropertyName ||
        other._elements.length != _elements.length) {
      return false;
    }
    for (var i = 0; i < _elements.length; i++) {
      if (_elements[i].key != other._elements[i].key) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_elements.map((e) => e.key));

  /// The canonical form: dashed elements joined with `.`, `[...]`
  /// elements in brackets.
  @override
  String toString() {
    final result = StringBuffer();
    for (final element in _elements) {
      if (element.indexed) {
        result
          ..write('[')
          ..write(element.value)
          ..write(']');
      } else {
        if (result.isNotEmpty) {
          result.write('.');
        }
        result.write(element.dashed);
      }
    }
    return result.toString();
  }

  static final _digits = RegExp(r'^[0-9]+$');
  static final _canonicalElement = RegExp(r'^[a-z0-9][a-z0-9-]*$');

  // A canonical name, or `null`: elements of `a-z`, `0-9` and `-` (not
  // first), separated by single dots, each optionally followed by
  // `[...]` indexes (which may contain anything but unbalanced brackets).
  static ConfigurationPropertyName? _parse(String name) {
    if (name.isEmpty) {
      return empty;
    }
    if (name.startsWith('.') || name.endsWith('.') || name.endsWith('[')) {
      return null;
    }
    final elements = <_Element>[];
    final buffer = StringBuffer();
    var depth = 0;
    for (var i = 0; i < name.length; i++) {
      final char = name[i];
      // `a..b` and `a.[0]` have an empty element (invalid in Spring Boot).
      if (depth == 0 && (char == '.' || char == '[') && i > 0) {
        if (name[i - 1] == '.') {
          return null;
        }
      }
      if (char == '[') {
        if (depth == 0) {
          if (buffer.isNotEmpty) {
            final value = buffer.toString();
            if (!_canonicalElement.hasMatch(value)) {
              return null;
            }
            elements.add(_Element(value, indexed: false));
            buffer.clear();
          }
        } else {
          buffer.write(char);
        }
        depth++;
      } else if (char == ']') {
        if (depth == 0) {
          return null;
        }
        depth--;
        if (depth == 0) {
          elements.add(_Element(buffer.toString(), indexed: true));
          buffer.clear();
        } else {
          buffer.write(char);
        }
      } else if (char == '.' && depth == 0) {
        if (buffer.isNotEmpty) {
          final value = buffer.toString();
          if (!_canonicalElement.hasMatch(value)) {
            return null;
          }
          elements.add(_Element(value, indexed: false));
          buffer.clear();
        }
      } else {
        // After `]` only `.` or `[` may follow.
        if (depth == 0 && i > 0 && name[i - 1] == ']') {
          return null;
        }
        buffer.write(char);
      }
    }
    if (depth != 0) {
      return null;
    }
    if (buffer.isNotEmpty) {
      final value = buffer.toString();
      if (!_canonicalElement.hasMatch(value)) {
        return null;
      }
      elements.add(_Element(value, indexed: false));
    }
    return ConfigurationPropertyName._(elements);
  }

  static List<String> _invalidCharacters(String name) => {
    for (final char in name.split(''))
      if (!RegExp(r'[a-z0-9.\-\[\]]').hasMatch(char)) char,
  }.toList();
}

/// The forms of a (non-indexed) element of a [ConfigurationPropertyName],
/// like Spring Boot's `ConfigurationPropertyName.Form`.
enum ConfigurationPropertyNameForm {
  /// As written: `readTimeout`, `read_timeout`, `read-timeout`.
  original,

  /// Lower case with only letters, digits and dashes: `read-timeout`
  /// (`readtimeout` for `readTimeout`).
  dashed,

  /// Lower case with only letters and digits: `readtimeout`.
  uniform,
}

/// A property name that is not a valid canonical
/// [ConfigurationPropertyName], like Spring Boot's
/// `InvalidConfigurationPropertyNameException`.
///
/// ```dart
/// try {
///   ConfigurationPropertyName.of('app.readTimeout');
/// } on InvalidConfigurationPropertyNameException catch (error) {
///   print(error.invalidCharacters); // [T]
/// }
/// ```
final class InvalidConfigurationPropertyNameException implements Exception {
  /// Creates the exception for [name] with its [invalidCharacters].
  InvalidConfigurationPropertyNameException(this.name, this.invalidCharacters);

  /// The rejected name.
  final String name;

  /// The characters that are not allowed.
  final List<String> invalidCharacters;

  @override
  String toString() =>
      "InvalidConfigurationPropertyNameException: Configuration property "
      "name '$name' is not valid. Canonical names should be kebab-case "
      "('-' separated), lowercase alpha-numeric characters and must start "
      'with a letter${invalidCharacters.isEmpty ? '' : ' (invalid characters: ${invalidCharacters.join(', ')})'}';
}

// One element: its text as written and its comparison key (the text for
// `[...]` elements, lower-case letters and digits otherwise).
final class _Element {
  _Element(this.value, {required this.indexed})
    : key = indexed
          ? value
          : value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  final String value;
  final bool indexed;
  final String key;

  String get dashed {
    final lower = value.toLowerCase().replaceAll(RegExp('[^a-z0-9-]'), '');
    return lower.replaceFirst(RegExp('^-+'), '');
  }
}
