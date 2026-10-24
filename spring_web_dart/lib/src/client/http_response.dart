import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/response_status.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';
import 'package:spring_web_dart/src/media_type.dart';

/// A response from an `HttpTransport`: status code, headers and the body
/// bytes. Non-2xx codes are ordinary responses, not errors. Like Spring's
/// `ClientHttpResponse`.
///
/// ```dart
/// final response = await transport.send(request);
/// if (response.statusCode.is2xxSuccessful) {
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
  /// [request]. Throws an [ArgumentError] unless [statusCode] has three
  /// digits (100–999), like Spring's `HttpStatusCode.valueOf`, or is 0 (the
  /// opaque redirect a browser gives when redirects are not followed).
  HttpResponse(
    int statusCode, {
    HttpHeaders? headers,
    List<int> body = const [],
    this.request,
  }) : statusCode = clientResponseStatus(statusCode),
       headers = headers ?? HttpHeaders(),
       _body = body is Uint8List ? body : Uint8List.fromList(body);

  /// The status code (an `int` with `is2xxSuccessful`, ...).
  final HttpStatusCode statusCode;

  /// The response headers.
  final HttpHeaders headers;

  /// The request this answers, when known.
  final HttpRequest? request;

  final Uint8List _body;

  /// The body bytes.
  Uint8List get bodyBytes => _body;

  /// The body as text, decoded with the `charset` of the `Content-Type`
  /// (quoted or not, any name Dart knows: UTF-8, ISO-8859-1, US-ASCII and
  /// their aliases); UTF-8 without one or for a charset Dart does not
  /// know. Malformed bytes are replaced, not thrown.
  String get bodyText => decodeBody(_body, headers.contentType);

  /// Decodes [bytes] with the `charset` of [contentType], like [bodyText].
  static String decodeBody(List<int> bytes, String? contentType) {
    Encoding? encoding;
    if (contentType != null) {
      try {
        encoding = MediaType.parse(contentType).charset;
      } on ArgumentError {
        encoding = null;
      }
    }
    return switch (encoding) {
      AsciiCodec() => const AsciiDecoder(allowInvalid: true).convert(bytes),
      Latin1Codec() => const Latin1Decoder(allowInvalid: true).convert(bytes),
      final Encoding other when other is! Utf8Codec => other.decode(bytes),
      _ => utf8.decode(bytes, allowMalformed: true),
    };
  }

  /// Whether the status is 2xx.
  bool get isSuccess => statusCode.is2xxSuccessful;

  @override
  String toString() =>
      'HttpResponse($statusCode${_phrase(statusCode)}'
      '${request == null ? '' : ' for $request'})';

  static String _phrase(int code) => switch (HttpStatus.resolve(code)) {
    final status? => ' ${status.reasonPhrase}',
    null => '',
  };
}
