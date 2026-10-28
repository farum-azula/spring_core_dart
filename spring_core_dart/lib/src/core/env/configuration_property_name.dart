/// A property name split into its elements (`app`, `read-timeout`) and
/// compared the relaxed way, so `app.readTimeout`, `app.read_timeout` and
/// `app.read-timeout` are the same name.
///
/// Config files, environment variables and command lines spell the same
/// property differently, and `@ConfigurationProperties` binding must still
/// match them to one field. The binder and the config data loader compare
/// names through this class. Applications do not use it; it is for code
/// that walks the configuration itself, such as a starter that binds a map
/// of clients by name.
///
/// Canonical names ([ConfigurationPropertyName.of]) are lower case with
/// `-` between words and `[index]` for list elements and map keys:
/// `app.read-timeout`, `app.hosts[0].name`, `app.headers[X-Shop]`. Names
/// as they appear in property sources are read with
/// [ConfigurationPropertyName.adapt]. Outside `[...]`, comparison ignores
/// case and every character that is not a letter or digit; `[...]`
/// elements compare exactly, and `a.b.0` equals `a.b[0]`.
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
  /// Reads [name] as a source wrote it, split at [separator] and at
  /// `[...]`. Any case and any character is accepted; elements without a
  /// letter or digit are dropped. Use it for keys found in property
  /// sources, which need not be canonical.
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
  ConfigurationPropertyName._(List<_Element> elements)
    : _elements = List.unmodifiable(elements);

  /// Parses [name], which must be canonical, such as a prefix written in
  /// code. Throws [InvalidConfigurationPropertyNameException] when it is
  /// not: upper-case letters, `_`, a leading or trailing `.`, an empty
  /// element, unbalanced brackets. The empty string is the [empty] name.
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

  /// Parses [name] like [ConfigurationPropertyName.of], but returns `null`
  /// instead of throwing when it is not canonical.
  static ConfigurationPropertyName? ofIfValid(String name) => _parse(name);

  /// Whether [name] is canonical, so [ConfigurationPropertyName.of]
  /// accepts it.
  static bool isValid(String name) => _parse(name) != null;

  /// The name with no elements, the root above every property.
  static final empty = ConfigurationPropertyName._(const []);

  final List<_Element> _elements;

  /// How many elements the name has (`app.hosts[0]` has three).
  int get numberOfElements => _elements.length;

  /// Whether this is the [empty] name.
  bool get isEmpty => _elements.isEmpty;

  /// The text of the element at [index] in the given [form] (as written
  /// unless given). A `[...]` element is returned as written, without the
  /// brackets.
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

  /// Whether the element at [index] was written in brackets (a list index
  /// or a map key).
  bool isIndexed(int index) => _elements[index].indexed;

  /// Whether the element at [index] is a bracketed list index of digits
  /// only, such as `[0]`.
  bool isNumericIndex(int index) =>
      _elements[index].indexed && _digits.hasMatch(_elements[index].value);

  /// Whether the last element was written in brackets.
  bool get isLastElementIndexed =>
      _elements.isNotEmpty && _elements.last.indexed;

  /// A new name: this one followed by [suffix], a canonical name or an
  /// `[index]`. Throws [InvalidConfigurationPropertyNameException] for a
  /// suffix that is not canonical.
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

  /// A new name with only the first [size] elements (this name when it
  /// has no more).
  ConfigurationPropertyName chop(int size) => size >= _elements.length
      ? this
      : ConfigurationPropertyName._(_elements.sublist(0, size));

  /// The name without its last element ([empty] for a single element).
  ConfigurationPropertyName get parent =>
      isEmpty ? this : chop(_elements.length - 1);

  /// Whether [name] is this name plus exactly one element: `app` is the
  /// parent of `app.port`, not of `app.db.port`.
  bool isParentOf(ConfigurationPropertyName name) =>
      name.numberOfElements == numberOfElements + 1 && _isPrefixOf(name);

  /// Whether [name] is below this name at any depth: `app` is an ancestor
  /// of `app.db.port`.
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

  /// Whether [other] has the same elements, compared the relaxed way:
  /// case and non-alphanumeric characters ignored outside brackets, exact
  /// inside them.
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

  /// The canonical text: elements in the dashed form joined with `.`,
  /// bracketed elements in brackets (`app.read-timeout`, `app.hosts[0]`).
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

/// How an element of a [ConfigurationPropertyName] is returned by
/// [ConfigurationPropertyName.getElement]: as written, dashed or reduced
/// to letters and digits. Bracketed elements are always returned as
/// written.
///
/// Spring (Java): Spring Boot's `ConfigurationPropertyName.Form`.
enum ConfigurationPropertyNameForm {
  /// As written in the source: `readTimeout`, `read_timeout`,
  /// `read-timeout`.
  original,

  /// Lower case with only letters, digits and dashes, as in a canonical
  /// name: `read-timeout` stays, `readTimeout` gives `readtimeout`.
  dashed,

  /// Lower case with only letters and digits, the form names are compared
  /// in: `readtimeout`.
  uniform,
}

/// The error for a name that should be canonical and is not, such as a
/// `@ConfigurationProperties` prefix written `app.readTimeout` instead of
/// `app.read-timeout`.
///
/// Thrown by [ConfigurationPropertyName.of]; the message lists the
/// offending characters. Applications see it as a startup failure and fix
/// the name.
///
/// ```dart
/// try {
///   ConfigurationPropertyName.of('app.readTimeout');
/// } on InvalidConfigurationPropertyNameException catch (error) {
///   print(error.invalidCharacters); // [T]
/// }
/// ```
///
/// Spring (Java): Spring Boot's `InvalidConfigurationPropertyNameException`.
final class InvalidConfigurationPropertyNameException implements Exception {
  /// Creates the exception for [name], listing its [invalidCharacters].
  InvalidConfigurationPropertyNameException(this.name, this.invalidCharacters);

  /// The name that was rejected.
  final String name;

  /// The characters of [name] that a canonical name cannot contain, each
  /// once. Empty when the characters are fine but their arrangement is
  /// not (`a..b`, `.a`).
  final List<String> invalidCharacters;

  @override
  String toString() {
    final invalid = invalidCharacters.isEmpty
        ? ''
        : ' (invalid characters: ${invalidCharacters.join(', ')})';
    return 'InvalidConfigurationPropertyNameException: Configuration property '
        "name '$name' is not valid. Canonical names should be kebab-case "
        "('-' separated), lowercase alpha-numeric characters and must start "
        'with a letter$invalid';
  }
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
