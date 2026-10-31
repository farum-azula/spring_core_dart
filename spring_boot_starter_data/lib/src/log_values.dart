import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';

/// Writes the values of statements for trace log lines: each value with
/// the name it is bound to, through `LogFormatUtils.formatValue` (quotes,
/// line breaks and control characters replaced, long values cut), and the
/// value of a name that looks secret masked even there.
///
/// Values are logged only at trace; the debug lines hold the statements
/// alone.
abstract final class LogValues {
  static const _masked = '******';

  // Words that mark a secret in a parameter, property or column name.
  static const _secretWords = {
    'password',
    'passwd',
    'pwd',
    'passphrase',
    'secret',
    'token',
    'key',
    'apikey',
    'credential',
    'credentials',
  };

  /// Whether [name] (a parameter, a property or a column: `password`,
  /// `apiKey`, `refresh_token`, `clientSecret`) looks like it holds a
  /// secret: one of its words, split at `_`, `-`, `.` and at camel-case
  /// humps, is `password`, `passwd`, `pwd`, `passphrase`, `secret`,
  /// `token`, `key`, `apikey` or `credential(s)`. `monkey` and `tokenizer`
  /// are not secret words.
  static bool looksSecret(String name) {
    final words = name
        .replaceAllMapped(
          RegExp('([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .toLowerCase()
        .split(RegExp('[^a-z0-9]+'));
    return words.any(_secretWords.contains);
  }

  /// [value] for a trace line, masked when [name] looks secret.
  static String value(String name, Object? value) => looksSecret(name)
      ? _masked
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
