import 'dart:async';

import 'package:spring_boot_starter_security/src/web/cookie_signer.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Remembers the page a browser asked for before it was sent to log in,
/// so the login can send it back there.
///
/// A user opens `/orders/42`, is redirected to the login form, logs in,
/// and lands on `/orders/42` again rather than on `/`. A chain with
/// sessions uses [CookieRequestCache], so that a client who is not logged
/// in gets no session; a `stateless` chain uses [NullRequestCache].
/// [HttpSessionRequestCache], Spring's default, keeps it in the session.
/// Change it with `HttpSecurity.requestCache`.
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
  FutureOr<void> removeRequest(
    ServerHttpRequest request,
    ServerHttpResponse response,
  );
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
  void removeRequest(ServerHttpRequest request, ServerHttpResponse response) {}
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
    final saved = _savedAddress(requestMatcher, request);
    if (saved == null) {
      return;
    }
    final HttpSession session;
    try {
      session = request.getSession()!;
    } on TooManyActiveSessionsException {
      return; // the store is full: nothing to come back to
    }
    session.setAttribute(savedRequestKey, saved);
  }

  @override
  String? getRedirectUrl(ServerHttpRequest request) =>
      request.getSession(create: false)?.getAttribute(savedRequestKey)
          as String?;

  @override
  void removeRequest(ServerHttpRequest request, ServerHttpResponse response) =>
      request.getSession(create: false)?.removeAttribute(savedRequestKey);
}

/// The [RequestCache] of chains with sessions: it keeps the page to come
/// back to in a cookie, signed by the [CookieSigner], so that a client who
/// is not logged in gets no session (and a flood of such clients fills no
/// memory of the server).
///
/// It saves the same requests as [HttpSessionRequestCache] (only page
/// requests, with the `continue` parameter), in the cookie
/// [cookieName], `HttpOnly`, `SameSite=Lax`, `Secure` over HTTPS, valid
/// for [maxAge]. Reading it, the signature is checked first, then the
/// address again: only a path of this site (one leading `/`, no `\\`, no
/// control characters) is ever returned, never another host.
///
/// Spring (Java): `CookieRequestCache` (its cookie is not signed).
final class CookieRequestCache implements RequestCache {
  /// A cache saving the requests [requestMatcher] accepts (by default
  /// those of [HttpSessionRequestCache.defaultSavedRequestMatcher]), its
  /// cookie signed by [signer] and scoped to [cookiePath] (`/` when
  /// `null`).
  CookieRequestCache({
    RequestMatcher? requestMatcher,
    CookieSigner? signer,
    this.cookiePath,
    this.maxAge = const Duration(minutes: 30),
  }) : requestMatcher =
           requestMatcher ??
           HttpSessionRequestCache.defaultSavedRequestMatcher(),
       signer = signer ?? CookieSigner.shared;

  /// Decides which requests are saved.
  final RequestMatcher requestMatcher;

  /// Signs and checks the cookie.
  final CookieSigner signer;

  /// The cookie's `Path`; `/` when `null`.
  final String? cookiePath;

  /// How long a saved page stays valid.
  final Duration maxAge;

  /// The cookie's name, Spring's.
  static const cookieName = 'REDIRECT_URI';

  @override
  void saveRequest(ServerHttpRequest request, ServerHttpResponse response) {
    final saved = _savedAddress(requestMatcher, request);
    if (saved == null) {
      return;
    }
    response.addCookie(
      _cookie(request, signer.sign(cookieName, saved, maxAge)),
    );
  }

  @override
  String? getRedirectUrl(ServerHttpRequest request) {
    final saved = signer.open(cookieName, request.cookies[cookieName]);
    return saved != null && _isLocalPath(saved) ? saved : null;
  }

  @override
  void removeRequest(ServerHttpRequest request, ServerHttpResponse response) {
    if (request.cookies.containsKey(cookieName)) {
      response.addCookie(_cookie(request, '', remove: true));
    }
  }

  ResponseCookie _cookie(
    ServerHttpRequest request,
    String value, {
    bool remove = false,
  }) => ResponseCookie(
    cookieName,
    value,
    path: cookiePath ?? '/',
    httpOnly: true,
    secure: request.isSecure,
    sameSite: 'Lax',
    maxAge: remove ? Duration.zero : maxAge,
  );
}

// The path and query to save for [request] with the `continue` parameter,
// or null when it is not saved.
String? _savedAddress(RequestMatcher matcher, ServerHttpRequest request) {
  if (!matcher.matches(request)) {
    return null;
  }
  // The full path (the context path included) and the query, as the
  // browser asked: a path of this origin only.
  final uri = request.uri;
  final path = uri.path.isEmpty ? '/' : uri.path;
  final query = uri.query;
  final saved =
      '$path?${query.isEmpty ? '' : '$query&'}'
      '${HttpSessionRequestCache.matchingRequestParameterName}';
  return _isLocalPath(saved) ? saved : null;
}

// One leading slash and nothing a browser would read as another host
// (`//host`, `/\\host`) or that could split a header (control characters).
bool _isLocalPath(String address) =>
    address.startsWith('/') &&
    !address.startsWith('//') &&
    !address.contains(r'\') &&
    !address.codeUnits.any((c) => c < 0x20 || c == 0x7f);

// `/**/favicon.*`: a browser asking for the icon of a page.
final class _FaviconMatcher extends SimpleRequestMatcher {
  const _FaviconMatcher();

  @override
  bool matches(ServerHttpRequest request) =>
      request.path.split('/').last.startsWith('favicon.');
}
