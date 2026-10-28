import 'dart:convert';

import 'package:spring_web_dart/src/media_type.dart';

/// The headers of an HTTP request or response: name and value pairs where
/// names ignore case and a name may appear several times.
///
/// Every request and response of this package carries one: the client's
/// `HttpRequest` and `HttpResponse`, a `ResponseEntity`, the server's
/// `ServerHttpRequest` and `ServerHttpResponse`. It keeps the order and
/// the casing the headers were added with. Besides plain text access
/// (`headers['Accept']`, [getAll], [set], [add]), it reads and writes the
/// common headers as typed values ([contentType], [contentLength],
/// [accept], [eTag], [lastModified], [contentDisposition], ...), so you do
/// not format dates or quote entity tags yourself. A controller method gets
/// the request's headers by declaring a parameter of this type.
///
/// ```dart
/// // A controller answers 304 when the client's copy is still current,
/// // else the book with headers that let the client cache it.
/// @GetMapping('/books/{isbn}')
/// ResponseEntity<Book> find(@PathVariable() String isbn, HttpHeaders sent) {
///   final book = books.find(isbn);
///   if (sent.ifNoneMatch.contains('"${book.version}"')) {
///     return ResponseEntity(304);
///   }
///   final headers = HttpHeaders()
///     ..eTag = book.version // sent quoted: "7"
///     ..lastModified = book.updatedAt;
///   return ResponseEntity(200, body: book, headers: headers);
/// }
/// ```
///
/// Names ignore case, and repeated names keep every value:
///
/// ```dart
/// final headers = HttpHeaders({'Accept': 'application/json'})
///   ..add('X-Tag', 'a')
///   ..add('x-tag', 'b');
/// headers['accept'];       // 'application/json'
/// headers.getAll('X-TAG'); // ['a', 'b']
/// ```
///
/// The name constants end in `Header` (`HttpHeaders.contentTypeHeader`, as
/// in `dart:io`) because the typed accessors take the plain names
/// (`headers.contentType`). As in Spring Framework 7, the class is not a
/// `Map`.
///
/// Spring (Java):
/// ```java
/// @GetMapping("/books/{isbn}")
/// ResponseEntity<Book> find(@PathVariable String isbn,
///     @RequestHeader HttpHeaders sent) {
///   Book book = books.find(isbn);
///   if (sent.getIfNoneMatch().contains("\"" + book.version() + "\"")) {
///     return ResponseEntity.status(HttpStatus.NOT_MODIFIED).build();
///   }
///   HttpHeaders headers = new HttpHeaders();
///   headers.setETag(book.version());
///   headers.setLastModified(book.updatedAt());
///   return new ResponseEntity<>(book, headers, HttpStatus.OK);
/// }
/// ```
class HttpHeaders {
  /// Headers holding one value for each entry of [values], in the map's
  /// order; empty when [values] is omitted.
  HttpHeaders([Map<String, String>? values]) {
    values?.forEach(set);
  }

  /// Headers from name and value pairs, in order. A name may repeat,
  /// which gives it several values (several `Set-Cookie`, for example).
  HttpHeaders.fromEntries(Iterable<MapEntry<String, String>> entries) {
    for (final entry in entries) {
      add(entry.key, entry.value);
    }
  }

  /// A read-only view of [headers], to hand out headers that the receiver
  /// must not change. The view shows later changes made through
  /// [headers]; every method of the view that would change it throws an
  /// `UnsupportedError`. Like Spring's `HttpHeaders.readOnlyHttpHeaders`.
  HttpHeaders.readOnly(HttpHeaders headers)
    : _entries = headers._entries,
      _readOnly = true;

  /// `Accept`: the media types the client can read in the response.
  static const acceptHeader = 'Accept';

  /// `Accept-Charset`: the character sets the client can read.
  static const acceptCharsetHeader = 'Accept-Charset';

  /// `Accept-Encoding`: the compressions the client can read (`gzip`, `br`).
  static const acceptEncodingHeader = 'Accept-Encoding';

