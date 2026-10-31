/// The browser origins a server takes requests from, checked as Spring's
/// `CorsConfiguration` checks its `allowedOrigins` and
/// `allowedOriginPatterns`.
///
/// A browser sends the origin of the page (`https://shop.example`: a
/// scheme, a host and a port) in the `Origin` header of a cross-origin
/// request and of a WebSocket handshake. The web starter's CORS rules
/// (`CorsConfiguration`) and the WebSocket starter's handshake check
/// (`setAllowedOrigins`, `allowedOrigins` of `@WebSocketEndpoint`) both
/// decide with this class, so they accept the same origins:
///
/// - [allowedOrigins] are whole origins, compared without case
///   (`https://shop.example`); `*` allows any origin.
/// - [allowedOriginPatterns] are for families of origins, compared with
///   case: `*` matches any text, as Spring's `.*`
///   (`https://*.shop.example` takes `https://eu.shop.example` and
///   `https://a.b.shop.example`, not `https://shop.example`; `*` may span
///   the scheme too, as in `*.shop.example` or `*localhost*`), and a port
///   list at the end takes the listed ports
///   (`http://localhost:[3000,3001]`) or, with `[*]`, any port or none
///   (`http://localhost:[*]`).
/// - A value may hold several, separated by commas
///   (`'https://a.example, https://b.example'`, handy for one property),
///   and a trailing `/` is ignored, in the values and in the origin
///   checked.
///
/// ```dart
/// final origins = AllowedOrigins(
///   allowedOrigins: ['https://shop.example'],
///   allowedOriginPatterns: ['https://*.shop.example', 'http://localhost:[*]'],
/// );
/// origins.checkOrigin('https://eu.shop.example'); // 'https://eu.shop.example'
/// origins.checkOrigin('http://localhost:3000'); // 'http://localhost:3000'
/// origins.checkOrigin('https://evil.example'); // null
/// ```
///
/// One difference from Spring: an origin longer than [maxOriginLength]
/// (1024) characters is never allowed, as no real one comes close. A
/// pattern is matched in time that grows with the origin's length, not
/// with its square or cube as a backtracking regular expression's
/// (Spring's) can with two or three `*`.
///
/// A pattern's `*` matches what Spring's matches, so it is no tighter a
/// check: `https://*.example.com` also takes
/// `https://evil.com/.example.com`. That is no hole, as only a browser is
/// bound by the answer, and it sends the page's real origin; any other
/// client can send any `Origin` it likes anyway.
///
/// Spring (Java): `CorsConfiguration.setAllowedOrigins`,
/// `setAllowedOriginPatterns` and `checkOrigin`.
final class AllowedOrigins {
  /// The origins [allowedOrigins] and the patterns
  /// [allowedOriginPatterns], each value split at its commas (not those
  /// of a port list) and stripped of a trailing `/`.
  AllowedOrigins({
    Iterable<String> allowedOrigins = const [],
    Iterable<String> allowedOriginPatterns = const [],
  }) : allowedOrigins = List.unmodifiable([
         for (final value in allowedOrigins)
           for (final origin in _split(value)) _trimTrailingSlash(origin),
       ]),
       _patterns = List.unmodifiable([
         for (final value in allowedOriginPatterns)
           for (final pattern in _split(value))
             _OriginPattern(_trimTrailingSlash(pattern)),
       ]);

  /// The allowed origins, as compared: split at commas, without a
  /// trailing `/`.
  final List<String> allowedOrigins;

  final List<_OriginPattern> _patterns;

  /// The patterns, as compared: split at commas, without a trailing `/`.
  List<String> get allowedOriginPatterns => [
    for (final pattern in _patterns) pattern.declared,
  ];

  /// Whether [allowedOrigins] holds `*`, which allows every origin.
  bool get allowsAnyOrigin => allowedOrigins.contains(_all);

