import 'package:spring_core_dart/src/expression/expression_exceptions.dart';

/// The compiler of the regular expressions used by `matches` (the
/// operator and the String method), with Spring's length limit and a
/// guard against patterns that could hang the program.
///
/// A pattern from an expression may come from a user, and some patterns
/// take exponential time on some inputs (catastrophic backtracking).
/// Spring counts the characters `OperatorMatches` reads and aborts such a
/// match at run time; Dart's `RegExp` cannot be interrupted, so patterns
/// of that shape are refused before they run: an unbounded repetition
/// (`*`, `+`, `{n,}`) of a group that itself contains one (`(a+)+`,
/// `(a*)*`, `(\w+\s?)*`), or of an alternation whose alternatives can
/// start with the same character (`(a|aa)+`, `(\d|\w)+`). The syntax is
/// Dart's `RegExp`, not Java's. Applications do not call it; it explains
/// why a `matches` fails with EL1073E.
///
/// ```dart
/// SpelPatterns.compile(r'\d+(\.\d{2})?'); // anchored RegExp
/// SpelPatterns.compile('(a+)+'); // SpelEvaluationException: EL1073E
/// ```
///
/// Spring (Java):
/// ```java
/// // OperatorMatches: MAX_REGEX_LENGTH = 1000, MatcherInput counts accesses
/// // and throws SpelMessage.FLAWED_PATTERN.
/// ```
abstract final class SpelPatterns {
  static final _cache = <String, RegExp>{};
  static const _cacheLimit = 256;

  /// [pattern] as a `RegExp` that must match the whole string (Java's
  /// `String.matches`); up to 256 compiled patterns are cached.
  ///
  /// Throws a [SpelEvaluationException] (without position) with
  /// `maxRegexLengthExceeded`, `flawedPattern` or `invalidPattern`.
  static RegExp compile(String pattern) {
    final cached = _cache[pattern];
    if (cached != null) {
      return cached;
    }
    if (pattern.length > SpelLimits.maxRegexLength) {
      throw SpelEvaluationException(
        SpelMessage.maxRegexLengthExceeded,
        inserts: [SpelLimits.maxRegexLength],
      );
    }
    final RegExp regex;
    try {
      regex = RegExp('^(?:$pattern)\$');
    } on FormatException catch (error) {
      throw SpelEvaluationException(
        SpelMessage.invalidPattern,
        inserts: [pattern],
        cause: error,
      );
    }
    if (_PatternScanner(pattern).isFlawed()) {
      throw SpelEvaluationException(
        SpelMessage.flawedPattern,
        inserts: [pattern],
      );
    }
    if (_cache.length >= _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    return _cache[pattern] = regex;
  }
}

// The first thing an alternative can match: a literal character, a class
// escape (\d, \w, \s and negations), `.`, a bracket class, or unknown
// (a group, an optional atom, an empty alternative).
final class _First {
  const _First(this.kind, [this.text = '']);

  static const unknown = _First('unknown');

  final String kind; // literal, escape, any, set, unknown
  final String text;
}

final class _Frame {
  bool unbounded = false;
  final firsts = <_First>[];
  bool alternativeStarted = false;
}

// A single pass over the pattern that tracks groups, alternatives and
// quantifiers; it only needs to be right for valid patterns (the pattern
// was compiled successfully before).
final class _PatternScanner {
  _PatternScanner(this.pattern);

  final String pattern;
  int _pos = 0;

  bool isFlawed() {
    final frames = [_Frame()];
    var lastWasFirst = false;
    var haveAtom = false;

    void atom(_First first) {
      final frame = frames.last;
      lastWasFirst = !frame.alternativeStarted;
      if (lastWasFirst) {
        frame.firsts.add(first);
        frame.alternativeStarted = true;
      }
      haveAtom = true;
    }

    void endAlternative(_Frame frame) {
      if (!frame.alternativeStarted) {
        frame.firsts.add(_First.unknown);
      }
      frame.alternativeStarted = false;
    }

    // Applies a quantifier to the last atom ([group] when it was a group);
    // true when that makes the pattern flawed.
    bool quantify((int, bool) quantifier, _Frame? group) {
      final (min, unbounded) = quantifier;
      final frame = frames.last;
      haveAtom = false;
      if (unbounded) {
        if (group != null && (group.unbounded || _overlapping(group.firsts))) {
          return true;
        }
        frame.unbounded = true;
      }
      if (min == 0 && lastWasFirst) {
        // An optional first atom: the alternative may start with the next
        // one, so its first character is unknown.
        frame.firsts[frame.firsts.length - 1] = _First.unknown;
      }
      return false;
    }

    while (_pos < pattern.length) {
      final c = pattern[_pos];
      switch (c) {
        case r'\':
          atom(_escape());
        case '[':
          atom(_set());
        case '(':
          _pos++;
          _skipGroupPrefix();
          frames.add(_Frame());
          haveAtom = false;
        case ')':
          _pos++;
          if (frames.length == 1) {
            continue;
          }
          final group = frames.removeLast();
          endAlternative(group);
          atom(_First.unknown);
          final quantifier = _pos < pattern.length ? _quantifier() : null;
          if (quantifier != null && quantify(quantifier, group)) {
            return true;
          }
          // Whether the group contains an unbounded repetition matters to
          // the groups around it.
          frames.last.unbounded |= group.unbounded;
          haveAtom = false;
        case '|':
          _pos++;
          endAlternative(frames.last);
          haveAtom = false;
        case '^' || r'$':
          _pos++;
        case '.':
          _pos++;
          atom(const _First('any'));
        case '*' || '+' || '?' || '{':
          final quantifier = _quantifier();
          if (quantifier == null) {
            // A literal `{`.
            _pos++;
            atom(_First('literal', c));
          } else if (haveAtom && quantify(quantifier, null)) {
            return true;
          }
        default:
          _pos++;
          atom(_First('literal', c));
      }
    }
    return false;
  }

