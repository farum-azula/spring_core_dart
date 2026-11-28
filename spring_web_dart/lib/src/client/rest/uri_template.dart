/// A URI template compiled once: the text between its `{variables}`
/// already encoded, the variables in order. A `RestClient` keeps the
/// templates it has seen, so a call expands a template without parsing it
/// again.
///
/// Encoding is Spring's `EncodingMode.TEMPLATE_AND_VALUES` (the default of
/// `RestClient`): the template's own text keeps its reserved characters
/// (`/`, `?`, `&`, `=`, ...) and percent-encodes what a URI cannot hold
/// (spaces, non-ASCII, `"`, ...; an existing `%XX` stays); a variable's
/// value is encoded strictly, every character but `A-Z a-z 0-9 - . _ ~`,
/// so `a/b` stays one path segment and `a&b=c` one query value.
///
/// Spring (Java): `UriTemplate` with `DefaultUriBuilderFactory`.
final class UriTemplate {
  /// The template [source], compiled: `{name}` (or `{name:pattern}`, whose
  /// pattern is ignored) marks a variable. Throws a [FormatException] for
  /// a `{` without its `}`.
  factory UriTemplate(String source) {
    final literals = <String>[];
    final names = <String>[];
    final inPath = <bool>[];
    final literal = StringBuffer();
    var path = true;
    for (var i = 0; i < source.length; i++) {
      final unit = source.codeUnitAt(i);
      if (unit != 0x7B) {
        if (unit == 0x3F || unit == 0x23) {
          path = false;
        }
        literal.writeCharCode(unit);
        continue;
      }
      var depth = 1;
      var end = i + 1;
      for (; end < source.length && depth > 0; end++) {
        final inner = source.codeUnitAt(end);
        if (inner == 0x7B) {
          depth++;
        } else if (inner == 0x7D) {
          depth--;
        }
      }
      if (depth != 0) {
        throw FormatException('A "{" without its "}"', source, i);
      }
      final variable = source.substring(i + 1, end - 1);
      final colon = variable.indexOf(':');
      literals.add(encodeLiteral(literal.toString()));
      literal.clear();
      names.add((colon < 0 ? variable : variable.substring(0, colon)).trim());
      inPath.add(path);
      i = end - 1;
    }
    literals.add(encodeLiteral(literal.toString()));
    return UriTemplate._(source, literals, names, inPath);
  }

  UriTemplate._(this.source, this._literals, this._names, this._inPath)
    : _constant = _names.isEmpty ? Uri.parse(_literals.single) : null;

  /// The template as written.
  final String source;

  final List<String> _literals;
  final List<String> _names;
  final List<bool> _inPath;
  final Uri? _constant;

  /// The names of the variables, in order (a name used twice is twice).
  List<String> get variableNames => List.unmodifiable(_names);

  /// The URI with [variables]: a `List` gives the values in order (each
  /// `{...}` takes the next), a `Map` by name (with [defaults] for the
  /// names it lacks), any other value is the one value of a template with
  /// one variable, and `null` is no values.
  ///
  /// A `null` value is an empty text; a list value is joined with commas,
  /// a `DateTime` in ISO-8601, an enum by its name, anything else by
  /// `toString()`. Throws an [ArgumentError] when a value is missing, when
  /// a list has more values than the template has variables (Spring
  /// ignores them; here they are a mistake), or when a path variable is
  /// `.` or `..`, which would move the call to another path.
  Uri expand(
    Object? variables, [
    Map<String, Object?> defaults = const {},
  ]) {
    final constant = _constant;
    if (constant != null) {
      if (variables is List && variables.isNotEmpty) {
        throw ArgumentError.value(
          variables,
          'variables',
          'The template "$source" has no variables',
        );
      }
      return constant;
    }
    final out = StringBuffer(_literals[0]);
    final valueOf = switch (variables) {
      final List<Object?> list => () {
        if (list.length > _names.length) {
          throw ArgumentError.value(
            list,
            'variables',
            'The template "$source" has ${_names.length} variables, '
                'not ${list.length}',
          );
        }
        return (int index) => index < list.length
            ? list[index]
            : throw ArgumentError(
                'Not enough variable values to expand "${_names[index]}" '
                'of "$source" (${list.length} given)',
              );
      }(),
      final Map<Object?, Object?> map => (int index) {
        final name = _names[index];
        if (map.containsKey(name)) {
          return map[name];
        }
        if (defaults.containsKey(name)) {
          return defaults[name];
        }
        throw ArgumentError('No value for the variable "$name" of "$source"');
      },
      null when defaults.isNotEmpty => (int index) {
        final name = _names[index];
        return defaults.containsKey(name)
            ? defaults[name]
            : throw ArgumentError(
                'No value for the variable "$name" of "$source"',
              );
      },
      null => (int index) => throw ArgumentError(
        'No value for the variable "${_names[index]}" of "$source"',
      ),
      final Object single =>
        _names.length == 1
            ? (int index) => single
            : throw ArgumentError.value(
                single,
                'variables',
                'The template "$source" has ${_names.length} variables: '
                    'give a List or a Map',
              ),
    };
    for (var i = 0; i < _names.length; i++) {
      final text = uriValueText(valueOf(i));
      if (_inPath[i] && (text == '.' || text == '..')) {
        throw ArgumentError.value(
          text,
          _names[i],
          'A path variable must not be "." or "..": it would change the '
          'path of "$source"',
        );
      }
      out
        ..write(encodeStrict(text))
        ..write(_literals[i + 1]);
    }
    return Uri.parse(out.toString());
  }

