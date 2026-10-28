import 'dart:convert';

/// A parsed media type (MIME type), such as `application/json` or
/// `text/plain;charset=UTF-8`: the kind of data a body holds.
///
/// HTTP names the format of a body in the `Content-Type` header and the
/// formats a client can read in `Accept`. Most code only needs the
/// static constants, which are plain `String`s and so work in annotations
/// and headers: `produces: MediaType.applicationJson`. Parse a
/// [MediaType] when a header's value must be examined: its [type] and
/// [subtype], a parameter such as the [charset], or whether it matches
/// another type with wildcards (`text/*`) or a suffix (`+json`), which
/// [includes] and [isCompatibleWith] answer. A plain string comparison
/// gets those cases wrong (`application/json; charset=utf-8`).
///
/// ```dart
/// // Is the received body JSON? Also true for application/problem+json
/// // and for a Content-Type with a charset.
/// bool isJson(String? contentType) =>
///     contentType != null &&
///     MediaType.parse('application/*+json')
///         .isCompatibleWith(MediaType.parse(contentType));
///
/// // Read the text with the charset the server announced.
/// final type = MediaType.parse(response.headers.contentType!);
/// final text = (type.charset ?? utf8).decode(bytes);
/// ```
///
/// Spring (Java): `MediaType`; the string constants here are Spring's
/// `..._VALUE` constants.
/// ```java
/// MediaType.parseMediaType("application/*+json")
///     .isCompatibleWith(MediaType.parseMediaType(contentType));
/// ```
final class MediaType {
  /// The media type [type]/[subtype] (`*` by default) with [parameters];
  /// type and subtype are lower-cased. Throws an
  /// [InvalidMediaTypeException] for an invalid value: type, subtype and
  /// parameter names must be HTTP tokens, parameter values tokens or
  /// quoted strings (`"..."` or `'...'`), `charset` a legal charset name,
  /// and `q` a number from 0 to 1. A wildcard type needs a wildcard
  /// subtype (`*/*`). A parameter given twice, in any case, keeps the last
  /// value. Use [parse] to read a header value.
  MediaType(
    String type, [
    String subtype = wildcardType,
    Map<String, String> parameters = const {},
  ]) : type = _checkToken(type.toLowerCase(), 'type'),
       subtype = _checkToken(subtype.toLowerCase(), 'subtype'),
       parameters = Map.unmodifiable(_checkParameters(parameters)) {
    if (this.type == wildcardType && this.subtype != wildcardType) {
      throw InvalidMediaTypeException(
        toString(),
        'wildcard type is legal only in "*/*" (all media types)',
      );
    }
    final quality = getParameter('q');
    if (quality != null) {
      final value = double.tryParse(quality);
      if (value == null || value < 0 || value > 1) {
        throw InvalidMediaTypeException(
          toString(),
          'invalid quality value "$quality": should be between 0.0 and 1.0',
        );
      }
    }
  }

