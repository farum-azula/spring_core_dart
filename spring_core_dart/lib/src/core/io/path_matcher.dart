/// Tests paths such as `config/dev/app.properties` against patterns with
/// wildcards such as `config/**/*.properties`, and pulls values out of
/// them.
///
/// The resource pattern resolver and `@PropertySource` use it to expand
/// location patterns. [AntPathMatcher] is the only implementation;
/// applications rarely need either, but can use one for their own
/// matching of paths or dotted names.
///
/// ```dart
/// // Which uploaded files are stylesheets.
/// final PathMatcher matcher = AntPathMatcher();
/// matcher.match('/static/**/*.css', '/static/css/app.css'); // true
/// ```
///
/// Spring (Java):
/// ```java
/// PathMatcher matcher = new AntPathMatcher();
/// matcher.match("/static/**/*.css", "/static/css/app.css"); // true
/// ```
abstract interface class PathMatcher {
  /// Whether [path] contains pattern syntax (`*`, `?` or a `{name}`
  /// variable), so it must be matched rather than compared.
  ///
  /// ```dart
  /// matcher.isPattern('/users/{id}'); // true
  /// matcher.isPattern('/users/42'); // false
  /// ```
  bool isPattern(String path);

  /// Whether the whole of [path] matches [pattern].
  ///
  /// ```dart
  /// matcher.match('com/t?st.jsp', 'com/test.jsp'); // true
  /// matcher.match('com/**/test.jsp', 'com/a/b/test.jsp'); // true
  /// ```
  bool match(String pattern, String path);

  /// Whether [path] matches the beginning of [pattern], so a longer path
  /// starting with it could still match. Used to skip directories that
  /// cannot contain a match.
  ///
  /// ```dart
  /// matcher.matchStart('/api/*/users', '/api/v1'); // true
  /// ```
  bool matchStart(String pattern, String path);

  /// The part of [path] matched by the wildcard part of [pattern], such as
  /// the file path below a mapped directory.
  ///
  /// ```dart
  /// matcher.extractPathWithinPattern('/docs/*', '/docs/a/b.html');
  /// // 'a/b.html'
  /// ```
  String extractPathWithinPattern(String pattern, String path);

  /// The values of the `{name}` variables of [pattern] in [path], by name.
  ///
  /// Throws [StateError] if [path] does not match [pattern].
  ///
  /// ```dart
  /// matcher.extractUriTemplateVariables('/hotels/{hotel}', '/hotels/1');
  /// // {'hotel': '1'}
  /// ```
  Map<String, String> extractUriTemplateVariables(String pattern, String path);

  /// A comparator that sorts patterns from the most to the least specific
  /// for [path], to pick the best of several matching patterns. A pattern
  /// equal to [path] comes first and `/**` last.
  ///
  /// ```dart
  /// final patterns = ['/**', '/hotels/*', '/hotels/{id}']
  ///   ..sort(matcher.getPatternComparator('/hotels/1'));
  /// // ['/hotels/{id}', '/hotels/*', '/**']
  /// ```
  Comparator<String> getPatternComparator(String path);

  /// Joins two patterns into one, such as a prefix and a sub-pattern:
  /// `/hotels/*` and `/booking` give `/hotels/booking`.
  ///
  /// ```dart
  /// matcher.combine('/hotels', '{hotel}'); // '/hotels/{hotel}'
  /// matcher.combine('/*.html', '/hotels'); // '/hotels.html'
  /// ```
  String combine(String pattern1, String pattern2);
}

