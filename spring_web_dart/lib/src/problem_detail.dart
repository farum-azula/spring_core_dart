import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_status.dart';

/// An error response body following RFC 9457 (`application/problem+json`),
/// like Spring's `ProblemDetail`: [type], [title], [status], [detail],
/// [instance], and extra [properties] written next to them.
///
/// ```dart
/// final problem = ProblemDetail.forStatusAndDetail(
///   HttpStatus.notFound,
///   'No book 978-0',
/// )..setProperty('isbn', '978-0');
/// problem.toJson();
/// // {type: about:blank, title: Not Found, status: 404,
/// //  detail: No book 978-0, isbn: 978-0}
/// ```
///
/// Spring (Java):
/// ```java
/// ProblemDetail problem =
///     ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, "No book 978-0");
/// problem.setProperty("isbn", "978-0");
/// ```
class ProblemDetail {
  /// A problem with [status] and the other members.
  ProblemDetail(
    this.status, {
    Uri? type,
    this.title,
    this.detail,
    this.instance,
    Map<String, Object?>? properties,
  }) : type = type ?? blankType,
       properties = properties ?? {};

  /// A problem with [status] only (the title is its reason phrase).
  factory ProblemDetail.forStatus(int status) => ProblemDetail(status);

  /// A problem with [status] and [detail].
  factory ProblemDetail.forStatusAndDetail(int status, String? detail) =>
      ProblemDetail(status, detail: detail);

  /// Reads the JSON members of a problem (`status` is required).
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

  /// `about:blank`: no type of its own, the status says it all.
  static final Uri blankType = Uri.parse('about:blank');

  /// The HTTP status.
  int status;

  /// A URI identifying the problem type.
  Uri type;

  /// A short summary; the status's reason phrase when not set.
  String? title;

  /// An explanation of this occurrence.
  String? detail;

  /// A URI of this occurrence (usually the request path).
  Uri? instance;

  /// Extension members, written next to the standard ones.
  final Map<String, Object?> properties;

  /// Adds the extension member [name].
  void setProperty(String name, Object? value) => properties[name] = value;

  /// The title, or the status's reason phrase.
  String? get effectiveTitle =>
      title ?? HttpStatus.resolve(status)?.reasonPhrase;

  /// The JSON object: the standard members, then [properties].
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

/// An exception that knows its HTTP answer, like Spring's `ErrorResponse`:
/// a server writes [statusCode], [headers] and [body].
abstract interface class ErrorResponse {
  /// The status of the response.
  int get statusCode;

  /// Headers of the response (`Allow`, `WWW-Authenticate`, ...).
  HttpHeaders get headers;

  /// The body.
  ProblemDetail get body;
}

/// An exception carrying its response, like Spring's
/// `ErrorResponseException`. Throw it (or [ResponseStatusException]) from
/// a handler to answer with an error.
class ErrorResponseException implements Exception, ErrorResponse {
  /// An error with [statusCode] and [body] (by default a problem with the
  /// status only).
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

  /// What caused it, if anything.
  final Object? cause;

  @override
  String toString() =>
      // The text names the actual class, subclasses included, like Java's
      // getClass().getName().
      // ignore: no_runtimetype_tostring
      '$runtimeType: $statusCode'
      '${body.detail == null ? '' : ' ${body.detail}'}';
}

/// Answers with [statusCode] and [reason] as the detail, like Spring's
/// `ResponseStatusException`.
///
/// ```dart
/// throw ResponseStatusException(HttpStatus.notFound, 'No book $isbn');
/// ```
class ResponseStatusException extends ErrorResponseException {
  /// An error with [statusCode] and [reason].
  ResponseStatusException(super.statusCode, [this.reason, Object? cause])
    : super(
        body: ProblemDetail.forStatusAndDetail(statusCode, reason),
        cause: cause,
      );

  /// The detail of the answer.
  final String? reason;
}
