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

/// Where a request came from, kept as `Authentication.details`, like
/// Spring's `WebAuthenticationDetails`.
final class WebAuthenticationDetails {
  /// The details of [request].
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

  /// The client's address.
  final String? remoteAddress;

  /// The session at the time of the login (never shown in `toString`).
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

/// What happens to the session at login, like Spring's
/// `SessionAuthenticationStrategy`.
abstract interface class SessionAuthenticationStrategy {
  /// Called after [authentication] succeeded for [request].
  FutureOr<void> onAuthentication(
    Authentication authentication,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );
}

/// Gives an existing session a new id at login, like Spring's
/// `ChangeSessionIdAuthenticationStrategy` (the default): an id someone
/// planted before the login (session fixation) is worthless after it.
final class ChangeSessionIdAuthenticationStrategy
    implements SessionAuthenticationStrategy {
  /// The strategy.
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

/// Leaves the session alone (no sessions, or the fixation protection
/// switched off), like Spring's `NullAuthenticatedSessionStrategy`.
final class NullAuthenticatedSessionStrategy
    implements SessionAuthenticationStrategy {
  /// The strategy.
  const NullAuthenticatedSessionStrategy();

  @override
  void onAuthentication(
    Authentication authentication,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {}
}

/// Replaces the CSRF token at login, like Spring's
/// `CsrfAuthenticationStrategy`: a token seen before the login is not
/// valid after it.
final class CsrfAuthenticationStrategy
    implements SessionAuthenticationStrategy {
  /// Over [repository].
  const CsrfAuthenticationStrategy(this.repository);

  /// The tokens.
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

/// Several strategies in order, like Spring's
/// `CompositeSessionAuthenticationStrategy`.
final class CompositeSessionAuthenticationStrategy
    implements SessionAuthenticationStrategy {
  /// [strategies] in order.
  CompositeSessionAuthenticationStrategy(
    List<SessionAuthenticationStrategy> strategies,
  ) : strategies = List.unmodifiable(strategies);

  /// The strategies.
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

/// Answers a successful form login, like Spring's
/// `AuthenticationSuccessHandler`.
abstract interface class AuthenticationSuccessHandler {
  /// [authentication] logged in through [request].
  FutureOr<void> onAuthenticationSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication authentication,
  );
}

/// Answers a failed form login, like Spring's
/// `AuthenticationFailureHandler`.
abstract interface class AuthenticationFailureHandler {
  /// The login of [request] failed with [exception].
  FutureOr<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  );
}

/// Redirects to the page the user wanted (saved by the [requestCache]),
/// else to [defaultTargetUrl], like Spring's
/// `SavedRequestAwareAuthenticationSuccessHandler`.
final class SavedRequestAwareAuthenticationSuccessHandler
    implements AuthenticationSuccessHandler {
  /// A handler; [alwaysUseDefaultTargetUrl] ignores the saved request.
  const SavedRequestAwareAuthenticationSuccessHandler({
    this.requestCache = const NullRequestCache(),
    this.defaultTargetUrl = '/',
    this.alwaysUseDefaultTargetUrl = false,
    this.contextPath = '',
  });

  /// Where the wanted page is.
  final RequestCache requestCache;

  /// Where to go without one.
  final String defaultTargetUrl;

  /// Whether to always go to [defaultTargetUrl].
  final bool alwaysUseDefaultTargetUrl;

  /// The application's context path.
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
    await requestCache.removeRequest(request);
    await sendRedirect(response, saved ?? '$contextPath$defaultTargetUrl');
  }
}

/// Redirects to [failureUrl] (`/login?error`), like Spring's
/// `SimpleUrlAuthenticationFailureHandler`.
final class SimpleUrlAuthenticationFailureHandler
    implements AuthenticationFailureHandler {
  /// Redirects to [failureUrl].
  const SimpleUrlAuthenticationFailureHandler(
    this.failureUrl, {
    this.contextPath = '',
  });

  /// Where to go.
  final String failureUrl;

  /// The application's context path.
  final String contextPath;

  @override
  Future<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  ) => sendRedirect(response, '$contextPath$failureUrl');
}

/// A 401 (with the entry point's challenge) on failure, like Spring's
/// `AuthenticationEntryPointFailureHandler`.
final class AuthenticationEntryPointFailureHandler
    implements AuthenticationFailureHandler {
  /// Answers failures with [entryPoint].
  const AuthenticationEntryPointFailureHandler(this.entryPoint);

  /// The entry point.
  final AuthenticationEntryPoint entryPoint;

  @override
  FutureOr<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  ) => entryPoint.commence(request, response, exception);
}

