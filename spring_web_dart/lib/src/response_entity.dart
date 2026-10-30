import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';

/// An HTTP response as a value: a status code, headers and an optional
/// body.
///
/// A controller method normally returns just the body, and the server
/// answers `200 OK` with it. Return a `ResponseEntity` instead when the
/// status or the headers depend on what happened: `201 Created` with a
/// `Location` header, `404 Not Found` when nothing was found, an `ETag`
/// for caching. Build one with the shortcuts ([ResponseEntity.ok],
/// [created], [notFound], [status], ...). In the other direction, a Feign
/// client method declared to return `Future<ResponseEntity<Book>>` gives
/// the caller the status and headers of the answer next to the decoded
/// body. The client still throws a `FeignException` for an error status
/// (unless the client dismisses 404s, which then come back as a 404
/// entity without a body).
///
/// ```dart
/// // A controller: 201 Created, with the address of the new book.
/// @PostMapping('/books')
/// Future<ResponseEntity<Book>> create(@RequestBody() Book book) async {
///   final saved = await books.save(book);
///   return ResponseEntity.created(Uri.parse('/books/${saved.isbn}'))
///       .body(saved);
/// }
///
/// // 200 with the book, or 404 without a body.
/// @GetMapping('/books/{isbn}')
/// Future<ResponseEntity<Book>> find(@PathVariable() String isbn) async =>
///     ResponseEntity.ofNullable(await books.findOrNull(isbn));
///
/// // A Feign client returning ResponseEntity<Book> for the same call:
/// // the caller learns where the book was stored.
/// final response = await catalog.create(book);
/// log.info(response.headers.location); // /books/978-0
/// ```
///
/// Spring (Java):
/// ```java
/// @PostMapping("/books")
/// ResponseEntity<Book> create(@RequestBody Book book) {
///   Book saved = books.save(book);
///   return ResponseEntity.created(URI.create("/books/" + saved.isbn()))
///       .body(saved);
/// }
///
/// @GetMapping("/books/{isbn}")
/// ResponseEntity<Book> find(@PathVariable String isbn) {
///   return ResponseEntity.of(books.findById(isbn));
/// }
/// ```
class ResponseEntity<T> {
  /// A response with [statusCode], [body] and [headers]. Throws an
  /// [ArgumentError] unless [statusCode] has three digits (100–999).
  ///
  /// The entity's [headers] are a read-only view of the [headers] given
  /// here: they cannot be changed through the entity, but later changes
  /// to the object passed in show through. The builders ([status],
  /// [created], ...) are usually shorter.
  ResponseEntity(int statusCode, {this.body, HttpHeaders? headers})
    : statusCode = HttpStatusCode.valueOf(statusCode),
      headers = HttpHeaders.readOnly(headers ?? HttpHeaders());

  /// A `200 OK` response with [body] and no headers: the same as
  /// returning [body] itself from a controller.
  ResponseEntity.ok(T this.body)
    : statusCode = HttpStatus.ok,
      headers = HttpHeaders.readOnly(HttpHeaders());

  /// `200 OK` with [body], or `404 Not Found` without a body when [body]
  /// is `null`; for a lookup that may find nothing. The same as
  /// [ofNullable]; it mirrors Spring's `ResponseEntity.of(Optional)`, and
  /// a nullable value stands for the `Optional`.
  static ResponseEntity<T> of<T>(T? body) => ofNullable(body);

  /// `200 OK` with [body], or `404 Not Found` without a body when [body]
  /// is `null`; for a lookup that may find nothing.
  static ResponseEntity<T> ofNullable<T>(T? body) => body == null
      ? ResponseEntity<T>(HttpStatus.notFound)
      : ResponseEntity<T>(HttpStatus.ok, body: body);

  /// A builder for a response with any [statusCode]; throws an
  /// [ArgumentError] unless it is between 100 and 999. Use it for the
  /// statuses without a shortcut here (`409 Conflict`, `304 Not
  /// Modified`, ...).
  static ResponseEntityBuilder status(int statusCode) =>
      ResponseEntityBuilder._(statusCode);

  /// A builder for a `201 Created` response, with [location], the address
  /// of the new resource, in the `Location` header.
  static ResponseEntityBuilder created(Uri location) =>
      ResponseEntityBuilder._(HttpStatus.created)..location(location);

  /// A builder for a `202 Accepted` response: the request was taken but
  /// is processed later.
  static ResponseEntityBuilder accepted() =>
      ResponseEntityBuilder._(HttpStatus.accepted);

  /// A builder for a `204 No Content` response: success, with no body.
  static ResponseEntityBuilder noContent() =>
      ResponseEntityBuilder._(HttpStatus.noContent);

  /// A builder for a `400 Bad Request` response: the request itself is
  /// wrong.
  static ResponseEntityBuilder badRequest() =>
      ResponseEntityBuilder._(HttpStatus.badRequest);

