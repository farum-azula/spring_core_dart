import 'dart:convert';

/// HTTP headers: names are case-insensitive, a name may have several
/// values, insertion order and the original casing are kept. Like Spring's
/// `HttpHeaders` (Spring Framework 7: not a `Map`).
///
/// ```dart
/// final headers = HttpHeaders({'Accept': 'application/json'})
///   ..add('X-Tag', 'a')
///   ..add('x-tag', 'b')
///   ..contentType = MediaType.applicationJson
///   ..setBearerAuth(token);
/// headers['accept'];             // 'application/json'
/// headers.getAll('X-TAG');       // ['a', 'b']
/// headers.toSingleValueMap();    // {Accept: application/json, X-Tag: a, ...}
/// headers.forEach((name, values) => print('$name: $values'));
/// ```
///
/// The name constants end in `Header` (`HttpHeaders.contentTypeHeader`, as
/// in `dart:io`) because the typed accessors take the plain names
/// (`headers.contentType`).
///
/// Spring (Java):
/// ```java
/// HttpHeaders headers = new HttpHeaders();
/// headers.setContentType(MediaType.APPLICATION_JSON);
/// headers.setBearerAuth(token);
/// headers.add("X-Tag", "a");
/// headers.get("x-tag");
/// headers.forEach((name, values) -> ...);
/// ```
class HttpHeaders {
  /// Headers with one value per name of [values].
  HttpHeaders([Map<String, String>? values]) {
    values?.forEach(set);
  }

  /// Headers from [entries] (a name may repeat).
  HttpHeaders.fromEntries(Iterable<MapEntry<String, String>> entries) {
    for (final entry in entries) {
      add(entry.key, entry.value);
    }
  }

  /// `Accept`.
  static const acceptHeader = 'Accept';

  /// `Accept-Charset`.
  static const acceptCharsetHeader = 'Accept-Charset';

  /// `Accept-Encoding`.
  static const acceptEncodingHeader = 'Accept-Encoding';

  /// `Accept-Language`.
  static const acceptLanguageHeader = 'Accept-Language';

  /// `Accept-Patch`.
  static const acceptPatchHeader = 'Accept-Patch';

  /// `Accept-Ranges`.
  static const acceptRangesHeader = 'Accept-Ranges';

  /// `Access-Control-Allow-Credentials`.
  static const accessControlAllowCredentialsHeader =
      'Access-Control-Allow-Credentials';

  /// `Access-Control-Allow-Headers`.
  static const accessControlAllowHeadersHeader = 'Access-Control-Allow-Headers';

  /// `Access-Control-Allow-Methods`.
  static const accessControlAllowMethodsHeader = 'Access-Control-Allow-Methods';

  /// `Access-Control-Allow-Origin`.
  static const accessControlAllowOriginHeader = 'Access-Control-Allow-Origin';

  /// `Access-Control-Expose-Headers`.
  static const accessControlExposeHeadersHeader =
      'Access-Control-Expose-Headers';

  /// `Access-Control-Max-Age`.
  static const accessControlMaxAgeHeader = 'Access-Control-Max-Age';

  /// `Access-Control-Request-Headers`.
  static const accessControlRequestHeadersHeader =
      'Access-Control-Request-Headers';

  /// `Access-Control-Request-Method`.
  static const accessControlRequestMethodHeader =
      'Access-Control-Request-Method';

  /// `Age`.
  static const ageHeader = 'Age';

  /// `Allow`.
  static const allowHeader = 'Allow';

  /// `Authorization`.
  static const authorizationHeader = 'Authorization';

  /// `Cache-Control`.
  static const cacheControlHeader = 'Cache-Control';

  /// `Connection`.
  static const connectionHeader = 'Connection';

  /// `Content-Encoding`.
  static const contentEncodingHeader = 'Content-Encoding';

  /// `Content-Disposition`.
  static const contentDispositionHeader = 'Content-Disposition';

  /// `Content-Language`.
  static const contentLanguageHeader = 'Content-Language';

  /// `Content-Length`.
  static const contentLengthHeader = 'Content-Length';

  /// `Content-Location`.
  static const contentLocationHeader = 'Content-Location';

  /// `Content-Range`.
  static const contentRangeHeader = 'Content-Range';

  /// `Content-Type`.
  static const contentTypeHeader = 'Content-Type';

  /// `Cookie`.
  static const cookieHeader = 'Cookie';

  /// `Date`.
  static const dateHeader = 'Date';

  /// `ETag`.
  static const etagHeader = 'ETag';

  /// `Expect`.
  static const expectHeader = 'Expect';

  /// `Expires`.
  static const expiresHeader = 'Expires';

  /// `From`.
  static const fromHeader = 'From';

  /// `Host`.
  static const hostHeader = 'Host';

  /// `If-Match`.
  static const ifMatchHeader = 'If-Match';

  /// `If-Modified-Since`.
  static const ifModifiedSinceHeader = 'If-Modified-Since';

  /// `If-None-Match`.
  static const ifNoneMatchHeader = 'If-None-Match';

  /// `If-Range`.
  static const ifRangeHeader = 'If-Range';

  /// `If-Unmodified-Since`.
  static const ifUnmodifiedSinceHeader = 'If-Unmodified-Since';

  /// `Last-Modified`.
  static const lastModifiedHeader = 'Last-Modified';

  /// `Link`.
  static const linkHeader = 'Link';

  /// `Location`.
  static const locationHeader = 'Location';

  /// `Max-Forwards`.
  static const maxForwardsHeader = 'Max-Forwards';

