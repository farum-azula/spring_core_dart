import 'package:spring_web_dart/spring_web_dart.dart';

/// [request] with [timeout] as the limit of its whole exchange
/// (`HttpRequest.timeout`), everything else kept: how a call of the
/// starter carries its own time limit when no deadline of the caller runs,
/// without a zone to run in.
HttpRequest timedRequest(HttpRequest request, Duration timeout) => HttpRequest(
  method: request.method,
  url: request.url,
  headers: request.headers,
  body: request.body,
  timeout: timeout,
  readTimeout: request.readTimeout,
  connectTimeout: request.connectTimeout,
  followRedirects: request.followRedirects,
  sensitiveHeaders: request.sensitiveHeaders,
  abort: request.abort,
  attributes: request.attributes,
);
