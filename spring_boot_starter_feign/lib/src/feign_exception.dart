import 'package:spring_web_dart/spring_web_dart.dart';

/// A failed Feign call, like Feign's `FeignException`: the [status] of the
/// response (`-1` when there was none), the request and the response body.
/// HTTP errors are thrown as subclasses such as [FeignNotFound] or
/// [FeignServiceUnavailable] (see [FeignException.errorStatus]).
///
/// ```dart
/// try {
///   await catalog.find('978-0');
/// } on FeignNotFound {
///   return null;
/// } on FeignException catch (error) {
///   print('${error.status}: ${error.responseBody}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try { catalog.find("978-0"); }
/// catch (FeignException.NotFound e) { return null; }
/// ```
class FeignException implements Exception {
  /// A failure with [status] and [message].
  FeignException(
    this.status,
    this.message, {
    this.request,
    this.responseBody,
    this.responseHeaders,
    this.cause,
  });

  /// The response status; `-1` when no response was received.
  final int status;

  /// What happened.
  final String message;

  /// The request that failed.
  final HttpRequest? request;

  /// The response body as text, if there was one.
  final String? responseBody;

  /// The response headers, if there was a response.
  final HttpHeaders? responseHeaders;

  /// The underlying error (e.g. an `HttpTransportException`).
  final Object? cause;

  /// The exception for an error [response] of the method [methodKey]
  /// (`CatalogClient#find(String)`): a client (4xx) or server (5xx)
  /// subclass.
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

  @override
  String toString() {
    final body = responseBody;
    // The text names the actual class, subclasses included, like Java's
    // getClass().getName().
    // ignore: no_runtimetype_tostring
    return '$runtimeType: $message'
        '${body == null || body.isEmpty ? '' : ': $body'}';
  }
}

/// A 4xx response (`FeignException.FeignClientException`).
class FeignClientException extends FeignException {
  /// A client error with [status].
  FeignClientException(
    super.status,
    super.message, {
    super.request,
    super.responseBody,
    super.responseHeaders,
  });
}

/// A 5xx response (`FeignException.FeignServerException`).
class FeignServerException extends FeignException {
  /// A server error with [status].
  FeignServerException(
    super.status,
    super.message, {
    super.request,
    super.responseBody,
    super.responseHeaders,
  });
}

/// 400 Bad Request.
class FeignBadRequest extends FeignClientException {
  /// The exception for a 400 response.
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

/// 401 Unauthorized.
class FeignUnauthorized extends FeignClientException {
  /// The exception for a 401 response.
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

/// 403 Forbidden.
class FeignForbidden extends FeignClientException {
  /// The exception for a 403 response.
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

/// 404 Not Found.
class FeignNotFound extends FeignClientException {
  /// The exception for a 404 response.
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

/// 405 Method Not Allowed.
class FeignMethodNotAllowed extends FeignClientException {
  /// The exception for a 405 response.
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

/// 406 Not Acceptable.
class FeignNotAcceptable extends FeignClientException {
  /// The exception for a 406 response.
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

/// 409 Conflict.
class FeignConflict extends FeignClientException {
  /// The exception for a 409 response.
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

/// 410 Gone.
class FeignGone extends FeignClientException {
  /// The exception for a 410 response.
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

/// 415 Unsupported Media Type.
class FeignUnsupportedMediaType extends FeignClientException {
  /// The exception for a 415 response.
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

/// 422 Unprocessable Entity.
class FeignUnprocessableEntity extends FeignClientException {
  /// The exception for a 422 response.
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

/// 429 Too Many Requests.
class FeignTooManyRequests extends FeignClientException {
  /// The exception for a 429 response.
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

/// 500 Internal Server Error.
class FeignInternalServerError extends FeignServerException {
  /// The exception for a 500 response.
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

/// 501 Not Implemented.
class FeignNotImplemented extends FeignServerException {
  /// The exception for a 501 response.
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

/// 502 Bad Gateway.
class FeignBadGateway extends FeignServerException {
  /// The exception for a 502 response.
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

/// 503 Service Unavailable.
class FeignServiceUnavailable extends FeignServerException {
  /// The exception for a 503 response.
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

/// 504 Gateway Timeout.
class FeignGatewayTimeout extends FeignServerException {
  /// The exception for a 504 response.
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

/// A failure that may succeed when tried again: a connection error, a
/// timeout, or a response with `Retry-After` (Feign's
/// `RetryableException`). The `Retryer` bean decides whether to retry.
///
/// ```dart
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
  /// A retryable failure; [retryAfter] is when to try again, if known.
  RetryableException(
    super.status,
    super.message, {
    this.retryAfter,
    super.request,
    super.responseBody,
    super.responseHeaders,
    super.cause,
  });

  /// When the server asked to try again (`Retry-After`).
  final DateTime? retryAfter;
}

/// A response body that could not be read as the method's return type
/// (Feign's `DecodeException`).
class DecodeException extends FeignException {
  /// A decoding failure of a response with [status].
  DecodeException(super.status, super.message, {super.request, super.cause});
}

/// A request body that could not be written (Feign's `EncodeException`).
class EncodeException extends FeignException {
  /// An encoding failure.
  EncodeException(String message, {super.cause}) : super(-1, message);
}

/// Turns an error response (status ≥ 400) into the exception the client
/// method throws, like Feign's `ErrorDecoder`. Declare a bean to replace the
/// [DefaultErrorDecoder].
///
/// ```dart
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
  /// The exception for the error [response] of [methodKey]
  /// (`CatalogClient#find(String)`).
  Exception decode(String methodKey, HttpResponse response);
}

/// The default [ErrorDecoder]: a `Retry-After` header (seconds or an HTTP
/// date) makes it a [RetryableException], otherwise
/// [FeignException.errorStatus]. Like Feign's `ErrorDecoder.Default`.
class DefaultErrorDecoder implements ErrorDecoder {
  /// The default decoder.
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
  static DateTime? _retryAfter(String value) {
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return DateTime.now().add(Duration(seconds: seconds));
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
