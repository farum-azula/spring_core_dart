/// An HTTP status code (any three-digit number, standard or not) with
/// checks for its class: success, client error, server error, ...
///
/// It is the type of `statusCode` on `ResponseEntity`, `HttpResponse` and
/// `StreamedHttpResponse`, so code reading a response can write
/// `status.is4xxClientError` instead of comparing number ranges. It is an
/// extension type over `int`: it costs nothing at runtime, compares with
/// plain `int`s and passes wherever an `int` is expected. The standard
/// codes also have named constants in [HttpStatus]; a code without one
/// (such as 599 from some proxy) is still an [HttpStatusCode].
///
/// ```dart
/// // Retry a call only when the server, not the request, was at fault.
/// final status = response.statusCode;
/// if (status.is5xxServerError) {
///   return retry();
/// }
/// if (status == HttpStatus.notFound) {
///   return null;
/// }
/// ```
///
/// Spring (Java): `HttpStatusCode`.
/// ```java
/// HttpStatusCode status = response.getStatusCode();
/// if (status.is5xxServerError()) {
///   return retry();
/// }
/// if (status.isSameCodeAs(HttpStatus.NOT_FOUND)) {
///   return null;
/// }
/// ```
extension type const HttpStatusCode(int value) implements int {
  /// [code] as a status code, checked: throws an `ArgumentError` unless it
  /// has three digits (100–999). The plain constructor does not check.
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

  /// Whether the code is 1xx, Informational: an interim answer.
  bool get is1xxInformational => _series == 1;

  /// Whether the code is 2xx, Successful.
  bool get is2xxSuccessful => _series == 2;

  /// Whether the code is 3xx, Redirection: the resource is elsewhere or
  /// unchanged.
  bool get is3xxRedirection => _series == 3;

  /// Whether the code is 4xx, Client Error: the request was wrong.
  bool get is4xxClientError => _series == 4;

  /// Whether the code is 5xx, Server Error: the server failed.
  bool get is5xxServerError => _series == 5;

  /// Whether the code is an error, 4xx or 5xx.
  bool get isError => is4xxClientError || is5xxServerError;

  /// Whether [other] has the same code; the same as `==`, kept for code
  /// written after Spring.
  bool isSameCodeAs(HttpStatusCode other) => value == other.value;

  int get _series => value ~/ 100;
}

/// The five classes of HTTP status codes, named by their first digit:
/// informational (1xx), successful, redirection, client error and server
/// error (5xx).
///
/// Use it to switch over the kind of answer rather than over single
/// codes. For a yes/no question, the checks of [HttpStatusCode]
/// (`is2xxSuccessful`, ...) are shorter.
///
/// ```dart
/// // Count answers by class for a metrics dashboard.
/// final series = HttpStatusSeries.resolve(response.statusCode);
/// counts.update(series?.name ?? 'other', (n) => n + 1, ifAbsent: () => 1);
///
/// HttpStatusSeries.valueOf(404); // HttpStatusSeries.clientError
/// HttpStatus.ok.series;          // HttpStatusSeries.successful
/// ```
///
/// Spring (Java): `HttpStatus.Series`.
/// ```java
/// HttpStatus.Series series = HttpStatus.Series.resolve(statusCode);
/// HttpStatus.Series.valueOf(404); // CLIENT_ERROR
/// ```
enum HttpStatusSeries {
  /// 1xx: an interim answer; the final one follows.
  informational(1),

  /// 2xx: the request succeeded.
  successful(2),

  /// 3xx: the client should look elsewhere, or use its cached copy.
  redirection(3),

  /// 4xx: the request was wrong.
  clientError(4),

  /// 5xx: the server failed to answer a valid request.
  serverError(5);

  HttpStatusSeries(this.value);

  /// The first digit of the codes in this series: 4 for client errors.
  final int value;

  /// The series of [statusCode]; throws an `ArgumentError` for a code
  /// outside 100–599. Use [resolve] when the code may be unusual.
  static HttpStatusSeries valueOf(int statusCode) =>
      resolve(statusCode) ??
      (throw ArgumentError.value(
        statusCode,
        'statusCode',
        'No matching series',
      ));

  /// The series of [statusCode], or `null` for a code outside 100–599.
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

/// The standard HTTP status codes as named constants (`HttpStatus.ok`,
/// `HttpStatus.notFound`, ...), each with its reason phrase.
///
/// Use the constants wherever a status is written or tested, so the code
/// says `HttpStatus.created` instead of `201`: in `@ResponseStatus`, in
/// `ResponseEntity.status`, in `ResponseStatusException`, when checking a
/// response. They are extension types over `int` (through
/// [HttpStatusCode]), so they compare with plain numbers and with any
/// `statusCode`, and they have the checks of [HttpStatusCode] too. The
/// names are those of Spring Framework 7, which follow RFC 9110
/// (`unprocessableContent` for 422, `contentTooLarge` for 413).
///
/// ```dart
/// // In a controller: an unknown book is a 404.
/// throw ResponseStatusException(HttpStatus.notFound, 'No book $isbn');
///
/// // On a client: tell "gone" apart from other errors.
/// if (response.statusCode == HttpStatus.gone) { ... }
///
/// HttpStatus.serviceUnavailable.reasonPhrase; // 'Service Unavailable'
/// HttpStatus.resolve(599);                    // null: not standard
/// ```
///
/// Spring (Java): `HttpStatus`, an enum there.
/// ```java
/// throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No book " + isbn);
///
/// if (response.getStatusCode() == HttpStatus.GONE) { ... }
///
/// HttpStatus.SERVICE_UNAVAILABLE.getReasonPhrase();
/// HttpStatus.resolve(599);
/// ```
extension type const HttpStatus._(int value) implements HttpStatusCode {
  /// 100 Continue: the client may send the request body. Named with a
  /// trailing `_` because `continue` is a Dart keyword.
  static const continue_ = HttpStatus._(100);