/// Logs in with `Authorization: Basic`, like Spring's
/// `BasicAuthenticationFilter`: a request with valid credentials goes on
/// as the user (for this request only: Basic is stateless); invalid ones
/// get the [authenticationEntryPoint]'s 401; a request without the header
/// goes on unauthenticated.
///
/// The header must be one `Basic <base64>` of `user:password` (the first
/// `:` separates them), at most [maxHeaderLength] long; anything else is
/// bad credentials.
final class BasicAuthenticationFilter implements WebFilter {
  /// A filter authenticating with [authenticationManager].
  const BasicAuthenticationFilter(
    this.authenticationManager, {
    this.authenticationEntryPoint = const BasicAuthenticationEntryPoint(),
    this.securityContextRepository =
        const RequestAttributeSecurityContextRepository(),
    this.maxHeaderLength = 8192,
    this.eventPublisher,
  });

  /// Checks the credentials.
  final AuthenticationManager authenticationManager;

  /// Answers bad credentials.
  final AuthenticationEntryPoint authenticationEntryPoint;

  /// Where the context is saved (the request only, by default).
  final SecurityContextRepository securityContextRepository;

  /// The longest header accepted.
  final int maxHeaderLength;

  /// Not used by Basic (no interactive event), kept for symmetry.
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

  /// The credentials of [request]'s `Authorization: Basic` header, `null`
  /// without one; throws [BadCredentialsException] for a malformed one.
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

/// Logs in with a form `POST` (`username`, `password` fields), like
/// Spring's `UsernamePasswordAuthenticationFilter`: on success the session
/// gets a new id, the context is stored in it, an
/// `InteractiveAuthenticationSuccessEvent` is published and the
/// [successHandler] redirects; on failure the [failureHandler] does.
final class UsernamePasswordAuthenticationFilter implements WebFilter {
  /// A filter for `POST` [loginProcessingUrl].
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

  /// Checks the credentials.
  final AuthenticationManager authenticationManager;

  /// Which requests are logins.
  final RequestMatcher requiresAuthenticationMatcher;

  /// The username field.
  final String usernameParameter;

  /// The password field.
  final String passwordParameter;

  /// After success.
  final AuthenticationSuccessHandler successHandler;

  /// After failure.
  final AuthenticationFailureHandler failureHandler;

  /// The session at login.
  final SessionAuthenticationStrategy sessionStrategy;

  /// Where the logged-in context goes.
  final SecurityContextRepository securityContextRepository;

  /// Publishes `InteractiveAuthenticationSuccessEvent`.
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

/// Clears something at logout, like Spring's `LogoutHandler`.
abstract interface class LogoutHandler {
  /// Logs [authentication] out of [request].
  FutureOr<void> logout(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  );
}

/// Ends the session and empties the context, like Spring's
/// `SecurityContextLogoutHandler`.
final class SecurityContextLogoutHandler implements LogoutHandler {
  /// The handler.
  const SecurityContextLogoutHandler({
    this.invalidateHttpSession = true,
    this.securityContextRepository =
        const HttpSessionSecurityContextRepository(),
  });

  /// Whether the session ends.
  final bool invalidateHttpSession;

  /// Where the context was stored.
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

/// Expires cookies at logout, like Spring's `CookieClearingLogoutHandler`.
final class CookieClearingLogoutHandler implements LogoutHandler {
  /// Clears [cookieNames].
  CookieClearingLogoutHandler(List<String> cookieNames, {this.path = '/'})
    : cookieNames = List.unmodifiable(cookieNames);

