import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';

/// The body of an error response in the standard JSON form of RFC 9457
/// (`application/problem+json`): a status, a title, a detail message and
/// any extra fields.
///
/// It gives every error of an API the same shape, so clients can read
/// them all with the same code. The web server already answers its own
/// errors this way (a missing parameter, an invalid body, an unknown
/// path). Return one from a controller or an `@ExceptionHandler` method
/// to answer an application error the same way: the server writes it with
/// its [status], as `application/problem+json`, and fills [instance] with
/// the request path when it is not set. On the client side,
/// [ProblemDetail.fromJson] reads such a body from an error answer.
///
/// ```dart
/// // In a @ControllerAdvice: an unknown book is a 404 problem that also
/// // names the ISBN.
/// @ExceptionHandler()
/// ProblemDetail notFound(BookNotFoundException e) =>
///     ProblemDetail.forStatusAndDetail(HttpStatus.notFound, 'No book')
///       ..setProperty('isbn', e.isbn);
/// // {"type": "about:blank", "title": "Not Found", "status": 404,
/// //  "detail": "No book", "instance": "/books/978-0", "isbn": "978-0"}
/// ```
///
/// Spring (Java):
/// ```java
/// @ExceptionHandler
/// ProblemDetail notFound(BookNotFoundException e) {
///   ProblemDetail problem =
///       ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, "No book");
///   problem.setProperty("isbn", e.getIsbn());
///   return problem;
/// }
/// ```
class ProblemDetail {
  /// A problem with [status] and any of the standard members; [type]
  /// defaults to [blankType].
  ProblemDetail(
    this.status, {
    Uri? type,
    this.title,
    this.detail,
    this.instance,
    Map<String, Object?>? properties,
  }) : type = type ?? blankType,
       properties = properties ?? {};

  /// A problem with [status] only; its title will be the status's reason
  /// phrase (`Not Found` for 404).
  factory ProblemDetail.forStatus(int status) => ProblemDetail(status);

  /// A problem with [status] and a [detail] message for the client; the
  /// most common way to make one.
  factory ProblemDetail.forStatusAndDetail(int status, String? detail) =>
      ProblemDetail(status, detail: detail);

