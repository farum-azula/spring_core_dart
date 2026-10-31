import 'dart:convert';

import 'package:spring_web_dart/spring_web_dart.dart';

/// The error a Feign client method throws when its call fails.
///
/// It carries what is known about the failure: the [status] of the
/// response (`-1` when there was none), the [request], and the response
/// body and headers. An error status is thrown as a subclass, so callers
/// catch the cases they handle: [FeignNotFound] for a 404,
/// [FeignClientException] for any 4xx, [FeignServerException] for any 5xx
/// (see [FeignException.errorStatus]). A call that got no answer throws a
/// [RetryableException]; a body that does not fit the return type a
/// [DecodeException]. An `ErrorDecoder` bean can throw exceptions of
/// your own instead.
///
/// ```dart
/// // A missing book is not an error for the shop; anything else is.
/// try {
///   await catalog.find('978-0');
/// } on FeignNotFound {
///   return null;
/// } on FeignException catch (error) {
///   log.warning('${error.status}: ${error.responseBody}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try { catalog.find("978-0"); }
/// catch (FeignException.NotFound e) { return null; }
/// ```
class FeignException implements Exception {
  /// A failure with [status] (`-1` without a response) and [message].
  FeignException(
    this.status,
    this.message, {
    this.request,
    this.responseBody,
    this.responseHeaders,
    this.cause,
  });

  /// The status of the response; `-1` when no response was received.
  final int status;

  /// What happened, in Feign's form:
  /// `[404 Not Found] during [GET] to [<url>] [<method key>]`.
  final String message;

  /// The request that failed, when known.
  final HttpRequest? request;

  /// The response body as text, often an error message or a problem
  /// document from the server; `null` without a response.
  final String? responseBody;

  /// The response headers; `null` without a response.
  final HttpHeaders? responseHeaders;

  /// The error that caused this one, such as an `HttpTransportException`
  /// for a failed connection; `null` when none.
  final Object? cause;

  /// The exception for the error [response] of the method [methodKey]
  /// (`CatalogClient#find(String)`): the subclass for its status (such as
  /// [FeignNotFound]), else a [FeignClientException] for another 4xx, a
  /// [FeignServerException] for another 5xx, or a plain [FeignException]
  /// for any other status. An `ErrorDecoder` of your own may call it for
  /// the statuses it leaves alone.
  static FeignException errorStatus(String methodKey, HttpResponse response) {
    final status = response.statusCode;
    final reason = HttpStatus.resolve(status)?.reasonPhrase;
    final message =
        '[$status${reason == null ? '' : ' $reason'}] during '
        '[${response.request?.method.value ?? '?'}] to '
        '[${response.request?.url ?? '?'}] [$methodKey]';
    final body = response.bodyText;
    final request = response.request;
    final headers = response.headers;
    FeignException create(
      FeignException Function(
        String message,
        HttpRequest? request,
        String body,
        HttpHeaders headers,
      )
      build,
    ) => build(message, request, body, headers);
    return switch (status) {
      400 => create(FeignBadRequest.new),
      401 => create(FeignUnauthorized.new),
      403 => create(FeignForbidden.new),
      404 => create(FeignNotFound.new),
      405 => create(FeignMethodNotAllowed.new),
      406 => create(FeignNotAcceptable.new),
      409 => create(FeignConflict.new),
      410 => create(FeignGone.new),
      415 => create(FeignUnsupportedMediaType.new),
      422 => create(FeignUnprocessableEntity.new),
      429 => create(FeignTooManyRequests.new),
      500 => create(FeignInternalServerError.new),
      501 => create(FeignNotImplemented.new),
      502 => create(FeignBadGateway.new),
      503 => create(FeignServiceUnavailable.new),
      504 => create(FeignGatewayTimeout.new),
      >= 400 && < 500 => FeignClientException(
        status,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      ),
      >= 500 && < 600 => FeignServerException(
        status,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      ),
      _ => FeignException(
        status,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      ),
    };
  }