  /// The cookies.
  final List<String> cookieNames;

  /// Their path.
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

/// Removes the CSRF token at logout, like Spring's `CsrfLogoutHandler`.
final class CsrfLogoutHandler implements LogoutHandler {
  /// Over [repository].
  const CsrfLogoutHandler(this.repository);

  /// The tokens.
  final CsrfTokenRepository repository;

  @override
  FutureOr<void> logout(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) => repository.saveToken(null, request, response);
}

/// Answers a logout, like Spring's `LogoutSuccessHandler`.
abstract interface class LogoutSuccessHandler {
  /// [authentication] logged out.
  FutureOr<void> onLogoutSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  );
}

/// Redirects to [targetUrl] (`/login?logout`).
final class SimpleUrlLogoutSuccessHandler implements LogoutSuccessHandler {
  /// Redirects to [targetUrl].
  const SimpleUrlLogoutSuccessHandler(this.targetUrl, {this.contextPath = ''});

  /// Where to go.
  final String targetUrl;

  /// The application's context path.
  final String contextPath;

  @override
  Future<void> onLogoutSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) => sendRedirect(response, '$contextPath$targetUrl');
}

/// A plain status (`200` by default; `204` suits APIs), like Spring's
/// `HttpStatusReturningLogoutSuccessHandler`.
final class HttpStatusReturningLogoutSuccessHandler
    implements LogoutSuccessHandler {
  /// Answers with [status] (`200` like Spring by default).
  const HttpStatusReturningLogoutSuccessHandler([this.status = HttpStatus.ok]);

  /// The status.
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

/// Logs out on `POST /logout`, like Spring's `LogoutFilter`: the
/// [handlers] run (session ended, context emptied, CSRF token removed),
/// a `LogoutSuccessEvent` is published, then the [successHandler]
/// answers. `GET /logout` is not a logout (a link or an image could
/// trigger it): with form login it shows a confirmation page.
final class LogoutFilter implements WebFilter {
  /// A filter for [logoutUrl] with one of [methods] (only `POST` while CSRF
  /// protection is on, like Spring).
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

  /// The handlers.
  final List<LogoutHandler> handlers;

  /// Which requests log out.
  final RequestMatcher logoutRequestMatcher;

  /// Answers.
  final LogoutSuccessHandler successHandler;

  /// Publishes `LogoutSuccessEvent`.
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

/// Serves the default login page (`GET /login`) when form login has no
/// page of its own, like Spring's `DefaultLoginPageGeneratingFilter`;
/// `?error` and `?logout` show a message. The page carries the CSRF token.
final class DefaultLoginPageGeneratingFilter implements WebFilter {
  /// A page at [loginPageUrl] posting to [loginProcessingUrl].
  DefaultLoginPageGeneratingFilter({
    String loginPageUrl = '/login',
    this.loginProcessingUrl = '/login',
    this.usernameParameter = 'username',
    this.passwordParameter = 'password',
    this.contextPath = '',
  }) : _page = PathPatternRequestMatcher(loginPageUrl, method: HttpMethod.get);

  /// Where the form posts.
  final String loginProcessingUrl;

  /// The username field.
  final String usernameParameter;

  /// The password field.
  final String passwordParameter;

  /// The application's context path.
  final String contextPath;

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
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <title>Please sign in</title>
  </head>
  <body>
    <div class="content">
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
    </div>
  </body>
</html>
''');
    await response.close();
  }
}

/// Serves the logout confirmation page (`GET /logout`), like Spring's
/// `DefaultLogoutPageGeneratingFilter`: a button posting the logout with
/// the CSRF token.
final class DefaultLogoutPageGeneratingFilter implements WebFilter {
  /// A page at [logoutUrl].
  DefaultLogoutPageGeneratingFilter({
    String logoutUrl = '/logout',
    this.contextPath = '',
  }) : _logoutUrl = logoutUrl,
       _page = PathPatternRequestMatcher(logoutUrl, method: HttpMethod.get);

  /// The application's context path.
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
