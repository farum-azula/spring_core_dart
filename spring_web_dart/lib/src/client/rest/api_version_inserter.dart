import 'package:spring_web_dart/src/client/rest/request_values.dart';
import 'package:spring_web_dart/src/client/rest/uri_template.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/media_type.dart';

/// Turns the API version of a call (`Object`, a `String` such as `'1.2'`
/// mostly) into the text the request carries; `toString()` by default.
///
/// Spring (Java): `org.springframework.web.client.ApiVersionFormatter`.
typedef ApiVersionFormatter = String Function(Object version);

/// Puts the API version of a call into its request: a header, a query
/// parameter, a path segment or a parameter of the `Content-Type`. A
/// `RestClient` built with one sends its `defaultApiVersion`, or the
/// `apiVersion(...)` of a call, through it; a call with a version on a
/// client without one fails with a [StateError], as in Spring.
///
/// ```dart
/// final rest = RestClient.builder()
///     .baseUrl('https://api.neon.books')
///     .apiVersionInserter(ApiVersionInserter.useHeader('API-Version'))
///     .defaultApiVersion('1.2')
///     .build();
///
/// await rest.get().uri('/books').retrieve().body<String>(); // API-Version: 1.2
/// await rest.get().uri('/books').apiVersion('2.0').retrieve().body<String>();
/// ```
///
/// Several places at once, or a formatter, through [builder]:
///
/// ```dart
/// ApiVersionInserter.builder()
///     .useQueryParam('version')
///     .withVersionFormatter((version) => 'v$version')
///     .build();
/// ```
///
/// An application's own inserter extends this class and overrides
/// [insertVersionIntoUri], [insertVersionIntoHeaders] or both; each leaves
/// the request as it is by default.
///
/// Spring (Java): `org.springframework.web.client.ApiVersionInserter`,
/// whose two `insertVersion` overloads are [insertVersionIntoUri] and
/// [insertVersionIntoHeaders] here:
/// ```java
/// RestClient.builder()
///     .apiVersionInserter(ApiVersionInserter.useHeader("API-Version"))
///     .defaultApiVersion("1.2")
///     .build();
/// ```
abstract class ApiVersionInserter {
  /// An inserter that changes nothing; for a subclass.
  const ApiVersionInserter();

  /// An inserter that sets the header [header] to the version.
  ///
  /// Spring (Java): `ApiVersionInserter.useHeader(String)`.
  factory ApiVersionInserter.useHeader(String header) =>
      ApiVersionInserterBuilder().useHeader(header).build();

  /// An inserter that adds the query parameter [queryParam] with the
  /// version.
  ///
  /// Spring (Java): `ApiVersionInserter.useQueryParam(String)`.
  factory ApiVersionInserter.useQueryParam(String queryParam) =>
      ApiVersionInserterBuilder().useQueryParam(queryParam).build();

  /// An inserter that inserts the version as the path segment number
  /// [pathSegmentIndex] (from 0): with 0, `/books/1` becomes
  /// `/1.2/books/1`.
  ///
  /// Spring (Java): `ApiVersionInserter.usePathSegment(Integer)`.
  factory ApiVersionInserter.usePathSegment(int pathSegmentIndex) =>
      ApiVersionInserterBuilder().usePathSegment(pathSegmentIndex).build();

  /// An inserter that adds the parameter [mediaTypeParam] with the version
  /// to the `Content-Type` of the request, when it has one
  /// (`application/json;v=1.2`).
  ///
  /// Spring (Java): `ApiVersionInserter.useMediaTypeParam(String)`.
  factory ApiVersionInserter.useMediaTypeParam(String mediaTypeParam) =>
      ApiVersionInserterBuilder().useMediaTypeParam(mediaTypeParam).build();

  /// A builder for an inserter that uses several places, or a formatter.
  ///
  /// Spring (Java): `ApiVersionInserter.builder()`.
  static ApiVersionInserterBuilder builder() => ApiVersionInserterBuilder();

  /// [uri] with [version] in it; [uri] as it is by default.
  ///
  /// Spring (Java): `insertVersion(Object, URI)`.
  Uri insertVersionIntoUri(Object version, Uri uri) => uri;

  /// Puts [version] into [headers]; changes nothing by default.
  ///
  /// Spring (Java): `insertVersion(Object, HttpHeaders)`.
  void insertVersionIntoHeaders(Object version, HttpHeaders headers) {}
}

