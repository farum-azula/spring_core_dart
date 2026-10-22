/// HTTP status codes and their reason phrases, like Spring's `HttpStatus`
/// (as plain `int`s, which is what responses carry).
///
/// ```dart
/// if (response.statusCode == HttpStatus.notFound) { ... }
/// HttpStatus.reasonPhrase(503);    // 'Service Unavailable'
/// HttpStatus.isServerError(503);   // true
/// ```
///
/// Spring (Java):
/// ```java
/// if (status == HttpStatus.NOT_FOUND) { ... }
/// HttpStatus.SERVICE_UNAVAILABLE.getReasonPhrase();
/// HttpStatus.valueOf(503).is5xxServerError();
/// ```
final class HttpStatus {
  HttpStatus._();

  /// 200 OK.
  static const ok = 200;

  /// 201 Created.
  static const created = 201;

  /// 202 Accepted.
  static const accepted = 202;

  /// 204 No Content.
  static const noContent = 204;

  /// 301 Moved Permanently.
  static const movedPermanently = 301;

  /// 302 Found.
  static const found = 302;

  /// 304 Not Modified.
  static const notModified = 304;

  /// 400 Bad Request.
  static const badRequest = 400;

  /// 401 Unauthorized.
  static const unauthorized = 401;

  /// 403 Forbidden.
  static const forbidden = 403;

  /// 404 Not Found.
  static const notFound = 404;

  /// 405 Method Not Allowed.
  static const methodNotAllowed = 405;

  /// 409 Conflict.
  static const conflict = 409;

  /// 410 Gone.
  static const gone = 410;

  /// 422 Unprocessable Entity.
  static const unprocessableEntity = 422;

  /// 429 Too Many Requests.
  static const tooManyRequests = 429;

  /// 500 Internal Server Error.
  static const internalServerError = 500;

  /// 502 Bad Gateway.
  static const badGateway = 502;

  /// 503 Service Unavailable.
  static const serviceUnavailable = 503;

  /// 504 Gateway Timeout.
  static const gatewayTimeout = 504;

  static const _phrases = {
    100: 'Continue',
    101: 'Switching Protocols',
    200: 'OK',
    201: 'Created',
    202: 'Accepted',
    203: 'Non-Authoritative Information',
    204: 'No Content',
    205: 'Reset Content',
    206: 'Partial Content',
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
    413: 'Payload Too Large',
    414: 'URI Too Long',
    415: 'Unsupported Media Type',
    416: 'Range Not Satisfiable',
    417: 'Expectation Failed',
    418: "I'm a teapot",
    422: 'Unprocessable Entity',
    423: 'Locked',
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
    505: 'HTTP Version Not Supported',
  };

  /// The standard reason phrase of [code] (`Not Found` for 404); a generic
  /// one (`Client Error`, ...) for codes without a standard phrase.
  static String reasonPhrase(int code) =>
      _phrases[code] ??
      switch (code ~/ 100) {
        1 => 'Informational',
        2 => 'Success',
        3 => 'Redirection',
        4 => 'Client Error',
        5 => 'Server Error',
        _ => 'Unknown',
      };

  /// Whether [code] is 2xx.
  static bool isSuccess(int code) => code >= 200 && code < 300;

  /// Whether [code] is 4xx.
  static bool isClientError(int code) => code >= 400 && code < 500;

  /// Whether [code] is 5xx.
  static bool isServerError(int code) => code >= 500 && code < 600;

  /// Whether [code] is 4xx or 5xx.
  static bool isError(int code) => code >= 400 && code < 600;
}