  /// Reads one media type from text such as a `Content-Type` value:
  /// `application/json`, `text/plain; charset=UTF-8`, or `*` (read as
  /// `*/*`, which some old clients send). Throws an
  /// [InvalidMediaTypeException] for invalid text; a parameter without
  /// `=` is skipped.
  static MediaType parse(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      throw InvalidMediaTypeException(value, "'mimeType' must not be empty");
    }
    final parts = _split(text, ';');
    var full = parts.first.trim();
    // java.net.HttpURLConnection returns a *; q=.2 Accept header.
    if (full == wildcardType) {
      full = all;
    }
    final slash = full.indexOf('/');
    if (slash < 0) {
      throw InvalidMediaTypeException(value, 'does not contain "/"');
    }
    if (slash == full.length - 1) {
      throw InvalidMediaTypeException(
        value,
        'does not contain subtype after "/"',
      );
    }
    final type = full.substring(0, slash);
    final subtype = full.substring(slash + 1);
    if (subtype.contains('/')) {
      throw InvalidMediaTypeException(value, 'does not contain a single "/"');
    }
    // Like Spring's MimeTypeUtils: a parameter without "=" is ignored.
    final parameters = <String, String>{};
    for (final part in parts.skip(1)) {
      final parameter = part.trim();
      final eq = parameter.indexOf('=');
      if (eq < 0) {
        continue;
      }
      final name = parameter.substring(0, eq).trim();
      parameters
        ..removeWhere((key, _) => key.toLowerCase() == name.toLowerCase())
        ..[name] = parameter.substring(eq + 1).trim();
    }
    try {
      return MediaType(type, subtype, parameters);
    } on InvalidMediaTypeException catch (error) {
      throw InvalidMediaTypeException(value, error.reason);
    }
  }

  /// Reads a comma-separated list such as an `Accept` header, in order;
  /// empty for `null` or blank text. Throws an
  /// [InvalidMediaTypeException] when one entry is invalid.
  static List<MediaType> parseMediaTypes(String? value) => [
    if (value != null)
      for (final part in _split(value, ','))
        if (part.trim().isNotEmpty) parse(part),
  ];

  /// `*`: the wildcard for a type or subtype.
  static const wildcardType = '*';

  /// `*/*`: any media type, as in `Accept: */*`.
  static const all = '*/*';

  /// `application/atom+xml`: an Atom feed.
  static const applicationAtomXml = 'application/atom+xml';

  /// `application/cbor`: CBOR, a binary form of JSON.
  static const applicationCbor = 'application/cbor';

  /// `application/x-www-form-urlencoded`: the fields of an HTML form, as
  /// `name=value&...`.
  static const applicationFormUrlencoded = 'application/x-www-form-urlencoded';

  /// `application/graphql-response+json`: a GraphQL answer.
  static const applicationGraphqlResponse = 'application/graphql-response+json';

  /// `application/json`: JSON, the default body format of controllers and
  /// Feign clients.
  static const applicationJson = 'application/json';

  /// `application/x-ndjson`: newline-delimited JSON.
  static const applicationNdjson = 'application/x-ndjson';

  /// `application/octet-stream`: bytes of no particular format.
  static const applicationOctetStream = 'application/octet-stream';

  /// `application/pdf`: a PDF document.
  static const applicationPdf = 'application/pdf';

  /// `application/problem+json`: an error body in RFC 9457 form, as a
  /// `ProblemDetail` is written.
  static const applicationProblemJson = 'application/problem+json';

  /// `application/problem+xml`: an RFC 9457 error body in XML.
  static const applicationProblemXml = 'application/problem+xml';

  /// `application/x-protobuf`: Protocol Buffers.
  static const applicationProtobuf = 'application/x-protobuf';

  /// `application/rss+xml`: an RSS feed.
  static const applicationRssXml = 'application/rss+xml';

  /// `application/xhtml+xml`: an XHTML page.
  static const applicationXhtmlXml = 'application/xhtml+xml';

  /// `application/xml`: XML.
  static const applicationXml = 'application/xml';

  /// `application/yaml`: YAML.
  static const applicationYaml = 'application/yaml';

  /// `image/gif`: a GIF image.
  static const imageGif = 'image/gif';

  /// `image/jpeg`: a JPEG image.
  static const imageJpeg = 'image/jpeg';

  /// `image/png`: a PNG image.
  static const imagePng = 'image/png';

  /// `multipart/form-data`: an HTML form with files; read with
  /// `@RequestPart`.
  static const multipartFormData = 'multipart/form-data';

  /// `multipart/mixed`: several bodies of different types in one.
  static const multipartMixed = 'multipart/mixed';

  /// `multipart/related`: a document with the parts it refers to.
  static const multipartRelated = 'multipart/related';

  /// `text/event-stream`: server-sent events, a stream of messages from
  /// the server.
  static const textEventStream = 'text/event-stream';

  /// `text/html`: an HTML page.
  static const textHtml = 'text/html';

  /// `text/markdown`: Markdown text.
  static const textMarkdown = 'text/markdown';

  /// `text/plain`: plain text.
  static const textPlain = 'text/plain';

  /// `text/xml`: XML, as text.
  static const textXml = 'text/xml';

  /// The primary type, in lower case: `application` in
  /// `application/json`, or `*`.
  final String type;

  /// The subtype, in lower case: `problem+json` in
  /// `application/problem+json`, or `*`.
  final String subtype;

  /// The parameters with names and values as written, such as
  /// `{charset: UTF-8}`; unmodifiable. Use [getParameter] to look one up
  /// regardless of case.
  final Map<String, String> parameters;

  /// The value of the parameter [name], found regardless of case and
  /// without its quotes; `null` when there is none.
  String? getParameter(String name) {
    for (final MapEntry(:key, :value) in parameters.entries) {
      if (key.toLowerCase() == name.toLowerCase()) {
        return _unquote(value);
      }
    }
    return null;
  }

  /// The `dart:convert` encoding named by the `charset` parameter, such as
  /// `latin1` for `ISO-8859-1`; `null` without one, or for a charset Dart
  /// does not know.
  Encoding? get charset => switch (getParameter('charset')) {
    final name? => Encoding.getByName(name),
    null => null,
  };

  /// The quality of this type in an `Accept` list (its `q` parameter,
  /// from 0 to 1); `1.0` without one.
  double get qualityValue => switch (getParameter('q')) {
    final value? => double.parse(value),
    null => 1.0,
  };

  /// Whether the type is `*`, which only `*/*` has.
  bool get isWildcardType => type == wildcardType;

  /// Whether the subtype is `*` (`text/*`) or `*+suffix`
  /// (`application/*+json`).
  bool get isWildcardSubtype =>
      subtype == wildcardType || subtype.startsWith('*+');

  /// Whether neither type nor subtype is a wildcard: a type a body can
  /// actually have.
  bool get isConcrete => !isWildcardType && !isWildcardSubtype;

  /// The structure suffix of the subtype, after its last `+`: `json` for
  /// `problem+json`; `null` without one.
  String? get subtypeSuffix {
    final plus = subtype.lastIndexOf('+');
    return plus < 0 || plus == subtype.length - 1
        ? null
        : subtype.substring(plus + 1);
  }

  /// Whether every body of type [other] is also of this type: `*/*`
  /// includes everything, `text/*` includes `text/plain`, and
  /// `application/*+json` includes `application/problem+json`. One-way:
  /// `text/plain` does not include `text/*`. Parameters are ignored. A
  /// server uses it to check a request's `Content-Type` against
  /// `consumes`.
  bool includes(MediaType other) {
    if (isWildcardType) {
      return true;
    }
    if (type != other.type) {
      return false;
    }
    if (subtype == other.subtype) {
      return true;
    }
    if (!isWildcardSubtype) {
      return false;
    }
    final plus = subtype.lastIndexOf('+');
    if (plus < 0) {
      return true;
    }
    final otherPlus = other.subtype.lastIndexOf('+');
    return otherPlus >= 0 &&
        subtype.substring(0, plus) == wildcardType &&
        subtype.substring(plus + 1) == other.subtype.substring(otherPlus + 1);
  }

  /// Whether this media type and [other] can describe the same body: one
  /// includes the other, in either direction (`text/*` and `text/plain`
  /// are compatible both ways). Parameters are ignored. A server uses it
  /// to match `produces` against the request's `Accept`.
  bool isCompatibleWith(MediaType other) {
    if (isWildcardType || other.isWildcardType) {
      return true;
    }
    if (type != other.type) {
      return false;
    }
    if (subtype == other.subtype) {
      return true;
    }
    if (!isWildcardSubtype && !other.isWildcardSubtype) {
      return false;
    }
    final suffix = subtypeSuffix;
    final otherSuffix = other.subtypeSuffix;
    if (subtype == wildcardType || other.subtype == wildcardType) {
      return true;
    }
    if (isWildcardSubtype && suffix != null) {
      return suffix == other.subtype || suffix == otherSuffix;
    }
    if (other.isWildcardSubtype && otherSuffix != null) {
      return subtype == otherSuffix || otherSuffix == suffix;
    }
    return false;
  }

  /// Whether [other] has the same type and subtype, whatever the
  /// parameters: `text/plain;charset=UTF-8` and `text/plain` match.
  bool equalsTypeAndSubtype(MediaType other) =>
      type == other.type && subtype == other.subtype;

  /// A copy with [parameters] instead of the current ones, such as
  /// `type.withParameters({'charset': 'UTF-8'})`.
  MediaType withParameters(Map<String, String> parameters) =>
      MediaType(type, subtype, parameters);

  /// Whether [other] has the same type, subtype and parameters, comparing
  /// parameter names and the `charset` value regardless of case. Use
  /// [equalsTypeAndSubtype] to ignore the parameters.
  @override
  bool operator ==(Object other) =>
      other is MediaType &&
      equalsTypeAndSubtype(other) &&
      _normalized(parameters).toString() ==
          _normalized(other.parameters).toString();

  @override
  int get hashCode =>
      Object.hash(type, subtype, _normalized(parameters).toString());

  /// The media type as a header value: `type/subtype;name=value`.
  @override
  String toString() => [
    '$type/$subtype',
    for (final MapEntry(:key, :value) in parameters.entries) '$key=$value',
  ].join(';');

  static Map<String, String> _normalized(Map<String, String> parameters) {
    final keys = [for (final key in parameters.keys) key.toLowerCase()]..sort();
    final lower = {
      for (final MapEntry(:key, :value) in parameters.entries)
        key.toLowerCase(): key.toLowerCase() == 'charset'
            ? _unquote(value).toLowerCase()
            : value,
    };
    return {for (final key in keys) key: lower[key]!};
  }

  static String _unquote(String value) =>
      _isQuoted(value) ? value.substring(1, value.length - 1) : value;

  static Map<String, String> _checkParameters(Map<String, String> values) {
    final checked = <String, String>{};
    for (final MapEntry(key: name, :value) in values.entries) {
      if (name.isEmpty) {
        throw InvalidMediaTypeException(
          '$name=$value',
          "'parameter' must not be empty",
        );
      }
      if (value.isEmpty) {
        throw InvalidMediaTypeException(
          '$name=$value',
          "'value' must not be empty",
        );
      }
      _checkToken(name, 'parameter name');
      if (name.toLowerCase() == 'charset') {
        final charset = _unquote(value);
        if (!_charsetName.hasMatch(charset)) {
          throw InvalidMediaTypeException(
            '$name=$value',
            'unsupported charset "$charset"',
          );
        }
      } else if (!_isQuoted(value)) {
        _checkToken(value, 'parameter value');
      }
      checked
        ..removeWhere((key, _) => key.toLowerCase() == name.toLowerCase())
        ..[name] = value;
    }
    return checked;
  }

  // java.nio.charset.Charset's legal names.
  static final _charsetName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9\-+:_.]*$');

  static bool _isQuoted(String value) =>
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")));

  // RFC 7230 token characters.
  static final _token = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

  static String _checkToken(String value, String what) {
    if (!_token.hasMatch(value)) {
      throw InvalidMediaTypeException(value, 'invalid token in $what');
    }
    return value;
  }

  // Splits [value] at [separator] outside of quoted strings.
  static List<String> _split(String value, String separator) {
    final parts = <String>[];
    var quoted = false;
    var start = 0;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char == '"' && (i == 0 || value[i - 1] != r'\')) {
        quoted = !quoted;
      } else if (char == separator && !quoted) {
        parts.add(value.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(value.substring(start));
    return parts;
  }
}

/// The error thrown by [MediaType.parse] and the [MediaType] constructor
/// for text that is not a valid media type.
///
/// It is an `ArgumentError`. The web server does not let it escape: it
/// treats an invalid `Content-Type` or `Accept` of a request as missing,
/// and reports an invalid `produces` or `consumes` of a mapping at
/// startup.
///
/// Spring (Java): `InvalidMediaTypeException`.
final class InvalidMediaTypeException extends ArgumentError {
  /// The text [mediaType] is invalid because of [reason].
  InvalidMediaTypeException(this.mediaType, this.reason)
    : super('Invalid media type "$mediaType": $reason');

  /// The text that could not be read.
  final String mediaType;

  /// Why it is invalid, such as `does not contain "/"`.
  final String reason;
}
