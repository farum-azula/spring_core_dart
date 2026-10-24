import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';

/// A response with its status code and headers, not only the body, like
/// Spring's `ResponseEntity`. A Feign client method returning
/// `Future<ResponseEntity<Book>>` gets all three.
///
/// ```dart
/// final response = await catalog.create(book); // ResponseEntity<Book>
/// if (response.statusCode == HttpStatus.created) {
///   print(response.headers.location);
///   print(response.body!.title);
/// }
/// response.statusCode.is2xxSuccessful; // true
/// ResponseEntity.ok(book);
/// ResponseEntity.created(Uri.parse('/books/1')).body(book);
/// ResponseEntity.notFound().build<Book>();
/// ```
///
/// Spring (Java):
/// ```java
/// ResponseEntity<Book> response = catalog.create(book);
/// response.getStatusCode(); response.getHeaders().getLocation(); response.getBody();
/// response.getStatusCode().is2xxSuccessful();
/// ResponseEntity.ok(book);
/// ResponseEntity.created(URI.create("/books/1")).body(book);
/// ResponseEntity.notFound().build();
/// ```
class ResponseEntity<T> {
  /// A response with [statusCode], [body] and [headers]; [headers] are
  /// read-only from here on, like Spring's `HttpEntity`. Throws an
  /// [ArgumentError] unless [statusCode] has three digits (100–999), like
  /// Spring's `HttpStatusCode.valueOf`.
  ResponseEntity(int statusCode, {this.body, HttpHeaders? headers})
    : statusCode = HttpStatusCode.valueOf(statusCode),
      headers = HttpHeaders.readOnly(headers ?? HttpHeaders());

  /// A `200 OK` response with [body].
  ResponseEntity.ok(T this.body)
    : statusCode = HttpStatus.ok,
      headers = HttpHeaders.readOnly(HttpHeaders());

  /// `200 OK` with [body], or `404 Not Found` without a body when [body]
  /// is `null`, like Spring's `ResponseEntity.of(Optional)` (Dart has no
  /// `Optional`: a nullable body stands for it).
  static ResponseEntity<T> of<T>(T? body) => ofNullable(body);

  /// `200 OK` with [body], or `404 Not Found` without a body when [body]
  /// is `null`, like Spring's `ResponseEntity.ofNullable`.
  static ResponseEntity<T> ofNullable<T>(T? body) => body == null
      ? ResponseEntity<T>(HttpStatus.notFound)
      : ResponseEntity<T>(HttpStatus.ok, body: body);

  /// A builder for a response with [statusCode] (100–999, an
  /// [ArgumentError] otherwise), like Spring's `ResponseEntity.status(...)`.
  static ResponseEntityBuilder status(int statusCode) =>
      ResponseEntityBuilder._(statusCode);

  /// A builder for a `201 Created` response with the `Location`
  /// [location], like Spring's `ResponseEntity.created(uri)`.
  static ResponseEntityBuilder created(Uri location) =>
      ResponseEntityBuilder._(HttpStatus.created)..location(location);

  /// A builder for a `202 Accepted` response.
  static ResponseEntityBuilder accepted() =>
      ResponseEntityBuilder._(HttpStatus.accepted);

  /// A builder for a `204 No Content` response.
  static ResponseEntityBuilder noContent() =>
      ResponseEntityBuilder._(HttpStatus.noContent);

  /// A builder for a `400 Bad Request` response.
  static ResponseEntityBuilder badRequest() =>
      ResponseEntityBuilder._(HttpStatus.badRequest);

  /// A builder for a `404 Not Found` response.
  static ResponseEntityBuilder notFound() =>
      ResponseEntityBuilder._(HttpStatus.notFound);

  /// A builder for a `422 Unprocessable Content` response.
  static ResponseEntityBuilder unprocessableContent() =>
      ResponseEntityBuilder._(HttpStatus.unprocessableContent);

  /// A builder for a `500 Internal Server Error` response.
  static ResponseEntityBuilder internalServerError() =>
      ResponseEntityBuilder._(HttpStatus.internalServerError);

