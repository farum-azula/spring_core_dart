import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_security/src/web/csrf.dart';
import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/filter_chain.dart';
import 'package:spring_boot_starter_security/src/web/request_cache.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.web.authentication');

/// Facts about the request a login came from: the client's address and
/// the session id.
///
/// The form, basic and bearer-token logins store it as
/// `Authentication.details`, where an event listener can read it, for
/// example to audit logins by address. [toString] hides the session id.
///
/// ```dart
/// @EventListener()
/// void onLogin(AuthenticationSuccessEvent event) {
///   final details = event.authentication.details;
///   if (details is WebAuthenticationDetails) {
///     audit.loggedIn(event.authentication.name, from: details.remoteAddress);
///   }
/// }
/// ```
///
/// Spring (Java): `WebAuthenticationDetails`.
final class WebAuthenticationDetails {
  /// The details of [request], read now: the remote address and the
  /// current session id, if there is a session.
  WebAuthenticationDetails.of(ServerHttpRequest request)
    : remoteAddress = request.remoteAddress,
      sessionId = _sessionId(request);

  static String? _sessionId(ServerHttpRequest request) {
    try {
      return request.getSession(create: false)?.id;
    } on StateError {
      return null;
    }
  }

  /// The client's IP address as the server sees it (a proxy's address
  /// behind a reverse proxy); `null` when unknown.
  final String? remoteAddress;

  /// The session id at the time of the login, before the login changed
  /// it; `null` without a session. Never shown by `toString`.
  final String? sessionId;

  @override
  bool operator ==(Object other) =>
      other is WebAuthenticationDetails &&
      other.remoteAddress == remoteAddress &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(remoteAddress, sessionId);

  @override
  String toString() =>
      'WebAuthenticationDetails [RemoteIpAddress=$remoteAddress, '
      'SessionId=${sessionId == null ? null : '[PROTECTED]'}]';
}

/// What is done to the session when a user logs in, to close attacks that
/// prepare a session before the login.
///
/// Form login runs the chain's strategies: by default a new session id
/// ([ChangeSessionIdAuthenticationStrategy]) and a new CSRF token
/// ([CsrfAuthenticationStrategy]). Implement it to do more at login, such
/// as limiting the sessions per user.
///
/// Spring (Java): `SessionAuthenticationStrategy`.
abstract interface class SessionAuthenticationStrategy {
  /// Runs after [authentication] succeeded for [request], before the
  /// context is saved; an [AuthenticationException] thrown here fails the
  /// login.
  FutureOr<void> onAuthentication(
    Authentication authentication,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );
}

/// The default [SessionAuthenticationStrategy] for sessions: an existing
/// session gets a new id at login, keeping its contents.
///
/// Without it, an attacker could plant a session id in the victim's
/// browser before the login and use the same id afterwards (session
/// fixation). Switch it off only with
/// `sessionManagement((s) => s.sessionFixation(changeSessionId: false))`.
///
/// Spring (Java): `ChangeSessionIdAuthenticationStrategy`, also the
/// default there.
final class ChangeSessionIdAuthenticationStrategy
    implements SessionAuthenticationStrategy {
  /// The stateless strategy.
  const ChangeSessionIdAuthenticationStrategy();

  @override
  Future<void> onAuthentication(
    Authentication authentication,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    if (request.getSession(create: false) != null) {
      await request.changeSessionId();
    }
  }
}