  /// `Accept-Language`: the languages the client prefers.
  static const acceptLanguageHeader = 'Accept-Language';

  /// `Accept-Patch`: the media types a server accepts in a `PATCH` body.
  static const acceptPatchHeader = 'Accept-Patch';

  /// `Accept-Ranges`: whether a server serves parts of a resource (`bytes`).
  static const acceptRangesHeader = 'Accept-Ranges';

  /// `Access-Control-Allow-Credentials`: in CORS, whether the browser may send
  /// cookies and credentials.
  static const accessControlAllowCredentialsHeader =
      'Access-Control-Allow-Credentials';

  /// `Access-Control-Allow-Headers`: in CORS, the request headers the server
  /// allows.
  static const accessControlAllowHeadersHeader = 'Access-Control-Allow-Headers';

  /// `Access-Control-Allow-Methods`: in CORS, the methods the server allows.
  static const accessControlAllowMethodsHeader = 'Access-Control-Allow-Methods';

  /// `Access-Control-Allow-Origin`: in CORS, the origin allowed to read the
  /// response.
  static const accessControlAllowOriginHeader = 'Access-Control-Allow-Origin';

  /// `Access-Control-Expose-Headers`: in CORS, the response headers scripts may
  /// read.
  static const accessControlExposeHeadersHeader =
      'Access-Control-Expose-Headers';

  /// `Access-Control-Max-Age`: in CORS, how long, in seconds, a preflight
  /// answer may be cached.
  static const accessControlMaxAgeHeader = 'Access-Control-Max-Age';

  /// `Access-Control-Request-Headers`: in a CORS preflight, the headers the
  /// real request will send.
  static const accessControlRequestHeadersHeader =
      'Access-Control-Request-Headers';

  /// `Access-Control-Request-Method`: in a CORS preflight, the method of the
  /// real request.
  static const accessControlRequestMethodHeader =
      'Access-Control-Request-Method';

  /// `Age`: how long, in seconds, a response has been in a cache.
  static const ageHeader = 'Age';

  /// `Allow`: the methods a resource supports (sent with a 405).
  static const allowHeader = 'Allow';

  /// `Authorization`: the credentials of the client (`Bearer ...`, `Basic
  /// ...`).
  static const authorizationHeader = 'Authorization';

  /// `Cache-Control`: the caching rules (`no-cache`, `max-age=60`).
  static const cacheControlHeader = 'Cache-Control';

  /// `Connection`: options of the connection (`keep-alive`, `Upgrade`).
  static const connectionHeader = 'Connection';

  /// `Content-Encoding`: the compression applied to the body (`gzip`).
  static const contentEncodingHeader = 'Content-Encoding';

  /// `Content-Disposition`: whether a body is shown, saved as a file or is a
  /// form field; see [ContentDisposition].
  static const contentDispositionHeader = 'Content-Disposition';

  /// `Content-Language`: the language of the body.
  static const contentLanguageHeader = 'Content-Language';

  /// `Content-Length`: the size of the body, in bytes.
  static const contentLengthHeader = 'Content-Length';

  /// `Content-Location`: the URL of the resource the body represents.
  static const contentLocationHeader = 'Content-Location';

  /// `Content-Range`: which part of the resource a partial body (206) holds.
  static const contentRangeHeader = 'Content-Range';

  /// `Content-Type`: the media type of the body (`application/json`).
  static const contentTypeHeader = 'Content-Type';

  /// `Cookie`: the cookies the client sends back (`a=1; b=2`).
  static const cookieHeader = 'Cookie';

  /// `Date`: when the message was sent.
  static const dateHeader = 'Date';

  /// `ETag`: the version tag of the resource in the response.
  static const etagHeader = 'ETag';

  /// `Expect`: what the client expects before sending the body
  /// (`100-continue`).
  static const expectHeader = 'Expect';

  /// `Expires`: the date after which a cached response is stale.
  static const expiresHeader = 'Expires';

