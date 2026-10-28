import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

const _log = SpringLog('spring.security.oauth2.client.web');

/// The address of the application as [request] reached it: its scheme,
/// host and port, followed by [contextPath]; the value of `{baseUrl}` in
/// a redirect URI template.
///
/// The host is the request's `Host` header, as in Spring. A forged
/// `Host` only makes the provider refuse the redirect URI (it must be
/// registered there), and the token request sends back the redirect URI
/// saved with the login, never one read from the callback.
Uri requestBaseUrl(ServerHttpRequest request, {String contextPath = ''}) {
  final uri = request.uri;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: contextPath,
  );
}

/// Where an OAuth 2.0 login keeps its [OAuth2AuthorizationRequest] between
/// the redirect to the provider and the provider's redirect back.
///
/// The request holds what the callback must check (`state`, the PKCE
/// verifier, the `nonce`), so it must stay on the server, bound to the
/// browser that started the login. The default,
/// [HttpSessionOAuth2AuthorizationRequestRepository], keeps it in the
/// HTTP session.
///
/// Spring (Java): `AuthorizationRequestRepository<OAuth2AuthorizationRequest>`.
abstract interface class OAuth2AuthorizationRequestRepository {
  /// The saved request whose `state` is the `state` parameter of
  /// [request], or `null`.
  FutureOr<OAuth2AuthorizationRequest?> loadAuthorizationRequest(
    ServerHttpRequest request,
  );

  /// Saves [authorizationRequest] for the browser of [request];
  /// `null` removes the saved one.
  FutureOr<void> saveAuthorizationRequest(
    OAuth2AuthorizationRequest? authorizationRequest,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );

  /// Removes and returns the saved request whose `state` is the `state`
  /// parameter of [request]; `null` (and nothing removed) when there is
  /// none or the state differs.
  FutureOr<OAuth2AuthorizationRequest?> removeAuthorizationRequest(
    ServerHttpRequest request,
    ServerHttpResponse response,
  );
}

/// The default [OAuth2AuthorizationRequestRepository]: one authorization
/// request per HTTP session.
///
/// Starting a login replaces the request of a login started before in the
/// same browser. The callback finds it only with its exact `state`
/// (compared in constant time) and removes it: a callback is accepted
/// once, a replayed or forged one finds nothing. A callback with another
/// `state` leaves the saved request alone, so a forged callback cannot
/// break a login in progress.
///
/// Spring (Java): `HttpSessionOAuth2AuthorizationRequestRepository`, one
/// request per session since Spring Security 5.7.
final class HttpSessionOAuth2AuthorizationRequestRepository
    implements OAuth2AuthorizationRequestRepository {
  /// The repository; it has no state of its own.
  const HttpSessionOAuth2AuthorizationRequestRepository();

  /// The session attribute holding the request.
  static const authorizationRequestAttributeName =
      'HttpSessionOAuth2AuthorizationRequestRepository.AUTHORIZATION_REQUEST';

  @override
  OAuth2AuthorizationRequest? loadAuthorizationRequest(
    ServerHttpRequest request,
  ) {
    final state = switch (request.queryParameters[OAuth2ParameterNames.state]) {
      [final value] when value.isNotEmpty => value,
      _ => null,
    };
    if (state == null) {
      return null;
    }
    final saved = request
        .getSession(create: false)
        ?.getAttribute(authorizationRequestAttributeName);
    if (saved is! OAuth2AuthorizationRequest ||
        !constantTimeEquals(utf8.encode(saved.state), utf8.encode(state))) {
      return null;
    }
    return saved;
  }

  @override
  Future<void> saveAuthorizationRequest(
    OAuth2AuthorizationRequest? authorizationRequest,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    if (authorizationRequest == null) {
      request
          .getSession(create: false)
          ?.removeAttribute(authorizationRequestAttributeName);
      return;
    }
    if (authorizationRequest.state.isEmpty) {
      throw ArgumentError('authorizationRequest.state cannot be empty');
    }
    (await request.getSessionAsync())!.setAttribute(
      authorizationRequestAttributeName,
      authorizationRequest,
    );
  }

  @override
  OAuth2AuthorizationRequest? removeAuthorizationRequest(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    final saved = loadAuthorizationRequest(request);
    if (saved != null) {
      request
          .getSession(create: false)
          ?.removeAttribute(authorizationRequestAttributeName);
    }
    return saved;
  }
}