/// A [SessionAuthenticationStrategy] that does nothing to the session.
///
/// For chains without sessions, or where session fixation protection is
/// handled elsewhere.
///
/// Spring (Java): `NullAuthenticatedSessionStrategy`.
final class NullAuthenticatedSessionStrategy
    implements SessionAuthenticationStrategy {
  /// The stateless strategy.
  const NullAuthenticatedSessionStrategy();

  @override
  void onAuthentication(
    Authentication authentication,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {}
}

/// A [SessionAuthenticationStrategy] that removes the CSRF token at login,
/// so the next page gets a new one.
///
/// A token seen before the login, perhaps by someone else on a shared
/// machine, is not valid after it. The chain adds it while CSRF
/// protection is on.
///
/// Spring (Java): `CsrfAuthenticationStrategy`.
final class CsrfAuthenticationStrategy
    implements SessionAuthenticationStrategy {
  /// A strategy removing the token stored in [repository].
  const CsrfAuthenticationStrategy(this.repository);

  /// Where the CSRF tokens are kept.
  final CsrfTokenRepository repository;

  @override
  Future<void> onAuthentication(
    Authentication authentication,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    if (await repository.loadToken(request) != null) {
      await repository.saveToken(null, request, response);
    }
  }
}

/// A [SessionAuthenticationStrategy] that runs several others in order.
///
/// Spring (Java): `CompositeSessionAuthenticationStrategy`.
final class CompositeSessionAuthenticationStrategy
    implements SessionAuthenticationStrategy {
  /// A strategy running [strategies] in order.
  CompositeSessionAuthenticationStrategy(
    List<SessionAuthenticationStrategy> strategies,
  ) : strategies = List.unmodifiable(strategies);

  /// The strategies, in order; cannot be modified.
  final List<SessionAuthenticationStrategy> strategies;

  @override
  Future<void> onAuthentication(
    Authentication authentication,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    for (final strategy in strategies) {
      await strategy.onAuthentication(authentication, request, response);
    }
  }
}

/// What the browser gets after a successful form login.
///
/// The default, [SavedRequestAwareAuthenticationSuccessHandler],
/// redirects to the page the user wanted, else to `/`. Implement it to
/// answer differently, for example with JSON for a login posted by a
/// script, and set it with `formLogin((f) => f.successHandler(...))`.
///
/// Spring (Java): `AuthenticationSuccessHandler`.
abstract interface class AuthenticationSuccessHandler {
  /// Answers [request], whose login succeeded as [authentication]; the
  /// user is already stored in the session.
  FutureOr<void> onAuthenticationSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication authentication,
  );
}

/// What the browser gets after a failed form login.
///
/// The default, [SimpleUrlAuthenticationFailureHandler], redirects to
/// `/login?error`. Do not tell the client why the login failed: a wrong
/// password and an unknown user must look the same.
///
/// Spring (Java): `AuthenticationFailureHandler`.
abstract interface class AuthenticationFailureHandler {
  /// Answers [request], whose login failed with [exception]; the
  /// exception is for logs, not for the client.
  FutureOr<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  );
}

/// The default [AuthenticationSuccessHandler] of form login: a redirect to
/// the page the user wanted before logging in, else to
/// [defaultTargetUrl].
///
/// The wanted page comes from the [requestCache], which forgets it once
/// used. Configure it with `formLogin((f) => f.defaultSuccessUrl(...))`.
///
/// Spring (Java): `SavedRequestAwareAuthenticationSuccessHandler`.
final class SavedRequestAwareAuthenticationSuccessHandler
    implements AuthenticationSuccessHandler {
  /// A handler redirecting to the saved request, else to
  /// [defaultTargetUrl]; with [alwaysUseDefaultTargetUrl] it always goes
  /// to [defaultTargetUrl].
  const SavedRequestAwareAuthenticationSuccessHandler({
    this.requestCache = const NullRequestCache(),
    this.defaultTargetUrl = '/',
    this.alwaysUseDefaultTargetUrl = false,
    this.contextPath = '',
  });

  /// Where the page the user wanted was saved.
  final RequestCache requestCache;

  /// Where to go when no page was saved, `/` by default: a path of this
  /// application (the [contextPath] is put in front) or an absolute URL,
  /// such as the address of a Flutter web app served elsewhere
  /// (`http://localhost:5050/`). It is configuration: nothing in the
  /// request can change it.
  final String defaultTargetUrl;

  /// Whether to go to [defaultTargetUrl] even when a page was saved;
  /// `false` by default.
  final bool alwaysUseDefaultTargetUrl;

  /// The application's context path (`server.servlet.context-path`); `''`
  /// for none.
  final String contextPath;

  @override
  Future<void> onAuthenticationSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication authentication,
  ) async {
    final saved = alwaysUseDefaultTargetUrl
        ? null
        : await requestCache.getRedirectUrl(request);
    await requestCache.removeRequest(request, response);
    await sendRedirect(
      response,
      saved ?? _redirectUrl(contextPath, defaultTargetUrl),
    );
  }
}