  /// `From`: the email address of the user behind the client.
  static const fromHeader = 'From';

  /// `Host`: the host (and port) the request is for.
  static const hostHeader = 'Host';

  /// `If-Match`: the request applies only if the resource still has one of
  /// these tags.
  static const ifMatchHeader = 'If-Match';

  /// `If-Modified-Since`: answer 304 unless the resource changed since this
  /// date.
  static const ifModifiedSinceHeader = 'If-Modified-Since';

  /// `If-None-Match`: answer 304 if the resource still has one of these tags.
  static const ifNoneMatchHeader = 'If-None-Match';

  /// `If-Range`: send the requested range only if the resource is unchanged.
  static const ifRangeHeader = 'If-Range';

  /// `If-Unmodified-Since`: the request applies only if the resource did not
  /// change since this date.
  static const ifUnmodifiedSinceHeader = 'If-Unmodified-Since';

  /// `Last-Modified`: when the resource last changed.
  static const lastModifiedHeader = 'Last-Modified';

  /// `Link`: links to related resources (`<url>; rel="next"`).
  static const linkHeader = 'Link';

  /// `Location`: the URL of a created resource (201) or of a redirect (3xx).
  static const locationHeader = 'Location';

  /// `Max-Forwards`: how many proxies may still forward a `TRACE` or `OPTIONS`.
  static const maxForwardsHeader = 'Max-Forwards';

  /// `Origin`: the origin (scheme, host, port) of the page that sent the
  /// request.
  static const originHeader = 'Origin';

  /// `Pragma`: the HTTP/1.0 cache rule (`no-cache`).
  static const pragmaHeader = 'Pragma';

  /// `Proxy-Authenticate`: how to authenticate to a proxy (sent with a 407).
  static const proxyAuthenticateHeader = 'Proxy-Authenticate';

  /// `Proxy-Authorization`: the credentials of the client for a proxy.
  static const proxyAuthorizationHeader = 'Proxy-Authorization';

  /// `Range`: the part of the resource the client wants (`bytes=0-1023`).
  static const rangeHeader = 'Range';

  /// `Referer`: the page the request comes from.
  static const refererHeader = 'Referer';

  /// `Retry-After`: how long to wait before trying again (with a 503 or 429).
  static const retryAfterHeader = 'Retry-After';

  /// `Server`: the software of the server.
  static const serverHeader = 'Server';

  /// `Set-Cookie`: a cookie the client must store; one header per cookie.
  static const setCookieHeader = 'Set-Cookie';

  /// `TE`: the transfer encodings the client accepts.
  static const teHeader = 'TE';

  /// `Trailer`: the headers sent after a chunked body.
  static const trailerHeader = 'Trailer';

  /// `Transfer-Encoding`: how the body is sent (`chunked`).
  static const transferEncodingHeader = 'Transfer-Encoding';

  /// `Upgrade`: the protocol to switch to (`websocket`).
  static const upgradeHeader = 'Upgrade';

  /// `User-Agent`: the software of the client.
  static const userAgentHeader = 'User-Agent';

  /// `Vary`: the request headers a cached response depends on.
  static const varyHeader = 'Vary';

  /// `Via`: the proxies the message went through.
  static const viaHeader = 'Via';

  /// `Warning`: extra information about the message (obsolete in HTTP).
  static const warningHeader = 'Warning';

  /// `WWW-Authenticate`: how to authenticate (sent with a 401).
  static const wwwAuthenticateHeader = 'WWW-Authenticate';

  List<MapEntry<String, String>> _entries = [];

  bool _readOnly = false;

  /// Whether changing these headers throws, as it does on a view made
  /// with [HttpHeaders.readOnly].
  bool get isReadOnly => _readOnly;

  void _checkWritable() {
    if (_readOnly) {
      throw UnsupportedError('HttpHeaders are read-only');
    }
  }

  static bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();