  /// A builder for a `404 Not Found` response; usually finished with
  /// `build()`.
  static ResponseEntityBuilder notFound() =>
      ResponseEntityBuilder._(HttpStatus.notFound);

  /// A builder for a `422 Unprocessable Content` response: the request is
  /// well formed but its content cannot be processed.
  static ResponseEntityBuilder unprocessableContent() =>
      ResponseEntityBuilder._(HttpStatus.unprocessableContent);

  /// A builder for a `500 Internal Server Error` response.
  static ResponseEntityBuilder internalServerError() =>
      ResponseEntityBuilder._(HttpStatus.internalServerError);

  /// The status code: an `int` that also has checks such as
  /// `is2xxSuccessful`, and compares with the [HttpStatus] constants.
  final HttpStatusCode statusCode;

  /// The body, or `null` when the response has none.
  final T? body;

  /// The response headers; read-only.
  final HttpHeaders headers;

  /// Whether [body] is not `null`.
  bool get hasBody => body != null;

  /// Whether the status is a success (2xx).
  bool get isSuccess => statusCode.is2xxSuccessful;

  /// Whether [other] has the same status code, headers and body. Lists,
  /// maps and sets in the body are compared by content, so an entity
  /// decoded from JSON equals one built by hand in a test.
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

/// The builder returned by [ResponseEntity.status], [ResponseEntity.created]
/// and the other shortcuts: the status is set, headers are added one by
/// one, and [body] or [build] makes the [ResponseEntity].
///
/// It saves building an [HttpHeaders] object by hand when a response
/// needs a header or two. Each header method returns the builder, so the
/// calls chain.
///
/// ```dart
/// // An image with caching headers, so browsers can revalidate it.
/// @GetMapping('/books/{isbn}/cover')
/// Future<ResponseEntity<Uint8List>> cover(@PathVariable() String isbn) async {
///   final cover = await covers.find(isbn);
///   return ResponseEntity.status(HttpStatus.ok)
///       .contentType(MediaType.imagePng)
///       .eTag(cover.hash)
///       .lastModified(cover.updatedAt)
///       .body(cover.bytes);
/// }
/// ```
///
/// Spring (Java): `ResponseEntity.BodyBuilder`.
/// ```java
/// return ResponseEntity.status(HttpStatus.OK)
///     .contentType(MediaType.IMAGE_PNG)
///     .eTag(cover.hash())
///     .lastModified(cover.updatedAt())
///     .body(cover.bytes());
/// ```
final class ResponseEntityBuilder {
  ResponseEntityBuilder._(int statusCode)
    : _statusCode = HttpStatusCode.valueOf(statusCode);

  final int _statusCode;
  final _headers = HttpHeaders();

  /// Adds [values] to the header [name], after any values it already
  /// has: `.header('Cache-Control', ['no-store'])`.
  ResponseEntityBuilder header(String name, List<String> values) {
    for (final value in values) {
      _headers.add(name, value);
    }
    return this;
  }

  /// Copies every header of [headers]; a name already set on the builder
  /// gets the new values instead of its old ones.
  ResponseEntityBuilder headers(HttpHeaders headers) {
    _headers.putAll(headers);
    return this;
  }

  /// Sets the `Location` header: where the new or moved resource is.
  ResponseEntityBuilder location(Uri location) {
    _headers.location = location;
    return this;
  }

  /// Sets the `Content-Type` header, such as `MediaType.applicationJson`.
  /// Without it, the server picks the type from the body and the
  /// request's `Accept` header.
  ResponseEntityBuilder contentType(String mediaType) {
    _headers.contentType = mediaType;
    return this;
  }

  /// Sets the `ETag` header, a version tag of the body for caching; [tag]
  /// is put in quotes unless it already is (`W/"..."` included). The web
  /// server answers a `GET` or `HEAD` whose `If-None-Match` has the tag
  /// with a 304 and no body, when the status is 200 (Spring's
  /// `HttpEntityMethodProcessor`).
  ResponseEntityBuilder eTag(String tag) {
    _headers.eTag = tag;
    return this;
  }

  /// Sets the `Last-Modified` header, written as an HTTP date in UTC. The
  /// web server answers a `GET` or `HEAD` with an `If-Modified-Since` at
  /// or after it (and no `If-None-Match`) with a 304, and one with an
  /// `If-Unmodified-Since` before it with a 412, when the status is 200.
  ResponseEntityBuilder lastModified(DateTime date) {
    _headers.lastModified = date;
    return this;
  }

  /// Finishes the response with [body]; `T` is usually inferred from the
  /// method's return type.
  ResponseEntity<T> body<T>(T? body) =>
      ResponseEntity<T>(_statusCode, body: body, headers: _headers.copy());

  /// Finishes the response without a body; write `build<Book>()` when
  /// `T` cannot be inferred.
  ResponseEntity<T> build<T>() =>
      ResponseEntity<T>(_statusCode, headers: _headers.copy());
}
