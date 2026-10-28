import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The error of a request that no controller or other handler maps; it
/// is answered with a 404.
///
/// The dispatcher throws it when every handler mapping has passed on the
/// request, and also for a path outside `server.servlet.context-path`.
/// Catch it in a `@ControllerAdvice` to answer unknown paths your own
/// way.
///
/// ```dart
/// // Unknown API paths answer with a hint where the documentation is.
/// @ExceptionHandler()
/// @ResponseStatus(HttpStatus.notFound)
/// ProblemDetail unknown(NoHandlerFoundException e) =>
///     ProblemDetail.forStatusAndDetail(
///       HttpStatus.notFound,
///       'No ${e.path}; see https://shop.example/api-docs',
///     );
/// ```
///
/// Spring (Java):
/// ```java
/// @ExceptionHandler
/// ProblemDetail unknown(NoHandlerFoundException e) { ... }
/// ```
class NoHandlerFoundException extends ErrorResponseException {
  /// No handler for [method] on [path]; the detail says
  /// `No endpoint GET /x.`.
  NoHandlerFoundException(this.method, this.path)
    : super(
        HttpStatus.notFound,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.notFound,
          'No endpoint ${method.value} $path.',
        ),
      );

  /// The method of the request.
  final HttpMethod method;

  /// The path of the request.
  final String path;
}

/// The error of a request whose path is mapped, but not for its method,
/// such as a `DELETE` on a path that only has a `GET`; it is answered with
/// a 405 and an `Allow` header listing the methods the path supports.
///
/// The router throws it. Spring's counterpart is
/// `HttpRequestMethodNotSupportedException`.
class HttpRequestMethodNotSupportedException extends ErrorResponseException {
  /// [method] is not one of the [supported] methods of the path.
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

  /// The method of the request.
  final HttpMethod method;

  /// The methods the path supports (a `GET` mapping also supports
  /// `HEAD`).
  final Set<HttpMethod> supported;
}

/// The error of a request whose body has a `Content-Type` the handler
/// does not read; it is answered with a 415 and, when known, an `Accept`
/// header listing the types it reads.
///
/// The router throws it when no mapping's `consumes` matches, and the
/// body binding when a `@RequestBody` object comes in another type than
/// JSON. Spring's counterpart is `HttpMediaTypeNotSupportedException`.
class HttpMediaTypeNotSupportedException extends ErrorResponseException {
  /// [contentType] is not one of the [supported] types.
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

  /// The `Content-Type` of the request; `null` when it has none.
  final String? contentType;

  /// The media types the handler reads.
  final List<String> supported;
}

/// The error of a request whose `Accept` header admits nothing the
/// handler can write; it is answered with a 406.
///
/// The router throws it when no mapping's `produces` matches `Accept`,
/// and the response writer when an object cannot be written as JSON
/// because the client does not accept JSON. Spring's counterpart is
/// `HttpMediaTypeNotAcceptableException`.
class HttpMediaTypeNotAcceptableException extends ErrorResponseException {
  /// None of the [supported] types is acceptable to the client.
  HttpMediaTypeNotAcceptableException(this.supported)
    : super(
        HttpStatus.notAcceptable,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.notAcceptable,
          'Acceptable representations: [${supported.join(', ')}].',
        ),
      );

  /// The media types the handler can write.
  final List<String> supported;
}

/// The error of a request that lacks a value a controller parameter
/// requires; it is answered with a 400, such as
/// `Required parameter 'q' is not present.`.
///
/// A parameter is required unless it is nullable or has a default value,
/// so `@RequestParam('q') String q` throws this for a request without
/// `q`, while `String? q` gets `null`. Spring has one exception per kind
/// of value (`MissingServletRequestParameterException`, ...).
class MissingRequestValueException extends ErrorResponseException {
  /// The [kind] of value named [name] is missing.
  MissingRequestValueException(this.kind, this.name)
    : super(
        HttpStatus.badRequest,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.badRequest,
          "Required $kind '$name' is not present.",
        ),
      );

  /// The kind of value that is missing: `parameter`, `header`, `cookie`,
  /// `path variable` or `part`.
  final String kind;

  /// The name of the missing parameter, header, cookie, variable or part.
  final String name;
}

