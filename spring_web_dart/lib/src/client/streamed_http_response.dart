import 'dart:async';
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/response_status.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';

/// An HTTP response whose status and headers have arrived but whose body
/// is still coming, as a stream of byte chunks.
///
/// `HttpTransport.stream` returns it, for responses that are too long to
/// hold in memory or that never end: server-sent events, file downloads,
/// progress reports. The caller looks at the status first, then reads the
/// body chunk by chunk as the server sends it. The body holds the
/// connection open: read it to the end, cancel its subscription, or call
/// [discard], otherwise the connection stays busy. Feign clients use it
/// for methods that return an `EventStream`; applications rarely see it.
///
/// ```dart
/// final response = await transport.stream(request);
/// if (!response.isSuccess) {
///   // An error is short: read it whole to put the server's message in
///   // the exception.
///   final error = await response.read();
///   throw StateError(error.bodyText);
/// }
/// // `file` is an `IOSink`: each chunk is written as it arrives, so the
/// // download is never all in memory.
/// await for (final chunk in response.body) {
///   file.add(chunk);
/// }
/// ```
///
/// Spring (Java): the body of a `ClientHttpResponse` read as an
/// `InputStream`, or `ResponseSpec.bodyToFlux(DataBuffer.class)` in
/// `WebClient`.
final class StreamedHttpResponse {
  /// A response with [statusCode] and [headers] whose [body] is still
  /// arriving, answering [request] when it is known. Transports and test
  /// doubles create it.
  ///
  /// Throws an [ArgumentError] unless [statusCode] has three digits
  /// (100–999) or is 0: the opaque response a browser gives for a
  /// redirect it was told not to follow.
  StreamedHttpResponse(
    int statusCode, {
    required this.body,
    HttpHeaders? headers,
    this.request,
  }) : statusCode = clientResponseStatus(statusCode),
       headers = headers ?? HttpHeaders();

  /// The status code. It is an `int`, so it compares with `200` or
  /// [HttpStatus.ok], and it adds checks such as `is2xxSuccessful`.
  final HttpStatusCode statusCode;

  /// The response headers, with every value the server sent.
  final HttpHeaders headers;

  /// The body as byte chunks, in the order and sizes the network delivers
  /// them. It can be listened to once. A connection that breaks while the
  /// body is read gives an `HttpTransportException` error on the stream.
  /// Cancelling the subscription closes the connection.
  final Stream<List<int>> body;

  /// The request this response answers, or `null` when the creator did
  /// not pass it.
  final HttpRequest? request;

  /// Whether the status is 2xx.
  bool get isSuccess => statusCode.is2xxSuccessful;

  /// Reads the rest of the body and returns the whole response as an
  /// [HttpResponse]. Use it when the body turns out to be short after
  /// all, typically an error message to decode. It listens to [body], so
  /// the body cannot be read again afterwards.
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

  /// Drops the body without reading it and closes the connection: for a
  /// response the caller does not want, such as a `204` that ends an
  /// event stream. It listens to [body], so call it only when nobody else
  /// does.
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