  /// 101 Switching Protocols: the connection changes protocol, as when a
  /// WebSocket opens.
  static const switchingProtocols = HttpStatus._(101);

  /// 102 Processing: still working (WebDAV). Deprecated in Spring, as it
  /// was dropped from the HTTP RFCs.
  static const processing = HttpStatus._(102);

  /// 103 Early Hints: headers sent ahead of the final answer, so the
  /// browser can start loading linked resources.
  static const earlyHints = HttpStatus._(103);

  /// 200 OK: the request succeeded; the usual answer.
  static const ok = HttpStatus._(200);

  /// 201 Created: a new resource was made; its address goes in the
  /// `Location` header.
  static const created = HttpStatus._(201);

  /// 202 Accepted: the request was taken and will be processed later.
  static const accepted = HttpStatus._(202);

  /// 203 Non-Authoritative Information: a proxy changed the answer of the
  /// origin server.
  static const nonAuthoritativeInformation = HttpStatus._(203);

  /// 204 No Content: success, with no body; common after a delete.
  static const noContent = HttpStatus._(204);

  /// 205 Reset Content: success; the client should reset its form.
  static const resetContent = HttpStatus._(205);

  /// 206 Partial Content: the body is the part asked for with `Range`.
  static const partialContent = HttpStatus._(206);

  /// 207 Multi-Status: several statuses in the body (WebDAV).
  static const multiStatus = HttpStatus._(207);

  /// 208 Already Reported: members listed earlier are not repeated
  /// (WebDAV).
  static const alreadyReported = HttpStatus._(208);

  /// 226 IM Used: the body is a delta applied to the current resource.
  static const imUsed = HttpStatus._(226);

  /// 300 Multiple Choices: the resource has several forms to pick from.
  static const multipleChoices = HttpStatus._(300);

  /// 301 Moved Permanently: the resource has a new address for good, in
  /// `Location`.
  static const movedPermanently = HttpStatus._(301);

  /// 302 Found: the resource is at another address for now, in
  /// `Location`.
  static const found = HttpStatus._(302);

  /// 303 See Other: get the result at the address in `Location`; the
  /// usual answer after a form post.
  static const seeOther = HttpStatus._(303);

  /// 304 Not Modified: the client's cached copy is still current; no
  /// body.
  static const notModified = HttpStatus._(304);

  /// 307 Temporary Redirect: repeat the same request at the address in
  /// `Location`, for now.
  static const temporaryRedirect = HttpStatus._(307);

  /// 308 Permanent Redirect: repeat the same request at the address in
  /// `Location`, for good.
  static const permanentRedirect = HttpStatus._(308);

  /// 400 Bad Request: the request is malformed or misses a value; the
  /// usual answer to a failed validation.
  static const badRequest = HttpStatus._(400);

  /// 401 Unauthorized: the request needs authentication (a login or a
  /// token) that is missing or wrong.
  static const unauthorized = HttpStatus._(401);

  /// 402 Payment Required: reserved for future use.
  static const paymentRequired = HttpStatus._(402);

  /// 403 Forbidden: the caller is known but not allowed to do this.
  static const forbidden = HttpStatus._(403);

  /// 404 Not Found: nothing exists at this path.
  static const notFound = HttpStatus._(404);

  /// 405 Method Not Allowed: the path exists but not with this method;
  /// the `Allow` header lists the valid ones.
  static const methodNotAllowed = HttpStatus._(405);

  /// 406 Not Acceptable: the server cannot answer in any media type the
  /// `Accept` header allows.
  static const notAcceptable = HttpStatus._(406);

  /// 407 Proxy Authentication Required: a proxy needs the client to
  /// authenticate.
  static const proxyAuthenticationRequired = HttpStatus._(407);

  /// 408 Request Timeout: the client took too long to send the request.
  static const requestTimeout = HttpStatus._(408);

  /// 409 Conflict: the request clashes with the current state, such as a
  /// duplicate or an outdated version.
  static const conflict = HttpStatus._(409);

  /// 410 Gone: the resource existed but was removed for good.
  static const gone = HttpStatus._(410);

  /// 411 Length Required: the request needs a `Content-Length` header.
  static const lengthRequired = HttpStatus._(411);

  /// 412 Precondition Failed: a condition such as `If-Match` does not
  /// hold.
  static const preconditionFailed = HttpStatus._(412);

