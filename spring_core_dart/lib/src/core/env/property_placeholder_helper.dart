import 'package:spring_core_dart/src/core/env/env_exceptions.dart';

/// The engine that replaces `${name}` and `${name:default}` placeholders
/// in text, looking each name up with a function you give.
///
/// The environment uses it to resolve placeholders in property values and
/// `@Value`. Use it directly to fill placeholders from something that is
/// not the environment, such as a map of template variables or a
/// database row; to resolve against the configuration, call
/// `environment.resolvePlaceholders` instead.
///
/// - Defaults may contain placeholders: `${a:${b:c}}`.
/// - Keys may contain placeholders: `${prefix.${suffix}}`.
/// - A found value is resolved again, so values may refer to other
///   values; a loop is detected and reported.
/// - `${db:url}` is first looked up as the key `db:url`, then as `db` with
///   the default `url` (Spring 6.2).
/// - The escape character (`\` by default) before the prefix or the
///   separator makes it literal: `\${not.a.placeholder}` gives
///   `${not.a.placeholder}`.
/// - A `${` without a closing `}` is kept as text.
///
/// ```dart
/// // Fills a URL template from values that are not properties.
/// final helper = PropertyPlaceholderHelper();
/// final values = {'host': 'localhost', 'port': '8080'};
/// helper.replacePlaceholders(
///   r'http://${host}:${port:80}/${path:}',
///   (key) => values[key],
/// ); // 'http://localhost:8080/'
/// ```
///
/// Spring (Java):
/// ```java
/// var helper = new PropertyPlaceholderHelper("${", "}", ":", '\\', false);
/// Map<String, String> values = Map.of("host", "localhost", "port", "8080");
/// String url = helper.replacePlaceholders(
///     "http://${host}:${port:80}/${path:}", values::get);
/// ```
class PropertyPlaceholderHelper {
  /// Creates a helper for the given syntax. The defaults give Spring's
  /// `${key:default}` with `\` as the escape character.
  ///
  /// With [ignoreUnresolvablePlaceholders] `false` (the default), a
  /// placeholder that cannot be resolved and has no default throws
  /// `PlaceholderResolutionException`; with `true` it stays in the text.
  PropertyPlaceholderHelper({
    this.prefix = r'${',
    this.suffix = '}',
    this.valueSeparator = ':',
    this.escapeCharacter = r'\',
    this.ignoreUnresolvablePlaceholders = false,
  }) : _simplePrefix = _simplePrefixFor(prefix, suffix);

  /// The text that opens a placeholder, `${` by default.
  final String prefix;

  /// The text that closes a placeholder, `}` by default.
  final String suffix;

  /// The text between a key and its default, `:` by default; `null` turns
  /// defaults off.
  final String? valueSeparator;

  /// The character that makes a following [prefix] or [valueSeparator]
  /// literal, `\` by default; `null` turns escaping off.
  final String? escapeCharacter;

  /// Whether a placeholder that cannot be resolved stays in the text
  /// (`true`) instead of throwing (`false`).
  final bool ignoreUnresolvablePlaceholders;

  // Opening bracket that nests with [suffix] (e.g. `{` for `${`/`}`), so
  // `${a{b}}` ends at the second `}` like in Spring.
  final String? _simplePrefix;

  static String? _simplePrefixFor(String prefix, String suffix) {
    const pairs = {'}': '{', ']': '[', ')': '('};
    final simple = pairs[suffix];
    return simple != null && prefix.endsWith(simple) ? simple : null;
  }

  /// Returns [value] with every placeholder replaced, looking keys up with
  /// [resolver].
  ///
  /// [resolver] returns the value of a key, or `null` when it has none;
  /// placeholders in what it returns are resolved too. Throws
  /// `PlaceholderResolutionException` for a circular reference, and for a
  /// placeholder without value or default unless
  /// [ignoreUnresolvablePlaceholders] is set.
  ///
  /// ```dart
  /// helper.replacePlaceholders(r'${a:${b:c}}', (_) => null); // 'c'
  /// ```
  String replacePlaceholders(
    String value,
    String? Function(String key) resolver,
  ) => _parse(value, resolver, <String>[]);

