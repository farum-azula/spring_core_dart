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
/// ```
///
/// Spring (Java):
/// ```java
/// ResponseEntity<Book> response = catalog.create(book);
/// response.getStatusCode(); response.getHeaders().getLocation(); response.getBody();
/// response.getStatusCode().is2xxSuccessful();
/// ResponseEntity.ok(book);
/// ```
class ResponseEntity<T> {
  /// A response with [statusCode], [body] and [headers].
  ResponseEntity(int statusCode, {this.body, HttpHeaders? headers})
    : statusCode = HttpStatusCode(statusCode),
      headers = headers ?? HttpHeaders();

  /// A `200 OK` response with [body].
  ResponseEntity.ok(T this.body)
    : statusCode = HttpStatus.ok,
      headers = HttpHeaders();

  /// The status code (an `int` with `is2xxSuccessful`, ...), like
  /// Spring's `getStatusCode()`.
  final HttpStatusCode statusCode;

  /// The body, if any.
  final T? body;

  /// The headers.
  final HttpHeaders headers;

  /// Whether the status is 2xx.
  bool get isSuccess => statusCode.is2xxSuccessful;

  @override
  String toString() =>
      'ResponseEntity($statusCode${_phrase(statusCode)}'
      '${body == null ? '' : ', $body'})';

  static String _phrase(int code) => switch (HttpStatus.resolve(code)) {
    final status? => ' ${status.reasonPhrase}',
    null => '',
  };
}
