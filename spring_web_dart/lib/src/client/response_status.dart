import 'package:spring_web_dart/src/http_status.dart';

/// Checks and converts the status code of a response received by a client.
/// It accepts three digits, as [HttpStatusCode.valueOf] does, and also 0:
/// the status of the opaque response a browser gives for a `fetch` with
/// `redirect: 'manual'`. Anything else throws an `ArgumentError`. Used by
/// the constructors of `HttpResponse` and `StreamedHttpResponse`.
HttpStatusCode clientResponseStatus(int code) =>
    code == 0 ? const HttpStatusCode(0) : HttpStatusCode.valueOf(code);
