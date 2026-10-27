// Filters (chapter 3) run around every request, before the handler is
// looked up: the security chain is one of them.
import 'dart:math';

import 'package:neon_books_server/src/app.spring.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Gives every request an id (the client's `X-Request-Id`, or a new one),
/// sends it back, and adds it to every log line written while the request
/// is handled (`SpringLog.withFields`, like an MDC).
@Component()
@Order(Ordered.highestPrecedence)
class RequestIdFilter extends OncePerRequestFilter {
  static final _random = Random.secure();

  @override
  Future<void> doFilterInternal(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    final id =
        request.headers['X-Request-Id'] ??
        _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    response.headers.set('X-Request-Id', id);
    return SpringLog.withFields({
      'request': id,
    }, () => chain.doFilter(request, response));
  }
}

/// One line per request: method, path, status, time. A plain `WebFilter`.
@Component()
@Order(Ordered.highestPrecedence + 1)
@Log(topic: 'neon.access', fieldName: 'accessLog')
class AccessLogFilter implements WebFilter {
  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    final watch = Stopwatch()..start();
    try {
      await chain.doFilter(request, response);
    } finally {
      accessLog.debug(
        () =>
            '${request.method.value} ${request.path} ${response.statusCode} '
            '${watch.elapsedMilliseconds} ms',
      );
    }
  }
}
