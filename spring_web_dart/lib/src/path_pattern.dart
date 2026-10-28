/// A URL path pattern, such as `/books/{isbn}` or `/static/**`, parsed
/// once and then tested against request paths.
///
/// Every path an application writes for the web server is one of these:
/// the paths of `@GetMapping` and the other mappings, of CORS mappings,
/// of interceptors, of security rules, of WebSocket handlers. The
/// framework parses them; applications rarely use the class directly,
/// except in their own filters or when testing what a pattern matches.
///
/// | Syntax | Matches |
/// |---|---|
/// | `/books` | the path itself |
/// | `?` | one character of a segment |
/// | `*` | zero or more characters of a segment |
/// | `**` | zero or more segments, at the end only (`/static/**`) |
/// | `{isbn}` | one segment, captured as `isbn` |
/// | `{isbn:\d+}` | one segment matching the regex, captured |
/// | `{*rest}` | the rest of the path, captured with its leading `/` (end only) |
///
/// Paths are compared segment by segment, each percent-decoded, and
/// captured values are decoded. A trailing slash matters: `/books/` does
/// not match `/books`, as in Spring 6. When several patterns match, the
/// more specific one should win; sorting patterns ([compareTo]) puts it
/// first.
///
/// ```dart
/// // A filter that only guards the admin API.
/// final admin = PathPattern.parse('/api/admin/**');
/// if (admin.matches(request.path)) { ... }
///
/// final book = PathPattern.parse('/books/{isbn}');
/// book.match('/books/978-0')?.variables; // {isbn: 978-0}
/// book.matches('/books');                // false
/// ```
///
/// Spring (Java): `PathPattern`.
/// ```java
/// PathPattern book = PathPatternParser.defaultInstance.parse("/books/{isbn}");
/// book.matchAndExtract(PathContainer.parsePath("/books/978-0"))
///     .getUriVariables(); // {isbn=978-0}
/// ```
final class PathPattern implements Comparable<PathPattern> {
  PathPattern._(this.pattern, this._segments, this._trailingSlash);

  /// Parses [pattern]. A missing leading `/` is added, and an empty
  /// pattern is `/`. Throws a [FormatException] for a malformed pattern:
  /// `**` or `{*name}` before the end, unbalanced braces, an invalid
  /// regex, or a variable used twice.
  factory PathPattern.parse(String pattern) {
    var text = pattern.trim();
    if (text.isEmpty) {
      text = '/';
    }
    if (!text.startsWith('/')) {
      text = '/$text';
    }
    final trailingSlash = text.length > 1 && text.endsWith('/');
    final raw = text.substring(1).split('/');
    if (trailingSlash) {
      raw.removeLast();
    }
    if (raw.length == 1 && raw.single.isEmpty) {
      raw.clear();
    }
    final segments = <_Segment>[];
    final names = <String>{};
    for (final (index, part) in raw.indexed) {
      final last = index == raw.length - 1;
      final segment = _Segment.parse(part, pattern);
      if (segment.isMultiSegment && !last) {
        throw FormatException(
          '"**" and "{*name}" may only appear at the end of a pattern',
          pattern,
        );
      }
      for (final name in segment.variables) {
        if (!names.add(name)) {
          throw FormatException('Duplicate variable {$name}', pattern);
        }
      }
      segments.add(segment);
    }
    return PathPattern._(text, segments, trailingSlash);
  }

  /// The pattern as written, with a leading `/` added if it had none.
  final String pattern;

  final List<_Segment> _segments;
  final bool _trailingSlash;

  /// The names of the variables the pattern captures, in order:
  /// `[id, isbn]` for `/authors/{id}/books/{isbn}`.
  List<String> get variableNames => [
    for (final segment in _segments) ...segment.variables,
  ];

  /// Whether the pattern is a fixed path, with no wildcards and no
  /// variables.
  bool get isLiteral => _segments.every((s) => s.isLiteral);

  /// Whether [path] matches the pattern; see [match] for the format of
  /// [path].
  bool matches(String path) => match(path) != null;

  /// Matches [path], the raw path of a request (percent-encoded, without
  /// the query string). Returns the captured variables, or `null` when
  /// the path does not match.
  PathMatch? match(String path) {
    var text = path.isEmpty ? '/' : path;
    if (!text.startsWith('/')) {
      text = '/$text';
    }
    final trailingSlash = text.length > 1 && text.endsWith('/');
    final rawSegments = text.substring(1).split('/');
    if (trailingSlash) {
      rawSegments.removeLast();
    }
    if (rawSegments.length == 1 && rawSegments.single.isEmpty) {
      rawSegments.clear();
    }
    final segments = [for (final s in rawSegments) _decode(s)];
    final variables = <String, String>{};
    for (var i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      if (segment.isMultiSegment) {
        final rest = segments.sublist(i.clamp(0, segments.length));
        if (segment.captureRest case final name?) {
          variables[name] = rest.isEmpty
              ? (trailingSlash ? '/' : '')
              : '/${rest.join('/')}${trailingSlash ? '/' : ''}';
        }
        return PathMatch(variables);
      }
      if (i >= segments.length) {
        return null;
      }
      if (!segment.matchInto(segments[i], variables)) {
        return null;
      }
    }
    if (segments.length != _segments.length) {
      return null;
    }
    if (trailingSlash != _trailingSlash) {
      return null;
    }
    return PathMatch(variables);
  }