  /// 413 Content Too Large, formerly Payload Too Large: the body is over
  /// the server's limit.
  static const contentTooLarge = HttpStatus._(413);

  /// 414 URI Too Long: the URL is longer than the server accepts.
  static const uriTooLong = HttpStatus._(414);

  /// 415 Unsupported Media Type: the server cannot read a body of this
  /// `Content-Type`.
  static const unsupportedMediaType = HttpStatus._(415);

  /// 416 Requested range not satisfiable: the `Range` asked for lies
  /// outside the resource.
  static const requestedRangeNotSatisfiable = HttpStatus._(416);

  /// 417 Expectation Failed: the server cannot meet the `Expect` header.
  static const expectationFailed = HttpStatus._(417);

  /// 418 I'm a teapot: an April Fools' joke of RFC 2324. Deprecated in
  /// Spring.
  static const iAmATeapot = HttpStatus._(418);

  /// 421 Misdirected Request: the request reached a server that cannot
  /// answer for this host.
  static const misdirectedRequest = HttpStatus._(421);

  /// 422 Unprocessable Content, formerly Unprocessable Entity: the body
  /// is well formed but its content is not valid.
  static const unprocessableContent = HttpStatus._(422);

  /// 423 Locked: the resource is locked (WebDAV).
  static const locked = HttpStatus._(423);

  /// 424 Failed Dependency: an action this one depends on failed
  /// (WebDAV).
  static const failedDependency = HttpStatus._(424);

  /// 425 Too Early: the server will not risk processing a request that
  /// might be replayed.
  static const tooEarly = HttpStatus._(425);

  /// 426 Upgrade Required: the client must switch to another protocol,
  /// named in the `Upgrade` header.
  static const upgradeRequired = HttpStatus._(426);

  /// 428 Precondition Required: the request must be conditional (with
  /// `If-Match`), to avoid lost updates.
  static const preconditionRequired = HttpStatus._(428);

  /// 429 Too Many Requests: the caller hit a rate limit; `Retry-After`
  /// may say when to try again.
  static const tooManyRequests = HttpStatus._(429);

  /// 431 Request Header Fields Too Large: the headers are over the
  /// server's limit.
  static const requestHeaderFieldsTooLarge = HttpStatus._(431);

  /// 451 Unavailable For Legal Reasons: the resource is blocked by law.
  static const unavailableForLegalReasons = HttpStatus._(451);

  /// 500 Internal Server Error: the server failed unexpectedly; the
  /// answer to an unhandled exception.
  static const internalServerError = HttpStatus._(500);

  /// 501 Not Implemented: the server does not support this function.
  static const notImplemented = HttpStatus._(501);

  /// 502 Bad Gateway: a gateway or proxy got an invalid answer from the
  /// server behind it.
  static const badGateway = HttpStatus._(502);

  /// 503 Service Unavailable: the server is overloaded or down for
  /// maintenance; `Retry-After` may say for how long.
  static const serviceUnavailable = HttpStatus._(503);

  /// 504 Gateway Timeout: a gateway or proxy got no answer in time from
  /// the server behind it.
  static const gatewayTimeout = HttpStatus._(504);

  /// 505 HTTP Version not supported: the server does not speak the
  /// request's HTTP version.
  static const httpVersionNotSupported = HttpStatus._(505);

  /// 506 Variant Also Negotiates: the server's content negotiation is
  /// misconfigured.
  static const variantAlsoNegotiates = HttpStatus._(506);

  /// 507 Insufficient Storage: the server has no room to store the
  /// result (WebDAV).
  static const insufficientStorage = HttpStatus._(507);

  /// 508 Loop Detected: the server found an infinite loop (WebDAV).
  static const loopDetected = HttpStatus._(508);

  /// 509 Bandwidth Limit Exceeded: not standard, used by some hosting
  /// servers. Deprecated in Spring.
  static const bandwidthLimitExceeded = HttpStatus._(509);

  /// 510 Not Extended: the request needs an HTTP extension the server
  /// lacks. Deprecated in Spring.
  static const notExtended = HttpStatus._(510);

  /// 511 Network Authentication Required: the client must log in to the
  /// network first, as on a hotel Wi-Fi.
  static const networkAuthenticationRequired = HttpStatus._(511);

  /// Every constant, in order of code.
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

  /// The constant for [statusCode]; throws an `ArgumentError` for a code
  /// without one. Use [resolve] when the code may be non-standard.
  static HttpStatus valueOf(int statusCode) =>
      resolve(statusCode) ??
      (throw ArgumentError.value(
        statusCode,
        'statusCode',
        'No matching constant',
      ));

  /// The constant for [statusCode], or `null` for a code without one;
  /// handy to get a [reasonPhrase] for any received code.
  static HttpStatus? resolve(int statusCode) =>
      _phrases.containsKey(statusCode) ? HttpStatus._(statusCode) : null;

  /// The standard text of the status, as in the status line:
  /// `Not Found` for 404.
  String get reasonPhrase => _phrases[value]!;

  /// The class of the status: [HttpStatusSeries.clientError] for 404.
  HttpStatusSeries get series => HttpStatusSeries.valueOf(value);
}