  /// Reads a problem from its decoded JSON, such as the body of an error
  /// answer received by a client. Members other than the standard five go
  /// to [properties]. A missing `status` is read as 500.
  factory ProblemDetail.fromJson(Map<String, Object?> json) {
    final known = {'type', 'title', 'status', 'detail', 'instance'};
    return ProblemDetail(
      (json['status'] as num?)?.toInt() ?? 500,
      type: switch (json['type']) {
        final String type => Uri.parse(type),
        _ => null,
      },
      title: json['title'] as String?,
      detail: json['detail'] as String?,
      instance: switch (json['instance']) {
        final String instance => Uri.parse(instance),
        _ => null,
      },
      properties: {
        for (final entry in json.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  /// `about:blank`, the default [type]: the problem has no type of its
  /// own, and the status says what kind of error it is.
  static final Uri blankType = Uri.parse('about:blank');

  /// The HTTP status code. When a server writes the problem, the response
  /// gets this status.
  int status;

  /// A URI naming the kind of problem, for clients that tell problems
  /// apart by type (`https://example.com/problems/out-of-stock`);
  /// [blankType] when there is none.
  Uri type;

  /// A short, human-readable summary of the kind of problem; when `null`,
  /// the JSON uses the status's reason phrase (see [effectiveTitle]).
  String? title;

  /// An explanation of this particular error for the client, such as
  /// `No book 978-0`.
  String? detail;

  /// A URI for this particular error, usually the request path; a server
  /// sets it to the path when it is `null`.
  Uri? instance;

  /// Extra members, written into the JSON next to the standard ones; for
  /// example the field errors of a failed validation, under `errors`.
  final Map<String, Object?> properties;

  /// Adds the extra member [name] with [value] to [properties], replacing
  /// an earlier value.
  void setProperty(String name, Object? value) => properties[name] = value;

  /// The [title], or the status's reason phrase when it is `null`;
  /// `null` only for a status without a known phrase.
  String? get effectiveTitle =>
      title ?? HttpStatus.resolve(status)?.reasonPhrase;

  /// The JSON object: [type], [effectiveTitle], [status], [detail] and
  /// [instance] (leaving out `null`s), then [properties]. A property with a
  /// standard name replaces that member.
  Map<String, Object?> toJson() => {
    'type': type.toString(),
    'title': ?effectiveTitle,
    'status': status,
    'detail': ?detail,
    if (instance case final instance?) 'instance': instance.toString(),
    ...properties,
  };

  @override
  String toString() => 'ProblemDetail${toJson()}';
}

/// An error that carries its own HTTP answer: a status, headers and a
/// [ProblemDetail] body.
///
/// When a controller throws an error implementing it, the server answers
/// with that status, headers and body instead of a generic 500. Every
/// error of the web server (unknown path, wrong method, invalid body, ...)
/// is one. Most applications throw [ResponseStatusException] or extend
/// [ErrorResponseException] rather than implement this interface.
///
/// Spring (Java): `ErrorResponse`.
abstract interface class ErrorResponse {
  /// The HTTP status of the answer.
  int get statusCode;

  /// Headers to add to the answer, such as `Allow` for a wrong method or
  /// `WWW-Authenticate` for a missing login.
  HttpHeaders get headers;

  /// The problem written as the body; the server sets its status to
  /// [statusCode].
  ProblemDetail get body;
}

/// An exception that makes the server answer with a given status, headers
/// and problem body: the base class of the web server's own errors.
///
/// Throw it from a controller (or from code it calls) when the answer
/// needs more than a status and a message, such as extra headers or
/// properties in the problem. Subclass it for an application error that
/// always has the same answer. For just a status and a message,
/// [ResponseStatusException] is shorter.
///
/// ```dart
/// // Too many requests: 429 with the time to wait.
/// throw ErrorResponseException(
///   HttpStatus.tooManyRequests,
///   headers: HttpHeaders()..set(HttpHeaders.retryAfterHeader, '30'),
///   body: ProblemDetail.forStatusAndDetail(
///     HttpStatus.tooManyRequests,
///     'Try again in 30 seconds',
///   ),
/// );
/// ```
///
/// Spring (Java): `ErrorResponseException`.
class ErrorResponseException implements Exception, ErrorResponse {
  /// An error answered with [statusCode], [headers] (none by default) and
  /// [body] (by default a problem with the status only); [cause] is the
  /// error that led to it, if any.
  ErrorResponseException(
    this.statusCode, {
    ProblemDetail? body,
    HttpHeaders? headers,
    this.cause,
  }) : body = body ?? ProblemDetail.forStatus(statusCode),
       headers = headers ?? HttpHeaders();

  @override
  final int statusCode;

  @override
  final ProblemDetail body;

  @override
  final HttpHeaders headers;

  /// The error that led to this one, or `null`; it is not sent to the
  /// client.
  final Object? cause;

  @override
  String toString() =>
      // The text names the actual class, subclasses included, like Java's
      // getClass().getName().
      // ignore: no_runtimetype_tostring
      '$runtimeType: $statusCode'
      '${body.detail == null ? '' : ' ${body.detail}'}';
}

/// An exception that makes the server answer with a status code and an
/// optional message.
///
/// It is the quickest way to end a request with an error from anywhere in
/// a controller: the server answers with [statusCode] and a problem whose
/// detail is [reason]. Use [ErrorResponseException] when the answer needs
/// headers too, or an `@ExceptionHandler` to map your own exception types.
///
/// ```dart
/// @GetMapping('/books/{isbn}')
/// Future<Book> find(@PathVariable() String isbn) async =>
///     await books.findOrNull(isbn) ??
///     (throw ResponseStatusException(HttpStatus.notFound, 'No book $isbn'));
/// ```
///
/// Spring (Java):
/// ```java
/// throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No book " + isbn);
/// ```
class ResponseStatusException extends ErrorResponseException {
  /// An error answered with [statusCode] and [reason] as the problem's
  /// detail; [cause] is the error that led to it, if any.
  ResponseStatusException(super.statusCode, [this.reason, Object? cause])
    : super(
        body: ProblemDetail.forStatusAndDetail(statusCode, reason),
        cause: cause,
      );

  /// The message sent to the client as the problem's detail, or `null`.
  final String? reason;
}
