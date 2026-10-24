import 'package:spring_web_dart/src/http_status.dart';

/// The status of a client response: three digits like
/// [HttpStatusCode.valueOf], or 0 for the opaque redirect a browser gives
/// for a `fetch` with `redirect: 'manual'`; anything else throws an
/// `ArgumentError`.
HttpStatusCode clientResponseStatus(int code) =>
    code == 0 ? const HttpStatusCode(0) : HttpStatusCode.valueOf(code);
