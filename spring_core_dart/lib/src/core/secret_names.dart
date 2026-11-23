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

  // Words of their own that mark a secret anywhere in a name: too short,
  // or too common as a part of other words, to be looked for inside a
  // longer name.
  static const _secretWords = {'pwd', 'key'};

  // Words that mark a secret as the last word of a name (`user.jwt`,
  // `sentry.dsn`, `card_cvv`), but not before another word: `jwt.issuer-uri`,
  // `session.timeout` and `cookie.name` name settings of the thing, not
  // its value.
  static const _lastSecretWords = {
    'jwt',
    'bearer',
    'authorization',
    'cookie',
    'session',
    'dsn',
    'otp',
    'pin',
    'cvv',
    'cvc',
    'hmac',
    'assertion',
    'verifier',
  };

  // What marks a secret anywhere in a name, once its case and separators are
  // gone (`sslpassword`, `dbPassword`, `client_secret`, `apiToken`). The
  // lookaheads leave out the words that only start like one.
  static final _secretParts = RegExp(
    'password|passwd|passphrase|passcode|secret(?!ar)|credential'
    '|token(?!iz|is)|apikey|privatekey|accesskey|signingkey|encryptionkey'
    '|sessionid|connectionstring|mnemonic|seedphrase|clientassertion'
    '|codeverifier',
  );

  /// Whether [name] (a field, a parameter, a property, a column or a URL's
  /// query parameter) looks like it holds a secret. Case and separators
  /// (`_`, `-`, `.`, spaces) do not matter: `password`, `sslpassword`,
  /// `dbPassword`, `refresh_token`, `apitoken`, `CLIENT_SECRET`,
  /// `privateKey` all do.
  ///
  /// It does when the name, written together in lower case, contains
  /// `password`, `passwd`, `passphrase`, `passcode`, `secret`,
  /// `credential`, `token`, `apikey`, `privatekey`, `accesskey`,
  /// `signingkey`, `encryptionkey`, `sessionid`, `connectionstring`,
  /// `mnemonic`, `seedphrase`, `clientassertion` or `codeverifier`;
  /// when one of its words (split at separators and camel-case humps) is
  /// `pwd` or `key`; or when its last word is `jwt`, `bearer`,
  /// `authorization`, `cookie`, `session`, `dsn`, `otp`, `pin`, `cvv`,
  /// `cvc`, `hmac`, `assertion` or `verifier`. Words that merely start
  /// like these are not secret: `secretary`, `tokenizer`, `tokenise`,
  /// names that only contain the letters of `key` (`keyword`, `monkey`,
  /// `keyboard`), and settings of a secret thing (`jwt.issuer-uri`,
  /// `session.timeout`).
  ///
  /// The rule errs towards masking: `tokens_per_page` is masked. A name
  /// that holds a secret in other words (`pw`) is not.
  ///
  /// Only the name is looked at, never the value: the entries of a `Map`
  /// or a `List`, the fields of a record and the parts of a URL in a value
  /// are not inspected (a `Map<String, String> headers` field shows its
  /// `Authorization` entry). Give such a value a secret name, or mark it
  /// hidden where the writer allows it.
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
        .split(RegExp('[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    return words.any(_secretWords.contains) ||
        (words.isNotEmpty && _lastSecretWords.contains(words.last));
  }

  /// [value] with the credentials a URL in it carries masked: the password
  /// of its user-info (`postgres://ada:******@db/shop`) and the value of
  /// every query parameter whose name looks secret (`?sslpassword=******`).
  /// A value that is no URL with a scheme and an authority is returned as
  /// it is.
  ///
  /// Spring Boot (Java): the `Sanitizer`'s masking of a URI's user-info
  /// (`SanitizingFunction.sanitizeUris()`).
  static String maskedUrl(String value) {
    final text = value.trim();
    if (!text.contains('://')) {
      return value;
    }
    final url = Uri.tryParse(text);
    if (url == null || !url.hasScheme || !url.hasAuthority) {
      return value;
    }
    var changed = false;
    var userInfo = url.userInfo;
    final colon = userInfo.indexOf(':');
    if (colon >= 0) {
      userInfo = '${userInfo.substring(0, colon)}:$masked';
      changed = true;
    }
    String? query;
    if (url.hasQuery) {
      final parts = <String>[];
      for (final part in url.query.split('&')) {
        final equals = part.indexOf('=');
        final name = equals < 0 ? part : part.substring(0, equals);
        if (equals >= 0 && looksSecret(_decoded(name))) {
          parts.add('$name=$masked');
          changed = true;
        } else {
          parts.add(part);
        }
      }
      query = parts.join('&');
    }
    if (!changed) {
      return value;
    }
    return url.replace(userInfo: userInfo, query: query).toString();
  }

  static String _decoded(String name) {
    try {
      return Uri.decodeQueryComponent(name);
    } on FormatException {
      return name;
    }
  }
}
