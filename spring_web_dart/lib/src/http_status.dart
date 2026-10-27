/// An HTTP status code, known or not, like Spring's `HttpStatusCode`: an
/// `int` with the `is2xxSuccessful`-style checks. What `ResponseEntity`,
/// `HttpResponse` and `StreamedHttpResponse` carry as `statusCode`; known
/// codes have an [HttpStatus] constant.
///
/// It is an extension type over `int`, so it compares with `int`s and
/// passes where an `int` is expected.
///
/// ```dart
/// final status = response.statusCode;  // HttpStatusCode
/// if (status.is4xxClientError) { ... }
/// status == 404;                        // true for a 404
/// HttpStatusCode.valueOf(599).isError;  // true (no constant for 599)
/// ```
///
/// Spring (Java):
/// ```java
/// HttpStatusCode status = response.getStatusCode();
/// if (status.is4xxClientError()) { ... }
/// HttpStatusCode.valueOf(599).isError();
/// ```
extension type const HttpStatusCode(int value) implements int {
  /// [code] as a status code; throws `ArgumentError` unless it has three
  /// digits (100–999), like Spring's `HttpStatusCode.valueOf`.
  factory HttpStatusCode.valueOf(int code) {
    if (code < 100 || code > 999) {
      throw ArgumentError.value(
        code,
        'code',
        'Status code must be a 3-digit positive integer',
      );
    }
    return HttpStatusCode(code);
  }

  /// Whether the code is 1xx Informational.
  bool get is1xxInformational => _series == 1;

  /// Whether the code is 2xx Successful.
  bool get is2xxSuccessful => _series == 2;

  /// Whether the code is 3xx Redirection.
  bool get is3xxRedirection => _series == 3;

  /// Whether the code is 4xx Client Error.
  bool get is4xxClientError => _series == 4;

  /// Whether the code is 5xx Server Error.
  bool get is5xxServerError => _series == 5;

  /// Whether the code is 4xx or 5xx.
  bool get isError => is4xxClientError || is5xxServerError;

  /// Whether [other] has the same code.
  bool isSameCodeAs(HttpStatusCode other) => value == other.value;

  int get _series => value ~/ 100;
}

/// The series of a status code (its first digit), like Spring's
/// `HttpStatus.Series`.
///
/// ```dart
/// HttpStatusSeries.valueOf(404);    // HttpStatusSeries.clientError
/// HttpStatus.ok.series;             // HttpStatusSeries.successful
/// ```
///
/// Spring (Java):
/// ```java
/// HttpStatus.Series.valueOf(404);   // CLIENT_ERROR
/// ```
enum HttpStatusSeries {
  /// 1xx.
  informational(1),

  /// 2xx.
  successful(2),

  /// 3xx.
  redirection(3),

  /// 4xx.
  clientError(4),

  /// 5xx.
  serverError(5);

  HttpStatusSeries(this.value);

  /// The first digit of the codes in this series.
  final int value;

  /// The series of [statusCode]; throws `ArgumentError` for a code outside
  /// 1xx–5xx.
  static HttpStatusSeries valueOf(int statusCode) =>
      resolve(statusCode) ??
      (throw ArgumentError.value(
        statusCode,
        'statusCode',
        'No matching series',
      ));

  /// The series of [statusCode], or `null` for a code outside 1xx–5xx.
  static HttpStatusSeries? resolve(int statusCode) {
    final digit = statusCode ~/ 100;
    for (final series in values) {
      if (series.value == digit) {
        return series;
      }
    }
    return null;
  }
}

/// The standard HTTP status codes, like Spring's `HttpStatus` with its
/// Spring Framework 7 names (`unprocessableContent`, `contentTooLarge`):
/// constants with [reasonPhrase], [series] and the checks of
/// [HttpStatusCode].
///
/// The constants are `int`s (an extension type over [HttpStatusCode]), so
/// `response.statusCode == HttpStatus.notFound` works directly.
///
/// ```dart
/// if (response.statusCode == HttpStatus.notFound) { ... }
/// HttpStatus.serviceUnavailable.reasonPhrase;    // 'Service Unavailable'
/// HttpStatus.valueOf(503).is5xxServerError;      // true
/// HttpStatus.resolve(599);                       // null
/// HttpStatus.created.series;                     // HttpStatusSeries.successful
/// ```
///
/// Spring (Java):
/// ```java
/// if (status == HttpStatus.NOT_FOUND) { ... }
/// HttpStatus.SERVICE_UNAVAILABLE.getReasonPhrase();
/// HttpStatus.valueOf(503).is5xxServerError();
/// HttpStatus.resolve(599);
/// ```
extension type const HttpStatus._(int value) implements HttpStatusCode {
  /// 100 Continue.
  static const continue_ = HttpStatus._(100);

  /// 101 Switching Protocols.
  static const switchingProtocols = HttpStatus._(101);