  /// The class, the [message] and a preview of the [responseBody], as
  /// Feign's message has: the whole body under 400 bytes, else its first
  /// 200 characters and its size (`... (5120 bytes)`). [responseBody]
  /// keeps all of it.
  @override
  String toString() {
    final body = responseBody;
    // The text names the actual class, subclasses included, like Java's
    // getClass().getName().
    // ignore: no_runtimetype_tostring
    return '$runtimeType: $message'
        '${body == null || body.isEmpty ? '' : ': ${_preview(body)}'}';
  }

  // Feign's FeignExceptionMessageBuilder: MAX_BODY_BYTES_LENGTH 400,
  // MAX_BODY_CHARS_LENGTH 200.
  static String _preview(String body) {
    // At most 4 bytes a character: short bodies need no encoding.
    final bytes = body.length < 100 ? 0 : utf8.encode(body).length;
    if (bytes < 400) {
      return body;
    }
    return '${String.fromCharCodes(body.runes.take(200))}... ($bytes bytes)';
  }
}

/// The error of a call answered with a 4xx status: the server refused
/// the request as it was sent.
///
/// Catch it for every client error at once; the common statuses have
/// subclasses of their own, such as [FeignNotFound]. Feign's counterpart
/// is `FeignException.FeignClientException`.
class FeignClientException extends FeignException {
  /// A client error with [status] and [message].
  FeignClientException(
    super.status,
    super.message, {
    super.request,
    super.responseBody,
    super.responseHeaders,
  });
}

/// The error of a call answered with a 5xx status: the server failed.
///
/// Catch it for every server error at once; the common statuses have
/// subclasses of their own, such as [FeignServiceUnavailable]. Feign's
/// counterpart is `FeignException.FeignServerException`.
class FeignServerException extends FeignException {
  /// A server error with [status] and [message].
  FeignServerException(
    super.status,
    super.message, {
    super.request,
    super.responseBody,
    super.responseHeaders,
  });
}