  /// [value] as the text of a URI variable or query parameter: `''` for
  /// `null`, a `DateTime` in ISO-8601, an enum by its name, the items of
  /// a list joined with commas, anything else by `toString()`.
  static String uriValueText(Object? value) => switch (value) {
    null => '',
    final String text => text,
    final DateTime date => date.toIso8601String(),
    final Enum item => item.name,
    final Iterable<Object?> items => items.map(uriValueText).join(','),
    _ => value.toString(),
  };

  /// [text] with every character but the unreserved ones (`A-Z a-z 0-9
  /// - . _ ~`) percent-encoded in UTF-8: a variable's value.
  static String encodeStrict(String text) {
    for (var i = 0; i < text.length; i++) {
      if (!_isUnreserved(text.codeUnitAt(i))) {
        return _encode(text, _isUnreserved);
      }
    }
    return text;
  }

  /// [text] with what a URI cannot hold percent-encoded (spaces,
  /// non-ASCII, `"`, `<`, `>`, `\`, `^`, `` ` ``, `{`, `|`, `}` and a `%`
  /// that starts no `%XX`); reserved characters and `%XX` stay: the text
  /// of a template.
  static String encodeLiteral(String text) =>
      encodeAllowing(text, _isUriCharacter);

  /// [text] with every character [allowed] does not accept
  /// percent-encoded in UTF-8; a `%XX` escape always stays.
  static String encodeAllowing(String text, bool Function(int unit) allowed) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (!allowed(unit) && !_isEscape(text, i)) {
        return _encode(text, allowed, keepEscapes: true);
      }
    }
    return text;
  }

  static bool _isEscape(String text, int i) =>
      text.codeUnitAt(i) == 0x25 &&
      i + 2 < text.length &&
      _isHex(text.codeUnitAt(i + 1)) &&
      _isHex(text.codeUnitAt(i + 2));

  static String _encode(
    String text,
    bool Function(int unit) allowed, {
    bool keepEscapes = false,
  }) {
    final out = StringBuffer();
    final runes = text.runes.toList();
    for (var i = 0, offset = 0; i < runes.length; i++) {
      final rune = runes[i];
      if (rune < 0x80 &&
          (allowed(rune) || (keepEscapes && _isEscape(text, offset)))) {
        out.writeCharCode(rune);
      } else {
        for (final byte in _utf8(rune)) {
          out
            ..write('%')
            ..write(_hexDigits[byte >> 4])
            ..write(_hexDigits[byte & 0x0F]);
        }
      }
      offset += rune > 0xFFFF ? 2 : 1;
    }
    return out.toString();
  }

  static List<int> _utf8(int rune) {
    if (rune < 0x80) {
      return [rune];
    }
    if (rune < 0x800) {
      return [0xC0 | (rune >> 6), 0x80 | (rune & 0x3F)];
    }
    if (rune < 0x10000) {
      return [
        0xE0 | (rune >> 12),
        0x80 | ((rune >> 6) & 0x3F),
        0x80 | (rune & 0x3F),
      ];
    }
    return [
      0xF0 | (rune >> 18),
      0x80 | ((rune >> 12) & 0x3F),
      0x80 | ((rune >> 6) & 0x3F),
      0x80 | (rune & 0x3F),
    ];
  }

  static const _hexDigits = '0123456789ABCDEF';

  static bool _isHex(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x46) ||
      (unit >= 0x61 && unit <= 0x66);

  static bool _isAlphaNumeric(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A);

  static bool _isUnreserved(int unit) =>
      _isAlphaNumeric(unit) ||
      unit == 0x2D || // -
      unit == 0x2E || // .
      unit == 0x5F || // _
      unit == 0x7E; // ~

  /// Whether [unit] is a sub-delimiter of RFC 3986: `! $ & ' ( ) * + , ; =`.
  static bool isSubDelimiter(int unit) =>
      unit == 0x21 ||
      unit == 0x24 ||
      (unit >= 0x26 && unit <= 0x2C) ||
      unit == 0x3B ||
      unit == 0x3D;

  /// Whether [unit] may stand in a path segment as it is (RFC 3986
  /// `pchar`): unreserved, a sub-delimiter, `:` or `@`.
  static bool isPathCharacter(int unit) =>
      _isUnreserved(unit) ||
      isSubDelimiter(unit) ||
      unit == 0x3A ||
      unit == 0x40;

  // Unreserved and reserved characters (RFC 3986).
  static bool _isUriCharacter(int unit) =>
      isPathCharacter(unit) ||
      unit == 0x2F || // /
      unit == 0x3F || // ?
      unit == 0x23 || // #
      unit == 0x5B || // [
      unit == 0x5D; // ]

  @override
  String toString() => source;
}