/// The default [AuthenticationFailureHandler] of form login: a redirect to
/// [failureUrl], `/login?error` by default, where the page says "Bad
/// credentials".
///
/// Spring (Java): `SimpleUrlAuthenticationFailureHandler`.
final class SimpleUrlAuthenticationFailureHandler
    implements AuthenticationFailureHandler {
  /// A handler redirecting to [failureUrl], prefixed with [contextPath].
  const SimpleUrlAuthenticationFailureHandler(
    this.failureUrl, {
    this.contextPath = '',
  });

  /// The path to redirect to (the context path is put in front), or an
  /// absolute URL.
  final String failureUrl;

  /// The application's context path; `''` for none.
  final String contextPath;

  @override
  Future<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  ) => sendRedirect(response, _redirectUrl(contextPath, failureUrl));
}

/// An [AuthenticationFailureHandler] that answers a failed login like a
/// request that must log in: through an [AuthenticationEntryPoint],
/// usually a 401 with a challenge.
///
/// For logins posted by scripts, which want a status rather than a
/// redirect.
///
/// Spring (Java): `AuthenticationEntryPointFailureHandler`.
final class AuthenticationEntryPointFailureHandler
    implements AuthenticationFailureHandler {
  /// A handler answering failures with [entryPoint].
  const AuthenticationEntryPointFailureHandler(this.entryPoint);

  /// The entry point that writes the answer.
  final AuthenticationEntryPoint entryPoint;

  @override
  FutureOr<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  ) => entryPoint.commence(request, response, exception);
}

/// The filter of HTTP Basic logins: a client sends its username and
/// password with every request, in an `Authorization: Basic` header.
///
/// `httpBasic()` adds it. For each request:
///
/// - no `Authorization` header, or one of another scheme: the request
///   goes on without a login (the rules may then ask for one);
/// - valid credentials: the request goes on as that user, for this
///   request only, since Basic creates no session;
/// - wrong credentials, a malformed header, or more than one
///   `Authorization` header: the [authenticationEntryPoint] answers, a
///   401 by default, and the request stops.
///
/// The header must be one `Basic <base64>` of `user:password` (the first
/// `:` separates them, so a password may contain `:`), at most
/// [maxHeaderLength] characters long. A request whose current user
/// already has that name is not checked again. Basic sends the password
/// with every request: use it over HTTPS only.
///
/// Spring (Java): `BasicAuthenticationFilter`.
final class BasicAuthenticationFilter implements WebFilter {
  /// A filter checking credentials with [authenticationManager]; the
  /// context is kept for the current request only by default.
  const BasicAuthenticationFilter(
    this.authenticationManager, {
    this.authenticationEntryPoint = const BasicAuthenticationEntryPoint(),
    this.securityContextRepository =
        const RequestAttributeSecurityContextRepository(),
    this.maxHeaderLength = 8192,
    this.eventPublisher,
  });

  /// Checks the username and password.
  final AuthenticationManager authenticationManager;

  /// Answers wrong or malformed credentials.
  final AuthenticationEntryPoint authenticationEntryPoint;

  /// Where the context of a successful login is saved; the request only,
  /// by default.
  final SecurityContextRepository securityContextRepository;

  /// The longest `Authorization` header accepted, in characters; 8 192 by
  /// default. A longer one is refused as bad credentials, so a huge header
  /// cannot cost decoding work.
  final int maxHeaderLength;

