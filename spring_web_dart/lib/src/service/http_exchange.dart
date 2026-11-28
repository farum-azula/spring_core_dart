import 'package:spring_web_dart/src/http_method.dart';

/// Declares an HTTP call on a method of an HTTP service interface, or the
/// settings every method of the interface shares when it is on the
/// interface: the URL (relative to the group's base URL), the method,
/// the `Content-Type` and `Accept`, headers and an API version.
///
/// The generator implements an interface imported by
/// `@ImportHttpServices` as direct `RestClient` calls of the interface's
/// group. The parameters say what goes where, as on a controller:
/// `@PathVariable`, `@RequestParam`, `@RequestHeader`, `@CookieValue`,
/// `@RequestBody`, `@RequestPart`. On a method, the shortcut annotations
/// ([GetExchange], [PostExchange], ...) are shorter; on the interface,
/// [url] is put before every method's and the other settings are the
/// methods' defaults.
///
/// ```dart
/// @HttpExchange('/books')
/// abstract interface class BookService {
///   @GetExchange('/{isbn}')
///   Future<Book> find(@PathVariable() String isbn);
///
///   @HttpExchange.of(url: '/{isbn}', method: HttpMethod.head)
///   Future<ResponseEntity<void>> exists(@PathVariable() String isbn);
/// }
/// ```
///
/// Spring (Java): `org.springframework.web.service.annotation.HttpExchange`:
/// ```java
/// @HttpExchange("/books")
/// interface BookService {
///   @GetExchange("/{isbn}")
///   Book find(@PathVariable String isbn);
/// }
/// ```
class HttpExchange {
  /// A call (or, on an interface, a URL prefix) of [url], with no method
  /// set: on a method that is `GET` unless the interface sets one.
  const HttpExchange([this.url = ''])
    : method = null,
      contentType = null,
      accept = const [],
      headers = const [],
      version = null;

  /// Every setting by name.
  const HttpExchange.of({
    this.url = '',
    this.method,
    this.contentType,
    this.accept = const [],
    this.headers = const [],
    this.version,
  });

  /// The URL: relative to the group's base URL (and to the interface's
  /// [url] for a method), or whole (`https://...`); it may hold
  /// `{variables}` and `${property}` placeholders. Spring's `value` and
  /// `url`.
  final String url;

  /// The HTTP method; `null`: the interface's, else `GET`.
  final HttpMethod? method;

  /// The `Content-Type` of the body (`MediaType.applicationJson`); `null`:
  /// chosen by the body's converter.
  final String? contentType;

  /// The media types for `Accept`; empty: none sent.
  final List<String> accept;

  /// Headers sent with each call, as `'Name=value'` (Spring's syntax;
  /// `${property}` placeholders are filled).
  final List<String> headers;

  /// The API version the call asks for; `null`: none.
  final String? version;
}

/// A `GET` call: [HttpExchange] with the method set.
///
/// ```dart
/// @GetExchange('/books/{isbn}')
/// Future<Book> find(@PathVariable() String isbn);
/// ```
///
/// Spring (Java): `@GetExchange`.
class GetExchange extends HttpExchange {
  /// A `GET` of [url].
  const GetExchange([String url = '']) : super.of(url: url, method: _get);

  /// A `GET` with every setting by name.
  const GetExchange.of({
    super.url,
    super.accept,
    super.headers,
    super.version,
  }) : super.of(method: _get);

  static const HttpMethod _get = HttpMethod.get;
}

/// A `POST` call: [HttpExchange] with the method set.
///
/// ```dart
/// @PostExchange('/books')
/// Future<Book> create(@RequestBody() Book book);
/// ```
///
/// Spring (Java): `@PostExchange`.
class PostExchange extends HttpExchange {
  /// A `POST` to [url].
  const PostExchange([String url = '']) : super.of(url: url, method: _post);

  /// A `POST` with every setting by name.
  const PostExchange.of({
    super.url,
    super.contentType,
    super.accept,
    super.headers,
    super.version,
  }) : super.of(method: _post);

  static const HttpMethod _post = HttpMethod.post;
}

/// A `PUT` call: [HttpExchange] with the method set.
///
/// Spring (Java): `@PutExchange`.
class PutExchange extends HttpExchange {
  /// A `PUT` to [url].
  const PutExchange([String url = '']) : super.of(url: url, method: _put);

  /// A `PUT` with every setting by name.
  const PutExchange.of({
    super.url,
    super.contentType,
    super.accept,
    super.headers,
    super.version,
  }) : super.of(method: _put);

  static const HttpMethod _put = HttpMethod.put;
}

/// A `PATCH` call: [HttpExchange] with the method set.
///
/// Spring (Java): `@PatchExchange`.
class PatchExchange extends HttpExchange {
  /// A `PATCH` of [url].
  const PatchExchange([String url = '']) : super.of(url: url, method: _patch);

  /// A `PATCH` with every setting by name.
  const PatchExchange.of({
    super.url,
    super.contentType,
    super.accept,
    super.headers,
    super.version,
  }) : super.of(method: _patch);

  static const HttpMethod _patch = HttpMethod.patch;
}

/// A `DELETE` call: [HttpExchange] with the method set.
///
/// Spring (Java): `@DeleteExchange`.
class DeleteExchange extends HttpExchange {
  /// A `DELETE` of [url].
  const DeleteExchange([String url = '']) : super.of(url: url, method: _delete);

  /// A `DELETE` with every setting by name.
  const DeleteExchange.of({
    super.url,
    super.contentType,
    super.accept,
    super.headers,
    super.version,
  }) : super.of(method: _delete);

  static const HttpMethod _delete = HttpMethod.delete;
}