/// Builds the [OAuth2AuthorizationRequest] of a request that starts a
/// login, or says it does not start one (`null`).
///
/// Spring (Java): `OAuth2AuthorizationRequestResolver`.
abstract interface class OAuth2AuthorizationRequestResolver {
  /// The authorization request [request] starts, or `null`.
  ///
  /// Throws an [InvalidClientRegistrationIdException] when the request
  /// names an unknown registration.
  Future<OAuth2AuthorizationRequest?> resolve(ServerHttpRequest request);
}

/// The path names a registration that does not exist.
///
/// The redirect filter answers it with a 400.
///
/// Spring (Java): `InvalidClientRegistrationIdException`.
class InvalidClientRegistrationIdException implements Exception {
  /// An unknown registration, described by [message].
  InvalidClientRegistrationIdException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'InvalidClientRegistrationIdException: $message';
}

/// The default [OAuth2AuthorizationRequestResolver]: a request to
/// `/oauth2/authorization/{registrationId}` starts the login of that
/// registration.
///
/// The authorization request gets a fresh `state`, a PKCE verifier and
/// its `S256` challenge (always, confidential clients included), and for
/// the `openid` scope a fresh `nonce`. The redirect URI is the
/// registration's template expanded for this request: `{baseUrl}` is the
/// scheme, host and port the request came to, plus the context path;
/// `{registrationId}` and `{action}` (the `action` query parameter,
/// `login` by default) too.
///
/// ```dart
/// // Ask Keycloak to skip its own page and use Google.
/// http.oauth2Login((login) => login.authorizationEndpoint(
///   (endpoint) => endpoint.authorizationRequestResolver(
///     DefaultOAuth2AuthorizationRequestResolver(
///       registrations,
///       additionalParameters: (request, registration) =>
///           {'kc_idp_hint': 'google'},
///     ),
///   ),
/// ));
/// ```
///
/// Spring (Java): `DefaultOAuth2AuthorizationRequestResolver` with
/// `OAuth2AuthorizationRequestCustomizers.withPkce()`;
/// [additionalParameters] stands for its authorization request
/// customizer.
final class DefaultOAuth2AuthorizationRequestResolver
    implements OAuth2AuthorizationRequestResolver {
  /// A resolver for the registrations of [clientRegistrationRepository],
  /// at [authorizationRequestBaseUri] (`/oauth2/authorization`) followed
  /// by the registration id.
  DefaultOAuth2AuthorizationRequestResolver(
    this.clientRegistrationRepository, {
    String authorizationRequestBaseUri = defaultAuthorizationRequestBaseUri,
    this.contextPath = '',
    this.additionalParameters,
  }) : _matcher = PathPatternRequestMatcher(
         '${_withoutSlash(authorizationRequestBaseUri)}/{registrationId}',
       );

  /// The default base path of the login starts.
  static const defaultAuthorizationRequestBaseUri = '/oauth2/authorization';

  /// The registrations.
  final ClientRegistrationRepository clientRegistrationRepository;

  /// The application's context path, part of `{baseUrl}`; `''` for none.
  final String contextPath;

  /// More parameters for the provider's page (`prompt`, `login_hint`,
  /// `kc_idp_hint`), by request and registration; they cannot replace
  /// the parameters of the flow.
  final Map<String, String> Function(
    ServerHttpRequest request,
    ClientRegistration registration,
  )?
  additionalParameters;

  final RequestMatcher _matcher;

  static String _withoutSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  @override
  Future<OAuth2AuthorizationRequest?> resolve(ServerHttpRequest request) async {
    final match = _matcher.matcher(request);
    final registrationId = match.variables['registrationId'];
    if (!match.isMatch || registrationId == null) {
      return null;
    }
    final registration = await clientRegistrationRepository
        .findByRegistrationId(registrationId);
    if (registration == null) {
      throw InvalidClientRegistrationIdException(
        'Invalid Client Registration with Id: $registrationId',
      );
    }
    if (registration.authorizationGrantType !=
        AuthorizationGrantType.authorizationCode) {
      throw InvalidClientRegistrationIdException(
        'Invalid Authorization Grant Type '
        '(${registration.authorizationGrantType}) for Client Registration '
        'with Id: $registrationId',
      );
    }
    final action = switch (request.queryParameters['action']) {
      [final value] when RegExp(r'^[A-Za-z]+$').hasMatch(value) => value,
      _ => 'login',
    };
    final redirectUri = expandRedirectUri(
      registration,
      baseUrl: requestBaseUrl(request, contextPath: contextPath),
      action: action,
    );
    return OAuth2AuthorizationRequest.forRegistration(
      registration,
      redirectUri: redirectUri,
      additionalParameters:
          additionalParameters?.call(request, registration) ?? const {},
    );
  }
}