  /// Not used: a Basic login publishes no interactive event. Kept for
  /// symmetry with the form login filter.
  final ApplicationEventPublisher? eventPublisher;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    final UsernamePasswordAuthenticationToken? token;
    try {
      token = convert(request);
    } on AuthenticationException catch (e) {
      SecurityContextHolder.clearContext();
      await authenticationEntryPoint.commence(request, response, e);
      return;
    }
    if (token == null) {
      return await chain.doFilter(request, response);
    }
    final existing = SecurityContextHolder.getContext().authentication;
    if (existing != null &&
        existing.isAuthenticated &&
        existing is! AnonymousAuthenticationToken &&
        existing.name == token.name) {
      // Already this user (Spring's authenticationIsRequired).
      return await chain.doFilter(request, response);
    }
    try {
      token.details = WebAuthenticationDetails.of(request);
      final result = await authenticationManager.authenticate(token);
      final context = SecurityContextHolder.createEmptyContext()
        ..authentication = result;
      SecurityContextHolder.setContext(context);
      await securityContextRepository.saveContext(context, request, response);
    } on AuthenticationException catch (e) {
      SecurityContextHolder.clearContext();
      _log.debug('Failed to process authentication request: ${e.message}');
      await authenticationEntryPoint.commence(request, response, e);
      return;
    }
    await chain.doFilter(request, response);
  }

  // Java's decoder accepts missing padding; Dart's needs it.
  static String _padded(String text) =>
      text.contains('=') || text.length % 4 == 0
      ? text
      : text.padRight((text.length + 3) & ~3, '=');

  /// The login request in [request]'s `Authorization: Basic` header, or
  /// `null` when there is no such header.
  ///
  /// Throws a [BadCredentialsException] for more than one `Authorization`
  /// header, and for a header that is too long, empty, not Base64 or UTF-8,
  /// or without a `:`.
  UsernamePasswordAuthenticationToken? convert(ServerHttpRequest request) {
    final headers = request.headers.getAll(HttpHeaders.authorizationHeader);
    if (headers.isEmpty) {
      return null;
    }
    if (headers.length > 1) {
      throw BadCredentialsException('Multiple Authorization headers');
    }
    // Spring's BasicAuthenticationConverter, step by step.
    final header = headers.single.trim();
    if (!header.toLowerCase().startsWith('basic')) {
      return null;
    }
    if (header.length > maxHeaderLength) {
      throw BadCredentialsException('The Authorization header is too long');
    }
    if (header.length == 5) {
      throw BadCredentialsException('Empty basic authentication token');
    }
    final encoded = header.substring(6);
    final String decoded;
    try {
      decoded = utf8.decode(base64.decode(_padded(encoded)));
    } on FormatException {
      throw BadCredentialsException(
        'Failed to decode basic authentication token',
      );
    }
    final colon = decoded.indexOf(':');
    if (colon < 0) {
      throw BadCredentialsException('Invalid basic authentication token');
    }
    return UsernamePasswordAuthenticationToken.unauthenticated(
      decoded.substring(0, colon),
      decoded.substring(colon + 1),
    );
  }
}

/// The filter of form logins: it handles the `POST` of the login form,
/// with the `username` and `password` fields.
///
/// `formLogin()` adds it. Other requests pass through. For a login:
///
/// - the fields are read from a form body of at most 64 KB; the username
///   is trimmed, and missing fields count as empty;
/// - on success, the [sessionStrategy] runs (a new session id, a new CSRF
///   token), the user is stored in the session, an
///   `InteractiveAuthenticationSuccessEvent` is published and the
///   [successHandler] answers, by default with a redirect to the page the
///   user wanted;
/// - on failure, the context is emptied and the [failureHandler] answers,
///   by default with a redirect to `/login?error`.
///
/// The form must carry the CSRF token while CSRF protection is on.
///
/// Spring (Java): `UsernamePasswordAuthenticationFilter`.
final class UsernamePasswordAuthenticationFilter implements WebFilter {
  /// A filter handling `POST` requests to `loginProcessingUrl` (`/login`
  /// by default).
  UsernamePasswordAuthenticationFilter(
    this.authenticationManager, {
    String loginProcessingUrl = '/login',
    this.usernameParameter = 'username',
    this.passwordParameter = 'password',
    this.successHandler = const SavedRequestAwareAuthenticationSuccessHandler(),
    this.failureHandler = const SimpleUrlAuthenticationFailureHandler(
      '/login?error',
    ),
    this.sessionStrategy = const ChangeSessionIdAuthenticationStrategy(),
    this.securityContextRepository =
        const HttpSessionSecurityContextRepository(),
    this.eventPublisher,
  }) : requiresAuthenticationMatcher = PathPatternRequestMatcher(
         loginProcessingUrl,
         method: HttpMethod.post,
       );

