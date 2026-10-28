import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// Writes a security error as an `application/problem+json` body with
/// [status], the standard title, the fixed [detail] text and the request's
/// path, adding [headers] (such as `WWW-Authenticate`), then closes the
/// response.
///
/// It never includes an exception's message, which could tell a client
/// too much. Does nothing when the response has already been sent. Use it
/// in your own entry points and handlers to answer like the built-in ones.
///
/// ```dart
/// await writeSecurityProblem(request, response, 403, 'Access Denied');
/// ```
Future<void> writeSecurityProblem(
  ServerHttpRequest request,
  ServerHttpResponse response,
  int status,
  String detail, {
  Map<String, String> headers = const {},
}) async {
  if (response.isCommitted) {
    return;
  }
  response.statusCode = status;
  headers.forEach(response.headers.set);
  final problem = ProblemDetail.forStatusAndDetail(status, detail)
    ..instance = Uri(path: request.path);
  response.headers.contentType = MediaType.applicationProblemJson;
  response.write(jsonEncode(problem.toJson()));
  await response.close();
}

/// What a request that must log in first is answered: a 401 with a
/// challenge, a redirect to the login page, and so on.
///
/// Each login method brings its own (basic: a 401 with
/// `WWW-Authenticate: Basic`; form login: a redirect to `/login`; bearer
/// tokens: a 401 with `WWW-Authenticate: Bearer`), and the chain picks
/// one by the kind of client. Implement it to answer differently, for
/// example with a JSON body your front end understands, and set it with
/// `exceptionHandling` or on the login method.
///
/// ```dart
/// // A single-page app wants a plain 401 it can react to.
/// http.exceptionHandling(
///   (e) => e.authenticationEntryPoint(const HttpStatusEntryPoint()),
/// );
/// ```
///
/// Spring (Java): `AuthenticationEntryPoint`.
abstract interface class AuthenticationEntryPoint {
  /// Answers [request], which must log in first; [authException] says
  /// why, for logs, and should not be sent to the client.
  FutureOr<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  );
}

/// What a logged-in user is answered when the access rules or method
/// security deny a request; a 403 by default.
///
/// Anonymous users are not answered here: they are asked to log in
/// through the [AuthenticationEntryPoint]. Implement it to show your own
/// "forbidden" page or body, and set it with `exceptionHandling`.
///
/// Spring (Java): `AccessDeniedHandler`.
abstract interface class AccessDeniedHandler {
  /// Answers [request], which [accessDeniedException] denied.
  FutureOr<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AccessDeniedException accessDeniedException,
  );
}

/// The default [AccessDeniedHandler]: `403 Forbidden` with a
/// `ProblemDetail` body whose detail is "Access Denied".
///
/// Spring (Java): `AccessDeniedHandlerImpl`, which sends the 403 to the
/// error page instead.
final class AccessDeniedHandlerImpl implements AccessDeniedHandler {
  /// The stateless handler.
  const AccessDeniedHandlerImpl();

  @override
  Future<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AccessDeniedException accessDeniedException,
  ) => writeSecurityProblem(
    request,
    response,
    HttpStatus.forbidden,
    'Access Denied',
  );
}

/// The [AuthenticationEntryPoint] of HTTP Basic: a `401` with
/// `WWW-Authenticate: Basic realm="...", charset="UTF-8"` (RFC 7617).
///
/// The header makes a browser show its username and password dialog, and
/// tells a program to send an `Authorization: Basic` header. `httpBasic()`
/// uses it, except for scripts (`X-Requested-With: XMLHttpRequest`), which
/// get a plain 401 so no dialog appears.
///
/// Spring (Java): Spring Security 7's `BasicAuthenticationEntryPoint`,
/// with the realm `Realm` by default as in its HTTP Basic configuration.
final class BasicAuthenticationEntryPoint implements AuthenticationEntryPoint {
  /// An entry point naming [realmName] in the challenge (`Realm` by
  /// default).
  const BasicAuthenticationEntryPoint([this.realmName = 'Realm']);

  /// The realm named in the challenge; browsers may show it in the
  /// dialog.
  final String realmName;

  @override
  Future<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  ) => writeSecurityProblem(
    request,
    response,
    HttpStatus.unauthorized,
    'Full authentication is required to access this resource',
    headers: {
      HttpHeaders.wwwAuthenticateHeader:
          'Basic realm="$realmName", charset="UTF-8"',
    },
  );
}

/// An [AuthenticationEntryPoint] that answers a fixed status, `401` by
/// default, with a `ProblemDetail` body and no challenge.
///
/// For APIs and single-page apps that handle the login themselves and
/// want no browser dialog and no redirect.
///
/// Spring (Java): `HttpStatusEntryPoint`.
final class HttpStatusEntryPoint implements AuthenticationEntryPoint {
  /// An entry point answering [status] (`401` when omitted).
  const HttpStatusEntryPoint([this.status = HttpStatus.unauthorized]);

