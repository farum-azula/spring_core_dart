import 'package:dart_spring_language_server/src/config/colors.dart';
import 'package:dart_spring_language_server/src/config/config_check.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/did_you_mean.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// Why a value is not one of its type, and the value it was probably
/// meant to be, if one is near.
typedef _Rejection = ({String message, String? guess});

/// What a value of a type must look like: why when [value] is not one,
/// `null` when it is.
typedef _TypeRule = _Rejection? Function(String value, SchemaProp prop);

/// The rules of the value types of the schema, by type name.
final Map<String, _TypeRule> _typeRules = {
  'int': _wholeNumber,
  'whole number': _wholeNumber,
  'double': _number,
  'num': _number,
  'number': _number,
  'elevation': _number,
  'bool': _boolean,
  'true / false': _boolean,
  'choice': _choice,
};

_Rejection? _wholeNumber(String value, SchemaProp prop) =>
    RegExp(r'^[+-]?\d+$').hasMatch(value)
    ? null
    : (message: "Expected a whole number, got '$value'", guess: null);

_Rejection? _number(String value, SchemaProp prop) =>
    num.tryParse(value) != null ||
        RegExp(r'^level\d$').hasMatch(value) ||
        value.toLowerCase() == 'infinity'
    ? null
    : (message: "Expected a number, got '$value'", guess: null);

_Rejection? _boolean(String value, SchemaProp prop) =>
    {'true', 'false'}.contains(value.toLowerCase())
    ? null
    : (
        message: "Expected true or false, got '$value'",
        guess: didYouMean(value, const ['true', 'false']),
      );

_Rejection? _choice(String value, SchemaProp prop) {
  final allowed = [for (final v in prop.values) v.$1];
  if (allowed.isEmpty ||
      allowed.any((v) => canonicalName(v) == canonicalName(value))) {
    return null;
  }
  final guess = didYouMean(value, allowed);
  return (
    message:
        "'$value' is not allowed here. Expected one of: "
        '${allowed.join(', ')}'
        "${guess == null ? '' : ". Did you mean '$guess'?"}",
    guess: guess,
  );
}

/// The types whose hint values are suggestions, not the only values.
const _openTypes = {
  'String',
  'int',
  'double',
  'num',
  'bool',
  'Object',
  'dynamic',
};

/// The value of a known key: of the wrong type, out of the hint's range,
/// not one of an enum's values (errors), or one the hint warns about. A
/// theme color is checked as a color or a part of a color object. Values
/// with placeholders or SpEL, and `$` references of the theme, stand for
/// any value.
final class ValueCheck implements ConfigKeyCheck {
  /// The check.
  const ValueCheck();

  @override
  void check(ConfigCheckPass pass, ResolvedKey key, List<Problem> problems) {
    final prop = key.resolution.node?.prop;
    final value = key.key.value;
    if (key.resolution.isUnknown ||
        prop == null ||
        !key.hasPlainValue ||
        value!.isEmpty ||
        value.contains(r'${') ||
        value.contains('#{')) {
      return;
    }
    final range = pass.document.range(
      key.key.line,
      key.key.valueStart,
      key.key.valueEnd,
    );
    final rest = key.resolution.rest;
    if (prop.theme && prop.type == 'color') {
      _checkColor(value, prop, rest, range, problems);
      return;
    }
    // A `$` reference stands for any value; its target is checked by the
    // reference check.
    if (rest.isNotEmpty || prop.theme && value.trimLeft().startsWith(r'$')) {
      return;
    }
    final base = prop.type.replaceAll('?', '').trim();
    if (_typeRules[base]?.call(value, prop) case final rejected?) {
      problems.add(
        Problem(
          range,
          rejected.message,
          error: true,
          fixes: Fix.suggesting(range, rejected.guess),
        ),
      );
      return;
    }
    _checkHint(value, prop, base, range, problems);
  }

  void _checkHint(
    String value,
    SchemaProp prop,
    String base,
    SourceRange range,
    List<Problem> problems,
  ) {
    final hint = prop.hint;
    if (hint == null) {
      return;
    }
    final isEnum =
        hint.values.isNotEmpty &&
        hint.provider == null &&
        !_openTypes.contains(base) &&
        !base.startsWith('List') &&
        !base.startsWith('Map');
    if (isEnum &&
        !hint.values.any((v) => canonicalName(v.$1) == canonicalName(value))) {
      problems.add(
        Problem(
          range,
          "'$value' is not allowed here. Expected one of: "
          '${[for (final v in hint.values) v.$1].join(', ')}',
          error: true,
        ),
      );
      return;
    }
    if (hint.range case (final low, final high)?) {
      final number = num.tryParse(value);
      if (number != null && (number < low || number > high)) {
        problems.add(
          Problem(range, '$value is out of range: $low to $high', error: true),
        );
        return;
      }
    }
    for (final (values, message) in hint.warn) {
      if (values.contains(value)) {
        problems.add(Problem(range, '$value: $message'));
      }
    }
  }

  // A color: a plain string, or a part of the object form.
  void _checkColor(
    String value,
    SchemaProp prop,
    List<String> rest,
    SourceRange range,
    List<Problem> problems,
  ) {
    var parts = rest;
    if (parts.isNotEmpty &&
        prop.states &&
        !colorObjectKeys.contains(parts[0])) {
      parts = parts.sublist(1); // a state name
    }
    void error(String message) =>
        problems.add(Problem(range, message, error: true));
    if (parts.isEmpty || parts.length == 1 && parts[0] == 'color') {
      if (colorProblem(value) case final problem?) {
        error(problem);
      }
      return;
    }
    final joined = parts.join('.');
    switch (joined) {
      case 'alpha' || 'mix.amount':
        if (!isPercent(value)) {
          error(
            "Expected a percentage from 0% to 100% (or 0 to 1), got '$value'",
          );
        }
      case 'mix.with':
        if (colorProblem(value) case final problem?) {
          error(problem);
        }
      default:
        error(
          "'$joined' is not a part of a color. A color object has "
          '`color`, `alpha` and `mix: { with, amount }`',
        );
    }
  }
}