  /// Checks the username and password.
  final AuthenticationManager authenticationManager;

  /// Decides which requests are login attempts: `POST` to the login
  /// processing URL.
  final RequestMatcher requiresAuthenticationMatcher;

  /// The form field holding the username, `username` by default.
  final String usernameParameter;

  /// The form field holding the password, `password` by default.
  final String passwordParameter;

  /// Answers a successful login.
  final AuthenticationSuccessHandler successHandler;

  /// Answers a failed login.
  final AuthenticationFailureHandler failureHandler;

  /// What is done to the session at login.
  final SessionAuthenticationStrategy sessionStrategy;

  /// Where the context of a successful login is saved; the session by
  /// default.
  final SecurityContextRepository securityContextRepository;

  /// Publishes the `InteractiveAuthenticationSuccessEvent` of a login;
  /// `null` publishes nothing.
  final ApplicationEventPublisher? eventPublisher;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    if (!requiresAuthenticationMatcher.matches(request)) {
      return await chain.doFilter(request, response);
    }
    final (current, form) = await readFormParameters(
      request,
      maxLength: 64 * 1024,
    );
    final username = form?[usernameParameter]?.firstOrNull?.trim() ?? '';
    final password = form?[passwordParameter]?.firstOrNull ?? '';
    final token = UsernamePasswordAuthenticationToken.unauthenticated(
      username,
      password,
    )..details = WebAuthenticationDetails.of(current);
    final Authentication result;
    try {
      result = await authenticationManager.authenticate(token);
      await sessionStrategy.onAuthentication(result, current, response);
    } on AuthenticationException catch (e) {
      SecurityContextHolder.clearContext();
      await failureHandler.onAuthenticationFailure(current, response, e);
      return;
    }
    final context = SecurityContextHolder.createEmptyContext()
      ..authentication = result;
    SecurityContextHolder.setContext(context);
    await securityContextRepository.saveContext(context, current, response);
    eventPublisher?.publishEvent(InteractiveAuthenticationSuccessEvent(result));
    await successHandler.onAuthenticationSuccess(current, response, result);
  }
}

/// One cleanup step of a logout, such as ending the session or expiring a
/// cookie.
///
/// The logout runs the chain's handlers in order. Implement it to clean
/// up something of your own, such as a server-side token, and add it with
/// `logout((l) => l.addLogoutHandler(...))`.
///
/// Spring (Java): `LogoutHandler`.
abstract interface class LogoutHandler {
  /// Cleans up after [authentication], the user logging out; `null` when
  /// nobody was logged in.
  FutureOr<void> logout(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  );
}

/// The [LogoutHandler] that does the logout itself: it ends the session
/// and stores an empty security context.
///
/// The chain always runs it last among the handlers.
///
/// Spring (Java): `SecurityContextLogoutHandler`.
final class SecurityContextLogoutHandler implements LogoutHandler {
  /// A handler ending the session unless [invalidateHttpSession] is
  /// `false`, and emptying the context in [securityContextRepository].
  const SecurityContextLogoutHandler({
    this.invalidateHttpSession = true,
    this.securityContextRepository =
        const HttpSessionSecurityContextRepository(),
  });

  /// Whether the session ends at logout, with everything stored in it;
  /// `true` by default.
  final bool invalidateHttpSession;

  /// Where the context was stored; an empty one is saved there.
  final SecurityContextRepository securityContextRepository;

  @override
  Future<void> logout(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) async {
    if (invalidateHttpSession) {
      request.getSession(create: false)?.invalidate();
    }
    final empty = SecurityContextHolder.createEmptyContext();
    SecurityContextHolder.setContext(empty);
    await securityContextRepository.saveContext(empty, request, response);
  }
}