  /// The status of the answer.
  final int status;

  @override
  Future<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  ) => writeSecurityProblem(
    request,
    response,
    status,
    'Full authentication is required to access this resource',
  );
}

/// An [AuthenticationEntryPoint] that answers `403` with "Access Denied":
/// there is no way to log in, so there is nothing to ask for.
///
/// The chain uses it when no login method is configured.
///
/// Spring (Java): `Http403ForbiddenEntryPoint`.
final class Http403ForbiddenEntryPoint implements AuthenticationEntryPoint {
  /// The stateless entry point.
  const Http403ForbiddenEntryPoint();

  @override
  Future<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  ) => writeSecurityProblem(
    request,
    response,
    HttpStatus.forbidden,
    'Access Denied',
  );
}

/// The [AuthenticationEntryPoint] of form login: a `302` redirect to the
/// login page.
///
/// `formLogin()` uses it for browsers asking for pages; other clients get
/// the entry point of another login method, if any.
///
/// Spring (Java): `LoginUrlAuthenticationEntryPoint`.
final class LoginUrlAuthenticationEntryPoint
    implements AuthenticationEntryPoint {
  /// An entry point redirecting to [loginFormUrl], prefixed with
  /// [contextPath].
  const LoginUrlAuthenticationEntryPoint(
    this.loginFormUrl, {
    this.contextPath = '',
  });

  /// The path of the login page, such as `/login`.
  final String loginFormUrl;

  /// The application's context path (`server.servlet.context-path`),
  /// put in front of [loginFormUrl]; `''` for none.
  final String contextPath;

  @override
  Future<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  ) => sendRedirect(response, '$contextPath$loginFormUrl');
}

/// Answers `302 Found` with the `Location` header set to [location] and
/// closes the response; does nothing when the response has already been
/// sent.
Future<void> sendRedirect(ServerHttpResponse response, String location) async {
  if (response.isCommitted) {
    return;
  }
  response
    ..statusCode = HttpStatus.found
    ..headers.set(HttpHeaders.locationHeader, location);
  await response.close();
}

/// An [AuthenticationEntryPoint] that picks another one by request: the
/// first of [entryPoints] whose matcher matches, else
/// [defaultEntryPoint].
///
/// The chain uses one when it has several login methods: browsers asking
/// for pages are redirected to the form, programs get the basic or bearer
/// challenge.
///
/// Spring (Java): `DelegatingAuthenticationEntryPoint`.
final class DelegatingAuthenticationEntryPoint
    implements AuthenticationEntryPoint {
  /// An entry point trying [entryPoints] in order, with
  /// [defaultEntryPoint] for requests none of them matches.
  DelegatingAuthenticationEntryPoint(
    List<(RequestMatcher, AuthenticationEntryPoint)> entryPoints, {
    required this.defaultEntryPoint,
  }) : entryPoints = List.unmodifiable(entryPoints);

  /// The matchers and their entry points, in order; cannot be modified.
  final List<(RequestMatcher, AuthenticationEntryPoint)> entryPoints;

  /// Used for requests no matcher matches.
  final AuthenticationEntryPoint defaultEntryPoint;

  @override
  FutureOr<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  ) {
    for (final (matcher, entryPoint) in entryPoints) {
      if (matcher.matches(request)) {
        return entryPoint.commence(request, response, authException);
      }
    }
    return defaultEntryPoint.commence(request, response, authException);
  }
}

/// An [AccessDeniedHandler] that picks another one by request: the first
/// of [handlers] whose matcher matches, else [defaultHandler].
///
/// The chain uses one for bearer-token requests, which get a
/// `WWW-Authenticate: Bearer error="insufficient_scope"` answer.
///
/// Spring (Java): `RequestMatcherDelegatingAccessDeniedHandler`.
final class DelegatingAccessDeniedHandler implements AccessDeniedHandler {
  /// A handler trying [handlers] in order, with [defaultHandler] (a plain
  /// 403 by default) for the rest.
  DelegatingAccessDeniedHandler(
    List<(RequestMatcher, AccessDeniedHandler)> handlers, {
    this.defaultHandler = const AccessDeniedHandlerImpl(),
  }) : handlers = List.unmodifiable(handlers);

  /// The matchers and their handlers, in order; cannot be modified.
  final List<(RequestMatcher, AccessDeniedHandler)> handlers;

  /// Used for requests no matcher matches.
  final AccessDeniedHandler defaultHandler;

  @override
  FutureOr<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AccessDeniedException accessDeniedException,
  ) {
    for (final (matcher, handler) in handlers) {
      if (matcher.matches(request)) {
        return handler.handle(request, response, accessDeniedException);
      }
    }
    return defaultHandler.handle(request, response, accessDeniedException);
  }
}