  // `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}`, each optionally lazy (`?`) or
  // possessive-looking (`+`); returns (minimum, unbounded) or null for a
  // `{` that is a literal.
  (int, bool)? _quantifier() {
    final c = pattern[_pos];
    (int, bool) result;
    if (c == '*') {
      _pos++;
      result = (0, true);
    } else if (c == '+') {
      _pos++;
      result = (1, true);
    } else if (c == '?') {
      _pos++;
      result = (0, false);
    } else {
      final match = RegExp(r'\{(\d+)(,(\d*))?\}').matchAsPrefix(pattern, _pos);
      if (match == null) {
        return null;
      }
      _pos = match.end;
      final min = int.parse(match[1]!);
      result = (min, match[2] != null && match[3]!.isEmpty);
    }
    if (_pos < pattern.length && pattern[_pos] == '?') {
      _pos++;
    }
    return result;
  }

  void _skipGroupPrefix() {
    if (_pos >= pattern.length || pattern[_pos] != '?') {
      return;
    }
    _pos++;
    if (_pos < pattern.length && pattern[_pos] == '<') {
      // (?<name>...), (?<=...), (?<!...)
      _pos++;
      if (_pos < pattern.length &&
          (pattern[_pos] == '=' || pattern[_pos] == '!')) {
        _pos++;
        return;
      }
      final close = pattern.indexOf('>', _pos);
      _pos = close < 0 ? pattern.length : close + 1;
      return;
    }
    // (?:...), (?=...), (?!...)
    if (_pos < pattern.length) {
      _pos++;
    }
  }

  _First _escape() {
    _pos++;
    if (_pos >= pattern.length) {
      return _First.unknown;
    }
    final c = pattern[_pos];
    _pos++;
    if ('dDwWsS'.contains(c)) {
      return _First('escape', c);
    }
    if ((c == 'p' || c == 'P' || c == 'u' || c == 'k') &&
        _pos < pattern.length &&
        (pattern[_pos] == '{' || pattern[_pos] == '<')) {
      final close = pattern.indexOf(pattern[_pos] == '{' ? '}' : '>', _pos);
      _pos = close < 0 ? pattern.length : close + 1;
      return _First.unknown;
    }
    if (RegExp('[a-zA-Z0-9]').hasMatch(c)) {
      // \n, \t, \x41, \1, ...: not worth decoding.
      return _First.unknown;
    }
    return _First('literal', c);
  }

  _First _set() {
    final start = _pos;
    _pos++;
    while (_pos < pattern.length && pattern[_pos] != ']') {
      if (pattern[_pos] == r'\') {
        _pos++;
      }
      _pos++;
    }
    _pos++;
    return _First(
      'set',
      pattern.substring(start, _pos.clamp(start, pattern.length)),
    );
  }

  static bool _overlapping(List<_First> firsts) {
    if (firsts.length < 2) {
      return false;
    }
    for (var i = 0; i < firsts.length; i++) {
      for (var j = i + 1; j < firsts.length; j++) {
        if (_overlap(firsts[i], firsts[j])) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _overlap(_First a, _First b) {
    if (a.kind == 'unknown' ||
        b.kind == 'unknown' ||
        a.kind == 'any' ||
        b.kind == 'any') {
      return true;
    }
    if (a.kind == 'literal' && b.kind == 'literal') {
      return a.text == b.text;
    }
    if (a.kind == 'literal' || b.kind == 'literal') {
      final literal = a.kind == 'literal' ? a : b;
      final other = a.kind == 'literal' ? b : a;
      final probe = other.kind == 'escape' ? '\\${other.text}' : other.text;
      try {
        return RegExp('^(?:$probe)\$').hasMatch(literal.text);
      } on FormatException {
        return true;
      }
    }
    if (a.kind == 'escape' && b.kind == 'escape') {
      const disjoint = {'dD', 'wW', 'sS', 'ds', 'ws', 'sd', 'sw'};
      return a.text == b.text ||
          !(disjoint.contains('${a.text}${b.text}') ||
              disjoint.contains('${b.text}${a.text}'));
    }
    return true;
  }
}