  /// The `Access-Control-Allow-Origin` value for a request from [origin]:
  /// `*` when [allowedOrigins] holds `*`, else [origin] itself (as given,
  /// with its trailing `/` if any) when it is in [allowedOrigins] or
  /// matches a pattern, and `null` when it is not allowed, or blank.
  ///
  /// Throws a [StateError] when [allowedOrigins] holds `*` and
  /// [allowCredentials] is true: browsers refuse
  /// `Access-Control-Allow-Origin: *` with credentials, so list the
  /// origins or use [allowedOriginPatterns]. A `*` pattern echoes the
  /// origin instead, and so works with credentials.
  ///
  /// An origin longer than [maxOriginLength] characters is not allowed,
  /// whatever the configuration.
  String? checkOrigin(String? origin, {bool allowCredentials = false}) {
    if (origin == null ||
        origin.length > maxOriginLength ||
        origin.trim().isEmpty) {
      return null;
    }
    final toCheck = _trimTrailingSlash(origin);
    if (allowedOrigins.isNotEmpty) {
      if (allowsAnyOrigin) {
        if (allowCredentials) {
          throw StateError(
            'When allowCredentials is true, allowedOrigins cannot contain '
            '"*" (the Access-Control-Allow-Origin header cannot be "*" '
            'then); list the origins or use allowedOriginPatterns.',
          );
        }
        return _all;
      }
      final lower = toCheck.toLowerCase();
      for (final allowed in allowedOrigins) {
        if (allowed.toLowerCase() == lower) {
          return origin;
        }
      }
    }
    for (final pattern in _patterns) {
      if (pattern.matches(toCheck)) {
        return origin;
      }
    }
    return null;
  }

  /// The longest origin [checkOrigin] allows: 1024 characters.
  ///
  /// A browser's origin is a scheme, a host of at most 253 characters (the
  /// longest DNS name; an IPv6 address is shorter) and a port of at most 5
  /// digits: under 300 characters with the longest schemes in use
  /// (`chrome-extension://`, `safari-web-extension://`). The bound leaves
  /// room to spare and keeps a client from making the server compare a
  /// huge `Origin` header (`dart:io` takes up to 1 MB of headers).
  static const int maxOriginLength = 1024;

  static const _all = '*';

  static String _trimTrailingSlash(String origin) =>
      origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;

  // Spring's parseCommaDelimitedOrigin: a value without a comma is kept
  // as it is; otherwise it is split at the commas outside `[...]`, and
  // each part is trimmed.
  static List<String> _split(String value) {
    if (!value.contains(',')) {
      return [value];
    }
    final parts = <String>[];
    var start = 0;
    var inPorts = false;
    for (var i = 0; i < value.length; i++) {
      switch (value[i]) {
        case '[':
          inPorts = true;
        case ']':
          inPorts = false;
        case ',' when !inPorts:
          parts.add(value.substring(start, i).trim());
          start = i + 1;
      }
    }
    if (start < value.length) {
      parts.add(value.substring(start).trim());
    }
    return parts;
  }

  @override
  String toString() =>
      'AllowedOrigins(allowedOrigins: $allowedOrigins, '
      'allowedOriginPatterns: $allowedOriginPatterns)';
}

/// A pattern of [AllowedOrigins.allowedOriginPatterns], as Spring's
/// `CorsConfiguration.OriginPattern`: the text is literal except `*`, and
/// a port list at the end (`:[8080,8081]`, `:[*]`) becomes the ports it
/// allows.
///
/// Spring compiles it to a regular expression (`\Q...\E`, each `*` a
/// `.*`); a backtracking one takes time in the square or cube of the
/// origin's length with two or three `*`. This matcher gives the same
/// answers in time proportional to the origin's length times the
/// pattern's. A `*` matches what Java's `.` matches, any character but a
/// line terminator ([_isWild]), so the line terminators of the origin
/// must be, in order, the same as those in the pattern's literal text:
/// the origin and the pattern are cut at them, and each piece of the
/// origin is matched against its piece of the pattern, where a `*`
/// matches any text (a match of the pieces' first and last literal at
/// their ends, and of the literals between, each at its first place after
/// the one before).
final class _OriginPattern {
  factory _OriginPattern(String declared) {
    if (declared == AllowedOrigins._all) {
      // Any origin, as Spring checks the declared pattern.
      return _OriginPattern._(declared, null, const [], const [[]]);
    }
    var value = declared;
    List<String>? ports;
    if (_portList.firstMatch(declared) case final match?) {
      value = match[1]!;
      ports = match[2] == '*' ? const [] : match[2]!.split(',');
    }
    final separators = <int>[];
    final pieces = <List<String>>[];
    var start = 0;
    for (var i = 0; i <= value.length; i++) {
      if (i == value.length || !_isWild(value.codeUnitAt(i))) {
        pieces.add(value.substring(start, i).split('*'));
        if (i < value.length) {
          separators.add(value.codeUnitAt(i));
        }
        start = i + 1;
      }
    }
    return _OriginPattern._(declared, ports, separators, pieces);
  }