  /// The status code (an `int` with `is2xxSuccessful`, ...), like
  /// Spring's `getStatusCode()`.
  final HttpStatusCode statusCode;

  /// The body, if any.
  final T? body;

  /// The headers.
  final HttpHeaders headers;

  /// Whether there is a body, like Spring's `hasBody()`.
  bool get hasBody => body != null;

  /// Whether the status is 2xx.
  bool get isSuccess => statusCode.is2xxSuccessful;

  /// The same status code, headers and body, like Spring's `equals`.
  @override
  bool operator ==(Object other) =>
      other is ResponseEntity &&
      other.statusCode == statusCode &&
      other.headers == headers &&
      _equalBodies(other.body, body);

  @override
  int get hashCode => Object.hash(statusCode, headers, _bodyHash(body));

  static bool _equalBodies(Object? a, Object? b) => switch ((a, b)) {
    (final List<Object?> a, final List<Object?> b) =>
      a.length == b.length &&
          [for (var i = 0; i < a.length; i++) i]
              .every((i) => _equalBodies(a[i], b[i])),
    (final Map<Object?, Object?> a, final Map<Object?, Object?> b) =>
      a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && _equalBodies(a[key], b[key]),
          ),
    (final Set<Object?> a, final Set<Object?> b) =>
      a.length == b.length && a.containsAll(b),
    _ => a == b,
  };

  static int _bodyHash(Object? body) => switch (body) {
    final List<Object?> list => Object.hashAll(list.map(_bodyHash)),
    final Map<Object?, Object?> map => Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in map.entries)
        Object.hash(key, _bodyHash(value)),
    ]),
    final Set<Object?> set => Object.hashAllUnordered(set),
    _ => body.hashCode,
  };

  @override
  String toString() =>
      'ResponseEntity($statusCode${_phrase(statusCode)}'
      '${body == null ? '' : ', $body'})';

  static String _phrase(int code) => switch (HttpStatus.resolve(code)) {
    final status? => ' ${status.reasonPhrase}',
    null => '',
  };
}

/// Builds a [ResponseEntity], like Spring's `ResponseEntity.BodyBuilder`
/// (from [ResponseEntity.status], [ResponseEntity.created], ...): set
/// headers, then finish with [body] or [build].
///
/// ```dart
/// ResponseEntity.status(HttpStatus.created)
///     .header('X-Id', '1')
///     .contentType(MediaType.applicationJson)
///     .body(book);
/// ```
final class ResponseEntityBuilder {
  ResponseEntityBuilder._(int statusCode)
    : _statusCode = HttpStatusCode.valueOf(statusCode);

  final int _statusCode;
  final _headers = HttpHeaders();

  /// Adds [values] to header [name].
  ResponseEntityBuilder header(String name, List<String> values) {
    for (final value in values) {
      _headers.add(name, value);
    }
    return this;
  }

  /// Sets every header of [headers], replacing the values of those names,
  /// like Spring's `headers(HttpHeaders)` (`putAll`).
  ResponseEntityBuilder headers(HttpHeaders headers) {
    _headers.putAll(headers);
    return this;
  }

  /// Sets the `Location`.
  ResponseEntityBuilder location(Uri location) {
    _headers.location = location;
    return this;
  }

  /// Sets the `Content-Type`.
  ResponseEntityBuilder contentType(String mediaType) {
    _headers.contentType = mediaType;
    return this;
  }

  /// Sets the `ETag` (quoted unless it already is).
  ResponseEntityBuilder eTag(String tag) {
    _headers.eTag = tag;
    return this;
  }

  /// Sets `Last-Modified`.
  ResponseEntityBuilder lastModified(DateTime date) {
    _headers.lastModified = date;
    return this;
  }

  /// The response with [body].
  ResponseEntity<T> body<T>(T? body) =>
      ResponseEntity<T>(_statusCode, body: body, headers: _headers.copy());

  /// The response without a body.
  ResponseEntity<T> build<T>() =>
      ResponseEntity<T>(_statusCode, headers: _headers.copy());
}