  /// This pattern followed by [other]: `/api` and `/books/{isbn}` give
  /// `/api/books/{isbn}`. An empty side gives the other one. The server
  /// uses it to join a controller's base path and a method's path.
  PathPattern combine(PathPattern other) {
    if (_segments.isEmpty && !_trailingSlash) {
      return other;
    }
    if (other._segments.isEmpty && !other._trailingSlash) {
      return this;
    }
    final left = pattern.endsWith('/')
        ? pattern.substring(0, pattern.length - 1)
        : pattern;
    return PathPattern.parse('$left${other.pattern}');
  }

  // Spring's SPECIFICITY_COMPARATOR: a catch-all last, then fewer
  // variables and wildcards first, then the longer pattern first.
  @override
  int compareTo(PathPattern other) {
    final catchAll = _isCatchAll.compareTo(other._isCatchAll);
    if (catchAll != 0) {
      return catchAll;
    }
    final score = _score.compareTo(other._score);
    if (score != 0) {
      return score;
    }
    return other._literalLength.compareTo(_literalLength);
  }

  int get _isCatchAll => _segments.any((s) => s.isMultiSegment) ? 1 : 0;

  int get _score => _segments.fold(0, (sum, s) => sum + s.score);

  int get _literalLength =>
      _segments.fold(0, (sum, s) => sum + s.literalLength);

  @override
  bool operator ==(Object other) =>
      other is PathPattern && other.pattern == pattern;

  @override
  int get hashCode => pattern.hashCode;

  @override
  String toString() => pattern;

  static String _decode(String segment) {
    try {
      return Uri.decodeComponent(segment);
    } on ArgumentError {
      return segment;
    }
  }
}

/// A successful [PathPattern.match]: the values the pattern captured from
/// the path.
final class PathMatch {
  /// A match that captured [variables].
  const PathMatch(this.variables);

  /// The captured values by variable name, percent-decoded:
  /// `{isbn: 978-0}`. Empty for a pattern without variables.
  final Map<String, String> variables;
}

final class _Segment {
  _Segment._({
    required this.isLiteral,
    required this.literal,
    required this.regex,
    required this.variables,
    required this.isMultiSegment,
    required this.captureRest,
    required this.score,
    required this.literalLength,
  });

  factory _Segment.parse(String text, String pattern) {
    if (text == '**') {
      return _Segment._(
        isLiteral: false,
        literal: null,
        regex: null,
        variables: const [],
        isMultiSegment: true,
        captureRest: null,
        score: 1,
        literalLength: 0,
      );
    }
    if (text.startsWith('{*') && text.endsWith('}')) {
      final name = text.substring(2, text.length - 1).trim();
      if (name.isEmpty) {
        throw FormatException('A {*name} needs a name', pattern);
      }
      return _Segment._(
        isLiteral: false,
        literal: null,
        regex: null,
        variables: [name],
        isMultiSegment: true,
        captureRest: name,
        score: 1,
        literalLength: 0,
      );
    }
    if (!text.contains('{') &&
        !text.contains('}') &&
        !text.contains('*') &&
        !text.contains('?')) {
      final literal = PathPattern._decode(text);
      return _Segment._(
        isLiteral: true,
        literal: literal,
        regex: null,
        variables: const [],
        isMultiSegment: false,
        captureRest: null,
        score: 0,
        literalLength: literal.length,
      );
    }
    final out = StringBuffer('^');
    final variables = <String>[];
    var score = 0;
    var literalLength = 0;
    var i = 0;
    while (i < text.length) {
      final char = text[i];
      if (char == '{') {
        var depth = 1;
        var j = i + 1;
        while (j < text.length && depth > 0) {
          if (text[j] == '{') {
            depth++;
          } else if (text[j] == '}') {
            depth--;
          }
          j++;
        }
        if (depth != 0) {
          throw FormatException('Unbalanced "{" in "$text"', pattern);
        }
        final body = text.substring(i + 1, j - 1);
        final colon = body.indexOf(':');
        final name = (colon < 0 ? body : body.substring(0, colon)).trim();
        if (name.isEmpty || name.startsWith('*')) {
          throw FormatException('Malformed variable {$body}', pattern);
        }
        // Within one (decoded) segment: anything, like Spring's capture.
        final regex = colon < 0 ? '.+' : body.substring(colon + 1);
        try {
          RegExp(regex);
        } on FormatException {
          throw FormatException('Invalid regex in {$body}', pattern);
        }
        out.write('(?<v${variables.length}>$regex)');
        variables.add(name);
        score++;
        i = j;
      } else if (char == '}') {
        throw FormatException('Unbalanced "}" in "$text"', pattern);
      } else if (char == '*') {
        out.write('.*');
        score++;
        i++;
      } else if (char == '?') {
        out.write('.');
        score++;
        i++;
      } else {
        out.write(RegExp.escape(char));
        literalLength++;
        i++;
      }
    }
    out.write(r'$');
    return _Segment._(
      isLiteral: false,
      literal: null,
      regex: RegExp(out.toString()),
      variables: variables,
      isMultiSegment: false,
      captureRest: null,
      score: score,
      literalLength: literalLength,
    );
  }

  final bool isLiteral;
  final String? literal;
  final RegExp? regex;
  final List<String> variables;
  final bool isMultiSegment;
  final String? captureRest;
  final int score;
  final int literalLength;

  bool matchInto(String segment, Map<String, String> variables) {
    if (literal case final literal?) {
      return literal == segment;
    }
    final match = regex!.firstMatch(segment);
    if (match == null) {
      return false;
    }
    for (final (index, name) in this.variables.indexed) {
      variables[name] = match.namedGroup('v$index') ?? '';
    }
    return true;
  }
}