/// The [PathMatcher] for Ant-style patterns, the syntax of locations such
/// as `classpath*:i18n/**/*.properties`.
///
/// - `?` matches one character, `*` zero or more characters within a
///   segment, `**` zero or more whole segments;
/// - `{name}` captures part of a segment, `{name:regex}` only when it
///   matches the regular expression.
///
/// The separator is `/` unless given, so the same matcher works for
/// dotted names. Applications rarely create one; resource patterns use it
/// already.
///
/// ```dart
/// final matcher = AntPathMatcher();
/// matcher.match('config/**/*.properties', 'config/dev/app.properties');
/// matcher.extractUriTemplateVariables(
///   '/users/{id:\\d+}',
///   '/users/42',
/// ); // {'id': '42'}
///
/// final dots = AntPathMatcher(pathSeparator: '.');
/// dots.match('app.*.enabled', 'app.cache.enabled'); // true
/// ```
///
/// Spring (Java):
/// ```java
/// var matcher = new AntPathMatcher();
/// matcher.match("config/**/*.properties", "config/dev/app.properties");
/// matcher.extractUriTemplateVariables("/users/{id:\\d+}", "/users/42");
///
/// var dots = new AntPathMatcher(".");
/// dots.match("app.*.enabled", "app.cache.enabled");
/// ```
class AntPathMatcher implements PathMatcher {
  /// Creates a matcher that splits paths at [pathSeparator] (`/` unless
  /// given), compares segments case-sensitively unless [caseSensitive] is
  /// `false`, and ignores whitespace around segments when [trimTokens] is
  /// `true`.
  AntPathMatcher({
    this.pathSeparator = defaultPathSeparator,
    this.caseSensitive = true,
    this.trimTokens = false,
  });

  /// The default separator, `/`.
  static const defaultPathSeparator = '/';

  /// The text between path segments.
  final String pathSeparator;

  /// Whether segments are compared case-sensitively (default `true`).
  final bool caseSensitive;

  /// Whether whitespace around segments is ignored (default `false`).
  final bool trimTokens;

  /// How many compiled segment patterns are cached before caching is
  /// turned off, as Spring's `AntPathMatcher.CACHE_TURNOFF_THRESHOLD`
  /// does: that many distinct patterns means they are generated, so the
  /// cache would only grow.
  static const cacheTurnoffThreshold = 65536;

  // Compiled segment matchers by segment pattern, until the threshold.
  final _matchers = <String, _AntPathStringMatcher>{};
  bool _cachePatterns = true;

  @override
  bool isPattern(String path) {
    var uriVar = false;
    for (var i = 0; i < path.length; i++) {
      final c = path[i];
      if (c == '*' || c == '?') {
        return true;
      }
      if (c == '{') {
        uriVar = true;
      } else if (c == '}' && uriVar) {
        return true;
      }
    }
    return false;
  }

  @override
  bool match(String pattern, String path) =>
      _doMatch(pattern, path, true, null);

  @override
  bool matchStart(String pattern, String path) =>
      _doMatch(pattern, path, false, null);

  @override
  Map<String, String> extractUriTemplateVariables(String pattern, String path) {
    final variables = <String, String>{};
    if (!_doMatch(pattern, path, true, variables)) {
      throw StateError('Pattern "$pattern" is not a match for "$path"');
    }
    return variables;
  }

