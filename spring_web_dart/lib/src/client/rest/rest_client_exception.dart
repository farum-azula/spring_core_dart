import 'dart:typed_data';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';

/// The base of what a `RestClient` throws: an error status
/// ([RestClientResponseException] and its subclasses), no response at all
/// ([ResourceAccessException]), or a body that could not be written or
/// read.
///
/// ```dart
/// try {
///   return await rest.get().uri('/books/{isbn}', [isbn]).retrieve()
///       .body<Book>();
/// } on HttpClientErrorException catch (error) {
///   if (error.statusCode == HttpStatus.notFound) return null;
///   rethrow;
/// }
/// ```
///
/// Spring (Java): `org.springframework.web.client.RestClientException`.
class RestClientException implements Exception {
  /// A failure described by [message], caused by [cause] when there is
  /// one.
  RestClientException(this.message, {this.cause});

  /// What went wrong, for people.
  final String message;

  /// The error behind this one (a `JsonMappingException`, an
  /// `HttpTransportException`), or `null`.
  final Object? cause;

  /// The name shown before the message (the class's).
  String get kind => 'RestClientException';

  @override
  String toString() => '$kind: $message';
}

/// A response with an error status: the status, the headers and the body
/// of the answer, which [bodyAs] reads with the client's converters (a
/// `ProblemDetail`, the API's own error object).
///
/// Its subclasses tell the status classes apart:
/// [HttpClientErrorException] (4xx), [HttpServerErrorException] (5xx),
/// and [UnknownHttpStatusCodeException] (any other status a status
/// handler turns into an error).
///
/// ```dart
/// } on RestClientResponseException catch (error) {
///   final problem = error.bodyAs<ProblemDetail>();
///   log.warning('${error.statusCode}: ${problem?.detail}');
/// }
/// ```
///
/// Spring (Java): `RestClientResponseException`.
class RestClientResponseException extends RestClientException {
  /// The error [statusCode] with [statusText], the response [headers] and
  /// [bodyBytes], answering [request]; [message] is what `toString`
  /// shows. [bodyReader] reads the body for [bodyAs] (the client's
  /// converters); without one, [bodyAs] reads only text and bytes.
  RestClientResponseException(
    super.message, {
    required this.statusCode,
    required this.statusText,
    required HttpHeaders headers,
    required Uint8List bodyBytes,
    this.request,
    Object? Function(TypeInfo<Object?> type)? bodyReader,
  }) : headers = HttpHeaders.readOnly(headers),
       // Named parameters cannot be private.
       // ignore: prefer_initializing_formals
       _bodyBytes = bodyBytes,
       // Named parameters cannot be private.
       // ignore: prefer_initializing_formals
       _bodyReader = bodyReader;

  @override
  String get kind => 'RestClientResponseException';

  /// The status of the answer.
  final HttpStatusCode statusCode;

  /// The reason phrase of [statusCode] (`Not Found`), empty for a status
  /// HTTP does not name.
  final String statusText;

  /// The response headers, read-only.
  final HttpHeaders headers;

  /// The request the answer is for, when it is known.
  final HttpRequest? request;

  final Uint8List _bodyBytes;
  final Object? Function(TypeInfo<Object?> type)? _bodyReader;

  /// The body as received; empty when there was none.
  Uint8List get bodyBytes => _bodyBytes;

  /// The body as text, in the charset of its `Content-Type` (UTF-8 by
  /// default).
  String get bodyText =>
      HttpResponse.decodeBody(_bodyBytes, headers.contentType);

  /// The body read as [T] ([type] for a generic one) with the client's
  /// converters, or `null` when it is empty or cannot be read as [T] (an
  /// HTML error page where JSON was expected).
  ///
  /// Spring (Java): `getResponseBodyAs(Class<E>)`.
  T? bodyAs<T>([TypeInfo<T>? type]) {
    if (_bodyBytes.isEmpty) {
      return null;
    }
    final target = type ?? ClassType<T>(nullable: true);
    final reader = _bodyReader;
    try {
      if (reader != null) {
        return reader(target) as T?;
      }
      final Object? text = target.type == String ? bodyText : null;
      final Object? bytes = target.type == Uint8List ? _bodyBytes : null;
      return (text ?? bytes) as T?;
    } on Object {
      return null;
    }
  }

  /// The exception of [response], by its status class:
  /// [HttpClientErrorException] for 4xx, [HttpServerErrorException] for 5xx,
  /// [UnknownHttpStatusCodeException] for any other. The message is
  /// `<status> <phrase>: <body>` (`[no body]` without one), as Spring's.
  /// [bodyReader] is passed on for [bodyAs].
  static RestClientResponseException of(
    HttpResponse response, {
    Object? Function(TypeInfo<Object?> type)? bodyReader,
  }) {
    final status = response.statusCode;
    final text = HttpStatus.resolve(status)?.reasonPhrase ?? '';
    final body = response.bodyBytes;
    final message =
        '$status${text.isEmpty ? '' : ' $text'}: '
        '${body.isEmpty ? '[no body]' : _shortened(response.bodyText)}';
    final factory =
        _bySeries[status ~/ 100] ?? UnknownHttpStatusCodeException.new;
    return factory(
      message,
      statusCode: status,
      statusText: text,
      headers: response.headers,
      bodyBytes: body,
      request: response.request,
      bodyReader: bodyReader,
    );
  }