/// A [LogoutHandler] that expires cookies, such as the session cookie.
///
/// `logout((l) => l.deleteCookies('JSESSIONID'))` adds one.
///
/// Spring (Java): `CookieClearingLogoutHandler`.
final class CookieClearingLogoutHandler implements LogoutHandler {
  /// A handler expiring the cookies [cookieNames] at [path].
  CookieClearingLogoutHandler(List<String> cookieNames, {this.path = '/'})
    : cookieNames = List.unmodifiable(cookieNames);

  /// The names of the cookies to expire.
  final List<String> cookieNames;

  /// The cookies' `Path`; it must match the path they were set with, or
  /// the browser keeps them.
  final String path;

  @override
  void logout(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) {
    for (final name in cookieNames) {
      response.addCookie(
        ResponseCookie(
          name,
          '',
          path: path,
          maxAge: Duration.zero,
          secure: request.isSecure,
          httpOnly: true,
        ),
      );
    }
  }
}

/// A [LogoutHandler] that removes the CSRF token, so the next page gets a
/// new one; the chain adds it while CSRF protection is on.
///
/// Spring (Java): `CsrfLogoutHandler`.
final class CsrfLogoutHandler implements LogoutHandler {
  /// A handler removing the token stored in [repository].
  const CsrfLogoutHandler(this.repository);

  /// Where the CSRF tokens are kept.
  final CsrfTokenRepository repository;

  @override
  FutureOr<void> logout(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) => repository.saveToken(null, request, response);
}

/// What the client gets after a logout.
///
/// By default a redirect to `/login?logout`
/// ([SimpleUrlLogoutSuccessHandler]); an API usually wants a plain status
/// ([HttpStatusReturningLogoutSuccessHandler]). Set it with
/// `logout((l) => l.logoutSuccessHandler(...))`.
///
/// Spring (Java): `LogoutSuccessHandler`.
abstract interface class LogoutSuccessHandler {
  /// Answers [request] after [authentication] logged out; `null` when
  /// nobody was logged in.
  FutureOr<void> onLogoutSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  );
}

/// The default [LogoutSuccessHandler]: a redirect to [targetUrl], usually
/// `/login?logout`, where the login page says "You have been signed out".
///
/// Spring (Java): `SimpleUrlLogoutSuccessHandler`.
final class SimpleUrlLogoutSuccessHandler implements LogoutSuccessHandler {
  /// A handler redirecting to [targetUrl], prefixed with [contextPath].
  const SimpleUrlLogoutSuccessHandler(this.targetUrl, {this.contextPath = ''});

  /// The path to redirect to (the context path is put in front), or an
  /// absolute URL.
  final String targetUrl;

  /// The application's context path; `''` for none.
  final String contextPath;

  @override
  Future<void> onLogoutSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) => sendRedirect(response, _redirectUrl(contextPath, targetUrl));
}

/// A [LogoutSuccessHandler] that answers a plain status without a body:
/// `200` by default, `204` suits APIs.
///
/// ```dart
/// http.logout((l) => l.logoutSuccessHandler(
///     const HttpStatusReturningLogoutSuccessHandler(HttpStatus.noContent)));
/// ```
///
/// Spring (Java): `HttpStatusReturningLogoutSuccessHandler`.
final class HttpStatusReturningLogoutSuccessHandler
    implements LogoutSuccessHandler {
  /// A handler answering [status]; `200` by default, as in Spring.
  const HttpStatusReturningLogoutSuccessHandler([this.status = HttpStatus.ok]);

  /// The status of the answer.
  final int status;

  @override
  Future<void> onLogoutSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) async {
    response.statusCode = status;
    await response.close();
  }
}

