import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/response_status.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';
import 'package:spring_web_dart/src/media_type.dart';

/// A complete HTTP response received by a client: the status code, the
/// headers and the whole body in memory.
///
/// `HttpTransport.send` returns it. A transport only reports what the
/// server answered: a `404` or a `500` is an ordinary response here, not
/// an error. Deciding what a status means is left to the caller. Feign
/// clients, for example, turn a non-2xx response into an exception with
/// their `ErrorDecoder`. Most applications meet this type only there, or
/// as the return type of a Feign method that wants the raw response.
///
/// ```dart
/// // `transport` is the application's `HttpTransport` bean.
/// final response = await transport.send(request);
/// if (response.isSuccess) {
///   final book = jsonDecode(response.bodyText) as Map<String, Object?>;
/// } else if (response.statusCode == HttpStatus.notFound) {
///   // No such book: not an error for this caller.
/// }
/// ```
///
/// Spring (Java): `ClientHttpResponse`, whose body is a stream to read:
/// ```java
/// ClientHttpResponse response = request.execute();
/// response.getStatusCode(); response.getHeaders(); response.getBody();
/// ```
final class HttpResponse {
  /// A response with [statusCode], [headers] and [body] bytes, answering
  /// [request] when it is known. Transports and test doubles create it.
  ///
  /// Throws an [ArgumentError] unless [statusCode] has three digits
  /// (100–999), as Spring's `HttpStatusCode.valueOf` requires, or is 0:
  /// the opaque response a browser gives for a redirect it was told not
  /// to follow.
  HttpResponse(
    int statusCode, {
    HttpHeaders? headers,
    List<int> body = const [],
    this.request,
  }) : statusCode = clientResponseStatus(statusCode),
       headers = headers ?? HttpHeaders(),
       _body = body is Uint8List ? body : Uint8List.fromList(body);

  /// The status code. It is an `int`, so it compares with `200` or
  /// [HttpStatus.ok], and it adds checks such as `is2xxSuccessful` and
  /// `is4xxClientError`.
  final HttpStatusCode statusCode;

  /// The response headers, with every value the server sent.
  final HttpHeaders headers;

  /// The request this response answers, or `null` when the creator did
  /// not pass it. Error messages use it to name the call.
  final HttpRequest? request;

  final Uint8List _body;

  /// The body bytes as received; empty when the response has no body.
  Uint8List get bodyBytes => _body;

  /// The body as text, decoded again on every read.
  ///
  /// The encoding is the `charset` of the `Content-Type` header, quoted or
  /// not, when Dart knows it (UTF-8, ISO-8859-1, US-ASCII and their
  /// aliases). Without a charset, or with one Dart does not know, the body
  /// is read as UTF-8. Malformed bytes become replacement characters
  /// instead of throwing.
  String get bodyText => decodeBody(_body, headers.contentType);

  /// Decodes [bytes] with the `charset` of [contentType], by the same
  /// rules as [bodyText]. For code that has the bytes and the header but
  /// no [HttpResponse], such as a decoder of streamed bodies. A
  /// `contentType` that cannot be parsed counts as no charset.
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

  /// Whether the status is 2xx. A redirect that was not followed (`3xx`,
  /// or 0 in a browser) is not a success.
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
