import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// No handler maps the request: 404, like Spring's
/// `NoHandlerFoundException`.
class NoHandlerFoundException extends ErrorResponseException {
  /// No handler for [method] [path].
  NoHandlerFoundException(this.method, this.path)
    : super(
        HttpStatus.notFound,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.notFound,
          'No endpoint ${method.value} $path.',
        ),
      );

  /// The request method.
  final HttpMethod method;

  /// The request path.
  final String path;
}

/// The path is mapped, but not for this method: 405 with `Allow`, like
/// Spring's `HttpRequestMethodNotSupportedException`.
class HttpRequestMethodNotSupportedException extends ErrorResponseException {
  /// [method] is not one of [supported].
  HttpRequestMethodNotSupportedException(this.method, this.supported)
    : super(
        HttpStatus.methodNotAllowed,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.methodNotAllowed,
          "Method '${method.value}' is not supported.",
        ),
        headers: HttpHeaders({
          HttpHeaders.allowHeader: supported.map((m) => m.value).join(', '),
        }),
      );

  /// The request method.
  final HttpMethod method;

  /// The methods the path supports.
  final Set<HttpMethod> supported;
}

/// The request's `Content-Type` is not one the handler consumes: 415 with
/// `Accept`, like Spring's `HttpMediaTypeNotSupportedException`.
class HttpMediaTypeNotSupportedException extends ErrorResponseException {
  /// [contentType] is not one of [supported].
  HttpMediaTypeNotSupportedException(this.contentType, this.supported)
    : super(
        HttpStatus.unsupportedMediaType,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.unsupportedMediaType,
          "Content-Type '${contentType ?? ''}' is not supported.",
        ),
        headers: HttpHeaders({
          if (supported.isNotEmpty)
            HttpHeaders.acceptHeader: supported.join(', '),
        }),
      );

  /// The request's content type.
  final String? contentType;

  /// What the handler accepts.
  final List<String> supported;
}

/// The handler cannot produce what `Accept` asks for: 406, like Spring's
/// `HttpMediaTypeNotAcceptableException`.
class HttpMediaTypeNotAcceptableException extends ErrorResponseException {
  /// None of [supported] is acceptable.
  HttpMediaTypeNotAcceptableException(this.supported)
    : super(
        HttpStatus.notAcceptable,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.notAcceptable,
          'Acceptable representations: [${supported.join(', ')}].',
        ),
      );

  /// What the handler produces.
  final List<String> supported;
}

/// A required request value is missing: 400, like Spring's
/// `MissingRequestValueException` family.
class MissingRequestValueException extends ErrorResponseException {
  /// The [kind] (`parameter`, `header`, `cookie`, `path variable`) [name]
  /// is missing.
  MissingRequestValueException(this.kind, this.name)
    : super(
        HttpStatus.badRequest,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.badRequest,
          "Required $kind '$name' is not present.",
        ),
      );

  /// What is missing: `parameter`, `header`, `cookie` or `path variable`.
  final String kind;

  /// Its name.
  final String name;
}

/// A request value cannot be converted to the parameter's type: 400, like
/// Spring's `MethodArgumentTypeMismatchException`.
class MethodArgumentTypeMismatchException extends ErrorResponseException {
  /// [value] of [name] is not a [requiredType].
  MethodArgumentTypeMismatchException(
    this.name,
    this.value,
    this.requiredType, [
    Object? cause,
  ]) : super(
         HttpStatus.badRequest,
         body: ProblemDetail.forStatusAndDetail(
           HttpStatus.badRequest,
           "Failed to convert '$name' with value: '$value'",
         ),
         cause: cause,
       );

  /// The parameter (or variable, header) name.
  final String name;

  /// The text sent.
  final String value;

  /// The type it should have been.
  final String requiredType;
}

/// The body cannot be read (missing, malformed JSON, wrong shape): 400,
/// like Spring's `HttpMessageNotReadableException`.
class HttpMessageNotReadableException extends ErrorResponseException {
  /// The body is unreadable because of [message].
  HttpMessageNotReadableException(this.message, [Object? cause])
    : super(
        HttpStatus.badRequest,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.badRequest,
          'Failed to read request',
        ),
        cause: cause,
      );

  /// Why (not sent to the client).
  final String message;

  @override
  String toString() => 'HttpMessageNotReadableException: $message';
}

/// A `@Valid` argument has constraint violations: 400 with the field
/// errors, like Spring's `MethodArgumentNotValidException`. The problem
/// lists them as `errors`: `[{"field": "isbn", "message": "...",
/// "rejectedValue": ""}]`.
class MethodArgumentNotValidException extends ErrorResponseException {
  /// The argument [parameterName] failed validation; [bindingResult]
  /// holds the errors.
  MethodArgumentNotValidException(this.parameterName, this.bindingResult)
    : super(
        HttpStatus.badRequest,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.badRequest,
          'Invalid request content.',
        ),
      );

  /// The parameter that was validated.
  final String parameterName;

  /// The errors.
  final BindingResult bindingResult;

  @override
  String toString() =>
      'MethodArgumentNotValidException: $parameterName: '
      '${bindingResult.errorCount} errors';
}

/// The request body is larger than `server.max-http-request-body-size`:
/// 413.
class PayloadTooLargeErrorException extends ErrorResponseException {
  /// The limit is [maxLength] bytes.
  PayloadTooLargeErrorException(int maxLength)
    : super(
        HttpStatus.contentTooLarge,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.contentTooLarge,
          'The request body exceeds $maxLength bytes.',
        ),
      );
}

/// An async request (an `SseEmitter`) timed out: 503, like Spring's
/// `AsyncRequestTimeoutException`.
class AsyncRequestTimeoutException extends ErrorResponseException {
  /// The timeout.
  AsyncRequestTimeoutException() : super(HttpStatus.serviceUnavailable);
}