/// The filter that logs the user out on `POST /logout`.
///
/// The [handlers] run in order (cookies expired, CSRF token removed,
/// session ended and context emptied), a `LogoutSuccessEvent` is
/// published for a user who was logged in, then the [successHandler]
/// answers. Other requests pass through.
///
/// While CSRF protection is on, only `POST` logs out: a `GET` could be
/// triggered by a link or an image on another site. `GET /logout` then
/// shows a confirmation page when form login uses the generated login
/// page. With CSRF protection off,
/// `GET`, `POST`, `PUT` and `DELETE` all log out.
///
/// Spring (Java): `LogoutFilter`.
final class LogoutFilter implements WebFilter {
  /// A filter logging out requests to `logoutUrl` (`/logout` by default)
  /// whose method is one of `methods` (only `POST` by default).
  LogoutFilter(
    List<LogoutHandler> handlers, {
    String logoutUrl = '/logout',
    Set<HttpMethod> methods = const {HttpMethod.post},
    this.successHandler = const SimpleUrlLogoutSuccessHandler('/login?logout'),
    this.eventPublisher,
  }) : handlers = List.unmodifiable(handlers),
       logoutRequestMatcher = OrRequestMatcher([
         for (final method in methods)
           PathPatternRequestMatcher(logoutUrl, method: method),
       ]);

  /// The cleanup steps, run in order; cannot be modified.
  final List<LogoutHandler> handlers;

  /// Decides which requests are logouts.
  final RequestMatcher logoutRequestMatcher;

  /// Answers the client after the logout.
  final LogoutSuccessHandler successHandler;

  /// Publishes the `LogoutSuccessEvent`; `null` publishes nothing.
  final ApplicationEventPublisher? eventPublisher;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    if (!logoutRequestMatcher.matches(request)) {
      return await chain.doFilter(request, response);
    }
    final authentication = SecurityContextHolder.getContext().authentication;
    for (final handler in handlers) {
      await handler.logout(request, response, authentication);
    }
    if (authentication != null &&
        authentication is! AnonymousAuthenticationToken) {
      eventPublisher?.publishEvent(LogoutSuccessEvent(authentication));
    }
    await successHandler.onLogoutSuccess(request, response, authentication);
  }
}

/// The filter that serves the generated login page at `GET /login` when
/// form login or `oauth2Login()` has no page of its own.
///
/// The page is plain HTML: with form login, a username field, a password
/// field and the CSRF token; with `oauth2Login()`, a link per
/// registration ("Login with OAuth 2.0"), named by its client name
/// (HTML-escaped). With `?error` it says "Bad credentials", with
/// `?logout` "You have been signed out"; the reason of a failed login is
/// never shown. Name your own page with
/// `formLogin((f) => f.loginPage('/sign-in'))` (or `oauth2Login`'s) and
/// the generated one is gone.
///
/// Spring (Java): `DefaultLoginPageGeneratingFilter`.
final class DefaultLoginPageGeneratingFilter implements WebFilter {
  /// A page served at `loginPageUrl` (`/login` by default) whose form
  /// posts to [loginProcessingUrl].
  DefaultLoginPageGeneratingFilter({
    String loginPageUrl = '/login',
    this.loginProcessingUrl = '/login',
    this.usernameParameter = 'username',
    this.passwordParameter = 'password',
    this.contextPath = '',
    this.formLoginEnabled = true,
    this.oauth2AuthenticationUrlToClientName,
  }) : _page = PathPatternRequestMatcher(loginPageUrl, method: HttpMethod.get);

  /// The path the form posts to, `/login` by default.
  final String loginProcessingUrl;

  /// The name of the username field, `username` by default.
  final String usernameParameter;

  /// The name of the password field, `password` by default.
  final String passwordParameter;

  /// The application's context path, put in front of the form's
  /// address and the links; `''` for none.
  final String contextPath;

  /// Whether the page has the username and password form; `true` by
  /// default.
  final bool formLoginEnabled;

  /// The OAuth 2.0 logins to link to: the path that starts each
  /// (`/oauth2/authorization/keycloak`) and the name to show; `null` for
  /// none.
  final FutureOr<Map<String, String>> Function()?
  oauth2AuthenticationUrlToClientName;