/// The error of a call answered with 400 Bad Request: the server found the
/// request malformed or invalid.
class FeignBadRequest extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 400 response,
  /// with its message, request, body and headers.
  FeignBadRequest(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        400,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 401 Unauthorized: the call lacks valid
/// credentials.
class FeignUnauthorized extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 401 response,
  /// with its message, request, body and headers.
  FeignUnauthorized(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        401,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 403 Forbidden: the credentials are valid
/// but not allowed to do this.
class FeignForbidden extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 403 response,
  /// with its message, request, body and headers.
  FeignForbidden(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        403,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 404 Not Found: what the call asks for does
/// not exist.
class FeignNotFound extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 404 response,
  /// with its message, request, body and headers.
  FeignNotFound(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        404,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 405 Method Not Allowed: the path does not
/// take this HTTP method.
class FeignMethodNotAllowed extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 405 response,
  /// with its message, request, body and headers.
  FeignMethodNotAllowed(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        405,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 406 Not Acceptable: the server cannot
/// answer in a type the `Accept` header allows.
class FeignNotAcceptable extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 406 response,
  /// with its message, request, body and headers.
  FeignNotAcceptable(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        406,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 409 Conflict: the call conflicts with the
/// current state, such as a duplicate.
class FeignConflict extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 409 response,
  /// with its message, request, body and headers.
  FeignConflict(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        409,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 410 Gone: what the call asks for existed
/// but was removed for good.
class FeignGone extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 410 response,
  /// with its message, request, body and headers.
  FeignGone(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        410,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 415 Unsupported Media Type: the server
/// does not read the body's `Content-Type`.
class FeignUnsupportedMediaType extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 415 response,
  /// with its message, request, body and headers.
  FeignUnsupportedMediaType(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        415,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 422 Unprocessable Entity: the body is
/// well-formed but its content is rejected.
class FeignUnprocessableEntity extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 422 response,
  /// with its message, request, body and headers.
  FeignUnprocessableEntity(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        422,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 429 Too Many Requests: the client called
/// too often and must slow down.
class FeignTooManyRequests extends FeignClientException {
  /// The exception [FeignException.errorStatus] builds for a 429 response,
  /// with its message, request, body and headers.
  FeignTooManyRequests(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        429,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 500 Internal Server Error: the server
/// failed while handling the call.
class FeignInternalServerError extends FeignServerException {
  /// The exception [FeignException.errorStatus] builds for a 500 response,
  /// with its message, request, body and headers.
  FeignInternalServerError(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        500,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 501 Not Implemented: the server does not
/// offer this operation.
class FeignNotImplemented extends FeignServerException {
  /// The exception [FeignException.errorStatus] builds for a 501 response,
  /// with its message, request, body and headers.
  FeignNotImplemented(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        501,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 502 Bad Gateway: a proxy or gateway got a
/// bad answer from the server behind it.
class FeignBadGateway extends FeignServerException {
  /// The exception [FeignException.errorStatus] builds for a 502 response,
  /// with its message, request, body and headers.
  FeignBadGateway(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        502,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 503 Service Unavailable: the server is
/// overloaded or down for now.
class FeignServiceUnavailable extends FeignServerException {
  /// The exception [FeignException.errorStatus] builds for a 503 response,
  /// with its message, request, body and headers.
  FeignServiceUnavailable(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        503,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call answered with 504 Gateway Timeout: a proxy or gateway
/// timed out waiting for the server behind it.
class FeignGatewayTimeout extends FeignServerException {
  /// The exception [FeignException.errorStatus] builds for a 504 response,
  /// with its message, request, body and headers.
  FeignGatewayTimeout(
    String message,
    HttpRequest? request,
    String body,
    HttpHeaders headers,
  ) : super(
        504,
        message,
        request: request,
        responseBody: body,
        responseHeaders: headers,
      );
}

/// The error of a call that may succeed when tried again: no connection,
/// a timeout, or a response with a `Retry-After` header.
///
/// Only these errors are retried: the client asks its `Retryer` whether
/// and when to try again, and throws this when the retryer gives up (or
/// when there is none). Its [status] is `-1` when there was no response.
/// An `ErrorDecoder` of your own can throw it to make more answers
/// retryable, such as every 503.
///
/// ```dart
/// // A busy server is worth another try.
/// final class Retry503 implements ErrorDecoder {
///   @override
///   Exception decode(String methodKey, HttpResponse response) =>
///       response.statusCode == 503
///           ? RetryableException(503, 'busy', request: response.request)
///           : const DefaultErrorDecoder().decode(methodKey, response);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// throw new RetryableException(503, "busy", Request.HttpMethod.GET,
///     (Long) null, request);
/// ```
class RetryableException extends FeignException {
  /// A failure that may be tried again; [retryAfter] is when, if the
  /// server said so.
  RetryableException(
    super.status,
    super.message, {
    this.retryAfter,
    super.request,
    super.responseBody,
    super.responseHeaders,
    super.cause,
  });

  /// The time the server asked to be called again (`Retry-After`), or
  /// `null`. `DefaultRetryer` waits until then, at most its `maxPeriod`.
  final DateTime? retryAfter;
}

/// The error of a call whose answer could not be read as the method's
/// return type, such as JSON of another shape or text where an object
/// was expected.
///
/// It usually means the interface does not match the service. For an
/// event stream, an event that cannot be read is this error on the
/// stream, which goes on. Feign's counterpart is `DecodeException`.
class DecodeException extends FeignException {
  /// A decoding failure of a response with [status]; [cause] is the
  /// parse error.
  DecodeException(super.status, super.message, {super.request, super.cause});
}

/// The error of a call whose arguments could not be written into the
/// request: a body the `ObjectMapper` cannot write, a nested object in a
/// form, or a value whose runtime type is an object where a path, query
/// or header needs a single value.
///
/// It is thrown before anything is sent, with [status] `-1`. Feign's
/// counterpart is `EncodeException`.
class EncodeException extends FeignException {
  /// An encoding failure described by [message]; [cause] is the error
  /// behind it.
  EncodeException(String message, {super.cause}) : super(-1, message);
}

/// Decides which exception a Feign call throws when the answer is not a
/// success.
///
/// By default ([DefaultErrorDecoder]) a client throws the
/// [FeignException] subclass of the status. Declare an `ErrorDecoder` bean
/// to throw exceptions of your own domain instead, read an error document
/// the service sends, or make some answers retryable; put it in a
/// client's `configuration` class to apply it to that client only. It is
/// called for every status outside 2xx, except for a dismissed 404 and
/// for methods that return the raw `HttpResponse`.
///
/// ```dart
/// // The catalog's 404 becomes the shop's own exception.
/// final class ShopErrors implements ErrorDecoder {
///   @override
///   Exception decode(String methodKey, HttpResponse response) =>
///       response.statusCode == 404
///           ? BookNotFound(response.request!.url.path)
///           : const DefaultErrorDecoder().decode(methodKey, response);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class ShopErrors implements ErrorDecoder {
///   public Exception decode(String methodKey, Response response) { ... }
/// }
/// ```
abstract interface class ErrorDecoder {
  /// The exception the call throws for the error [response] of the
  /// method [methodKey] (`CatalogClient#find(String)`). Return a
  /// [RetryableException] to let the `Retryer` try again.
  Exception decode(String methodKey, HttpResponse response);
}

/// The [ErrorDecoder] every client uses unless another is declared.
///
/// It throws the exception of [FeignException.errorStatus] for the
/// status, such as [FeignNotFound]; a response with a `Retry-After` header
/// (seconds or an HTTP date) becomes a [RetryableException] instead, so a
/// `Retryer` can wait and try again. A value that is neither, such as
/// `-5`, leaves the error not retryable, as in Feign. A decoder of your
/// own can hand the cases it does not handle to it. Feign's counterpart
/// is `ErrorDecoder.Default`.
class DefaultErrorDecoder implements ErrorDecoder {
  /// The default decoder; it has no state.
  const DefaultErrorDecoder();

  @override
  Exception decode(String methodKey, HttpResponse response) {
    final error = FeignException.errorStatus(methodKey, response);
    final retryAfter = switch (response.headers[HttpHeaders.retryAfterHeader]) {
      final value? => _retryAfter(value.trim()),
      null => null,
    };
    if (retryAfter != null) {
      return RetryableException(
        response.statusCode,
        error.message,
        retryAfter: retryAfter,
        request: response.request,
        responseBody: error.responseBody,
        responseHeaders: response.headers,
      );
    }
    return error;
  }

  // `Retry-After: 120` or `Retry-After: Wed, 21 Oct 2015 07:28:00 GMT`
  // (RFC 1123, like Feign's RetryAfterDecoder); null when unreadable.
  // Seconds are digits only, as in Feign (`120.0` too): `-5` or `+5` is
  // not retryable, and a huge number waits [_maxRetryAfter], not an
  // overflowed (past) time.
  static DateTime? _retryAfter(String value) {
    if (_seconds.firstMatch(value) case final match?) {
      final digits = match[1]!;
      final seconds = digits.length > 12 ? null : int.parse(digits);
      final delay = seconds == null || seconds > _maxRetryAfter.inSeconds
          ? _maxRetryAfter
          : Duration(seconds: seconds);
      return DateTime.now().add(delay);
    }
    final match = _httpDate.firstMatch(value);
    if (match == null) {
      return null;
    }
    final month = _months.indexOf(match[2]!.toLowerCase()) + 1;
    if (month == 0) {
      return null;
    }
    return DateTime.utc(
      int.parse(match[3]!),
      month,
      int.parse(match[1]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
  }

  static final _seconds = RegExp(r'^(\d+)(?:\.0*)?$');

  // The longest wait a Retry-After in seconds gives; the Retryer waits
  // its `maxPeriod` at most anyway.
  static const _maxRetryAfter = Duration(days: 365);

  static final _httpDate = RegExp(
    r'^(?:[A-Za-z]{3}, )?(\d{1,2}) ([A-Za-z]{3}) (\d{4}) '
    r'(\d{2}):(\d{2}):(\d{2}) (?:GMT|UTC|Z|\+0000)$',
  );

  static const _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
}
