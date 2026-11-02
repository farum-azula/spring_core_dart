/// Turns the names of the configuration (property keys, message keys, theme
/// names) into Dart member names, for the typed accessors that
/// [FlutterKeysBuilder](flutter_keys_builder.dart) writes.
///
/// The rules, also listed in the generator's README:
///
/// - `-` and `_` start a new word: `surface-container-low` is
///   `surfaceContainerLow`, `neon_night` is `neonNight`;
/// - the first letter is lower case: `NotBlank` is `notBlank`; the rest of
///   a name is kept, so a name already in camel case stays as it is
///   (`loginToOrder`);
/// - a name that starts with a digit gets a leading `$`: `2xl` is `$2xl`;
/// - a name that is a Dart keyword or a member every object has gets a
///   trailing `$`: `default` is `default$`, `hashCode` is `hashCode$`;
/// - a name with any other character (a space, `/`, a letter outside
///   `A-Z a-z`) has no Dart name ([member] returns `null`).
///
/// ```dart
/// DartNames.member('surface-container-low'); // surfaceContainerLow
/// DartNames.member('2xl'); // $2xl
/// DartNames.member('default'); // default$
/// DartNames.member('a b'); // null
/// ```
abstract final class DartNames {
  static const _reserved = {
    'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
    'default', 'do', 'else', 'enum', 'extends', 'false', 'final', //
    'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', //
    'return', 'super', 'switch', 'this', 'throw', 'true', 'try', 'var', //
    'void', 'while', 'with',
    // Members of every object.
    'hashCode', 'runtimeType', 'toString', 'noSuchMethod',
  };

  static final _valid = RegExp(r'^[A-Za-z0-9$]+$');

  /// The Dart member name of [key] (one segment, without dots), or `null`
  /// when it cannot be written as a Dart name.
  static String? member(String key) {
    final words = key.split(RegExp('[-_]+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) {
      return null;
    }
    var name = [
      _lowerFirst(words.first),
      for (final word in words.skip(1)) _upperFirst(word),
    ].join();
    if (!_valid.hasMatch(name)) {
      return null;
    }
    if (RegExp('^[0-9]').hasMatch(name)) {
      name = '\$$name';
    }
    return _reserved.contains(name) ? '$name\$' : name;
  }

  /// [name] with its first letter in upper case (for class names).
  static String upperFirst(String name) => _upperFirst(name);

  static String _lowerFirst(String s) => s[0].toLowerCase() + s.substring(1);

  static String _upperFirst(String s) => s[0].toUpperCase() + s.substring(1);

  /// [value] as a single-quoted Dart string literal.
  static String literal(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return "'$escaped'";
  }
}