  final RequestMatcher _page;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    if (!_page.matches(request)) {
      return await chain.doFilter(request, response);
    }
    final query = request.uri.queryParameters;
    final message = query.containsKey('error')
        ? '<div class="alert alert-danger" role="alert">Bad credentials</div>'
        : query.containsKey('logout')
        ? '<div class="alert alert-success" role="alert">You have been signed out</div>'
        : '';
    final form = formLoginEnabled ? _form(request, message) : '';
    final links = oauth2AuthenticationUrlToClientName;
    final oauth2 = links == null
        ? ''
        : _oauth2(await links(), formLoginEnabled ? '' : message);
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = 'text/html;charset=UTF-8'
      ..write('''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <title>Please sign in</title>
  </head>
  <body>
    <div class="content">
$form$oauth2    </div>
  </body>
</html>
''');
    await response.close();
  }

  String _form(ServerHttpRequest request, String message) {
    final csrf = csrfTokenOf(request);
    final hidden = csrf == null
        ? ''
        : '<input name="${_escape(csrf.parameterName)}" type="hidden" '
              'value="${_escape(csrf.token)}" />';
    return '''
      <form class="login-form" method="post" action="${_escape('$contextPath$loginProcessingUrl')}">
        <h2>Please sign in</h2>
        $message
        <p>
          <label for="username" class="screenreader">Username</label>
          <input type="text" id="username" name="${_escape(usernameParameter)}" placeholder="Username" required autofocus>
        </p>
        <p>
          <label for="password" class="screenreader">Password</label>
          <input type="password" id="password" name="${_escape(passwordParameter)}" placeholder="Password" required>
        </p>
        $hidden
        <button type="submit" class="primary">Sign in</button>
      </form>
''';
  }

  static String _row(String href, String name) =>
      '          <tr><td><a href="$href">$name</a></td></tr>\n';

  String _oauth2(Map<String, String> links, String message) {
    final rows = [
      for (final MapEntry(key: url, value: name) in links.entries)
        _row(_escape('$contextPath$url'), _escape(name)),
    ];
    return '''
      <h2>Login with OAuth 2.0</h2>
      $message
      <table class="table table-striped">
${rows.join()}      </table>
''';
  }
}

/// The filter that serves a logout confirmation page at `GET /logout`: a
/// button that posts the logout with the CSRF token.
///
/// A logout must be a `POST`, so a link to `/logout` lands here first.
/// The chain adds it with the generated login page.
///
/// Spring (Java): `DefaultLogoutPageGeneratingFilter`.
final class DefaultLogoutPageGeneratingFilter implements WebFilter {
  /// A page served at `logoutUrl` (`/logout` by default).
  DefaultLogoutPageGeneratingFilter({
    String logoutUrl = '/logout',
    this.contextPath = '',
  }) : _logoutUrl = logoutUrl,
       _page = PathPatternRequestMatcher(logoutUrl, method: HttpMethod.get);

  /// The application's context path, put in front of the form's
  /// address; `''` for none.
  final String contextPath;

  final String _logoutUrl;
  final RequestMatcher _page;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    if (!_page.matches(request)) {
      return await chain.doFilter(request, response);
    }
    final csrf = csrfTokenOf(request);
    final hidden = csrf == null
        ? ''
        : '<input name="${_escape(csrf.parameterName)}" type="hidden" '
              'value="${_escape(csrf.token)}" />';
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = 'text/html;charset=UTF-8'
      ..write('''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Confirm Log Out?</title>
  </head>
  <body>
    <div class="content">
      <form class="logout-form" method="post" action="${_escape('$contextPath$_logoutUrl')}">
        <h2>Are you sure you want to log out?</h2>
        $hidden
        <button class="primary" type="submit">Log Out</button>
      </form>
    </div>
  </body>
</html>
''');
    await response.close();
  }
}

String _escape(String text) => const HtmlEscape().convert(text);

// Spring's DefaultRedirectStrategy: an absolute URL as is, a path after
// the context path.
String _redirectUrl(String contextPath, String url) =>
    RegExp('^[a-z0-9.+-]+://', caseSensitive: false).hasMatch(url)
    ? url
    : '$contextPath$url';
