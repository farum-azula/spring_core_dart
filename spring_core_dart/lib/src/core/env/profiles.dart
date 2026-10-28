/// A condition on profiles, such as "`dev`, and `eu` or `us`", parsed
/// once and tested against the active profiles.
///
/// Profiles are names switched on for a run (`prod`, `eu`, `test`). Code
/// that must behave differently per profile asks the environment, and
/// this is the condition it asks with. Most applications write the same
/// expressions in `@Profile('...')` or `on-profile` in config files and
/// never build one; in code, `environment.matchesProfiles([...])` is
/// shorter. Build a `Profiles` to keep a parsed condition, or to test it
/// against profiles that are not an environment's.
///
/// An expression is a profile name, or names combined with `!` (not), `&`
/// (and), `|` (or) and parentheses. Mixing `&` and `|` without parentheses
/// is an error, as in Spring. Several expressions in one list are joined
/// with "or".
///
/// ```dart
/// // Parsed once, checked on every request.
/// final euTraffic = Profiles.of(['prod & (eu | uk)']);
/// if (environment.acceptsProfiles(euTraffic)) { ... }
///
/// // Without an environment: any test for "is this profile on".
/// Profiles.of(['dev', '!prod']).matches({'dev'}.contains); // true
/// ```
///
/// Spring (Java):
/// ```java
/// Profiles euTraffic = Profiles.of("prod & (eu | uk)");
/// if (environment.acceptsProfiles(euTraffic)) { ... }
/// Profiles.of("dev", "!prod").matches(Set.of("dev")::contains);
/// ```
abstract interface class Profiles {
  /// Parses [expressions] into one condition that holds when any of them
  /// does.
  ///
  /// Throws [ArgumentError] when the list is empty, an expression is blank
  /// or malformed (an unbalanced parenthesis, a missing operand, `&` and
  /// `|` mixed at one level).
  ///
  /// ```dart
  /// Profiles.of(['cloud & !local']);
  /// ```
  factory Profiles.of(List<String> expressions) {
    if (expressions.isEmpty) {
      throw ArgumentError.value(
        expressions,
        'expressions',
        'Must specify at least one profile expression',
      );
    }
    return _AnyOf([for (final e in expressions) _ProfilesParser(e).parse()]);
  }

  /// Whether the condition holds, given [isProfileActive], which tells for
  /// one profile name whether it is on.
  ///
  /// ```dart
  /// Profiles.of(['a & b']).matches({'a', 'b'}.contains); // true
  /// ```
  bool matches(bool Function(String profile) isProfileActive);
}

// Top level of `Profiles.of`: any of the expressions matches.
final class _AnyOf implements Profiles {
  _AnyOf(this._expressions);

  final List<Profiles> _expressions;

  @override
  bool matches(bool Function(String profile) isProfileActive) =>
      _expressions.any((e) => e.matches(isProfileActive));
}

final class _Name implements Profiles {
  _Name(this.name);

  final String name;

  @override
  bool matches(bool Function(String profile) isProfileActive) =>
      isProfileActive(name);
}

final class _Not implements Profiles {
  _Not(this.operand);

  final Profiles operand;

  @override
  bool matches(bool Function(String profile) isProfileActive) =>
      !operand.matches(isProfileActive);
}

final class _AllOf implements Profiles {
  _AllOf(this.operands);

  final List<Profiles> operands;

  @override
  bool matches(bool Function(String profile) isProfileActive) =>
      operands.every((o) => o.matches(isProfileActive));
}

final class _SomeOf implements Profiles {
  _SomeOf(this.operands);

  final List<Profiles> operands;

  @override
  bool matches(bool Function(String profile) isProfileActive) =>
      operands.any((o) => o.matches(isProfileActive));
}

// Recursive-descent parser for one profile expression:
//   expression := unary (('&' | '|') unary)*   (one operator kind per level)
//   unary      := '!' unary | '(' expression ')' | name
final class _ProfilesParser {
  _ProfilesParser(this.expression)
    // Tokens are operators, parentheses and names (runs of other non-space
    // characters).
    : _tokens = [
        for (final match in RegExp(
          r'[()&|!]|[^\s()&|!]+',
        ).allMatches(expression))
          match[0]!,
      ];

  final String expression;
  final List<String> _tokens;
  int _position = 0;

  Profiles parse() {
    if (_tokens.isEmpty) {
      throw ArgumentError.value(
        expression,
        'expression',
        'Invalid profile expression: must contain text',
      );
    }
    final result = _expression();
    if (_position != _tokens.length) {
      _malformed();
    }
    return result;
  }

  Profiles _expression() {
    final operands = [_unary()];
    String? operator;
    while (_position < _tokens.length &&
        (_tokens[_position] == '&' || _tokens[_position] == '|')) {
      final next = _tokens[_position++];
      if (operator != null && operator != next) {
        _malformed();
      }
      operator = next;
      operands.add(_unary());
    }
    return switch (operator) {
      null => operands.single,
      '&' => _AllOf(operands),
      _ => _SomeOf(operands),
    };
  }

  Profiles _unary() {
    if (_position >= _tokens.length) {
      _malformed();
    }
    final token = _tokens[_position++];
    switch (token) {
      case '!':
        return _Not(_unary());
      case '(':
        final inner = _expression();
        if (_position >= _tokens.length || _tokens[_position++] != ')') {
          _malformed();
        }
        return inner;
      case ')' || '&' || '|':
        _malformed();
      default:
        return _Name(token);
    }
  }

  Never _malformed() => throw ArgumentError.value(
    expression,
    'expression',
    'Malformed profile expression',
  );
}