/// Builds the built-in [ApiVersionInserter]: one or more places for the
/// version, and how it is written.
///
/// Spring (Java): `ApiVersionInserter.Builder`.
final class ApiVersionInserterBuilder {
  /// A builder with no place set yet.
  ApiVersionInserterBuilder();

  String? _header;
  String? _queryParam;
  String? _mediaTypeParam;
  int? _pathSegmentIndex;
  ApiVersionFormatter? _formatter;

  /// Sets the header [header] to the version.
  ApiVersionInserterBuilder useHeader(String? header) {
    if (header != null) {
      checkHeader(header, '');
    }
    _header = header;
    return this;
  }

  /// Adds the query parameter [queryParam] with the version.
  ApiVersionInserterBuilder useQueryParam(String? queryParam) {
    _queryParam = queryParam;
    return this;
  }

  /// Adds the parameter [param] with the version to the `Content-Type`.
  ApiVersionInserterBuilder useMediaTypeParam(String? param) {
    _mediaTypeParam = param;
    return this;
  }

  /// Inserts the version as the path segment number [pathSegmentIndex].
  ApiVersionInserterBuilder usePathSegment(int? pathSegmentIndex) {
    if (pathSegmentIndex != null && pathSegmentIndex < 0) {
      throw ArgumentError.value(
        pathSegmentIndex,
        'pathSegmentIndex',
        'must not be negative',
      );
    }
    _pathSegmentIndex = pathSegmentIndex;
    return this;
  }

  /// Writes the version with [formatter] instead of `toString()`.
  ApiVersionInserterBuilder withVersionFormatter(
    ApiVersionFormatter formatter,
  ) {
    _formatter = formatter;
    return this;
  }

  /// The inserter. Throws an [ArgumentError] when no place is set.
  ApiVersionInserter build() {
    if (_header == null &&
        _queryParam == null &&
        _mediaTypeParam == null &&
        _pathSegmentIndex == null) {
      throw ArgumentError(
        "Expected 'header', 'queryParam', 'mediaTypeParam', or "
        "'pathSegmentIndex' to be configured",
      );
    }
    return _DefaultApiVersionInserter(
      header: _header,
      queryParam: _queryParam,
      mediaTypeParam: _mediaTypeParam,
      pathSegmentIndex: _pathSegmentIndex,
      formatter: _formatter,
    );
  }
}

final class _DefaultApiVersionInserter extends ApiVersionInserter {
  const _DefaultApiVersionInserter({
    required this.header,
    required this.queryParam,
    required this.mediaTypeParam,
    required this.pathSegmentIndex,
    required this.formatter,
  });

  final String? header;
  final String? queryParam;
  final String? mediaTypeParam;
  final int? pathSegmentIndex;
  final ApiVersionFormatter? formatter;

  String _format(Object version) => formatter?.call(version) ?? '$version';

  @override
  Uri insertVersionIntoUri(Object version, Uri uri) {
    final queryParam = this.queryParam;
    final index = pathSegmentIndex;
    if (queryParam == null && index == null) {
      return uri;
    }
    final text = _format(version);
    var result = uri;
    if (index != null) {
      final path = result.path;
      final segments = [
        for (final segment in path.split('/'))
          if (segment.isNotEmpty) segment,
      ];
      if (index > segments.length) {
        throw StateError(
          "Cannot insert version into '$path' at path segment index $index",
        );
      }
      segments.insert(
        index,
        UriTemplate.encodeAllowing(text, UriTemplate.isPathCharacter),
      );
      final trailing = path.endsWith('/') && segments.length > 1 ? '/' : '';
      result = result.replace(path: '/${segments.join('/')}$trailing');
    }
    if (queryParam != null) {
      final pair =
          '${Uri.encodeQueryComponent(queryParam)}='
          '${Uri.encodeQueryComponent(text)}';
      result = result.replace(
        query: result.hasQuery && result.query.isNotEmpty
            ? '${result.query}&$pair'
            : pair,
      );
    }
    return result;
  }

  @override
  void insertVersionIntoHeaders(Object version, HttpHeaders headers) {
    final header = this.header;
    final param = mediaTypeParam;
    if (header == null && param == null) {
      return;
    }
    final text = _format(version);
    if (header != null) {
      checkHeader(header, text);
      headers.set(header, text);
    }
    if (param != null) {
      final contentType = headers.contentType;
      if (contentType != null) {
        final type = MediaType.parse(contentType);
        final value = type.withParameters({
          ...type.parameters,
          param: text,
        }).toString();
        checkHeader(HttpHeaders.contentTypeHeader, value);
        headers.contentType = value;
      }
    }
  }
}