  // Port of Spring's AntPathMatcher.doMatch: matches segments from the
  // start up to the first `**`, from the end down to the last `**`, then
  // searches the segment groups between `**`s left to right. With
  // [fullMatch] false (matchStart), a path that runs out first matches.
  // [variables], if given, collects `{name}` values.
  bool _doMatch(
    String pattern,
    String path,
    bool fullMatch,
    Map<String, String>? variables,
  ) {
    if (path.startsWith(pathSeparator) != pattern.startsWith(pathSeparator)) {
      return false;
    }
    final pattDirs = _tokenize(pattern);
    final pathDirs = _tokenize(path);
    var pattStart = 0;
    var pattEnd = pattDirs.length - 1;
    var pathStart = 0;
    var pathEnd = pathDirs.length - 1;

    // Match up to the first '**'.
    while (pattStart <= pattEnd && pathStart <= pathEnd) {
      final pattDir = pattDirs[pattStart];
      if (pattDir == '**') {
        break;
      }
      if (!_matchStrings(pattDir, pathDirs[pathStart], variables)) {
        return false;
      }
      pattStart++;
      pathStart++;
    }

    if (pathStart > pathEnd) {
      // Path exhausted.
      if (pattStart > pattEnd) {
        return pattern.endsWith(pathSeparator) == path.endsWith(pathSeparator);
      }
      if (!fullMatch) {
        return true;
      }
      if (pattStart == pattEnd &&
          pattDirs[pattStart] == '*' &&
          path.endsWith(pathSeparator)) {
        return true;
      }
      for (var i = pattStart; i <= pattEnd; i++) {
        if (pattDirs[i] != '**') {
          return false;
        }
      }
      return true;
    } else if (pattStart > pattEnd) {
      // Pattern exhausted but path remains.
      return false;
    } else if (!fullMatch && pattDirs[pattStart] == '**') {
      return true;
    }

    // Match from the end up to the last '**'.
    while (pattStart <= pattEnd && pathStart <= pathEnd) {
      final pattDir = pattDirs[pattEnd];
      if (pattDir == '**') {
        break;
      }
      if (!_matchStrings(pattDir, pathDirs[pathEnd], variables)) {
        return false;
      }
      if (pattEnd == pattDirs.length - 1 &&
          pattern.endsWith(pathSeparator) != path.endsWith(pathSeparator)) {
        return false;
      }
      pattEnd--;
      pathEnd--;
    }
    if (pathStart > pathEnd) {
      for (var i = pattStart; i <= pattEnd; i++) {
        if (pattDirs[i] != '**') {
          return false;
        }
      }
      return true;
    }

    // Match the segments between '**' blocks.
    while (pattStart != pattEnd && pathStart <= pathEnd) {
      var patIdxTmp = -1;
      for (var i = pattStart + 1; i <= pattEnd; i++) {
        if (pattDirs[i] == '**') {
          patIdxTmp = i;
          break;
        }
      }
      if (patIdxTmp == pattStart + 1) {
        // '**/**' collapses.
        pattStart++;
        continue;
      }
      final patLength = patIdxTmp - pattStart - 1;
      final strLength = pathEnd - pathStart + 1;
      var foundIdx = -1;
      // Each attempt collects its variables apart, so a failed attempt
      // (backtracking over `**`) leaves nothing behind.
      outer:
      for (var i = 0; i <= strLength - patLength; i++) {
        final attempt = variables == null ? null : <String, String>{};
        for (var j = 0; j < patLength; j++) {
          final subPat = pattDirs[pattStart + j + 1];
          final subStr = pathDirs[pathStart + i + j];
          if (!_matchStrings(subPat, subStr, attempt)) {
            continue outer;
          }
        }
        if (attempt != null) {
          _mergeVariables(variables!, attempt);
        }
        foundIdx = pathStart + i;
        break;
      }
      if (foundIdx == -1) {
        return false;
      }
      pattStart = patIdxTmp;
      pathStart = foundIdx + patLength;
    }

    for (var i = pattStart; i <= pattEnd; i++) {
      if (pattDirs[i] != '**') {
        return false;
      }
    }
    return true;
  }

  // Adds [found] to [variables]; a name bound twice must have one value.
  static void _mergeVariables(
    Map<String, String> variables,
    Map<String, String> found,
  ) {
    for (final MapEntry(:key, :value) in found.entries) {
      final previous = variables[key];
      if (previous != null && previous != value) {
        throw ArgumentError(
          "The value '$value' for URI variable '$key' does not match the "
          "previous value '$previous'",
        );
      }
      variables[key] = value;
    }
  }

  // Path segments without empty ones (so `//` and edge separators vanish).
  List<String> _tokenize(String path) => [
    for (final token in path.split(pathSeparator))
      if ((trimTokens ? token.trim() : token).isNotEmpty)
        if (trimTokens) token.trim() else token,
  ];

  bool _matchStrings(
    String pattern,
    String text,
    Map<String, String>? variables,
  ) => _matcher(pattern).matches(text, variables);

  _AntPathStringMatcher _matcher(String pattern) {
    final cached = _matchers[pattern];
    if (cached != null) {
      return cached;
    }
    final matcher = _AntPathStringMatcher(
      pattern,
      caseSensitive: caseSensitive,
    );
    if (_cachePatterns) {
      if (_matchers.length >= cacheTurnoffThreshold) {
        _cachePatterns = false;
        _matchers.clear();
      } else {
        _matchers[pattern] = matcher;
      }
    }
    return matcher;
  }

  /// How many compiled segment patterns are cached now, for tests and
  /// diagnostics.
  int get cachedPatternCount => _matchers.length;

