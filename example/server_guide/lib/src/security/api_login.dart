// An API client logs in, not a browser: no redirects, plain statuses.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

/// `POST /api/login` succeeded: 204 (the session cookie is in the
/// response).
final class ApiLoginSuccessHandler implements AuthenticationSuccessHandler {
  const ApiLoginSuccessHandler();

  @override
  Future<void> onAuthenticationSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication authentication,
  ) async {
    response.statusCode = HttpStatus.noContent;
    await response.close();
  }
}

/// `POST /api/login` failed: 401 with a ProblemDetail (the same for an
/// unknown user and a wrong password).
final class ApiLoginFailureHandler implements AuthenticationFailureHandler {
  const ApiLoginFailureHandler();

  @override
  Future<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  ) => writeSecurityProblem(
    request,
    response,
    HttpStatus.unauthorized,
    'Bad credentials',
  );
}

/// Sends the CSRF cookie with every response, so a client has the token
/// before its first POST (Spring's single-page-app recipe: the token is
/// created lazily otherwise, when something reads it).
final class CsrfCookieFilter extends OncePerRequestFilter {
  @override
  Future<void> doFilterInternal(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    csrfTokenOf(request); // reading it writes the cookie when it is new
    return chain.doFilter(request, response);
  }
}
