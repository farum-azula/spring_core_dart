import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';

/// A response from an `HttpTransport`: status code, headers and the body
/// bytes. Non-2xx codes are ordinary responses, not errors. Like Spring's
/// `ClientHttpResponse`.
///
/// ```dart
/// final response = await transport.send(request);
/// if (response.isSuccess) {
///   final json = jsonDecode(response.bodyText);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// ClientHttpResponse response = request.execute();
/// response.getStatusCode(); response.getHeaders(); response.getBody();
/// ```
final class HttpResponse {
  /// A response with [statusCode], [headers] and [body] bytes for
  /// [request].
  HttpResponse(
    this.statusCode, {
    HttpHeaders? headers,
    List<int> body = const [],
    this.request,
  }) : headers = headers ?? HttpHeaders(),
       _body = body is Uint8List ? body : Uint8List.fromList(body);

  /// The status code.
  final int statusCode;

  /// The response headers.
  final HttpHeaders headers;

  /// The request this answers, when known.
  final HttpRequest? request;

  final Uint8List _body;

  /// The body bytes.
  Uint8List get bodyBytes => _body;

  /// The body as text: UTF-8 (malformed bytes replaced), or Latin-1 when
  /// the `Content-Type` says `charset=iso-8859-1`.
  String get bodyText {
    final contentType = headers[HttpHeaders.contentType]?.toLowerCase() ?? '';
    if (contentType.contains('charset=iso-8859-1') ||
        contentType.contains('charset=latin1')) {
      return latin1.decode(_body);
    }
    return utf8.decode(_body, allowMalformed: true);
  }

  /// Whether the status is 2xx.
  bool get isSuccess => HttpStatus.isSuccess(statusCode);

  @override
  String toString() =>
      'HttpResponse($statusCode ${HttpStatus.reasonPhrase(statusCode)}'
      '${request == null ? '' : ' for $request'})';
}
