import 'dart:convert';

/// A media type such as `application/json;charset=UTF-8`, like Spring's
/// `MediaType`: [parse] reads one, [includes] and [isCompatibleWith]
/// compare them (wildcards and `+json`-style suffixes included).
///
/// The static constants are the media types as `String`s (Spring's
/// `..._VALUE` constants), so they work in annotations:
///
/// ```dart
/// headers.set(HttpHeaders.contentTypeHeader, MediaType.applicationJson);
/// @PostMapping.of(path: '/books', consumes: MediaType.applicationJson)
///
/// final type = MediaType.parse('application/problem+json');
/// MediaType.parse('application/*+json').includes(type);       // true
/// type.isCompatibleWith(MediaType.parse(MediaType.all));      // true
/// MediaType.parse('text/plain;charset=ISO-8859-1').charset;   // latin1
/// ```
///
/// Spring (Java):
/// ```java
/// headers.setContentType(MediaType.APPLICATION_JSON);
/// @PostMapping(path = "/books", consumes = MediaType.APPLICATION_JSON_VALUE)
///
/// MediaType type = MediaType.parseMediaType("application/problem+json");
/// MediaType.parseMediaType("application/*+json").includes(type);
/// type.isCompatibleWith(MediaType.ALL);
/// ```
final class MediaType {
  /// The media type [type]/[subtype] with [parameters]; type and subtype
  /// are lower-cased, like Spring.
  MediaType(
    String type, [
    String subtype = wildcardType,
    Map<String, String> parameters = const {},
  ]) : type = _checkToken(type.toLowerCase(), 'type'),
       subtype = _checkToken(subtype.toLowerCase(), 'subtype'),
       parameters = Map.unmodifiable(parameters) {
    if (this.type == wildcardType && this.subtype != wildcardType) {
      throw InvalidMediaTypeException(
        toString(),
        'wildcard type is legal only in "*/*" (all media types)',
      );
    }
    final quality = parameters.entries
        .where((entry) => entry.key.toLowerCase() == 'q')
        .map((entry) => entry.value)
        .firstOrNull;
    if (quality != null) {
      final value = double.tryParse(_unquote(quality));
      if (value == null || value < 0 || value > 1) {
        throw InvalidMediaTypeException(
          toString(),
          'invalid quality value "$quality": should be between 0.0 and 1.0',
        );
      }
    }
  }