  /// 102 Processing (deprecated in Spring: dropped from the HTTP RFCs).
  static const processing = HttpStatus._(102);

  /// 103 Early Hints.
  static const earlyHints = HttpStatus._(103);

  /// 200 OK.
  static const ok = HttpStatus._(200);

  /// 201 Created.
  static const created = HttpStatus._(201);

  /// 202 Accepted.
  static const accepted = HttpStatus._(202);

  /// 203 Non-Authoritative Information.
  static const nonAuthoritativeInformation = HttpStatus._(203);

  /// 204 No Content.
  static const noContent = HttpStatus._(204);

  /// 205 Reset Content.
  static const resetContent = HttpStatus._(205);

  /// 206 Partial Content.
  static const partialContent = HttpStatus._(206);

  /// 207 Multi-Status.
  static const multiStatus = HttpStatus._(207);

  /// 208 Already Reported.
  static const alreadyReported = HttpStatus._(208);

  /// 226 IM Used.
  static const imUsed = HttpStatus._(226);

  /// 300 Multiple Choices.
  static const multipleChoices = HttpStatus._(300);

  /// 301 Moved Permanently.
  static const movedPermanently = HttpStatus._(301);

  /// 302 Found.
  static const found = HttpStatus._(302);

  /// 303 See Other.
  static const seeOther = HttpStatus._(303);

  /// 304 Not Modified.
  static const notModified = HttpStatus._(304);

  /// 307 Temporary Redirect.
  static const temporaryRedirect = HttpStatus._(307);

  /// 308 Permanent Redirect.
  static const permanentRedirect = HttpStatus._(308);

  /// 400 Bad Request.
  static const badRequest = HttpStatus._(400);

  /// 401 Unauthorized.
  static const unauthorized = HttpStatus._(401);

  /// 402 Payment Required.
  static const paymentRequired = HttpStatus._(402);

  /// 403 Forbidden.
  static const forbidden = HttpStatus._(403);

  /// 404 Not Found.
  static const notFound = HttpStatus._(404);

  /// 405 Method Not Allowed.
  static const methodNotAllowed = HttpStatus._(405);

  /// 406 Not Acceptable.
  static const notAcceptable = HttpStatus._(406);

  /// 407 Proxy Authentication Required.
  static const proxyAuthenticationRequired = HttpStatus._(407);

  /// 408 Request Timeout.
  static const requestTimeout = HttpStatus._(408);

  /// 409 Conflict.
  static const conflict = HttpStatus._(409);

  /// 410 Gone.
  static const gone = HttpStatus._(410);

  /// 411 Length Required.
  static const lengthRequired = HttpStatus._(411);

  /// 412 Precondition Failed.
  static const preconditionFailed = HttpStatus._(412);

  /// 413 Content Too Large (formerly Payload Too Large).
  static const contentTooLarge = HttpStatus._(413);

  /// 414 URI Too Long.
  static const uriTooLong = HttpStatus._(414);

  /// 415 Unsupported Media Type.
  static const unsupportedMediaType = HttpStatus._(415);

  /// 416 Requested range not satisfiable.
  static const requestedRangeNotSatisfiable = HttpStatus._(416);

  /// 417 Expectation Failed.
  static const expectationFailed = HttpStatus._(417);

  /// 418 I'm a teapot (deprecated in Spring).
  static const iAmATeapot = HttpStatus._(418);

  /// 421 Misdirected Request.
  static const misdirectedRequest = HttpStatus._(421);

  /// 422 Unprocessable Content (formerly Unprocessable Entity).
  static const unprocessableContent = HttpStatus._(422);

  /// 423 Locked.
  static const locked = HttpStatus._(423);

  /// 424 Failed Dependency.
  static const failedDependency = HttpStatus._(424);

  /// 425 Too Early.
  static const tooEarly = HttpStatus._(425);

  /// 426 Upgrade Required.
  static const upgradeRequired = HttpStatus._(426);

  /// 428 Precondition Required.
  static const preconditionRequired = HttpStatus._(428);

  /// 429 Too Many Requests.
  static const tooManyRequests = HttpStatus._(429);

  /// 431 Request Header Fields Too Large.
  static const requestHeaderFieldsTooLarge = HttpStatus._(431);

  /// 451 Unavailable For Legal Reasons.
  static const unavailableForLegalReasons = HttpStatus._(451);

  /// 500 Internal Server Error.
  static const internalServerError = HttpStatus._(500);

  /// 501 Not Implemented.
  static const notImplemented = HttpStatus._(501);

  /// 502 Bad Gateway.
  static const badGateway = HttpStatus._(502);

  /// 503 Service Unavailable.
  static const serviceUnavailable = HttpStatus._(503);

  /// 504 Gateway Timeout.
  static const gatewayTimeout = HttpStatus._(504);

  /// 505 HTTP Version not supported.
  static const httpVersionNotSupported = HttpStatus._(505);

  /// 506 Variant Also Negotiates.
  static const variantAlsoNegotiates = HttpStatus._(506);

