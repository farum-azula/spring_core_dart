/// The family's one rule for names that hold a secret: what is written
/// where a value would be shown ([masked]), and which names are secret
/// ([looksSecret]).
///
/// Values go into log lines, `toString()` texts and screens. A password,
/// an API key or a token written there leaks to everyone who reads the
/// log. Whatever writes values by name asks this rule, so one name is
/// masked everywhere or nowhere: the data starter's statement logging (the
/// bound values, a database URL's query parameters), and the `toString()`
/// the generator writes for `@ToString` (decided at build time from the
/// field's name, the value never read).
///
/// ```dart
/// String show(String name, Object? value) =>
///     SecretNames.looksSecret(name) ? SecretNames.masked : '$value';
///
/// show('title', 'Dune');       // Dune
/// show('apiKey', 'sk-123');    // ******
/// show('db_password', 'x');    // ******
/// show('keyword', 'spice');    // spice
/// ```
///
/// Spring Boot (Java): the actuator's `Sanitizer`, whose default keys
/// (`password`, `secret`, `key`, `token`, `.*credentials.*`) mask the
/// values of `/env` and `/configprops` as `******`.
abstract final class SecretNames {
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

  /// Whether [name] (a field, a parameter, a property, a column or a URL's
  /// query parameter) looks like it holds a secret. Case and separators
  /// (`_`, `-`, `.`, spaces) do not matter: `password`, `sslpassword`,
  /// `dbPassword`, `refresh_token`, `apitoken`, `CLIENT_SECRET`,
  /// `privateKey` all do.
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
}