/// The filter that starts an OAuth 2.0 login: it sends the browser to the
/// provider's login page.
///
/// For a request the [authorizationRequestResolver] recognises
/// (`/oauth2/authorization/keycloak` by default), it saves the new
/// authorization request in the [authorizationRequestRepository] (the
/// session) and answers `302` to the provider's authorization endpoint
/// with `response_type=code`, the client id, the scopes, the `state`, the
/// redirect URI, the PKCE challenge and the `nonce` hash. A registration
/// that does not exist gets a 400; a registration that cannot be resolved
/// (the provider's discovery failed) a 500. Other requests pass.
///
/// `oauth2Login()` adds it.
///
/// Spring (Java): `OAuth2AuthorizationRequestRedirectFilter`.
final class OAuth2AuthorizationRequestRedirectFilter implements WebFilter {
  /// A filter starting the logins [authorizationRequestResolver]
  /// recognises.
  OAuth2AuthorizationRequestRedirectFilter(
    this.authorizationRequestResolver, {
    this.authorizationRequestRepository =
        const HttpSessionOAuth2AuthorizationRequestRepository(),
  });

  /// Recognises the requests that start a login and builds their
  /// authorization request.
  final OAuth2AuthorizationRequestResolver authorizationRequestResolver;

  /// Where the authorization request is kept until the callback.
  final OAuth2AuthorizationRequestRepository authorizationRequestRepository;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    final OAuth2AuthorizationRequest? authorizationRequest;
    try {
      authorizationRequest = await authorizationRequestResolver.resolve(
        request,
      );
    } on InvalidClientRegistrationIdException {
      // The id comes from the path: not logged, it could be anything.
      _log.warning('Authorization Request failed: unknown registration');
      await writeSecurityProblem(request, response, 400, 'Bad Request');
      return;
    } on Object catch (e) {
      _log.error('Authorization Request failed: ${e.runtimeType}');
      await writeSecurityProblem(
        request,
        response,
        HttpStatus.internalServerError,
        'Internal Server Error',
      );
      return;
    }
    if (authorizationRequest == null) {
      return await chain.doFilter(request, response);
    }
    if (authorizationRequest.grantType ==
        AuthorizationGrantType.authorizationCode) {
      await authorizationRequestRepository.saveAuthorizationRequest(
        authorizationRequest,
        request,
        response,
      );
    }
    await sendRedirect(
      response,
      authorizationRequest.authorizationRequestUri.toString(),
    );
  }
}