  @override
  String extractPathWithinPattern(String pattern, String path) {
    final patternParts = _tokenize(pattern);
    final pathParts = _tokenize(path);
    final builder = StringBuffer();
    var pathStarted = false;
    for (var segment = 0; segment < patternParts.length; segment++) {
      final patternPart = patternParts[segment];
      if (patternPart.contains('*') || patternPart.contains('?')) {
        for (; segment < pathParts.length; segment++) {
          if (pathStarted ||
              (segment == 0 && !pattern.startsWith(pathSeparator))) {
            builder.write(pathSeparator);
          }
          builder.write(pathParts[segment]);
          pathStarted = true;
        }
      }
    }
    return builder.toString();
  }

  @override
  String combine(String pattern1, String pattern2) {
    if (pattern1.isEmpty && pattern2.isEmpty) {
      return '';
    }
    if (pattern1.isEmpty) {
      return pattern2;
    }
    if (pattern2.isEmpty) {
      return pattern1;
    }
    final pattern1ContainsUriVar = pattern1.contains('{');
    if (pattern1 != pattern2 &&
        !pattern1ContainsUriVar &&
        match(pattern1, pattern2)) {
      return pattern2;
    }
    if (pattern1.endsWith('$pathSeparator*')) {
      return _concat(pattern1.substring(0, pattern1.length - 2), pattern2);
    }
    if (pattern1.endsWith('$pathSeparator**')) {
      return _concat(pattern1, pattern2);
    }
    final starDotPos1 = pattern1.indexOf('*.');
    if (pattern1ContainsUriVar || starDotPos1 == -1 || pathSeparator == '.') {
      return _concat(pattern1, pattern2);
    }
    final ext1 = pattern1.substring(starDotPos1 + 1);
    final dotPos2 = pattern2.indexOf('.');
    final file2 = dotPos2 == -1 ? pattern2 : pattern2.substring(0, dotPos2);
    final ext2 = dotPos2 == -1 ? '' : pattern2.substring(dotPos2);
    final ext1All = ext1 == '.*' || ext1.isEmpty;
    final ext2All = ext2 == '.*' || ext2.isEmpty;
    if (!ext1All && !ext2All) {
      throw ArgumentError('Cannot combine patterns: $pattern1 vs $pattern2');
    }
    return file2 + (ext1All ? ext2 : ext1);
  }

  // Joins with exactly one separator between the parts.
  String _concat(String path1, String path2) {
    final path1EndsWithSeparator = path1.endsWith(pathSeparator);
    final path2StartsWithSeparator = path2.startsWith(pathSeparator);
    if (path1EndsWithSeparator && path2StartsWithSeparator) {
      return path1 + path2.substring(1);
    }
    if (path1EndsWithSeparator || path2StartsWithSeparator) {
      return path1 + path2;
    }
    return path1 + pathSeparator + path2;
  }

  @override
  Comparator<String> getPatternComparator(String path) {
    return (pattern1, pattern2) {
      final info1 = _PatternInfo(pattern1);
      final info2 = _PatternInfo(pattern2);
      if (info1.isLeastSpecific && info2.isLeastSpecific) {
        return 0;
      } else if (info1.isLeastSpecific) {
        return 1;
      } else if (info2.isLeastSpecific) {
        return -1;
      }
      final pattern1EqualsPath = pattern1 == path;
      final pattern2EqualsPath = pattern2 == path;
      if (pattern1EqualsPath && pattern2EqualsPath) {
        return 0;
      } else if (pattern1EqualsPath) {
        return -1;
      } else if (pattern2EqualsPath) {
        return 1;
      }
      if (info1.isPrefixPattern && info2.isPrefixPattern) {
        return info2.length - info1.length;
      } else if (info1.isPrefixPattern && info2.doubleWildcards == 0) {
        return 1;
      } else if (info2.isPrefixPattern && info1.doubleWildcards == 0) {
        return -1;
      }
      if (info1.totalCount != info2.totalCount) {
        return info1.totalCount - info2.totalCount;
      }
      if (info1.length != info2.length) {
        return info2.length - info1.length;
      }
      if (info1.singleWildcards != info2.singleWildcards) {
        return info1.singleWildcards - info2.singleWildcards;
      }
      return info1.uriVars - info2.uriVars;
    };
  }
}

