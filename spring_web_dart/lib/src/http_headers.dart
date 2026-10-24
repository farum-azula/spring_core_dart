import 'dart:convert';

import 'package:spring_web_dart/src/media_type.dart';

/// HTTP headers: names are case-insensitive, a name may have several
/// values, insertion order and the original casing are kept. Like Spring's
/// `HttpHeaders` (Spring Framework 7: not a `Map`).
///
/// ```dart
/// final headers = HttpHeaders({'Accept': 'application/json'})
///   ..add('X-Tag', 'a')
///   ..add('x-tag', 'b')
///   ..contentType = MediaType.applicationJson
///   ..accept = [MediaType.parse(MediaType.applicationJson)]
///   ..eTag = 'v1'                  // "v1"
///   ..lastModified = DateTime.utc(2026, 10, 24)
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
/// headers.setAccept(List.of(MediaType.APPLICATION_JSON));
/// headers.setETag("v1");
/// headers.setLastModified(Instant.parse("2026-10-24T00:00:00Z"));
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

  /// The media types of `Accept` (every value, comma lists split), like
  /// Spring's `getAccept()`; empty when there is none. Throws an
  /// [InvalidMediaTypeException] for an invalid one.
  List<MediaType> get accept => [
    for (final value in getAll(acceptHeader))
      ...MediaType.parseMediaTypes(value),
  ];

  /// Sets `Accept` to [mediaTypes] (empty removes it).
  set accept(List<MediaType> mediaTypes) => _setOrRemove(
    acceptHeader,
    mediaTypes.isEmpty ? null : mediaTypes.join(', '),
  );

  /// The `ETag` as written (quotes included), or `null`.
  String? get eTag => this[etagHeader];

  /// Sets the `ETag`, quoting it unless it already is (`"v1"` or the weak
  /// `W/"v1"`), like Spring's `setETag`; `null` removes it.
  set eTag(String? value) =>
      _setOrRemove(etagHeader, value == null ? null : _quoteETag(value));

  /// The entity tags of `If-None-Match` (quotes included, `*` as is),
  /// like Spring's `getIfNoneMatch()`.
  List<String> get ifNoneMatch => _eTags(ifNoneMatchHeader);

  /// Sets `If-None-Match` to [eTags], quoting each like [eTag] (`*` as
  /// is); empty removes it.
  set ifNoneMatch(List<String> eTags) => _setOrRemove(
    ifNoneMatchHeader,
    eTags.isEmpty
        ? null
        : [for (final tag in eTags) tag == '*' ? tag : _quoteETag(tag)]
              .join(', '),
  );

  /// The `Last-Modified` date (UTC), or `null` when there is none; throws
  /// `ArgumentError` for a value that is not an HTTP date, like Spring's
  /// `getLastModified()`.
  DateTime? get lastModified => _date(lastModifiedHeader);

  /// Sets `Last-Modified` as an HTTP date (RFC 1123, second precision);
  /// `null` removes it.
  set lastModified(DateTime? value) => _setOrRemove(
    lastModifiedHeader,
    value == null ? null : formatDate(value),
  );

  /// The `Date` (UTC), or `null` when there is none; throws
  /// `ArgumentError` for a value that is not an HTTP date.
  DateTime? get date => _date(dateHeader);

  /// Sets `Date` as an HTTP date; `null` removes it.
  set date(DateTime? value) =>
      _setOrRemove(dateHeader, value == null ? null : formatDate(value));

  /// The `Content-Disposition`, or `null` when there is none (Spring's
  /// `getContentDisposition()` gives an empty one).
  ContentDisposition? get contentDisposition =>
      switch (this[contentDispositionHeader]) {
        final value? => ContentDisposition.parse(value),
        null => null,
      };

  /// Sets the `Content-Disposition`; `null` removes it.
  set contentDisposition(ContentDisposition? value) =>
      _setOrRemove(contentDispositionHeader, value?.toString());

  /// Sets `Content-Disposition: form-data; name=...; filename=...`, like
  /// Spring's `setContentDispositionFormData`.
  void setContentDispositionFormData(String name, [String? filename]) =>
      contentDisposition = ContentDisposition.formData(
        name: name,
        filename: filename,
      );

  /// [value] as an HTTP date (RFC 1123, in GMT), e.g.
  /// `Sat, 24 Oct 2026 08:00:00 GMT`.
  static String formatDate(DateTime value) {
    final utc = value.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${_days[utc.weekday - 1]}, ${two(utc.day)} '
        '${_months[utc.month - 1]} ${utc.year} '
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT';
  }

  /// Reads an HTTP date in the RFC 1123, RFC 850 or asctime format, like
  /// Spring; `null` when [value] is none of them.
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

/// The `Content-Disposition` header, like Spring's `ContentDisposition`:
/// its [type] (`attachment`, `inline`, `form-data`), [name] and
/// [filename]. A non-ASCII file name is written as `filename*` (RFC 5987,
/// UTF-8) and read back from it.
///
/// ```dart
/// headers.contentDisposition = const ContentDisposition.attachment(
///   filename: 'report.pdf',
/// );
/// headers.contentDisposition!.filename; // 'report.pdf'
/// ```
///
/// Spring (Java):
/// ```java
/// headers.setContentDisposition(
///     ContentDisposition.attachment().filename("report.pdf").build());
/// headers.getContentDisposition().getFilename();
/// ```
final class ContentDisposition {
  /// A disposition of [type] (e.g. `attachment`).
  const ContentDisposition(this.type, {this.name, this.filename});

  /// `attachment` with an optional [filename].
  const ContentDisposition.attachment({String? filename})
    : this('attachment', filename: filename);

  /// `inline` with an optional [filename].
  const ContentDisposition.inline({String? filename})
    : this('inline', filename: filename);

  /// `form-data` for the part [name], with an optional [filename].
  const ContentDisposition.formData({required String name, String? filename})
    : this('form-data', name: name, filename: filename);

  /// Reads a `Content-Disposition` value, like Spring's
  /// `ContentDisposition.parse`; throws `ArgumentError` for one without a
  /// type.
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

  /// `attachment`, `inline`, `form-data`, ...
  final String type;

  /// The `name` parameter (form data), or `null`.
  final String? name;

  /// The `filename` (or `filename*`) parameter, or `null`.
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

  /// The header value, e.g. `attachment; filename="report.pdf"`.
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
  static final _attrChar = RegExp(r"[A-Za-z0-9!#$&+\-.^_`|~]");

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
