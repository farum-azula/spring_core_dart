// An API client logs in, not a browser: no redirects, plain statuses.
import 'dart:convert';

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

/// `POST /api/logout` with single sign-on (the `sso` profile): the session
/// here is gone, and the answer says how to end the one at Keycloak too.
///
/// Logging out of this server alone would leave the browser logged in at
/// Keycloak, and the next "Sign in with Keycloak" would pass without a
/// password. Spring's `OidcClientInitiatedLogoutSuccessHandler` redirects
/// the browser to Keycloak's `end_session_endpoint`, but the app logs out
/// with a script request (`fetch`), which cannot follow a redirect to
/// another origin; a page would have to post a form instead. So the
/// answer is `200 {"logoutUrl": "..."}`, the same URL, and the web app
/// navigates there; Keycloak ends its session and sends the browser back
/// to [postLogoutRedirectUri] (the web app). With the ID token as
/// `id_token_hint`, Keycloak asks nothing; the browser sees it in the URL,
/// as with Spring's redirect (it is no access token: no API accepts it).
///
/// A user who did not log in through Keycloak here (a native app's bearer
/// token, no session at all) gets `204`, like the form login's logout.
final class SsoLogoutSuccessHandler implements LogoutSuccessHandler {
  const SsoLogoutSuccessHandler(
    this.registrations, {
    required this.postLogoutRedirectUri,
  });

  final ClientRegistrationRepository registrations;

  /// Where Keycloak sends the browser after its logout.
  final String postLogoutRedirectUri;

  @override
  Future<void> onLogoutSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) async {
    final logoutUrl = await _endSessionUrl(authentication);
    if (logoutUrl == null) {
      response.statusCode = HttpStatus.noContent;
    } else {
      response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = MediaType.applicationJson
        ..write(jsonEncode({'logoutUrl': '$logoutUrl'}));
    }
    await response.close();
  }

  Future<Uri?> _endSessionUrl(Authentication? authentication) async {
    if (authentication is! OAuth2AuthenticationToken) {
      return null;
    }
    final user = authentication.principal;
    final registration = await registrations.findByRegistrationId(
      authentication.authorizedClientRegistrationId,
    );
    final endpoint = registration?.providerDetails.endSessionEndpoint;
    if (user is! OidcUser || endpoint == null || endpoint.isEmpty) {
      return null;
    }
    final uri = Uri.parse(endpoint);
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'id_token_hint': user.idToken.tokenValue,
        'post_logout_redirect_uri': postLogoutRedirectUri,
      },
    );
  }
}