  /// The first value of the header [name], in any casing, or `null` when
  /// it is absent. Use [getAll] for a header that may repeat.
  String? operator [](String name) {
    for (final entry in _entries) {
      if (_same(entry.key, name)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Every value of the header [name], in any casing, in the order they
  /// were added; empty when it is absent. A value holding a comma list
  /// stays one value.
  List<String> getAll(String name) => [
    for (final entry in _entries)
      if (_same(entry.key, name)) entry.value,
  ];

  /// Replaces every value of [name] with the single [value], written with
  /// the casing of [name]. The header keeps its place if it was there,
  /// else it goes last.
  void set(String name, String value) {
    _checkWritable();
    final index = _entries.indexWhere((e) => _same(e.key, name));
    remove(name);
    final entry = MapEntry(name, value);
    if (index < 0 || index > _entries.length) {
      _entries.add(entry);
    } else {
      _entries.insert(index, entry);
    }
  }

  /// Adds [value] as one more value of [name], after those already there.
  void add(String name, String value) {
    _checkWritable();
    _entries.add(MapEntry(name, value));
  }

  /// Adds each of [values], in order, as more values of [name], like
  /// Spring's `addAll(name, values)`.
  void addAll(String name, Iterable<String> values) {
    for (final value in values) {
      add(name, value);
    }
  }

  /// Adds every name and value of [headers] after those already here,
  /// keeping both, like Spring's `addAll(HttpHeaders)`. Use [putAll] to
  /// replace instead.
  void addHeaders(HttpHeaders headers) {
    _checkWritable();
    _entries.addAll(List.of(headers._entries));
  }

  /// Copies [headers] over these: each name present in [headers] loses
  /// its current values and gets those of [headers] (at the end); the
  /// other names stay. Like Spring's `putAll(HttpHeaders)`.
  void putAll(HttpHeaders headers) {
    final other = List.of(headers._entries);
    headers.names.toList().forEach(remove);
    _checkWritable();
    _entries.addAll(other);
  }

  /// Calls [set] for each entry of [values], so each of those names ends
  /// with exactly that value, like Spring's `setAll`.
  void setAll(Map<String, String> values) => values.forEach(set);

  /// Removes every value of [name], in any casing; does nothing when it
  /// is absent.
  void remove(String name) {
    _checkWritable();
    _entries.removeWhere((e) => _same(e.key, name));
  }

  /// Removes every header.
  void clear() {
    _checkWritable();
    _entries.clear();
  }

  /// Whether the header [name], in any casing, is present (even with an
  /// empty value).
  bool contains(String name) => _entries.any((e) => _same(e.key, name));

  /// Whether [value] is one of the values of [name] (the name
  /// case-insensitive, the value exact), like Spring's
  /// `containsHeaderValue`.
  bool containsHeaderValue(String name, String value) =>
      _entries.any((e) => _same(e.key, name) && e.value == value);

  /// The number of different header names; several values of one name
  /// count once, like Spring's `size()`.
  int get size => names.length;

  /// Each header name once, with the casing and in the order of its first
  /// value.
  Iterable<String> get names {
    final seen = <String>{};
    return [
      for (final entry in _entries)
        if (seen.add(entry.key.toLowerCase())) entry.key,
    ];
  }

  /// Calls [action] once per header name with all its values, in the
  /// order the names were first added; the way to copy headers to another
  /// API.
  void forEach(void Function(String name, List<String> values) action) {
    for (final name in names) {
      action(name, getAll(name));
    }
  }

  /// A map from each name to its first value, like Spring's
  /// `toSingleValueMap()`; further values are left out.
  Map<String, String> toSingleValueMap() => {
    for (final name in names) name: this[name]!,
  };

  /// A map from each name to all its values joined with `, `. HTTP allows
  /// this form for most headers, but not for `Set-Cookie`, whose values
  /// must stay apart.
  Map<String, String> toMap() => {
    for (final name in names) name: getAll(name).join(', '),
  };

  /// A copy that later changes on either side do not affect; the copy of
  /// a read-only view can be changed.
  HttpHeaders copy() => HttpHeaders.fromEntries(_entries);

  /// Whether there is no header at all.
  bool get isEmpty => _entries.isEmpty;

  /// Whether there is at least one header.
  bool get isNotEmpty => _entries.isNotEmpty;

  /// The `Content-Type` as written (`application/json; charset=utf-8`),
  /// or `null` when absent. `MediaType.parse` reads its parts.
  String? get contentType => this[contentTypeHeader];

  /// Sets the `Content-Type`; `null` removes it. The `MediaType`
  /// constants are strings: `headers.contentType = MediaType.applicationJson`.
  set contentType(String? value) => _setOrRemove(contentTypeHeader, value);

  /// The `Location` (the URL of a created resource or of a redirect)
  /// parsed, or `null` when absent. Throws a `FormatException` when it is
  /// not a valid URI.
  Uri? get location => switch (this[locationHeader]) {
    final value? => Uri.parse(value),
    null => null,
  };

  /// Sets the `Location`; `null` removes it.
  set location(Uri? value) => _setOrRemove(locationHeader, value?.toString());

  /// The `Content-Length` in bytes, or -1 when it is absent or not a
  /// number, like Spring.
  int get contentLength =>
      int.tryParse(this[contentLengthHeader]?.trim() ?? '') ?? -1;

  /// Sets the `Content-Length` in bytes; a negative value removes it.
  set contentLength(int value) =>
      _setOrRemove(contentLengthHeader, value < 0 ? null : '$value');

  /// The media types the client accepts, from every `Accept` value with
  /// comma lists split, like Spring's `getAccept()`; empty when there is
  /// none. Throws an [InvalidMediaTypeException] for an invalid one.
  List<MediaType> get accept => [
    for (final value in getAll(acceptHeader))
      ...MediaType.parseMediaTypes(value),
  ];

  /// Sets `Accept` to [mediaTypes], as one comma list; an empty list
  /// removes it.
  set accept(List<MediaType> mediaTypes) => _setOrRemove(
    acceptHeader,
    mediaTypes.isEmpty ? null : mediaTypes.join(', '),
  );

  /// The `ETag`, the version tag of the resource, as written (quotes
  /// included, `"7"` or `W/"7"`), or `null` when absent.
  String? get eTag => this[etagHeader];

  /// Sets the `ETag`, quoting it unless it already is (`"v1"` or the weak
  /// `W/"v1"`), like Spring's `setETag`; `null` removes it.
  set eTag(String? value) =>
      _setOrRemove(etagHeader, value == null ? null : _quoteETag(value));

  /// The tags of `If-None-Match`, from every value, quotes included and
  /// `*` as is, like Spring's `getIfNoneMatch()`. A server answers 304
  /// when the current [eTag] is among them.
  List<String> get ifNoneMatch => _eTags(ifNoneMatchHeader);

  /// Sets `If-None-Match` to [eTags], quoting each like [eTag] (`*` as
  /// is); empty removes it.
  set ifNoneMatch(List<String> eTags) => _setOrRemove(
    ifNoneMatchHeader,
    eTags.isEmpty
        ? null
        : [
            for (final tag in eTags)
              if (tag == '*') tag else _quoteETag(tag),
          ].join(', '),
  );

  /// The `Last-Modified` date in UTC, or `null` when it is absent or not
  /// an HTTP date. Lenient, like Spring's `getLastModified()`, unlike
  /// [date].
  DateTime? get lastModified => switch (this[lastModifiedHeader]) {
    final value? => parseDate(value),
    null => null,
  };

  /// Sets `Last-Modified` as an HTTP date (RFC 1123, second precision);
  /// `null` removes it.
  set lastModified(DateTime? value) => _setOrRemove(
    lastModifiedHeader,
    value == null ? null : formatDate(value),
  );

  /// The `Date` in UTC, or `null` when it is absent. Throws an
  /// `ArgumentError` for a value that is not an HTTP date.
  DateTime? get date => _date(dateHeader);

  /// Sets `Date` as an HTTP date; `null` removes it.
  set date(DateTime? value) =>
      _setOrRemove(dateHeader, value == null ? null : formatDate(value));

  /// The `Content-Disposition` parsed, or `null` when absent (Spring's
  /// `getContentDisposition()` gives an empty one instead). Throws an
  /// `ArgumentError` when the value has no type.
  ContentDisposition? get contentDisposition =>
      switch (this[contentDispositionHeader]) {
        final value? => ContentDisposition.parse(value),
        null => null,
      };

  /// Sets the `Content-Disposition`; `null` removes it.
  set contentDisposition(ContentDisposition? value) =>
      _setOrRemove(contentDispositionHeader, value?.toString());

  /// Sets `Content-Disposition: form-data; name=...; filename=...`, the
  /// header of one part of a multipart form, like Spring's
  /// `setContentDispositionFormData`.
  void setContentDispositionFormData(String name, [String? filename]) =>
      contentDisposition = ContentDisposition.formData(
        name: name,
        filename: filename,
      );

  /// Writes [value] as an HTTP date (RFC 1123, converted to GMT, to the
  /// second), such as `Sat, 24 Oct 2026 08:00:00 GMT`.
  static String formatDate(DateTime value) {
    final utc = value.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${_days[utc.weekday - 1]}, ${two(utc.day)} '
        '${_months[utc.month - 1]} ${utc.year} '
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT';
  }

  /// Reads an HTTP date in any of the three formats HTTP allows (RFC
  /// 1123, RFC 850, asctime), like Spring, as a UTC `DateTime`; `null`
  /// when [value] is in none of them. A two-digit RFC 850 year below 70
  /// is in the 2000s.
  static DateTime? parseDate(String value) {
    final text = value.trim();
    for (final (format, day, month, year) in _dateFormats) {
      final match = format.firstMatch(text);
      if (match == null) {
        continue;
      }
      final monthIndex = _months.indexWhere(
        (name) => name.toLowerCase() == match[month]!.toLowerCase(),
      );
      if (monthIndex < 0) {
        return null;
      }
      var y = int.parse(match[year]!);
      if (y < 100) {
        // RFC 850 two-digit years.
        y += y < 70 ? 2000 : 1900;
      }
      final time = match.namedGroup('time')!.split(':');
      return DateTime.utc(
        y,
        monthIndex + 1,
        int.parse(match[day]!.trim()),
        int.parse(time[0]),
        int.parse(time[1]),
        int.parse(time[2]),
      );
    }
    return null;
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static final _dateFormats = [
    // RFC 1123: Sun, 06 Nov 1994 08:49:37 GMT
    (
      RegExp(
        r'^(?:[A-Za-z]{3}, )?(\d{1,2}) ([A-Za-z]{3}) (\d{4}) '
        r'(?<time>\d{2}:\d{2}:\d{2}) GMT$',
      ),
      1,
      2,
      3,
    ),
    // RFC 850: Sunday, 06-Nov-94 08:49:37 GMT
    (
      RegExp(
        r'^[A-Za-z]+, (\d{2})-([A-Za-z]{3})-(\d{2}) '
        r'(?<time>\d{2}:\d{2}:\d{2}) GMT$',
      ),
      1,
      2,
      3,
    ),
    // asctime: Sun Nov  6 08:49:37 1994
    (
      RegExp(
        r'^[A-Za-z]{3} ([A-Za-z]{3}) ( ?\d{1,2}) '
        r'(?<time>\d{2}:\d{2}:\d{2}) (\d{4})$',
      ),
      2,
      1,
      4,
    ),
  ];

  DateTime? _date(String name) {
    final value = this[name];
    if (value == null) {
      return null;
    }
    return parseDate(value) ??
        (throw ArgumentError.value(
          value,
          name,
          'Cannot parse date value "$value" for "$name" header',
        ));
  }

  static String _quoteETag(String tag) =>
      tag.startsWith('"') || tag.startsWith('W/"') ? tag : '"$tag"';

  List<String> _eTags(String name) => [
    for (final value in getAll(name))
      for (final match in _eTag.allMatches(value)) match[0]!,
  ];

  static final _eTag = RegExp(r'\*|(?:W/)?"[^"]*"');

  /// Sets `Authorization: Bearer <token>`, replacing other credentials;
  /// the way to send an OAuth 2 access token or a JWT.
  void setBearerAuth(String token) => set(authorizationHeader, 'Bearer $token');

  /// Sets `Authorization: Basic <credentials>` for [username] and
  /// [password], replacing other credentials. They are encoded with
  /// [encoding] (ISO-8859-1 by default, like Spring); throws an
  /// `ArgumentError` for characters it cannot encode or a [username]
  /// containing `:`.
  void setBasicAuth(
    String username,
    String password, {
    Encoding encoding = latin1,
  }) => set(
    authorizationHeader,
    'Basic ${encodeBasicAuth(username, password, encoding: encoding)}',
  );

  /// The Base64 credentials of Basic authentication for [username] and
  /// [password] (`username:password` encoded with [encoding]), like
  /// Spring's `HttpHeaders.encodeBasicAuth`. Throws an `ArgumentError`
  /// when [username] contains `:`.
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

  /// Whether [other] has the same names (in any casing) with the same
  /// values in the same order for each name, like Spring's `equals`. The
  /// order of different names does not matter.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! HttpHeaders || other.size != size) {
      return false;
    }
    for (final name in names) {
      final values = getAll(name);
      final otherValues = other.getAll(name);
      if (values.length != otherValues.length) {
        return false;
      }
      for (var i = 0; i < values.length; i++) {
        if (values[i] != otherValues[i]) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final name in names)
      Object.hash(name.toLowerCase(), Object.hashAll(getAll(name))),
  ]);

  @override
  String toString() => toMap().toString();
}

/// The value of a `Content-Disposition` header: whether a body is shown
/// by the browser (`inline`), saved as a file (`attachment`) or is one
/// field of a multipart form (`form-data`), with the file or field name.
///
/// A controller sets it on a download so that the browser saves the file
/// under a chosen name; each part of a multipart body has a `form-data`
/// one. A non-ASCII file name is written as `filename*` (RFC 5987, UTF-8)
/// and read back from it, so any name is safe.
///
/// ```dart
/// // A download the browser saves as report.pdf instead of showing it.
/// @GetMapping('/reports/{id}.pdf')
/// ResponseEntity<Uint8List> report(@PathVariable() String id) {
///   final headers = HttpHeaders()
///     ..contentType = 'application/pdf'
///     ..contentDisposition =
///         const ContentDisposition.attachment(filename: 'report.pdf');
///   return ResponseEntity(200, body: reports.pdf(id), headers: headers);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// headers.setContentDisposition(
///     ContentDisposition.attachment().filename("report.pdf").build());
/// headers.getContentDisposition().getFilename();
/// ```
final class ContentDisposition {
  /// A disposition of any [type], with an optional [name] and
  /// [filename]; the named constructors cover the three usual types.
  const ContentDisposition(this.type, {this.name, this.filename});

  /// `attachment`: the browser saves the body as a file, named
  /// [filename] when given.
  const ContentDisposition.attachment({String? filename})
    : this('attachment', filename: filename);

  /// `inline`: the browser shows the body, as it does without the
  /// header; [filename] is the name offered if the user saves it.
  const ContentDisposition.inline({String? filename})
    : this('inline', filename: filename);

  /// `form-data`: the part of a multipart form for the field [name];
  /// [filename] makes it a file.
  const ContentDisposition.formData({required String name, String? filename})
    : this('form-data', name: name, filename: filename);

  /// Reads a header value such as `attachment; filename="report.pdf"`,
  /// like Spring's `ContentDisposition.parse`. The type is lower-cased,
  /// quotes and backslash escapes are removed, `filename*` wins over
  /// `filename`, and other parameters are ignored. Throws an
  /// `ArgumentError` when the value has no type.
  static ContentDisposition parse(String value) {
    final parts = _split(value);
    final type = parts.first.trim();
    if (type.isEmpty) {
      throw ArgumentError.value(value, 'value', 'no disposition type');
    }
    String? name;
    String? filename;
    String? extendedFilename;
    for (final part in parts.skip(1)) {
      final eq = part.indexOf('=');
      if (eq < 0) {
        continue;
      }
      final key = part.substring(0, eq).trim().toLowerCase();
      final raw = part.substring(eq + 1).trim();
      switch (key) {
        case 'name':
          name = _unquote(raw);
        case 'filename':
          filename = _unquote(raw);
        case 'filename*':
          extendedFilename = _decodeExtended(raw);
      }
    }
    return ContentDisposition(
      type.toLowerCase(),
      name: name,
      filename: extendedFilename ?? filename,
    );
  }

  /// The disposition type: `attachment`, `inline`, `form-data`, or
  /// another; lower case when parsed.
  final String type;

  /// The `name` parameter, the form field of a `form-data` part; `null`
  /// otherwise.
  final String? name;

  /// The file name, from `filename*` (decoded) or `filename`; `null`
  /// when there is none.
  final String? filename;

  /// Whether the type is `attachment`.
  bool get isAttachment => type == 'attachment';

  /// Whether the type is `inline`.
  bool get isInline => type == 'inline';

  /// Whether the type is `form-data`.
  bool get isFormData => type == 'form-data';

  @override
  bool operator ==(Object other) =>
      other is ContentDisposition &&
      other.type == type &&
      other.name == name &&
      other.filename == filename;

  @override
  int get hashCode => Object.hash(type, name, filename);

  /// The header value, such as `attachment; filename="report.pdf"`.
  /// Quotes and backslashes in the names are escaped; a file name that is
  /// not printable ASCII is written as `filename*=UTF-8''...`.
  @override
  String toString() {
    final buffer = StringBuffer(type);
    if (name case final name?) {
      buffer.write('; name="${_escape(name)}"');
    }
    if (filename case final filename?) {
      if (_ascii.hasMatch(filename)) {
        buffer.write('; filename="${_escape(filename)}"');
      } else {
        buffer.write("; filename*=UTF-8''${_encodeExtended(filename)}");
      }
    }
    return buffer.toString();
  }

  static final _ascii = RegExp(r'^[\x20-\x7e]*$');

  static String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  static String _unquote(String value) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return value
          .substring(1, value.length - 1)
          .replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
    }
    return value;
  }