  /// 507 Insufficient Storage.
  static const insufficientStorage = HttpStatus._(507);

  /// 508 Loop Detected.
  static const loopDetected = HttpStatus._(508);

  /// 509 Bandwidth Limit Exceeded (deprecated in Spring).
  static const bandwidthLimitExceeded = HttpStatus._(509);

  /// 510 Not Extended (deprecated in Spring).
  static const notExtended = HttpStatus._(510);

  /// 511 Network Authentication Required.
  static const networkAuthenticationRequired = HttpStatus._(511);

  /// Every constant, by code.
  static const List<HttpStatus> values = [
    continue_,
    switchingProtocols,
    processing,
    earlyHints,
    ok,
    created,
    accepted,
    nonAuthoritativeInformation,
    noContent,
    resetContent,
    partialContent,
    multiStatus,
    alreadyReported,
    imUsed,
    multipleChoices,
    movedPermanently,
    found,
    seeOther,
    notModified,
    temporaryRedirect,
    permanentRedirect,
    badRequest,
    unauthorized,
    paymentRequired,
    forbidden,
    notFound,
    methodNotAllowed,
    notAcceptable,
    proxyAuthenticationRequired,
    requestTimeout,
    conflict,
    gone,
    lengthRequired,
    preconditionFailed,
    contentTooLarge,
    uriTooLong,
    unsupportedMediaType,
    requestedRangeNotSatisfiable,
    expectationFailed,
    iAmATeapot,
    misdirectedRequest,
    unprocessableContent,
    locked,
    failedDependency,
    tooEarly,
    upgradeRequired,
    preconditionRequired,
    tooManyRequests,
    requestHeaderFieldsTooLarge,
    unavailableForLegalReasons,
    internalServerError,
    notImplemented,
    badGateway,
    serviceUnavailable,
    gatewayTimeout,
    httpVersionNotSupported,
    variantAlsoNegotiates,
    insufficientStorage,
    loopDetected,
    bandwidthLimitExceeded,
    notExtended,
    networkAuthenticationRequired,
  ];

  static const _phrases = {
    100: 'Continue',
    101: 'Switching Protocols',
    102: 'Processing',
    103: 'Early Hints',
    200: 'OK',
    201: 'Created',
    202: 'Accepted',
    203: 'Non-Authoritative Information',
    204: 'No Content',
    205: 'Reset Content',
    206: 'Partial Content',
    207: 'Multi-Status',
    208: 'Already Reported',
    226: 'IM Used',
    300: 'Multiple Choices',
    301: 'Moved Permanently',
    302: 'Found',
    303: 'See Other',
    304: 'Not Modified',
    307: 'Temporary Redirect',
    308: 'Permanent Redirect',
    400: 'Bad Request',
    401: 'Unauthorized',
    402: 'Payment Required',
    403: 'Forbidden',
    404: 'Not Found',
    405: 'Method Not Allowed',
    406: 'Not Acceptable',
    407: 'Proxy Authentication Required',
    408: 'Request Timeout',
    409: 'Conflict',
    410: 'Gone',
    411: 'Length Required',
    412: 'Precondition Failed',
    413: 'Content Too Large',
    414: 'URI Too Long',
    415: 'Unsupported Media Type',
    416: 'Requested range not satisfiable',
    417: 'Expectation Failed',
    418: "I'm a teapot",
    421: 'Misdirected Request',
    422: 'Unprocessable Content',
    423: 'Locked',
    424: 'Failed Dependency',
    425: 'Too Early',
    426: 'Upgrade Required',
    428: 'Precondition Required',
    429: 'Too Many Requests',
    431: 'Request Header Fields Too Large',
    451: 'Unavailable For Legal Reasons',
    500: 'Internal Server Error',
    501: 'Not Implemented',
    502: 'Bad Gateway',
    503: 'Service Unavailable',
    504: 'Gateway Timeout',
    505: 'HTTP Version not supported',
    506: 'Variant Also Negotiates',
    507: 'Insufficient Storage',
    508: 'Loop Detected',
    509: 'Bandwidth Limit Exceeded',
    510: 'Not Extended',
    511: 'Network Authentication Required',
  };

  /// The constant for [statusCode]; throws `ArgumentError` when there is
  /// none (see [resolve]).
  static HttpStatus valueOf(int statusCode) =>
      resolve(statusCode) ??
      (throw ArgumentError.value(
        statusCode,
        'statusCode',
        'No matching constant',
      ));

  /// The constant for [statusCode], or `null` when there is none.
  static HttpStatus? resolve(int statusCode) =>
      _phrases.containsKey(statusCode) ? HttpStatus._(statusCode) : null;

  /// The reason phrase: `Not Found` for 404.
  String get reasonPhrase => _phrases[value]!;

  /// The series: [HttpStatusSeries.clientError] for 404.
  HttpStatusSeries get series => HttpStatusSeries.valueOf(value);
}