  // Which exception a status class gets: a table, so a new class is a new
  // entry, not another branch.
  static const Map<int, _Factory> _bySeries = {
    4: HttpClientErrorException.new,
    5: HttpServerErrorException.new,
  };

  // Long bodies (an HTML page) stay readable in a log line; bodyText has
  // the whole of it.
  static String _shortened(String body) => body.length <= 1000
      ? body
      : '${body.substring(0, 1000)}... (${body.length} characters)';
}

typedef _Factory = RestClientResponseException Function(
  String message, {
  required HttpStatusCode statusCode,
  required String statusText,
  required HttpHeaders headers,
  required Uint8List bodyBytes,
  HttpRequest? request,
  Object? Function(TypeInfo<Object?> type)? bodyReader,
});

/// A response with a status HTTP knows as an error class: the base of
/// [HttpClientErrorException] and [HttpServerErrorException].
///
/// Spring (Java): `HttpStatusCodeException`.
abstract class HttpStatusCodeException extends RestClientResponseException {
  /// As [RestClientResponseException.new].
  HttpStatusCodeException(
    super.message, {
    required super.statusCode,
    required super.statusText,
    required super.headers,
    required super.bodyBytes,
    super.request,
    super.bodyReader,
  });
}

/// A 4xx answer: the request was wrong (400), not allowed (401, 403),
/// for nothing (404), in conflict (409), too many (429), ...
///
/// ```dart
/// } on HttpClientErrorException catch (error) {
///   if (error.statusCode == HttpStatus.notFound) return null;
///   rethrow;
/// }
/// ```
///
/// Spring (Java): `HttpClientErrorException` (whose subclasses per status,
/// `HttpClientErrorException.NotFound` and so on, have no counterpart:
/// compare [statusCode]).
class HttpClientErrorException extends HttpStatusCodeException {
  /// As [RestClientResponseException.new].
  HttpClientErrorException(
    super.message, {
    required super.statusCode,
    required super.statusText,
    required super.headers,
    required super.bodyBytes,
    super.request,
    super.bodyReader,
  });

  @override
  String get kind => 'HttpClientErrorException';
}

/// A 5xx answer: the server failed (500), is overloaded (503), or a gateway
/// got no good answer (502, 504).
///
/// Spring (Java): `HttpServerErrorException`.
class HttpServerErrorException extends HttpStatusCodeException {
  /// As [RestClientResponseException.new].
  HttpServerErrorException(
    super.message, {
    required super.statusCode,
    required super.statusText,
    required super.headers,
    required super.bodyBytes,
    super.request,
    super.bodyReader,
  });

  @override
  String get kind => 'HttpServerErrorException';
}

/// An answer that a status handler treats as an error although its status
/// is neither 4xx nor 5xx (a 3xx not followed, a 1xx or a status HTTP does
/// not name).
///
/// Spring (Java): `UnknownHttpStatusCodeException`.
class UnknownHttpStatusCodeException extends RestClientResponseException {
  /// As [RestClientResponseException.new].
  UnknownHttpStatusCodeException(
    super.message, {
    required super.statusCode,
    required super.statusText,
    required super.headers,
    required super.bodyBytes,
    super.request,
    super.bodyReader,
  });

  @override
  String get kind => 'UnknownHttpStatusCodeException';
}

/// No response arrived: the connection could not be opened or broke, a
/// time limit ran out (the read timeout, the deadline of the enclosing
/// request), or the transport refused the address (`FilteredHostException`).
/// [cause] is the transport's error.
///
/// ```dart
/// } on ResourceAccessException catch (error) {
///   if (error.isTimeout) { ... }
/// }
/// ```
///
/// Spring (Java): `ResourceAccessException`, for an `IOException`.
class ResourceAccessException extends RestClientException {
  /// The failure described by [message], with the transport's [cause].
  ResourceAccessException(super.message, {super.cause});

  @override
  String get kind => 'ResourceAccessException';

  /// Whether a time limit ran out.
  bool get isTimeout => switch (cause) {
    final HttpTransportException error => error.isTimeout,
    RequestDeadlineExceededException() => true,
    _ => false,
  };

  /// Whether another try can end differently (a network failure, a
  /// timeout); `false` for a refused address or a deadline that passed.
  bool get isRetryable => switch (cause) {
    final HttpTransportException error => error.isRetryable,
    _ => false,
  };
}