  // Scans [value] left to right; [visited] holds the keys currently being
  // resolved (outermost first) for cycle detection.
  String _parse(
    String value,
    String? Function(String key) resolver,
    List<String> visited,
  ) {
    final result = StringBuffer();
    var position = 0;
    while (position < value.length) {
      final start = value.indexOf(prefix, position);
      if (start < 0) {
        result.write(value.substring(position));
        break;
      }
      // Drop the escape character and keep the prefix as literal text.
      if (_isEscaped(value, start)) {
        result
          ..write(value.substring(position, start - escapeCharacter!.length))
          ..write(prefix);
        position = start + prefix.length;
        continue;
      }
      final end = _findEnd(value, start + prefix.length);
      if (end < 0) {
        // No closing suffix: the prefix is literal text and scanning goes
        // on after it, so `${a ${b}` still resolves `${b}` (Spring 6.2's
        // PlaceholderParser).
        result.write(value.substring(position, start + prefix.length));
        position = start + prefix.length;
        continue;
      }
      result.write(value.substring(position, start));
      final original = value.substring(start, end + suffix.length);
      final content = value.substring(start + prefix.length, end);
      result.write(_resolve(content, original, resolver, visited, value));
      position = end + suffix.length;
    }
    return result.toString();
  }

  String _resolve(
    String content,
    String original,
    String? Function(String key) resolver,
    List<String> visited,
    String value,
  ) {
    final (rawKey, rawDefault) = _split(content);
    // Like Spring 6.2, a simple `key:default` is first tried as a key
    // as a whole (`${db:url}` finds a `db:url` property).
    if (rawDefault != null &&
        !content.contains(prefix) &&
        !visited.contains(content)) {
      final whole = resolver(content);
      if (whole != null) {
        return _parse(whole, resolver, [...visited, content]);
      }
    }
    // Resolve placeholders inside the key and default first.
    final key = _parse(rawKey, resolver, visited);
    if (visited.contains(key)) {
      throw PlaceholderResolutionException(
        "Circular placeholder reference '$key'",
        key,
        [...visited, value],
      );
    }
    final resolved = resolver(key);
    if (resolved == null && rawDefault != null) {
      return _parse(rawDefault, resolver, visited);
    }
    if (resolved == null) {
      if (ignoreUnresolvablePlaceholders) {
        // Keep the placeholder, but with its key already resolved.
        return original.replaceFirst(content, key);
      }
      throw PlaceholderResolutionException(
        "Could not resolve placeholder '$key'",
        key,
        [value, ...visited.reversed],
      );
    }
    // The value itself may contain placeholders; resolve them with [key]
    // marked as visited to detect `a -> b -> a` cycles.
    return _parse(resolved, resolver, [...visited, key]);
  }

  // Splits `key:default` at the first unescaped, top-level separator;
  // an escaped separator stays in the key as a literal.
  (String, String?) _split(String content) {
    final separator = valueSeparator;
    if (separator == null) {
      return (content, null);
    }
    final escape = escapeCharacter;
    final key = StringBuffer();
    var depth = 0;
    var i = 0;
    while (i < content.length) {
      if (content.startsWith(prefix, i)) {
        depth++;
        key.write(prefix);
        i += prefix.length;
      } else if (depth > 0 && content.startsWith(suffix, i)) {
        depth--;
        key.write(suffix);
        i += suffix.length;
      } else if (depth == 0 &&
          escape != null &&
          content.startsWith(escape + separator, i)) {
        key.write(separator);
        i += escape.length + separator.length;
      } else if (depth == 0 && content.startsWith(separator, i)) {
        return (key.toString(), content.substring(i + separator.length));
      } else {
        key.write(content[i]);
        i++;
      }
    }
    return (key.toString(), null);
  }

  bool _isEscaped(String value, int index) {
    final escape = escapeCharacter;
    return escape != null &&
        index >= escape.length &&
        value.startsWith(escape, index - escape.length);
  }

  // Index of the [suffix] closing a placeholder whose content starts at
  // [from], honoring nested placeholders and simple brackets; -1 if
  // unclosed.
  int _findEnd(String value, int from) {
    var depth = 0;
    var index = from;
    while (index < value.length) {
      if (value.startsWith(suffix, index)) {
        if (depth == 0) {
          return index;
        }
        depth--;
        index += suffix.length;
      } else if (value.startsWith(prefix, index)) {
        depth++;
        index += prefix.length;
      } else if (_simplePrefix != null &&
          value.startsWith(_simplePrefix, index)) {
        depth++;
        index += _simplePrefix.length;
      } else {
        index++;
      }
    }
    return -1;
  }
}