  /// Reads [value], e.g. `application/json`, `text/plain; charset=UTF-8`
  /// or `*` (`*/*`), like Spring's `MediaType.parseMediaType`. Throws an
  /// [InvalidMediaTypeException] for an invalid one.
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
    final parameters = <String, String>{};
    for (final part in parts.skip(1)) {
      final parameter = part.trim();
      if (parameter.isEmpty) {
        continue;
      }
      final eq = parameter.indexOf('=');
      if (eq <= 0) {
        throw InvalidMediaTypeException(
          value,
          'parameter "$parameter" has no "="',
        );
      }
      parameters[parameter.substring(0, eq).trim()] = parameter
          .substring(eq + 1)
          .trim();
    }
    try {
      return MediaType(type, subtype, parameters);
    } on InvalidMediaTypeException catch (error) {
      throw InvalidMediaTypeException(value, error.reason);
    }
  }

  /// Reads a comma-separated list such as an `Accept` header, like
  /// Spring's `MediaType.parseMediaTypes`; empty for `null` or blank.
  static List<MediaType> parseMediaTypes(String? value) => [
    if (value != null)
      for (final part in _split(value, ','))
        if (part.trim().isNotEmpty) parse(part),
  ];

  /// `*`.
  static const wildcardType = '*';

  /// `*/*`.
  static const all = '*/*';

  /// `application/atom+xml`.
  static const applicationAtomXml = 'application/atom+xml';

  /// `application/cbor`.
  static const applicationCbor = 'application/cbor';

  /// `application/x-www-form-urlencoded`.
  static const applicationFormUrlencoded = 'application/x-www-form-urlencoded';

  /// `application/graphql-response+json`.
  static const applicationGraphqlResponse = 'application/graphql-response+json';

  /// `application/json`.
  static const applicationJson = 'application/json';

  /// `application/x-ndjson`: newline-delimited JSON.
  static const applicationNdjson = 'application/x-ndjson';

  /// `application/octet-stream`.
  static const applicationOctetStream = 'application/octet-stream';

  /// `application/pdf`.
  static const applicationPdf = 'application/pdf';

  /// `application/problem+json`: RFC 9457 problem details.
  static const applicationProblemJson = 'application/problem+json';

  /// `application/problem+xml`: RFC 9457 problem details.
  static const applicationProblemXml = 'application/problem+xml';

  /// `application/x-protobuf`.
  static const applicationProtobuf = 'application/x-protobuf';

  /// `application/rss+xml`.
  static const applicationRssXml = 'application/rss+xml';

  /// `application/xhtml+xml`.
  static const applicationXhtmlXml = 'application/xhtml+xml';

  /// `application/xml`.
  static const applicationXml = 'application/xml';

  /// `application/yaml`.
  static const applicationYaml = 'application/yaml';

  /// `image/gif`.
  static const imageGif = 'image/gif';

  /// `image/jpeg`.
  static const imageJpeg = 'image/jpeg';

  /// `image/png`.
  static const imagePng = 'image/png';

  /// `multipart/form-data`.
  static const multipartFormData = 'multipart/form-data';

  /// `multipart/mixed`.
  static const multipartMixed = 'multipart/mixed';

  /// `multipart/related`.
  static const multipartRelated = 'multipart/related';

  /// `text/event-stream`: server-sent events.
  static const textEventStream = 'text/event-stream';

  /// `text/html`.
  static const textHtml = 'text/html';

  /// `text/markdown`.
  static const textMarkdown = 'text/markdown';

  /// `text/plain`.
  static const textPlain = 'text/plain';

  /// `text/xml`.
  static const textXml = 'text/xml';

  /// The primary type, e.g. `application` (lower case).
  final String type;

  /// The subtype, e.g. `problem+json` (lower case).
  final String subtype;

  /// The parameters as written, e.g. `{charset: UTF-8}`.
  final Map<String, String> parameters;

  /// The value of parameter [name] (case-insensitive), unquoted; `null`
  /// when there is none.
  String? getParameter(String name) {
    for (final MapEntry(:key, :value) in parameters.entries) {
      if (key.toLowerCase() == name.toLowerCase()) {
        return _unquote(value);
      }
    }
    return null;
  }

  /// The encoding of the `charset` parameter, or `null` (also for one
  /// Dart does not know).
  Encoding? get charset => switch (getParameter('charset')) {
    final name? => Encoding.getByName(name),
    null => null,
  };

  /// The `q` parameter, `1.0` without one.
  double get qualityValue => switch (getParameter('q')) {
    final value? => double.parse(value),
    null => 1.0,
  };

  /// Whether the type is `*` (`*/*`).
  bool get isWildcardType => type == wildcardType;

  /// Whether the subtype is `*` or `*+suffix` (`application/*+json`).
  bool get isWildcardSubtype =>
      subtype == wildcardType || subtype.startsWith('*+');

  /// Whether neither type nor subtype is a wildcard.
  bool get isConcrete => !isWildcardType && !isWildcardSubtype;

  /// The suffix after the last `+` of the subtype (`json` of
  /// `problem+json`), or `null`.
  String? get subtypeSuffix {
    final plus = subtype.lastIndexOf('+');
    return plus < 0 || plus == subtype.length - 1
        ? null
        : subtype.substring(plus + 1);
  }

  /// Whether this media type includes [other], like Spring's `includes`:
  /// `*/*` includes everything, `text/*` includes `text/plain`,
  /// `application/*+json` includes `application/problem+json`; not
  /// symmetric (`text/plain` does not include `text/*`). Parameters are
  /// ignored.
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

  /// Whether this media type and [other] have something in common, like
  /// Spring's `isCompatibleWith`: [includes] in either direction
  /// (`text/*` and `text/plain` are compatible both ways). Parameters are
  /// ignored.
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

  /// Whether type and subtype are the same as those of [other]
  /// (parameters ignored), like Spring's `equalsTypeAndSubtype`.
  bool equalsTypeAndSubtype(MediaType other) =>
      type == other.type && subtype == other.subtype;

  /// A copy with [parameters] instead of the current ones.
  MediaType withParameters(Map<String, String> parameters) =>
      MediaType(type, subtype, parameters);

  /// Equal type, subtype and parameters (names case-insensitive, the
  /// `charset` value too), like Spring.
  @override
  bool operator ==(Object other) =>
      other is MediaType &&
      equalsTypeAndSubtype(other) &&
      _normalized(parameters).toString() ==
          _normalized(other.parameters).toString();

  @override
  int get hashCode =>
      Object.hash(type, subtype, _normalized(parameters).toString());

  /// `type/subtype;name=value`, like Spring.
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
      value.length >= 2 && value.startsWith('"') && value.endsWith('"')
      ? value.substring(1, value.length - 1)
      : value;

  // RFC 7230 token characters.
  static final _token = RegExp(r"^[!#$%&'*+\-.^_`|~0-9a-z]+$");

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

/// An invalid media type for [MediaType.parse], like Spring's
/// `InvalidMediaTypeException`.
final class InvalidMediaTypeException extends ArgumentError {
  /// [mediaType] is invalid because of [reason].
  InvalidMediaTypeException(this.mediaType, this.reason)
    : super('Invalid media type "$mediaType": $reason');

  /// The text that was parsed.
  final String mediaType;

  /// Why it is invalid.
  final String reason;
}