  /// `Origin`.
  static const originHeader = 'Origin';

  /// `Pragma`.
  static const pragmaHeader = 'Pragma';

  /// `Proxy-Authenticate`.
  static const proxyAuthenticateHeader = 'Proxy-Authenticate';

  /// `Proxy-Authorization`.
  static const proxyAuthorizationHeader = 'Proxy-Authorization';

  /// `Range`.
  static const rangeHeader = 'Range';

  /// `Referer`.
  static const refererHeader = 'Referer';

  /// `Retry-After`.
  static const retryAfterHeader = 'Retry-After';

  /// `Server`.
  static const serverHeader = 'Server';

  /// `Set-Cookie`.
  static const setCookieHeader = 'Set-Cookie';

  /// `TE`.
  static const teHeader = 'TE';

  /// `Trailer`.
  static const trailerHeader = 'Trailer';

  /// `Transfer-Encoding`.
  static const transferEncodingHeader = 'Transfer-Encoding';

  /// `Upgrade`.
  static const upgradeHeader = 'Upgrade';

  /// `User-Agent`.
  static const userAgentHeader = 'User-Agent';

  /// `Vary`.
  static const varyHeader = 'Vary';

  /// `Via`.
  static const viaHeader = 'Via';

  /// `Warning`.
  static const warningHeader = 'Warning';

  /// `WWW-Authenticate`.
  static const wwwAuthenticateHeader = 'WWW-Authenticate';

  final _entries = <MapEntry<String, String>>[];

  static bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();

  /// The first value of [name], or `null`.
  String? operator [](String name) {
    for (final entry in _entries) {
      if (_same(entry.key, name)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Every value of [name], in insertion order.
  List<String> getAll(String name) => [
    for (final entry in _entries)
      if (_same(entry.key, name)) entry.value,
  ];

  /// Replaces the values of [name] with [value].
  void set(String name, String value) {
    final index = _entries.indexWhere((e) => _same(e.key, name));
    remove(name);
    final entry = MapEntry(name, value);
    if (index < 0 || index > _entries.length) {
      _entries.add(entry);
    } else {
      _entries.insert(index, entry);
    }
  }

  /// Adds [value] to the values of [name].
  void add(String name, String value) => _entries.add(MapEntry(name, value));

  /// Removes every value of [name].
  void remove(String name) => _entries.removeWhere((e) => _same(e.key, name));

  /// Whether [name] has a value.
  bool contains(String name) => _entries.any((e) => _same(e.key, name));

  /// The header names, each once, as first added.
  Iterable<String> get names {
    final seen = <String>{};
    return [
      for (final entry in _entries)
        if (seen.add(entry.key.toLowerCase())) entry.key,
    ];
  }

  /// Calls [action] once per header name with all its values, in the
  /// order the names were first added.
  void forEach(void Function(String name, List<String> values) action) {
    for (final name in names) {
      action(name, getAll(name));
    }
  }

  /// One entry per name with its first value, like Spring's
  /// `toSingleValueMap()`.
  Map<String, String> toSingleValueMap() => {
    for (final name in names) name: this[name]!,
  };

  /// One entry per name; several values are joined with `, ` (the form
  /// HTTP allows for most headers, not for `Set-Cookie`).
  Map<String, String> toMap() => {
    for (final name in names) name: getAll(name).join(', '),
  };

  /// An independent copy.
  HttpHeaders copy() => HttpHeaders.fromEntries(_entries);

  /// Whether there are no headers.
  bool get isEmpty => _entries.isEmpty;

  /// The `Content-Type` (e.g. `application/json`), or `null`.
  String? get contentType => this[contentTypeHeader];

  /// Sets the `Content-Type` (`null` removes it).
  set contentType(String? value) => _setOrRemove(contentTypeHeader, value);

  /// The `Location` as a URI, or `null`.
  Uri? get location => switch (this[locationHeader]) {
    final value? => Uri.parse(value),
    null => null,
  };

  /// Sets the `Location` (`null` removes it).
  set location(Uri? value) => _setOrRemove(locationHeader, value?.toString());

  /// The `Content-Length`, or -1 when it is unknown, like Spring.
  int get contentLength =>
      int.tryParse(this[contentLengthHeader]?.trim() ?? '') ?? -1;

  /// Sets the `Content-Length` (a negative value removes it).
  set contentLength(int value) =>
      _setOrRemove(contentLengthHeader, value < 0 ? null : '$value');

  /// Sets `Authorization: Bearer <token>`.
  void setBearerAuth(String token) => set(authorizationHeader, 'Bearer $token');

  /// Sets `Authorization: Basic <credentials>` for [username] and
  /// [password], encoded with [encoding] (ISO-8859-1 by default, like
  /// Spring; throws `ArgumentError` for characters it cannot encode).
  void setBasicAuth(
    String username,
    String password, {
    Encoding encoding = latin1,
  }) => set(
    authorizationHeader,
    'Basic ${encodeBasicAuth(username, password, encoding: encoding)}',
  );

  /// The Base64 credentials of Basic authentication for [username] and
  /// [password], like Spring's `HttpHeaders.encodeBasicAuth`.
  static String encodeBasicAuth(
    String username,
    String password, {
    Encoding encoding = latin1,
  }) {
    if (username.contains(':')) {
      throw ArgumentError.value(username, 'username', 'must not contain ":"');
    }
    return base64Encode(encoding.encode('$username:$password'));
  }

  void _setOrRemove(String name, String? value) =>
      value == null ? remove(name) : set(name, value);

  @override
  String toString() => toMap().toString();
}
