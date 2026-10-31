import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_security/src/oauth2/authorization_request_redirect.dart';
import 'package:spring_boot_starter_security/src/oauth2/authorized_client_repository.dart';
import 'package:spring_boot_starter_security/src/oauth2/oidc_id_token_decoder_factory.dart';
import 'package:spring_boot_starter_security/src/web/authentication.dart';
import 'package:spring_boot_starter_security/src/web/filter_chain.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

const _log = SpringLog('spring.security.oauth2.client.web');

/// The login request of an OAuth 2.0 callback, then its result.
///
/// [OAuth2LoginAuthenticationFilter] builds it from the saved
/// authorization request and the provider's redirect (not authenticated
/// yet); [OAuth2LoginAuthenticationProvider] or
/// [OidcAuthorizationCodeAuthenticationProvider] return it authenticated,
/// with the user and the tokens. The filter turns that into the
/// [OAuth2AuthenticationToken] the application sees. [toString] never
/// shows a token.
///
/// Spring (Java): `OAuth2LoginAuthenticationToken`.
final class OAuth2LoginAuthenticationToken extends AbstractAuthenticationToken {
  /// The login request of [clientRegistration] with [authorizationExchange]
  /// (what was sent, what came back); not authenticated.
  OAuth2LoginAuthenticationToken.unauthenticated(
    this.clientRegistration,
    this.authorizationExchange,
  ) : principal = null,
      accessToken = null,
      refreshToken = null,
      super();

  /// The login of [principal], with [authorities] (mapped) and the tokens
  /// the code was exchanged for; authenticated.
  OAuth2LoginAuthenticationToken.authenticated(
    this.clientRegistration,
    this.authorizationExchange,
    OAuth2User this.principal,
    Iterable<GrantedAuthority> authorities,
    OAuth2AccessToken this.accessToken, {
    this.refreshToken,
  }) : super(authorities) {
    super.isAuthenticated = true;
  }

  /// The registration of the login.
  final ClientRegistration clientRegistration;

  /// The authorization request and the provider's response.
  final OAuth2AuthorizationExchange authorizationExchange;

  /// The user, once authenticated.
  @override
  final OAuth2User? principal;

  /// The access token, once authenticated.
  final OAuth2AccessToken? accessToken;

  /// The refresh token, or `null`.
  final OAuth2RefreshToken? refreshToken;

  /// Always empty: the code is in [authorizationExchange].
  @override
  Object? get credentials => '';

  @override
  String toString() =>
      'OAuth2LoginAuthenticationToken '
      '[registrationId=${clientRegistration.registrationId}, '
      'authenticated=$isAuthenticated, principal=${principal?.name}]';
}

// The checks of the redirect against the saved request, before the code
// is exchanged: the state (the repository found the request by it; checked
// again for other repositories), the issuer of RFC 9207, an error of the
// provider, the code.
void _validateExchange(
  ClientRegistration registration,
  OAuth2AuthorizationExchange exchange,
) {
  Never fail(String code, [String? description]) {
    final error = OAuth2Error(code, description);
    throw OAuth2AuthenticationException(error, error.toString());
  }

  final request = exchange.authorizationRequest;
  final response = exchange.authorizationResponse;
  final state = response.state;
  if (state == null ||
      !constantTimeEquals(utf8.encode(state), utf8.encode(request.state))) {
    fail(OAuth2ErrorCodes.invalidStateParameter);
  }
  final issuer = registration.providerDetails.issuerUri;
  final metadata = registration.providerDetails.configurationMetadata;
  if (response.issuer case final iss?) {
    // Without issuer-uri there is nothing to compare with (RFC 9207 §2.4
    // compares with the issuer the client knows); the callback path of
    // each registration still keeps providers apart.
    if (issuer != null && iss != issuer) {
      fail(
        OAuth2ErrorCodes.invalidIssuer,
        'The redirect comes from another issuer than the registration',
      );
    }
  } else if (metadata['authorization_response_iss_parameter_supported'] ==
      true) {
    fail(
      OAuth2ErrorCodes.invalidIssuer,
      'The redirect has no iss parameter although the provider sends one',
    );
  }
  if (response.statusError) {
    final error = OAuth2Error(
      response.error!,
      response.errorDescription,
      response.errorUri,
    );
    throw OAuth2AuthenticationException(error, error.toString());
  }
  if (response.code == null || response.code!.isEmpty) {
    fail(OAuth2ErrorCodes.invalidRequest, 'The redirect has no code');
  }
}

