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
  /// What is written instead of a secret value.
  static const masked = '******';

  // Words of their own that mark a secret: too short, or too common as a
  // part of other words, to be looked for inside a longer name.
  static const _secretWords = {'pwd', 'key'};

  // What marks a secret anywhere in a name, once its case and separators are
  // gone (`sslpassword`, `dbPassword`, `client_secret`, `apiToken`). The
  // lookaheads leave out the words that only start like one.
  static final _secretParts = RegExp(
    'password|passwd|passphrase|secret(?!ar)|credential|token(?!iz|is)'
    '|apikey|privatekey|accesskey|signingkey|encryptionkey',
  );

  /// Whether [name] (a parameter, a property, a column or a URL's query
  /// parameter) looks like it holds a secret. Case and separators (`_`,
  /// `-`, `.`, spaces) do not matter: `password`, `sslpassword`,
  /// `dbPassword`, `refresh_token`, `apitoken`, `CLIENT_SECRET`, `privateKey`
  /// all do.
  ///
  /// It does when the name, written together in lower case, contains
  /// `password`, `passwd`, `passphrase`, `secret`, `credential`, `token`,
  /// `apikey`, `privatekey`, `accesskey`, `signingkey` or `encryptionkey`,
  /// or when one of its words (split at separators and camel-case humps) is
  /// `pwd` or `key`. Words that merely start like these are not secret:
  /// `secretary`, `tokenizer`, `tokenise`, and names that only contain the
  /// letters of `key` (`keyword`, `monkey`, `turkey`, `keyboard`).
  ///
  /// The rule errs towards masking: `tokens_per_page` is masked. A name
  /// that holds a secret in other words (`pw`, `pin`, `otp`) is not.
  static bool looksSecret(String name) {
    final lower = name.toLowerCase();
    if (_secretParts.hasMatch(lower.replaceAll(RegExp('[^a-z0-9]+'), ''))) {
      return true;
    }
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
      ? masked
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
