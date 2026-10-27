/// A parsed URL path pattern, like Spring's `PathPattern`:
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
/// Paths are compared segment by segment, each percent-decoded; captured
/// values are decoded. A trailing slash matters (`/books/` is not
/// `/books`), like Spring 6.
///
/// ```dart
/// final pattern = PathPattern.parse('/books/{isbn}');
/// pattern.match('/books/978-0')?.variables; // {isbn: 978-0}
/// pattern.matches('/books');                // false
/// ```
///
/// Spring (Java): `PathPatternParser.defaultInstance.parse("/books/{isbn}")`.
final class PathPattern implements Comparable<PathPattern> {
  PathPattern._(this.pattern, this._segments, this._trailingSlash);

  /// Parses [pattern]; throws a [FormatException] for a malformed one
  /// (`**` or `{*name}` before the end, unbalanced braces, a duplicate
  /// variable).
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

  /// The pattern as written (with a leading `/`).
  final String pattern;

  final List<_Segment> _segments;
  final bool _trailingSlash;

  /// The names of the captured variables, in order.
  List<String> get variableNames => [
    for (final segment in _segments) ...segment.variables,
  ];

  /// Whether the pattern has no wildcards and no variables.
  bool get isLiteral => _segments.every((s) => s.isLiteral);

  /// Whether [path] matches.
  bool matches(String path) => match(path) != null;

  /// The match of [path] (percent-encoded, without the query), or `null`.
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

  /// This pattern followed by [other] (`/api` + `/books/{isbn}`).
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

/// The result of [PathPattern.match]: the captured variables.
final class PathMatch {
  /// A match capturing [variables].
  const PathMatch(this.variables);

  /// The captured values, decoded, by variable name.
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