// The token response's parameters, plus the authorization response's own
// (Sign in with Apple's `user`, posted on the first login only) under
// names the token response does not use. Not signed: the user service may
// show them, never identify the user by them.
Map<String, Object?> _userRequestParameters(
  OAuth2LoginAuthenticationToken login,
  OAuth2AccessTokenResponse tokens,
) => {
  for (final MapEntry(:key, :value)
      in login
          .authorizationExchange
          .authorizationResponse
          .additionalParameters
          .entries)
    if (!_tokenParameterNames.contains(key)) key: value,
  ...tokens.additionalParameters,
};

const Set<String> _tokenParameterNames = {
  OAuth2ParameterNames.accessToken,
  OAuth2ParameterNames.tokenType,
  OAuth2ParameterNames.expiresIn,
  OAuth2ParameterNames.refreshToken,
  OAuth2ParameterNames.scope,
  OidcParameterNames.idToken,
};

Future<OAuth2AccessTokenResponse> _exchange(
  OAuth2LoginAuthenticationToken login,
  OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest> client,
) async {
  _validateExchange(login.clientRegistration, login.authorizationExchange);
  try {
    return await client.getTokenResponse(
      OAuth2AuthorizationCodeGrantRequest(
        login.clientRegistration,
        login.authorizationExchange,
      ),
    );
  } on OAuth2AuthorizationException catch (e) {
    throw OAuth2AuthenticationException(e.error, e.error.toString(), e);
  }
}

