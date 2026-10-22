import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';

/// A response with its status code and headers, not only the body, like
/// Spring's `ResponseEntity`. A Feign client method returning
/// `Future<ResponseEntity<Book>>` gets all three.
///
/// ```dart
/// final response = await catalog.create(book); // ResponseEntity<Book>
/// if (response.statusCode == HttpStatus.created) {
///   print(response.headers['Location']);
///   print(response.body!.title);
/// }
/// ResponseEntity.ok(book);
/// ```
///
/// Spring (Java):
/// ```java
/// ResponseEntity<Book> response = catalog.create(book);
/// response.getStatusCode(); response.getHeaders().getLocation(); response.getBody();
/// ResponseEntity.ok(book);
/// ```
class ResponseEntity<T> {
  /// A response with [statusCode], [body] and [headers].
  ResponseEntity(this.statusCode, {this.body, HttpHeaders? headers})
    : headers = headers ?? HttpHeaders();

  /// A `200 OK` response with [body].
  ResponseEntity.ok(T this.body)
    : statusCode = HttpStatus.ok,
      headers = HttpHeaders();

  /// The status code.
  final int statusCode;

  /// The body, if any.
  final T? body;

  /// The headers.
  final HttpHeaders headers;

  /// Whether the status is 2xx.
  bool get isSuccess => HttpStatus.isSuccess(statusCode);

  @override
  String toString() =>
      'ResponseEntity($statusCode ${HttpStatus.reasonPhrase(statusCode)}'
      '${body == null ? '' : ', $body'})';
}
