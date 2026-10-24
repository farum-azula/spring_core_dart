import 'dart:async';
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/response_status.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';

/// A response whose body arrives as a stream of byte chunks, from
/// `HttpTransport.stream`: for server-sent events, downloads and other
/// long responses. The status and headers are known; the body is read as
/// it comes. Cancelling the [body] subscription closes the connection.
///
/// ```dart
/// final response = await transport.stream(request);
/// if (!response.isSuccess) {
///   final error = await response.read(); // the whole body, for the message
///   throw StateError(error.bodyText);
/// }
/// await for (final chunk in response.body) { ... }
/// ```
///
/// Spring (Java): the body of a `ClientHttpResponse` read as an
/// `InputStream`, or `ResponseSpec.bodyToFlux(DataBuffer.class)` in
/// `WebClient`.
final class StreamedHttpResponse {
  /// A response with [statusCode] and [headers] whose [body] is still
  /// arriving. Throws an [ArgumentError] unless [statusCode] has three
  /// digits (100–999) or is 0 (the opaque redirect a browser gives when
  /// redirects are not followed).
  StreamedHttpResponse(
    int statusCode, {
    required this.body,
    HttpHeaders? headers,
    this.request,
  }) : statusCode = clientResponseStatus(statusCode),
       headers = headers ?? HttpHeaders();

  /// The status code (an `int` with `is2xxSuccessful`, ...).
  final HttpStatusCode statusCode;

  /// The response headers.
  final HttpHeaders headers;

  /// The body chunks (single subscription). Network failures arrive as
  /// `HttpTransportException` errors.
  final Stream<List<int>> body;

  /// The request this answers, when known.
  final HttpRequest? request;

  /// Whether the status is 2xx.
  bool get isSuccess => statusCode.is2xxSuccessful;

  /// Reads the whole body into an [HttpResponse] (e.g. to decode an error).
  Future<HttpResponse> read() async {
    final bytes = await body.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (builder, chunk) => builder..add(chunk),
    );
    return HttpResponse(
      statusCode,
      headers: headers,
      body: bytes.takeBytes(),
      request: request,
    );
  }

  /// Drops the body without reading it and closes the connection.
  Future<void> discard() => body.listen(null).cancel();

  @override
  String toString() =>
      'StreamedHttpResponse($statusCode${_phrase(statusCode)}'
      '${request == null ? '' : ' for $request'})';

  static String _phrase(int code) => switch (HttpStatus.resolve(code)) {
    final status? => ' ${status.reasonPhrase}',
    null => '',
  };
}
