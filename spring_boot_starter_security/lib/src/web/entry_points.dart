import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// Writes a security error as `application/problem+json` (status, title,
/// a fixed detail and the path, never the exception's message), with
/// [headers] (`WWW-Authenticate`).
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

/// Starts authentication when a request needs it, like Spring's
/// `AuthenticationEntryPoint`: a 401 with a challenge, a redirect to the
/// login page, ...
abstract interface class AuthenticationEntryPoint {
  /// Answers [request], which needs to authenticate ([authException] says
  /// why).
  FutureOr<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  );
}

/// Answers an authenticated request that may not do something, like
/// Spring's `AccessDeniedHandler`.
abstract interface class AccessDeniedHandler {
  /// Answers [request], denied by [accessDeniedException].
  FutureOr<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AccessDeniedException accessDeniedException,
  );
}

/// `403 Forbidden`, like Spring's `AccessDeniedHandlerImpl` (as a
/// `ProblemDetail`, "Access Denied").
final class AccessDeniedHandlerImpl implements AccessDeniedHandler {
  /// The handler.
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

/// `401` with `WWW-Authenticate: Basic realm="...", charset="UTF-8"`, like
/// Spring Security 7's `BasicAuthenticationEntryPoint` (RFC 7617; realm
/// `Realm` by default, as Spring Security's HTTP Basic configuration).
final class BasicAuthenticationEntryPoint implements AuthenticationEntryPoint {
  /// A challenge for [realmName].
  const BasicAuthenticationEntryPoint([this.realmName = 'Realm']);

  /// The realm.
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

/// A plain status (`401` by default), like Spring's `HttpStatusEntryPoint`.
final class HttpStatusEntryPoint implements AuthenticationEntryPoint {
  /// Answers with [status].
  const HttpStatusEntryPoint([this.status = HttpStatus.unauthorized]);

  /// The status.
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

/// `403` for every unauthenticated request, like Spring's
/// `Http403ForbiddenEntryPoint` (the entry point when no login method is
/// configured).
final class Http403ForbiddenEntryPoint implements AuthenticationEntryPoint {
  /// The entry point.
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

/// A redirect to the login page, like Spring's
/// `LoginUrlAuthenticationEntryPoint`.
final class LoginUrlAuthenticationEntryPoint
    implements AuthenticationEntryPoint {
  /// Redirects to [loginFormUrl] (under the context path).
  const LoginUrlAuthenticationEntryPoint(
    this.loginFormUrl, {
    this.contextPath = '',
  });

  /// The login page (`/login`).
  final String loginFormUrl;

  /// The application's context path.
  final String contextPath;

  @override
  Future<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  ) => sendRedirect(response, '$contextPath$loginFormUrl');
}

/// A `302` to [location].
Future<void> sendRedirect(ServerHttpResponse response, String location) async {
  if (response.isCommitted) {
    return;
  }
  response
    ..statusCode = HttpStatus.found
    ..headers.set(HttpHeaders.locationHeader, location);
  await response.close();
}

/// Picks the entry point by request, like Spring's
/// `DelegatingAuthenticationEntryPoint`: the first matching [entryPoints]
/// entry, else [defaultEntryPoint].
final class DelegatingAuthenticationEntryPoint
    implements AuthenticationEntryPoint {
  /// The [entryPoints] in order, [defaultEntryPoint] for the rest.
  DelegatingAuthenticationEntryPoint(
    List<(RequestMatcher, AuthenticationEntryPoint)> entryPoints, {
    required this.defaultEntryPoint,
  }) : entryPoints = List.unmodifiable(entryPoints);

  /// By matcher, in order.
  final List<(RequestMatcher, AuthenticationEntryPoint)> entryPoints;

  /// For requests no matcher matches.
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

/// Picks the access denied handler by request, like Spring's
/// `RequestMatcherDelegatingAccessDeniedHandler`.
final class DelegatingAccessDeniedHandler implements AccessDeniedHandler {
  /// The [handlers] in order, [defaultHandler] for the rest.
  DelegatingAccessDeniedHandler(
    List<(RequestMatcher, AccessDeniedHandler)> handlers, {
    this.defaultHandler = const AccessDeniedHandlerImpl(),
  }) : handlers = List.unmodifiable(handlers);

  /// By matcher, in order.
  final List<(RequestMatcher, AccessDeniedHandler)> handlers;

  /// For the rest.
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