/// The error of a request value that does not convert to the type of its
/// parameter, such as `?page=two` for an `int page`; it is answered with
/// a 400 naming the parameter.
///
/// Spring's counterpart is `MethodArgumentTypeMismatchException`.
class MethodArgumentTypeMismatchException extends ErrorResponseException {
  /// The text [value] of [name] does not convert to [requiredType];
  /// [cause] is the conversion error.
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

  /// The name of the parameter, path variable, header or cookie.
  final String name;

  /// The text the request sent.
  final String value;

  /// The name of the type the parameter needs, such as `int`.
  final String requiredType;
}

/// The error of a request body, or a JSON part of an upload, that cannot
/// be read into its parameter: missing while required, malformed JSON, or
/// JSON of the wrong shape. It is answered with a 400 whose detail stays
/// vague (`Failed to read request`); the reason is in [message], for the
/// logs.
///
/// Spring's counterpart is `HttpMessageNotReadableException`.
class HttpMessageNotReadableException extends ErrorResponseException {
  /// The body cannot be read because of [message]; [cause] is the parse
  /// error, if any.
  HttpMessageNotReadableException(this.message, [Object? cause])
    : super(
        HttpStatus.badRequest,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.badRequest,
          'Failed to read request',
        ),
        cause: cause,
      );

  /// Why the body could not be read; not sent to the client.
  final String message;

  @override
  String toString() => 'HttpMessageNotReadableException: $message';
}

/// The error of a `@Valid()` argument that breaks its constraints; it is
/// answered with a 400 that lists the violations.
///
/// The problem's `errors` property has one entry per violation, with the
/// message resolved through the `MessageSource`:
/// `[{"field": "isbn", "message": "must not be blank", "rejectedValue": ""}]`.
/// Catch it in an `@ExceptionHandler` to answer in another shape.
///
/// ```dart
/// // Answer with a plain map of field to message.
/// @ExceptionHandler()
/// @ResponseStatus(HttpStatus.badRequest)
/// Map<String, String?> invalid(MethodArgumentNotValidException e) => {
///   for (final error in e.bindingResult.fieldErrors())
///     error.field: error.defaultMessage,
/// };
/// ```
///
/// Spring (Java):
/// ```java
/// @ExceptionHandler
/// Map<String, String> invalid(MethodArgumentNotValidException e) { ... }
/// ```
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

  /// The name of the parameter that was validated.
  final String parameterName;

  /// The violations, by field (`fieldErrors()`) and for the whole object
  /// (`globalErrors`).
  final BindingResult bindingResult;

  @override
  String toString() =>
      'MethodArgumentNotValidException: $parameterName: '
      '${bindingResult.errorCount} errors';
}

/// The error of a request body larger than
/// `server.max-http-request-body-size` (10 MB by default); it is answered
/// with a 413. Uploads have their own limit and error,
/// `MaxUploadSizeExceededException`.
class PayloadTooLargeErrorException extends ErrorResponseException {
  /// The body passed the limit of [maxLength] bytes.
  PayloadTooLargeErrorException(int maxLength)
    : super(
        HttpStatus.contentTooLarge,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.contentTooLarge,
          'The request body exceeds $maxLength bytes.',
        ),
      );
}

/// The error of an asynchronous request that timed out, answered with a
/// 503 when thrown.
///
/// The starter itself does not throw it: an `SseEmitter` that times out
/// just ends its stream. It exists so that application code can signal
/// such a timeout with Spring's name, `AsyncRequestTimeoutException`.
class AsyncRequestTimeoutException extends ErrorResponseException {
  /// A timeout, with the 503 problem and no detail.
  AsyncRequestTimeoutException() : super(HttpStatus.serviceUnavailable);
}