  _OriginPattern._(this.declared, this._ports, this._separators, this._pieces)
    : _any = declared == AllowedOrigins._all;

  final String declared;
  final bool _any;
  // The port list: `null` for none, empty for `[*]`.
  final List<String>? _ports;
  // The characters a `*` does not match in the pattern's text, in order,
  // and the pieces between them, each cut at its `*`s.
  final List<int> _separators;
  final List<List<String>> _pieces;

  // Spring's PORTS_PATTERN, `(.*):\[(\*|\d+(,\d+)*)]`, with Java's `.`.
  static final _portList = RegExp(
    r'^([^\n\r\u0085\u2028\u2029]*):\[(\*|\d+(?:,\d+)*)\]$',
  );

  bool matches(String origin) {
    if (_any) {
      return true;
    }
    final ports = _ports;
    final length = origin.length;
    if (ports == null) {
      return _matchesText(origin, length);
    }
    if (ports.isEmpty) {
      // `[*]`: no port, or `:` and digits at the end.
      if (_matchesText(origin, length)) {
        return true;
      }
      var digits = length;
      while (digits > 0 && _isDigit(origin.codeUnitAt(digits - 1))) {
        digits--;
      }
      return digits < length &&
          digits > 0 &&
          origin.codeUnitAt(digits - 1) == _colon &&
          _matchesText(origin, digits - 1);
    }
    for (final port in ports) {
      final colon = length - port.length - 1;
      if (colon >= 0 &&
          origin.codeUnitAt(colon) == _colon &&
          origin.startsWith(port, colon + 1) &&
          _matchesText(origin, colon)) {
        return true;
      }
    }
    return false;
  }

  // Whether the first [end] characters of [origin] match the pattern's
  // text (without its port list).
  bool _matchesText(String origin, int end) {
    var from = 0;
    for (var k = 0; k < _pieces.length; k++) {
      var to = from;
      while (to < end && _isWild(origin.codeUnitAt(to))) {
        to++;
      }
      if (k < _separators.length) {
        if (to == end || origin.codeUnitAt(to) != _separators[k]) {
          return false;
        }
      } else if (to != end) {
        return false;
      }
      if (!_matchesPiece(_pieces[k], origin, from, to)) {
        return false;
      }
      from = to + 1;
    }
    return true;
  }

  // Whether [text] from [from] to [to] matches the literals [parts], with
  // any text between two of them (a `*` here matches any character).
  static bool _matchesPiece(List<String> parts, String text, int from, int to) {
    final first = parts.first;
    if (parts.length == 1) {
      return to - from == first.length && text.startsWith(first, from);
    }
    final last = parts.last;
    final tail = to - last.length;
    if (tail - from < first.length ||
        !text.startsWith(first, from) ||
        !text.startsWith(last, tail)) {
      return false;
    }
    var at = from + first.length;
    for (var i = 1; i < parts.length - 1; i++) {
      final part = parts[i];
      if (part.isEmpty) {
        continue;
      }
      final found = text.indexOf(part, at);
      if (found < 0 || found + part.length > tail) {
        return false;
      }
      at = found + part.length;
    }
    return true;
  }

  static const _colon = 0x3A;

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  /// Whether a `*` matches the UTF-16 code unit [unit]: what the `.` of
  /// Spring's (Java's) regular expression matches, any character but a
  /// line terminator (`\n`, `\r`, U+0085, U+2028, U+2029).
  static bool _isWild(int unit) =>
      unit != 0x0A &&
      unit != 0x0D &&
      unit != 0x85 &&
      unit != 0x2028 &&
      unit != 0x2029;
}

/// Whether [origin] matches the origin [pattern] (one pattern of
/// [AllowedOrigins.allowedOriginPatterns], without the length bound of
/// [AllowedOrigins.checkOrigin]).
///
/// For the tests of this package: `package:spring_web_dart/spring_web_dart.dart`
/// hides it.
bool matchesOriginPattern(String pattern, String origin) =>
    _OriginPattern(pattern).matches(origin);
