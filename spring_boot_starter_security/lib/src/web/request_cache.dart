import 'dart:async';

import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Remembers the page a browser asked for before it was sent to log in,
/// so the login can send it back there.
///
/// A user opens `/orders/42`, is redirected to the login form, logs in,
/// and lands on `/orders/42` again rather than on `/`. Form login uses the
/// session-based [HttpSessionRequestCache]; a `stateless` chain uses
/// [NullRequestCache]. Change it with `HttpSecurity.requestCache`.
///
/// Spring (Java): `RequestCache`.
abstract interface class RequestCache {
  /// Saves [request] when it is worth coming back to; called just before
  /// the client is asked to log in.
  FutureOr<void> saveRequest(
    ServerHttpRequest request,
    ServerHttpResponse response,
  );

  /// The saved path and query to go back to, or `null` when nothing was
  /// saved; always a path of this site, never another origin.
  FutureOr<String?> getRedirectUrl(ServerHttpRequest request);

  /// Forgets the saved request, once it has been used.
  FutureOr<void> removeRequest(ServerHttpRequest request);
}

/// A [RequestCache] that remembers nothing: after a login the user goes
/// to the default page. For APIs, which have no page to come back to.
///
/// Spring (Java): `NullRequestCache`.
final class NullRequestCache implements RequestCache {
  /// The stateless cache.
  const NullRequestCache();

  @override
  void saveRequest(ServerHttpRequest request, ServerHttpResponse response) {}

  @override
  String? getRedirectUrl(ServerHttpRequest request) => null;

  @override
  void removeRequest(ServerHttpRequest request) {}
}

/// The [RequestCache] of form login: it keeps the request's path and query
/// in the HTTP session.
///
/// Only page requests a browser would go back to are saved: `GET`, not
/// `XMLHttpRequest`, not asking for JSON, an event stream or a multipart
/// body, not a favicon. The saved address gets a `continue` parameter
/// (Spring's `matchingRequestParameterName`), so a saved request is used
/// only by the redirect made for it. A path starting with `//`, which a
/// browser would read as another host, is never saved. Nor is a request
/// that cannot get a session because the session limit is reached
/// ([TooManyActiveSessionsException]): the client is still asked to log
/// in, and lands on the default page afterwards.
///
/// Spring (Java): `HttpSessionRequestCache`.
final class HttpSessionRequestCache implements RequestCache {
  /// A cache saving the requests [requestMatcher] accepts, by default
  /// those of [defaultSavedRequestMatcher].
  HttpSessionRequestCache({RequestMatcher? requestMatcher})
    : requestMatcher = requestMatcher ?? defaultSavedRequestMatcher();

  /// Decides which requests are saved.
  final RequestMatcher requestMatcher;

  /// The session attribute holding the saved path and query.
  static const savedRequestKey = 'SPRING_SECURITY_SAVED_REQUEST';

  /// The query parameter added to the saved address, marking the
  /// redirect back.
  static const matchingRequestParameterName = 'continue';

  /// A new matcher for Spring's default: `GET` page requests, without
  /// scripts, JSON, event streams, multipart bodies and favicons.
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
    final HttpSession session;
    try {
      session = request.getSession()!;
    } on TooManyActiveSessionsException {
      return; // every session holds a login: nothing to come back to
    }
    session.setAttribute(savedRequestKey, saved);
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
