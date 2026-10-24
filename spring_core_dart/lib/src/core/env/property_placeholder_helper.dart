import 'package:spring_core_dart/src/core/env/env_exceptions.dart';

/// Replaces `${name}` / `${name:default}` placeholders, like Spring's
/// `PropertyPlaceholderHelper`.
///
/// - Defaults may contain placeholders: `${a:${b:c}}`.
/// - Keys may contain placeholders: `${prefix.${suffix}}`.
/// - Resolved values are resolved again (recursively), with cycle
///   detection.
/// - The escape character (default `\`) before the prefix or separator
///   keeps it literal: `\${not.a.placeholder}` → `${not.a.placeholder}`.
///
/// Environments use it internally; use it directly to resolve placeholders
/// against any lookup function.
///
/// ```dart
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
  /// Creates a helper with the given syntax; the defaults match Spring's
  /// `${key:default}` with `\` as escape character.
  ///
  /// When [ignoreUnresolvablePlaceholders] is `false`, unresolvable
  /// placeholders without a default throw `PlaceholderResolutionException`.
  PropertyPlaceholderHelper({
    this.prefix = r'${',
    this.suffix = '}',
    this.valueSeparator = ':',
    this.escapeCharacter = r'\',
    this.ignoreUnresolvablePlaceholders = false,
  }) : _simplePrefix = _simplePrefixFor(prefix, suffix);

  /// Start of a placeholder, `${` by default.
  final String prefix;

  /// End of a placeholder, `}` by default.
  final String suffix;

  /// Separates a key from its default value; `null` disables defaults.
  final String? valueSeparator;

  /// Escapes [prefix] and [valueSeparator]; `null` disables escaping.
  final String? escapeCharacter;

  /// Leaves unresolvable placeholders as they are instead of throwing.
  final bool ignoreUnresolvablePlaceholders;

  // Opening bracket that nests with [suffix] (e.g. `{` for `${`/`}`), so
  // `${a{b}}` ends at the second `}` like in Spring.
  final String? _simplePrefix;

  static String? _simplePrefixFor(String prefix, String suffix) {
    const pairs = {'}': '{', ']': '[', ')': '('};
    final simple = pairs[suffix];
    return simple != null && prefix.endsWith(simple) ? simple : null;
  }

  /// Replaces all placeholders in [value] using [resolver].
  ///
  /// [resolver] returns the raw value of a key or `null` if undefined;
  /// returned values are resolved recursively. Throws
  /// `PlaceholderResolutionException` for circular references.
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
    var resolved = resolver(key);
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
    resolved = _parse(resolved, resolver, [...visited, key]);
    return resolved;
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
