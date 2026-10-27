import 'dart:async';

import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Remembers the request that had to log in first, to come back to it
/// after the login, like Spring's `RequestCache`.
abstract interface class RequestCache {
  /// Saves [request] (when it is worth coming back to).
  FutureOr<void> saveRequest(
    ServerHttpRequest request,
    ServerHttpResponse response,
  );

  /// Where to go back: the saved path and query, never another origin.
  FutureOr<String?> getRedirectUrl(ServerHttpRequest request);

  /// Forgets the saved request.
  FutureOr<void> removeRequest(ServerHttpRequest request);
}

/// Remembers nothing (APIs), like Spring's `NullRequestCache`.
final class NullRequestCache implements RequestCache {
  /// The cache.
  const NullRequestCache();

  @override
  void saveRequest(ServerHttpRequest request, ServerHttpResponse response) {}

  @override
  String? getRedirectUrl(ServerHttpRequest request) => null;

  @override
  void removeRequest(ServerHttpRequest request) {}
}

/// Remembers the request in the session, like Spring's
/// `HttpSessionRequestCache`: only page requests a browser would go back
/// to — `GET`, not `XMLHttpRequest`, not JSON or event streams, not a
/// favicon. The way back gets `?continue` (Spring's
/// `matchingRequestParameterName`), so a saved request is used only by
/// the redirect made for it.
final class HttpSessionRequestCache implements RequestCache {
  /// A cache saving the requests [requestMatcher] accepts.
  HttpSessionRequestCache({RequestMatcher? requestMatcher})
    : requestMatcher = requestMatcher ?? defaultSavedRequestMatcher();

  /// Which requests are saved.
  final RequestMatcher requestMatcher;

  /// The session attribute.
  static const savedRequestKey = 'SPRING_SECURITY_SAVED_REQUEST';

  /// The parameter marking the way back.
  static const matchingRequestParameterName = 'continue';

  /// Spring's default: GET page requests.
  static RequestMatcher defaultSavedRequestMatcher() => AndRequestMatcher([
    const HttpMethodRequestMatcher(HttpMethod.get),
    const NegatedRequestMatcher(
      RequestHeaderRequestMatcher('X-Requested-With', 'XMLHttpRequest'),
    ),
    const NegatedRequestMatcher(_FaviconMatcher()),
    const NegatedRequestMatcher(
      MediaTypeRequestMatcher(
        ['application/json'],
        ignoredMediaTypes: ['*/*'],
        useEquals: true,
      ),
    ),
    const NegatedRequestMatcher(
      MediaTypeRequestMatcher(
        ['text/event-stream'],
        ignoredMediaTypes: ['*/*'],
        useEquals: true,
      ),
    ),
    const NegatedRequestMatcher(
      MediaTypeRequestMatcher(
        ['multipart/form-data'],
        ignoredMediaTypes: ['*/*'],
        useEquals: true,
      ),
    ),
  ]);

  @override
  void saveRequest(ServerHttpRequest request, ServerHttpResponse response) {
    if (!requestMatcher.matches(request)) {
      return;
    }
    // The full path (the context path included) and the query, as the
    // browser asked: a path of this origin only.
    final uri = request.uri;
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (!path.startsWith('/') || path.startsWith('//')) {
      return; // `//host`: a redirect there would leave the site
    }
    final query = uri.query;
    final saved =
        '$path?${query.isEmpty ? '' : '$query&'}$matchingRequestParameterName';
    request.getSession()!.setAttribute(savedRequestKey, saved);
  }

  @override
  String? getRedirectUrl(ServerHttpRequest request) =>
      request.getSession(create: false)?.getAttribute(savedRequestKey)
          as String?;

  @override
  void removeRequest(ServerHttpRequest request) =>
      request.getSession(create: false)?.removeAttribute(savedRequestKey);
}

// `/**/favicon.*`: a browser asking for the icon of a page.
final class _FaviconMatcher extends SimpleRequestMatcher {
  const _FaviconMatcher();

  @override
  bool matches(ServerHttpRequest request) =>
      request.path.split('/').last.startsWith('favicon.');
}