// Specificity counters of a pattern for [AntPathMatcher.getPatternComparator]
// (Spring's AntPatternComparator.PatternInfo).
final class _PatternInfo {
  _PatternInfo(this.pattern) {
    var pos = 0;
    while (pos < pattern.length) {
      if (pattern[pos] == '{') {
        uriVars++;
        pos++;
      } else if (pattern[pos] == '*') {
        if (pos + 1 < pattern.length && pattern[pos + 1] == '*') {
          doubleWildcards++;
          pos += 2;
        } else if (pos > 0 && pattern.substring(pos - 1) != '.*') {
          singleWildcards++;
          pos++;
        } else {
          pos++;
        }
      } else {
        pos++;
      }
    }
  }

  final String pattern;
  // `{var}` count; `*` count, excluding a trailing `.*`; `**` count.
  int uriVars = 0;
  int singleWildcards = 0;
  int doubleWildcards = 0;

  bool get isLeastSpecific => pattern == '/**';
  bool get isPrefixPattern => pattern.endsWith('/**');
  int get totalCount => uriVars + singleWildcards + 2 * doubleWildcards;
  // Length with each `{var}` counted as one character.
  int get length => pattern.replaceAll(RegExp(r'\{[^/]+?\}'), '#').length;
}

// Matches one path segment against a pattern with `*`, `?` and `{var}`.
// Plain segments are compared directly; others are compiled to a regex in
// which every `{var}` becomes a capturing group (`{var:regex}` uses the
// given regex).
final class _AntPathStringMatcher {
  _AntPathStringMatcher(String pattern, {required bool caseSensitive})
    : _exact = _isExact(pattern) ? pattern : null,
      _caseSensitive = caseSensitive {
    if (_exact != null) {
      return;
    }
    final regex = StringBuffer('^');
    var end = 0;
    for (final match in _globPattern.allMatches(pattern)) {
      regex.write(RegExp.escape(pattern.substring(end, match.start)));
      final token = match[0]!;
      if (token == '?') {
        regex.write('.');
      } else if (token == '*') {
        regex.write('.*');
      } else if (token.startsWith('{') && token.endsWith('}')) {
        final colon = token.indexOf(':');
        if (colon == -1) {
          regex.write('(.*)');
          _variableNames.add(token.substring(1, token.length - 1));
        } else {
          regex.write('(${token.substring(colon + 1, token.length - 1)})');
          _variableNames.add(token.substring(1, colon));
        }
      }
      end = match.end;
    }
    regex
      ..write(RegExp.escape(pattern.substring(end)))
      ..write(r'$');
    _regex = RegExp(
      regex.toString(),
      caseSensitive: caseSensitive,
      dotAll: true,
    );
  }

  // `?`, `*`, or `{...}` (which may contain nested `{n}` quantifiers or
  // escaped braces), as in Spring's GLOB_PATTERN.
  static final _globPattern = RegExp(
    r'\?|\*|\{((?:\{[^/]+?\}|[^/{}]|\\[{}])+?)\}',
  );

  final String? _exact;
  final bool _caseSensitive;
  late final RegExp _regex;
  final _variableNames = <String>[];

  static bool _isExact(String pattern) =>
      !pattern.contains('*') &&
      !pattern.contains('?') &&
      !pattern.contains('{');

  bool matches(String text, Map<String, String>? variables) {
    final exact = _exact;
    if (exact != null) {
      return _caseSensitive
          ? exact == text
          : exact.toLowerCase() == text.toLowerCase();
    }
    final match = _regex.firstMatch(text);
    if (match == null) {
      return false;
    }
    if (variables != null) {
      // Extra groups in a custom `{var:regex}` would shift the values.
      if (_variableNames.length != match.groupCount) {
        throw ArgumentError(
          'The number of capturing groups in the pattern segment '
          '${_regex.pattern} does not match the number of URI template '
          'variables it defines. Use non-capturing groups (?:...) instead.',
        );
      }
      for (var i = 0; i < _variableNames.length; i++) {
        final name = _variableNames[i];
        final value = match[i + 1]!;
        final previous = variables[name];
        if (previous != null && previous != value) {
          throw ArgumentError(
            "The value '$value' for URI variable '$name' does not match the "
            "previous value '$previous'",
          );
        }
        variables[name] = value;
      }
    }
    return true;
  }
}