/// The [AuthenticationProvider] of OAuth 2.0 logins without OpenID
/// Connect (GitHub, Facebook): it exchanges the code and loads the user
/// from the user-info endpoint.
///
/// The checks before the exchange: the `state` of the redirect is the
/// saved one, the `iss` parameter (RFC 9207) is the registration's issuer
/// when either says there is one, the provider sent no `error`. A
/// registration without `issuer-uri` (endpoints configured one by one)
/// has no issuer to compare with: its `iss` is not checked, and the
/// redirect URI of each registration keeps the providers apart (a
/// callback for another registration fails). The code
/// is exchanged with the PKCE verifier and the exact redirect URI of the
/// authorization request. The user's authorities go through
/// [authoritiesMapper]. A login that asked for the `openid` scope is left
/// to [OidcAuthorizationCodeAuthenticationProvider] (`null`).
///
/// Spring (Java): `OAuth2LoginAuthenticationProvider` (with
/// `OAuth2AuthorizationCodeAuthenticationProvider`); the `iss` check is
/// this package's.
final class OAuth2LoginAuthenticationProvider
    implements AuthenticationProvider {
  /// A provider exchanging codes with [accessTokenResponseClient] and
  /// loading users with [userService].
  const OAuth2LoginAuthenticationProvider(
    this.accessTokenResponseClient,
    this.userService, {
    this.authoritiesMapper = const NullAuthoritiesMapper(),
  });

  /// Exchanges the code at the token endpoint.
  final OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest>
  accessTokenResponseClient;

  /// Loads the user.
  final OAuth2UserService<OAuth2UserRequest, OAuth2User> userService;

  /// Maps the user's authorities.
  final GrantedAuthoritiesMapper authoritiesMapper;

  @override
  bool supports(Authentication authentication) =>
      authentication is OAuth2LoginAuthenticationToken;

  @override
  Future<Authentication?> authenticate(Authentication authentication) async {
    final login = authentication as OAuth2LoginAuthenticationToken;
    if (login.authorizationExchange.authorizationRequest.scopes.contains(
      'openid',
    )) {
      return null; // an OpenID Connect login
    }
    final tokens = await _exchange(login, accessTokenResponseClient);
    final user = await userService.loadUser(
      OAuth2UserRequest(
        login.clientRegistration,
        tokens.accessToken,
        additionalParameters: _userRequestParameters(login, tokens),
      ),
    );
    return OAuth2LoginAuthenticationToken.authenticated(
      login.clientRegistration,
      login.authorizationExchange,
      user,
      authoritiesMapper.mapAuthorities(user.authorities),
      tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }
}

/// The [AuthenticationProvider] of OpenID Connect logins (Keycloak,
/// Google, Auth0, Okta): it exchanges the code, checks the ID token and
/// loads the user.
///
/// The checks: those of [OAuth2LoginAuthenticationProvider] before the
/// exchange; then the token response must carry an ID token, which
/// [idTokenDecoder] checks (by default its signature with the provider's
/// JWK Set, its issuer, audience, `azp`, expiry and issue time), and its
/// `nonce` must be the hash of the one the login sent (no replayed ID
/// token). The [userService] adds the user info, whose `sub` must be the
/// ID token's. The authorities go through [authoritiesMapper]. A login
/// without the `openid` scope is left to
/// [OAuth2LoginAuthenticationProvider] (`null`).
///
/// Spring (Java): `OidcAuthorizationCodeAuthenticationProvider`.
final class OidcAuthorizationCodeAuthenticationProvider
    implements AuthenticationProvider {
  /// A provider exchanging codes with [accessTokenResponseClient], checking
  /// ID tokens with [idTokenDecoder] (an [OidcIdTokenDecoderFactory] by
  /// default) and loading users with [userService].
  OidcAuthorizationCodeAuthenticationProvider(
    this.accessTokenResponseClient,
    this.userService, {
    OidcIdTokenDecoder? idTokenDecoder,
    this.authoritiesMapper = const NullAuthoritiesMapper(),
  }) : idTokenDecoder = idTokenDecoder ?? OidcIdTokenDecoderFactory();

  /// Exchanges the code at the token endpoint.
  final OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest>
  accessTokenResponseClient;

  /// Loads the user.
  final OAuth2UserService<OidcUserRequest, OidcUser> userService;

  /// Checks the ID token.
  final OidcIdTokenDecoder idTokenDecoder;

  /// Maps the user's authorities.
  final GrantedAuthoritiesMapper authoritiesMapper;

  @override
  bool supports(Authentication authentication) =>
      authentication is OAuth2LoginAuthenticationToken;

  @override
  Future<Authentication?> authenticate(Authentication authentication) async {
    final login = authentication as OAuth2LoginAuthenticationToken;
    final request = login.authorizationExchange.authorizationRequest;
    if (!request.scopes.contains('openid')) {
      return null; // a plain OAuth 2.0 login
    }
    final registration = login.clientRegistration;
    final tokens = await _exchange(login, accessTokenResponseClient);
    final raw = tokens.additionalParameters[OidcParameterNames.idToken];
    if (raw is! String || raw.isEmpty) {
      final error = OAuth2Error(
        OAuth2ErrorCodes.invalidIdToken,
        'Missing (required) ID Token in Token Response for Client '
        'Registration: ${registration.registrationId}',
      );
      throw OAuth2AuthenticationException(error, error.toString());
    }
    final idToken = await idTokenDecoder.decode(registration, raw);
    if (request.nonce case final nonce?) {
      final result = OidcIdTokenValidator.validateNonce(idToken, nonce);
      if (result.hasErrors) {
        throw OAuth2AuthenticationException(
          result.errors.first,
          result.errors.first.toString(),
        );
      }
    }
    final user = await userService.loadUser(
      OidcUserRequest(
        registration,
        tokens.accessToken,
        idToken,
        additionalParameters: _userRequestParameters(login, tokens),
      ),
    );
    return OAuth2LoginAuthenticationToken.authenticated(
      registration,
      login.authorizationExchange,
      user,
      authoritiesMapper.mapAuthorities(user.authorities),
      tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }
}

/// The filter that finishes an OAuth 2.0 login: the provider redirects
/// the browser back here (`/login/oauth2/code/keycloak`) with a code.
///
/// For a request [requiresAuthenticationMatcher] matches:
///
/// 1. it must be an authorization response: `code` and `state`, or
///    `error` and `state` (else `invalid_request`), in the query of a
///    `GET`, or in the `application/x-www-form-urlencoded` body of a
///    `POST` (`response_mode=form_post`, at most 64 KB, a larger body
///    is a 413, nothing of the response in its query); any other method
///    (`HEAD`, `PUT`, ...) is an `invalid_request` that leaves the login
///    in progress alone;
/// 2. the authorization request saved when the login started is found
///    in the [authorizationRequestRepository] by its `state`: without
///    one (no login started in this browser, a wrong or replayed
///    `state`), the login fails with `authorization_request_not_found`;
///    the response must come the way that request asked for, a form post
///    for `response_mode=form_post`, a `GET` otherwise (else
///    `invalid_request`, and the saved request stays for the real
///    callback); then it is removed, so a callback is accepted once;
/// 3. the callback must come to the redirect URI of that request (a
///    callback for another registration fails with
///    `invalid_redirect_uri_parameter`: no mixed-up providers);
/// 4. the [authenticationManager] exchanges the code and loads the user
///    ([OAuth2LoginAuthenticationProvider],
///    [OidcAuthorizationCodeAuthenticationProvider]);
/// 5. the tokens go to the [authorizedClientRepository];
/// 6. the session gets a new id ([sessionStrategy]), the user is stored
///    in the [securityContextRepository] (the session), an
///    `InteractiveAuthenticationSuccessEvent` is published, and the
///    [successHandler] answers: by default a redirect to the page saved
///    before the login, else to the default success URL.
///
/// A failure clears the context and goes to the [failureHandler] (by
/// default a redirect to `/login?error`). Nothing about the failure
/// reaches the browser; the log has the error code, never the code or a
/// token. `oauth2Login()` adds it.
///
/// The provider's form post is a cross-site `POST`: it carries only
/// `SameSite=None; Secure` cookies, which the default
/// [CookieOAuth2AuthorizationRequestRepository] sets for a form post
/// login over HTTPS (a session repository needs
/// `server.servlet.session.cookie.same-site=none`). Without the cookie
/// no saved request is found and the login fails (closed), with a
/// warning in the log. The CSRF filter lets these posts through
/// (`oauth2Login()` exempts the callback's `POST`): the `state`, bound
/// to the browser that started the login, is their CSRF protection
/// (RFC 6749 §10.12).
///
/// Spring (Java): `OAuth2LoginAuthenticationFilter`; step 3 is this
/// package's (Spring trusts the registration id of the saved request),
/// and so are the checks of the method (Spring reads the parameters of
/// any method, sends no `response_mode`, and leaves CSRF and the cookie
/// to the application).
final class OAuth2LoginAuthenticationFilter implements WebFilter {
  /// A filter for the callbacks at `filterProcessesUrl`
  /// (`/login/oauth2/code/*` by default), any method.
  OAuth2LoginAuthenticationFilter(
    this.clientRegistrationRepository,
    this.authorizedClientRepository,
    this.authenticationManager, {
    String filterProcessesUrl = defaultFilterProcessesUri,
    this.authorizationRequestRepository =
        const CookieOAuth2AuthorizationRequestRepository(),
    this.successHandler = const SavedRequestAwareAuthenticationSuccessHandler(),
    this.failureHandler = const SimpleUrlAuthenticationFailureHandler(
      '/login?error',
    ),
    this.sessionStrategy = const ChangeSessionIdAuthenticationStrategy(),
    this.securityContextRepository =
        const HttpSessionSecurityContextRepository(),
    this.eventPublisher,
  }) : requiresAuthenticationMatcher = PathPatternRequestMatcher(
         filterProcessesUrl,
       );

  /// The default path of the callbacks.
  static const defaultFilterProcessesUri = '/login/oauth2/code/*';

  /// The error code of a callback without a saved authorization request.
  static const authorizationRequestNotFoundErrorCode =
      'authorization_request_not_found';

  /// The error code of a callback whose registration no longer exists.
  static const clientRegistrationNotFoundErrorCode =
      'client_registration_not_found';

  /// The error code of a callback that came to another redirect URI than
  /// the one of its authorization request.
  static const invalidRedirectUriParameterErrorCode =
      'invalid_redirect_uri_parameter';

  /// The registrations.
  final ClientRegistrationRepository clientRegistrationRepository;

  /// Where the tokens of a login go.
  final OAuth2AuthorizedClientRepository authorizedClientRepository;

  /// Exchanges the code and loads the user.
  final AuthenticationManager authenticationManager;

  /// Decides which requests are callbacks.
  final RequestMatcher requiresAuthenticationMatcher;

  /// Where the authorization request was saved.
  final OAuth2AuthorizationRequestRepository authorizationRequestRepository;

  /// Answers a successful login.
  final AuthenticationSuccessHandler successHandler;

  /// Answers a failed login.
  final AuthenticationFailureHandler failureHandler;

  /// What is done to the session at login.
  final SessionAuthenticationStrategy sessionStrategy;

  /// Where the context of a successful login is saved.
  final SecurityContextRepository securityContextRepository;

  /// Publishes the `InteractiveAuthenticationSuccessEvent`; `null`
  /// publishes nothing.
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
    final Authentication result;
    try {
      result = await _attempt(request, response);
      await sessionStrategy.onAuthentication(result, request, response);
    } on AuthenticationException catch (e) {
      SecurityContextHolder.clearContext();
      final reason = e is OAuth2AuthenticationException
          ? e.error.errorCode
          : '${e.runtimeType}';
      _log.debug('OAuth2 login failed: $reason');
      await failureHandler.onAuthenticationFailure(request, response, e);
      return;
    }
    final context = SecurityContextHolder.createEmptyContext()
      ..authentication = result;
    SecurityContextHolder.setContext(context);
    await securityContextRepository.saveContext(context, request, response);
    eventPublisher?.publishEvent(InteractiveAuthenticationSuccessEvent(result));
    await successHandler.onAuthenticationSuccess(request, response, result);
  }

  Future<OAuth2AuthenticationToken> _attempt(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    Never fail(String code, [String? description]) {
      final error = OAuth2Error(code, description);
      throw OAuth2AuthenticationException(error, error.toString());
    }

    // The response comes with the provider's redirect (GET) or its form
    // post: a HEAD, PUT, ... is no callback, and the login in progress
    // stays for the real one.
    if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
      fail(
        OAuth2ErrorCodes.invalidRequest,
        'The authorization response comes with a GET or a form POST',
      );
    }
    final posted = request.method == HttpMethod.post;
    var current = request;
    Map<String, List<String>> parameters;
    if (posted) {
      final (read, form) = await readFormParameters(
        request,
        maxLength: 64 * 1024,
      );
      current = read;
      final query = request.queryParameters;
      if (form == null ||
          query.containsKey(OAuth2ParameterNames.state) ||
          query.containsKey(OAuth2ParameterNames.code) ||
          query.containsKey(OAuth2ParameterNames.error)) {
        fail(OAuth2ErrorCodes.invalidRequest);
      }
      parameters = form;
    } else {
      parameters = request.queryParameters;
    }
    final authorizationResponse = OAuth2AuthorizationResponse.fromParameters(
      parameters,
      redirectUri: request.uri.replace(query: '').removeFragment().toString(),
    );
    bool present(String? value) => value != null && value.isNotEmpty;
    if (!present(authorizationResponse.state) ||
        !(present(authorizationResponse.code) ||
            present(authorizationResponse.error))) {
      fail(OAuth2ErrorCodes.invalidRequest);
    }
    final saved = await authorizationRequestRepository.loadAuthorizationRequest(
      current,
    );
    if (saved == null) {
      if (posted) {
        _warnAboutCrossSiteCookie();
      }
      fail(authorizationRequestNotFoundErrorCode);
    }
    final formPost = saved.responseMode == ResponseMode.formPost;
    if (formPost != posted) {
      // Left saved: a forged callback of the wrong kind cannot end the
      // login in progress.
      fail(
        OAuth2ErrorCodes.invalidRequest,
        formPost
            ? 'The login asked for response_mode=form_post: the response '
                  'must be posted'
            : 'The login asked for the response in the redirect URI',
      );
    }
    final authorizationRequest = await authorizationRequestRepository
        .removeAuthorizationRequest(current, response);
    if (authorizationRequest == null) {
      fail(authorizationRequestNotFoundErrorCode);
    }
    final registrationId = authorizationRequest.registrationId;
    final registration = registrationId == null
        ? null
        : await clientRegistrationRepository.findByRegistrationId(
            registrationId,
          );
    if (registration == null) {
      fail(
        clientRegistrationNotFoundErrorCode,
        'Client Registration not found with Id: $registrationId',
      );
    }
    if (Uri.parse(authorizationRequest.redirectUri).path != request.uri.path) {
      fail(
        invalidRedirectUriParameterErrorCode,
        'The callback came to another redirect URI than the one of the '
        'login',
      );
    }
    final details = WebAuthenticationDetails.of(current);
    final login = OAuth2LoginAuthenticationToken.unauthenticated(
      registration,
      OAuth2AuthorizationExchange(authorizationRequest, authorizationResponse),
    )..details = details;
    final result = await authenticationManager.authenticate(login);
    if (result is! OAuth2LoginAuthenticationToken ||
        result.principal == null ||
        result.accessToken == null) {
      throw InternalAuthenticationServiceException(
        'The AuthenticationManager did not return an authenticated '
        'OAuth2LoginAuthenticationToken',
      );
    }
    final user = result.principal!;
    final authentication = OAuth2AuthenticationToken(
      user,
      result.authorities,
      registration.registrationId,
    )..details = details;
    await authorizedClientRepository.saveAuthorizedClient(
      OAuth2AuthorizedClient(
        result.clientRegistration,
        authentication.name,
        result.accessToken!,
        refreshToken: result.refreshToken,
        idToken: user is OidcUser ? user.idToken : null,
      ),
      authentication,
      current,
      response,
    );
    return authentication;
  }

  static bool _warnedAboutCookie = false;

  static void _warnAboutCrossSiteCookie() {
    if (_warnedAboutCookie) {
      return;
    }
    _warnedAboutCookie = true;
    _log.warning(
      'An OAuth 2.0 form post callback found no authorization request: '
      "the provider's cross-site POST carries only SameSite=None; Secure "
      'cookies, so response_mode=form_post works over HTTPS only (with '
      'the session repository of the authorization requests: '
      'server.servlet.session.cookie.same-site=none)',
    );
  }
}
