import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';

/// Writes the values of statements for trace log lines: each value with
/// the name it is bound to, through `LogFormatUtils.formatValue` (quotes,
/// line breaks and control characters replaced, long values cut), and the
/// value of a name that looks secret ([SecretNames], the rule
/// `spring_core_dart` shares with the `toString()` of `@ToString`) masked
/// even there.
///
/// Values are logged only at trace; the debug lines hold the statements
/// alone.
abstract final class LogValues {
  /// [value] for a trace line, masked when [name] looks secret.
  static String value(String name, Object? value) =>
      SecretNames.looksSecret(name)
      ? SecretNames.masked
      : value == null
      ? 'null'
      : LogFormatUtils.formatValue(value);

  /// `{name: value, ...}` of [values] for a trace line.
  static String map(Map<String, Object?> values) {
    final entries = [
      for (final MapEntry(:key, value: v) in values.entries)
        '$key: ${value(key, v)}',
    ];
    return '{${entries.join(', ')}}';
  }

  /// The arguments of [names] (the method's parameter names, in order) for
  /// a trace line; an argument without a name is written by position.
  static String arguments(List<String> names, List<Object?> arguments) => [
    for (final (index, argument) in arguments.indexed)
      if (index < names.length)
        '${names[index]}: ${value(names[index], argument)}'
      else
        '?${index + 1}: ${value('', argument)}',
  ].join(', ');

  /// The bound values of [criteria], each named after the property of the
  /// part that consumes it.
  static String criteria(Criteria criteria) {
    final names = [
      for (final part in criteria.predicate.expand((or) => or.parts))
        for (var i = 0; i < part.type.argumentCount; i++) part.property,
    ];
    return arguments(names, criteria.arguments);
  }
}