  // RFC 5987 attr-char: ALPHA / DIGIT / "!#$&+-.^_`|~".
  static final _attrChar = RegExp(r'[A-Za-z0-9!#$&+\-.^_`|~]');

  static String _encodeExtended(String value) => [
    for (final byte in utf8.encode(value))
      if (byte < 0x80 && _attrChar.hasMatch(String.fromCharCode(byte)))
        String.fromCharCode(byte)
      else
        '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
  ].join();

  static String? _decodeExtended(String value) {
    final first = value.indexOf("'");
    final second = first < 0 ? -1 : value.indexOf("'", first + 1);
    if (second < 0) {
      return null;
    }
    final encoding = Encoding.getByName(value.substring(0, first)) ?? utf8;
    final text = value.substring(second + 1);
    final bytes = <int>[];
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '%' && i + 2 < text.length) {
        bytes.add(int.parse(text.substring(i + 1, i + 3), radix: 16));
        i += 2;
      } else {
        bytes.addAll(utf8.encode(text[i]));
      }
    }
    return encoding.decode(bytes);
  }

  static List<String> _split(String value) {
    final parts = <String>[];
    var quoted = false;
    var start = 0;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char == r'\' && quoted) {
        i++;
      } else if (char == '"') {
        quoted = !quoted;
      } else if (char == ';' && !quoted) {
        parts.add(value.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(value.substring(start));
    return parts;
  }
}
