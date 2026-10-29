import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_flutter_security/src/login/oauth2_login_service.dart';
import 'package:spring_boot_starter_flutter_security/src/login/oauth2_token_revocation_client.dart';
import 'package:spring_boot_starter_flutter_security/src/web/flutter_web_security_properties.dart';
import 'package:spring_boot_starter_flutter_security/src/web/spa_browser_page.dart';
import 'package:spring_boot_starter_flutter_security/src/web/web_crypto_dpop_key.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

const _log = SpringLog('spring.security.oauth2.client.login');

/// The [OAuth2LoginService] of a Flutter web app without a server of its
/// own: the browser logs in by itself, as a public client with PKCE, and
/// keeps the tokens in the tab's memory (`spring.flutter.security.web.mode=spa`).
///
/// The `server` mode (`ServerOAuth2LoginService`) is the stronger choice
/// whenever the app has a server: there no token ever reaches the page.
/// This mode is for apps that call APIs of others (or their own API,
/// which accepts the provider's tokens) straight from the browser. The
/// app's code is the same as on phones: `login(registrationId)`,
/// `restore()`, `logout()`, the Feign clients with the access token.
///
/// - [login] builds the authorization request of the registration (PKCE
///   `S256`, `state`, `nonce`, the client's
///   `OAuth2AuthorizationRequest.forRegistration`), keeps it in the tab's
///   `sessionStorage` for the round trip only, and navigates the page to
///   the provider. The result is `null`: the app stops there and starts
///   again when the provider sends the browser back.
/// - [restore], at startup, finishes that login: the page came back to
///   the redirect URI with `code` and `state`, which are checked as the
///   native login checks them (the `state`, the `iss` of RFC 9207, an
///   `error`); the code is exchanged at the token endpoint with the PKCE
///   verifier (no secret), the ID token checked (issuer, audience, times,
///   `nonce`), the user loaded and put into the `SecurityContextHolder`.
///   The `code` and `state` are removed from the address bar
///   (`history.replaceState`) and the request from `sessionStorage`. A
///   page that comes back without a login of its own (a reload of the
///   answer, a replayed link) logs nobody in.
/// - Without an answer, after a reload or in a new tab, [restore] brings
///   back a user who logged in in this browser before (silent
///   re-authentication, [FlutterWebSecurityProperties.silentRestore]):
///   the page goes to the provider with `prompt=none`, which answers at
///   once from its own session, without showing a page; `login_required`
///   means nobody is logged in there (not an error).
/// - [logout] forgets the tokens, revokes them when the provider has a
///   `revocation_endpoint` (best effort: it must allow CORS too), and
///   ends the provider's session: the page goes to its
///   `end_session_endpoint` with `id_token_hint`, and comes back to the
///   app.
///
/// **What is kept where.** The tokens only in the tab's memory (the
/// [TabOAuth2AuthorizedClientService]): a reload loses them, and the
/// silent re-authentication gets new ones. `sessionStorage` holds the
/// authorization request between leaving for the provider and coming
/// back (the `state`, the `nonce` and the PKCE `code_verifier`): the
/// verifier is useless without the code, which only the provider's
/// redirect carries, and it is removed as soon as the page is back.
/// `localStorage` holds only the id of the registration last logged in
/// with (the hint for the silent re-authentication), never a token.
///
/// **DPoP.** When a registration uses DPoP (`dpop=auto` or `true`), the
/// `DPoPKey` (a [WebCryptoDPoPKey] in the browser) is loaded before the
/// login,
/// its thumbprint sent as `dpop_jkt` (the code is bound to the key, RFC
/// 9449 §10), and the token requests and API calls carry proofs signed by
/// the non-extractable key.
///
/// **The provider** must accept a public client (no secret) with PKCE
/// whose redirect URI is the app's page, and allow the page's origin on
/// its token, user info and revocation endpoints (CORS; Keycloak's "Web
/// origins"). A registration with a client secret is refused: a browser
/// cannot keep it.
///
/// Spring has no counterpart: Spring Security logs browsers in on the
/// server. The checks are those of its `OAuth2LoginAuthenticationFilter`,
/// `OidcAuthorizationCodeAuthenticationProvider` and `OidcUserService`.
class SpaOAuth2LoginService implements OAuth2LoginService {
  /// A browser login on the registrations of
  /// [clientRegistrationRepository]; the package's auto-configuration
  /// passes the beans.
  SpaOAuth2LoginService({
    required this.clientRegistrationRepository,
    required this.authorizedClientService,
    required this.accessTokenResponseClient,
    required this.userService,
    required this.oidcUserService,
    required this.page,
    this.properties = const FlutterWebSecurityProperties(
      mode: WebLoginMode.spa,
    ),
    this.revocationClient,
    OidcIdTokenDecoder? idTokenDecoder,
    this.authoritiesMapper = const NullAuthoritiesMapper(),
    this.dPoPKey,
    this.eventPublisher,
    SecurityContextHolderStrategy? securityContextHolderStrategy,
    DateTime Function()? clock,
    this.requestLifetime = const Duration(minutes: 10),
  }) : idTokenDecoder = idTokenDecoder ?? TokenEndpointOidcIdTokenDecoder(),
       securityContextHolderStrategy =
           securityContextHolderStrategy ??
           SecurityContextHolder.getContextHolderStrategy(),
       _clock = clock ?? DateTime.now;

  /// The `sessionStorage` key of the authorization request on its round
  /// trip to the provider.
  static const authorizationRequestKey =
      'spring.security.oauth2.authorization-request';

  /// The `localStorage` key of the registration id last logged in with:
  /// the hint for the silent re-authentication. Never a token.
  static const loginHintKey = 'spring.security.oauth2.login-hint';

  /// The errors of a `prompt=none` request that mean "nobody is logged in
  /// at the provider" (OpenID Connect Core §3.1.2.6), not a failure.
  static const silentErrors = {
    'login_required',
    'interaction_required',
    'consent_required',
    'account_selection_required',
  };

  // The parameters of the provider's answer, removed from the address.
  static const _answerParameters = {
    OAuth2ParameterNames.code,
    OAuth2ParameterNames.state,
    OAuth2ParameterNames.issuer,
    OAuth2ParameterNames.error,
    OAuth2ParameterNames.errorDescription,
    OAuth2ParameterNames.errorUri,
    'session_state',
  };

  /// The registrations.
  final ClientRegistrationRepository clientRegistrationRepository;

  /// Where the tokens are kept: in the tab's memory.
  final OAuth2AuthorizedClientService authorizedClientService;

  /// Exchanges the code.
  final OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest>
  accessTokenResponseClient;

  /// Loads OAuth 2.0 users.
  final OAuth2UserService<OAuth2UserRequest, OAuth2User> userService;

  /// Loads OpenID Connect users.
  final OAuth2UserService<OidcUserRequest, OidcUser> oidcUserService;

  /// The page: its address, its storages, leaving it for the provider.
  final SpaBrowserPage page;

  /// The web login's settings ([FlutterWebSecurityProperties.silentRestore]).
  final FlutterWebSecurityProperties properties;

  /// Revokes the tokens in [logout]; without one they are not revoked.
  final OAuth2TokenRevocationClient? revocationClient;

  /// Decodes and checks the ID token.
  final OidcIdTokenDecoder idTokenDecoder;

  /// Maps the user's authorities.
  final GrantedAuthoritiesMapper authoritiesMapper;

  /// The key the DPoP proofs are signed with (the token clients' own), or
  /// `null`; a [LoadableDPoPKey] (the [WebCryptoDPoPKey]) is loaded before
  /// a login that uses it.
  final DPoPKey? dPoPKey;

  /// Receives the login and logout events, or `null`.
  final ApplicationEventPublisher? eventPublisher;

  /// Where the logged-in user is put.
  final SecurityContextHolderStrategy securityContextHolderStrategy;

  /// How long an authorization request waits for the provider's answer;
  /// an older answer logs nobody in.
  final Duration requestLifetime;

  final DateTime Function() _clock;
  OAuth2AuthenticationToken? _authentication;
  bool _busy = false;
  final StreamController<OAuth2AuthenticationToken?> _changes =
      StreamController.broadcast(sync: true);

  @override
  OAuth2AuthenticationToken? get authentication => _authentication;

  /// The logged-in user ([OidcUser] with OpenID Connect), or `null`.
  OAuth2User? get user => _authentication?.principal;

  @override
  bool get isLoggedIn => _authentication != null;

  @override
  Stream<OAuth2AuthenticationToken?> get authenticationChanges =>
      _changes.stream;

  /// Navigates the page to the provider's login for the registration
  /// [registrationId] and returns `null`: the app stops there, and
  /// [restore] finishes the login when the provider sends the browser
  /// back.
  ///
  /// [additionalParameters] go to the provider's page (`prompt=login`,
  /// `login_hint=ada@example.com`, `kc_idp_hint=google`).
  ///
  /// Throws an [OAuth2AuthenticationException] for an unknown
  /// registration, one that is not `authorization_code`, or one with a
  /// client secret (a browser cannot keep it); an [UnsupportedError] when
  /// the registration uses DPoP and the browser has no WebCrypto; a
  /// [StateError] while a restore or logout runs.
  @override
  Future<Authentication?> login(
    String registrationId, {
    Map<String, String> additionalParameters = const {},
  }) => _exclusive(() async {
    final registration = await _registration(registrationId);
    await _leaveForProvider(registration, additionalParameters, silent: false);
    return null;
  });

  /// Finishes a login when the page came back from the provider, or
  /// brings back the user of an earlier login in this browser; returns
  /// the authentication, or `null` when nobody is logged in (yet). Call it
  /// once at startup.
  ///
  /// 1. The page is the redirect URI with the provider's answer (`state`
  ///    with `code` or `error`) and this tab sent the request: the answer
  ///    is checked, the code exchanged, the ID token checked, the user
  ///    loaded and put into the security context, and an
  ///    `AuthenticationSuccessEvent` published. The answer leaves the
  ///    address bar either way.
  /// 2. An answer this tab did not ask for (a reload of the answer, an old
  ///    or forged link, an answer after [requestLifetime]): nobody is
  ///    logged in, and the answer leaves the address bar.
  /// 3. No answer, and someone logged in in this browser before (the
  ///    hint in `localStorage`) and [FlutterWebSecurityProperties.silentRestore]:
  ///    the page goes to the provider with `prompt=none` and the result is
  ///    `null`; the provider sends it back at once, and this method, at
  ///    the next start, finishes that login (or, with `login_required`,
  ///    forgets the hint).
  ///
  /// Throws an [OAuth2AuthenticationException] when the answer to a
  /// [login] is refused (the provider's `error`, a wrong `state` or
  /// `iss`, the token endpoint's refusal, a wrong ID token), so the app
  /// can say why; a failed silent re-authentication only logs. Throws a
  /// [StateError] while a login or logout runs.
  @override
  Future<OAuth2AuthenticationToken?> restore() => _exclusive(() async {
    final location = page.location;
    final pending = _takeRequest();
    if (_isAnswer(location)) {
      final redirect = pending == null
          ? _appUri()
          : Uri.tryParse(pending.redirectUri) ?? _appUri();
      if (!_samePage(location, redirect)) {
        // Not the redirect URI: the app's own parameters.
        if (pending != null && pending.silent) {
          _forgetHint();
        }
        return pending != null && !pending.silent ? null : _silent();
      }
      page.replaceLocation(_withoutAnswer(location));
      if (pending == null) {
        _log.warning(
          'A login answer that this tab did not ask for (a reload of the '
          'answer, or an old or forged link) was ignored: nobody logged in',
        );
        return null;
      }
      if (_clock().difference(pending.createdAt) > requestLifetime) {
        _log.warning(
          'The login answer came after ${requestLifetime.inMinutes} '
          'minutes and was ignored: nobody logged in',
        );
        return null;
      }
      try {
        final authentication = await _complete(pending, location);
        page.localStorage.setItem(loginHintKey, pending.registrationId);
        return authentication;
      } on OAuth2AuthenticationException catch (e) {
        if (!pending.silent) {
          rethrow;
        }
        _forgetHint();
        if (silentErrors.contains(e.error.errorCode)) {
          _log.debug(
            "Nobody is logged in at the provider of registration '"
            "${pending.registrationId}' (${e.error.errorCode})",
          );
        } else {
          _log.warning(
            "The silent login of registration '${pending.registrationId}' "
            'failed (${e.error.errorCode}): nobody logged in',
          );
        }
        return null;
      }
    }
    if (pending != null) {
      // The page came back without an answer (the back button on the
      // provider's page). After a silent try: no second one.
      if (pending.silent) {
        _forgetHint();
      }
      return null;
    }
    return _silent();
  });

  /// Logs the user out: forgets their tokens, clears the security context
  /// and publishes a `LogoutSuccessEvent`; then revokes the tokens at the
  /// provider (refresh token first, when it has a `revocation_endpoint`;
  /// best effort, a failure is logged) and ends the provider's session:
  /// the page goes to its `end_session_endpoint` with the ID token as
  /// `id_token_hint` and comes back to [postLogoutRedirectUri] (the app's
  /// address by default; the provider must allow it).
  ///
  /// The provider's session always ends when the provider has an
  /// `end_session_endpoint` ([endSession] is not needed): every tab of the
  /// browser shares it, and while it lives the next [login], or the
  /// silent re-authentication of another tab, passes without a password.
  /// Nothing but the hint is cleared when nobody is logged in.
  ///
  /// Throws a [StateError] while a login or restore runs.
  @override
  Future<void> logout({bool endSession = false, Uri? postLogoutRedirectUri}) =>
      _exclusive(() async {
        _forgetHint();
        page.sessionStorage.removeItem(authorizationRequestKey);
        final authentication = _authentication;
        if (authentication == null) {
          return;
        }
        final registrationId = authentication.authorizedClientRegistrationId;
        ClientRegistration? registration;
        OAuth2AuthorizedClient? client;
        try {
          registration = await clientRegistrationRepository
              .findByRegistrationId(registrationId);
          client = await authorizedClientService.loadAuthorizedClient(
            registrationId,
            authentication.name,
          );
        } on Object catch (e) {
          _log.debug('No revocation at logout (${e.runtimeType})');
        }
        await authorizedClientService.removeAuthorizedClient(
          registrationId,
          authentication.name,
        );
        _authentication = null;
        securityContextHolderStrategy.clearContext();
        _changes.add(null);
        eventPublisher?.publishEvent(LogoutSuccessEvent(authentication));
        if (registration == null) {
          return;
        }
        if (client != null) {
          await _revoke(registration, client);
        }
        final principal = authentication.principal;
        final idToken =
            client?.idToken?.tokenValue ??
            (principal is OidcUser ? principal.idToken.tokenValue : null);
        final endpoint = registration.providerDetails.endSessionEndpoint;
        if (endpoint == null || idToken == null) {
          return;
        }
        final base = Uri.parse(endpoint);
        page.navigate(
          base.replace(
            queryParameters: {
              ...base.queryParameters,
              OidcParameterNames.idTokenHint: idToken,
              OAuth2ParameterNames.clientId: registration.clientId,
              OidcParameterNames.postLogoutRedirectUri:
                  '${postLogoutRedirectUri ?? _appUri()}',
            },
          ),
        );
      });

  // The registration, usable by a browser.
  Future<ClientRegistration> _registration(String registrationId) async {
    final registration = await clientRegistrationRepository
        .findByRegistrationId(registrationId);
    if (registration == null) {
      throw OAuth2AuthenticationException(
        OAuth2Error(
          OAuth2ErrorCodes.clientRegistrationNotFound,
          'Client Registration not found with Id: $registrationId',
        ),
      );
    }
    if (registration.authorizationGrantType !=
        AuthorizationGrantType.authorizationCode) {
      throw OAuth2AuthenticationException(
        OAuth2Error(
          OAuth2ErrorCodes.unauthorizedClient,
          'The registration $registrationId is not an authorization_code '
          'registration',
        ),
      );
    }
    if (registration.clientAuthenticationMethod !=
        ClientAuthenticationMethod.none) {
      throw OAuth2AuthenticationException(
        OAuth2Error(
          OAuth2ErrorCodes.invalidClient,
          'The registration $registrationId authenticates with a client '
          'secret, which a browser cannot keep: in '
          '${FlutterWebSecurityProperties.prefix}.mode=spa register a public '
          'client (no client-secret; PKCE), or let the server log in '
          '(${FlutterWebSecurityProperties.prefix}.mode=server)',
        ),
      );
    }
    return registration;
  }

  Future<void> _leaveForProvider(
    ClientRegistration registration,
    Map<String, String> additionalParameters, {
    required bool silent,
  }) async {
    final parameters = {...additionalParameters};
    if (await _dPoPKeyFor(registration) case final key?) {
      // RFC 9449 §10: the code is bound to the key that will redeem it.
      parameters['dpop_jkt'] = JwkThumbprint.of(key.publicJwk);
    }
    if (silent) {
      parameters['prompt'] = 'none';
    }
    final request = OAuth2AuthorizationRequest.forRegistration(
      registration,
      redirectUri: expandRedirectUri(registration, baseUrl: _appUri()),
      additionalParameters: parameters,
    );
    page.sessionStorage.setItem(
      authorizationRequestKey,
      jsonEncode(_PendingRequest.of(request, silent, _clock()).encode()),
    );
    _log.debug(
      "Leaving for the provider's login of registration "
      "'${registration.registrationId}'${silent ? ' (prompt=none)' : ''}",
    );
    page.navigate(request.authorizationRequestUri);
  }

  // The DPoP key when the registration uses DPoP, loaded.
  Future<DPoPKey?> _dPoPKeyFor(ClientRegistration registration) async {
    final key = dPoPKey;
    if (key == null || !registration.usesDPoP(key)) {
      return null;
    }
    if (key is LoadableDPoPKey) {
      await key.load();
    }
    return key;
  }

  Future<OAuth2AuthenticationToken?> _silent() async {
    final registrationId = page.localStorage.getItem(loginHintKey);
    if (!properties.silentRestore || registrationId == null) {
      return null;
    }
    final ClientRegistration registration;
    try {
      registration = await _registration(registrationId);
    } on OAuth2AuthenticationException catch (e) {
      _forgetHint();
      _log.debug('No silent login (${e.error.errorCode})');
      return null;
    } on Object catch (e) {
      // The provider's discovery unreachable: the app starts offline.
      _log.warning(
        "No silent login: registration '$registrationId' unavailable "
        '(${e.runtimeType})',
      );
      return null;
    }
    try {
      await _leaveForProvider(registration, const {}, silent: true);
    } on UnsupportedError catch (e) {
      _forgetHint();
      _log.warning('No silent login: ${e.message}');
    }
    return null;
  }

  Future<OAuth2AuthenticationToken> _complete(
    _PendingRequest pending,
    Uri location,
  ) async {
    final registrationId = pending.registrationId;
    final registration = await _registration(registrationId);
    final sent = pending.request();
    final response = _checkRedirect(registration, sent, location);
    await _dPoPKeyFor(registration);
    final OAuth2AccessTokenResponse tokens;
    try {
      tokens = await accessTokenResponseClient.getTokenResponse(
        OAuth2AuthorizationCodeGrantRequest(
          registration,
          OAuth2AuthorizationExchange(sent, response),
        ),
      );
    } on OAuth2AuthorizationException catch (e) {
      throw OAuth2AuthenticationException(
        e.error,
        e.cause is HttpTransportException
            ? 'The token endpoint of registration $registrationId could not '
                  'be reached from the page: in '
                  '${FlutterWebSecurityProperties.prefix}.mode=spa the '
                  "provider must allow the page's origin (CORS; Keycloak: Web "
                  'origins of the client), or let the server log in '
                  '(${FlutterWebSecurityProperties.prefix}.mode=server)'
            : e.message,
        e,
      );
    }
    OidcIdToken? idToken;
    final OAuth2User user;
    if (sent.scopes.contains('openid')) {
      final raw = tokens.additionalParameters[OidcParameterNames.idToken];
      if (raw is! String || raw.isEmpty) {
        throw OAuth2AuthenticationException(
          OAuth2Error(
            OAuth2ErrorCodes.invalidIdToken,
            'Missing (required) ID Token in Token Response for Client '
            'Registration: $registrationId',
          ),
        );
      }
      idToken = await idTokenDecoder.decode(registration, raw);
      final nonce = OidcIdTokenValidator.validateNonce(idToken, sent.nonce!);
      if (nonce.hasErrors) {
        throw OAuth2AuthenticationException(nonce.errors.first);
      }
      user = await oidcUserService.loadUser(
        OidcUserRequest(
          registration,
          tokens.accessToken,
          idToken,
          additionalParameters: tokens.additionalParameters,
        ),
      );
    } else {
      user = await userService.loadUser(
        OAuth2UserRequest(
          registration,
          tokens.accessToken,
          additionalParameters: tokens.additionalParameters,
        ),
      );
    }
    final authentication = OAuth2AuthenticationToken(
      user,
      authoritiesMapper.mapAuthorities(user.authorities),
      registrationId,
    );
    if (_authentication case final previous?
        when previous.authorizedClientRegistrationId != registrationId ||
            previous.name != authentication.name) {
      await authorizedClientService.removeAuthorizedClient(
        previous.authorizedClientRegistrationId,
        previous.name,
      );
    }
    await authorizedClientService.saveAuthorizedClient(
      OAuth2AuthorizedClient(
        registration,
        authentication.name,
        tokens.accessToken,
        refreshToken: tokens.refreshToken,
        idToken: idToken,
      ),
      authentication,
    );
    _authentication = authentication;
    securityContextHolderStrategy.setContext(
      securityContextHolderStrategy.createEmptyContext()
        ..authentication = authentication,
    );
    _changes.add(authentication);
    eventPublisher?.publishEvent(AuthenticationSuccessEvent(authentication));
    _log.debug(
      "Logged in '${authentication.name}' with registration "
      "'$registrationId'${pending.silent ? ' (silently)' : ''}",
    );
    return authentication;
  }

  // The answer must come back to the redirect URI, carry the state sent
  // and, when it names an issuer, the registration's; then it must carry a
  // code or an error. As NativeOAuth2LoginService checks it.
  OAuth2AuthorizationResponse _checkRedirect(
    ClientRegistration registration,
    OAuth2AuthorizationRequest request,
    Uri redirected,
  ) {
    Never fail(String code, String description) =>
        throw OAuth2AuthenticationException(OAuth2Error(code, description));
    if (!_samePage(redirected, Uri.parse(request.redirectUri))) {
      fail(
        OAuth2ErrorCodes.invalidRedirectUri,
        'The provider came back to another URI than the redirect URI',
      );
    }
    final response = OAuth2AuthorizationResponse.fromRedirect(redirected);
    final state = response.state;
    if (state == null ||
        !constantTimeEquals(utf8.encode(state), utf8.encode(request.state))) {
      fail(
        OAuth2ErrorCodes.invalidStateParameter,
        'The state of the redirect does not match the login',
      );
    }
    final issuer = registration.providerDetails.issuerUri;
    final metadata = registration.providerDetails.configurationMetadata;
    if (response.issuer case final iss?) {
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
      throw OAuth2AuthenticationException(
        OAuth2Error(
          response.error!,
          response.errorDescription,
          response.errorUri,
        ),
      );
    }
    if (response.code == null || response.code!.isEmpty) {
      fail(OAuth2ErrorCodes.invalidRequest, 'The redirect has no code');
    }
    return response;
  }

  Future<void> _revoke(
    ClientRegistration registration,
    OAuth2AuthorizedClient client,
  ) async {
    final revocation = revocationClient;
    if (revocation == null ||
        registration.providerDetails.revocationEndpoint == null) {
      return;
    }
    for (final token in <AbstractOAuth2Token?>[
      client.refreshToken,
      client.accessToken,
    ]) {
      if (token == null) {
        continue;
      }
      try {
        await revocation.revoke(registration, token);
      } on OAuth2AuthorizationException catch (e) {
        _log.debug('Token revocation failed (${e.error.errorCode})');
      } on Object catch (e) {
        // Best effort (CORS may forbid it): the local logout happened.
        _log.debug('Token revocation failed (${e.runtimeType})');
      }
    }
  }

  // The request this tab sent, taken out of sessionStorage (it is used
  // once); null when there is none or it is unreadable.
  _PendingRequest? _takeRequest() {
    final stored = page.sessionStorage.getItem(authorizationRequestKey);
    if (stored == null) {
      return null;
    }
    page.sessionStorage.removeItem(authorizationRequestKey);
    try {
      return _PendingRequest.decode(stored);
    } on Object {
      // Never log the value: it holds the PKCE verifier.
      _log.warning('An unreadable authorization request was removed');
      return null;
    }
  }

  void _forgetHint() => page.localStorage.removeItem(loginHintKey);

  // The app's address: the page's origin and base href, without query or
  // fragment (`{baseUrl}` of the redirect URI templates, the default
  // post-logout address).
  Uri _appUri() {
    final base = page.baseUri;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path.isEmpty ? '/' : base.path,
    );
  }

  static bool _isAnswer(Uri location) {
    final query = location.queryParameters;
    return query.containsKey(OAuth2ParameterNames.state) &&
        (query.containsKey(OAuth2ParameterNames.code) ||
            query.containsKey(OAuth2ParameterNames.error));
  }

  // Scheme, host, port and path equal (an empty path is `/`).
  static bool _samePage(Uri a, Uri b) {
    String path(Uri uri) => uri.path.isEmpty ? '/' : uri.path;
    return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        a.port == b.port &&
        path(a) == path(b);
  }

  // [location] without the provider's answer; the app's own parameters
  // and the fragment (Flutter's route) stay.
  static Uri _withoutAnswer(Uri location) {
    final rest = {
      for (final MapEntry(:key, :value) in location.queryParametersAll.entries)
        if (!_answerParameters.contains(key)) key: value,
    };
    return Uri(
      scheme: location.scheme,
      host: location.host,
      port: location.hasPort ? location.port : null,
      path: location.path,
      queryParameters: rest.isEmpty ? null : rest,
      fragment: location.hasFragment ? location.fragment : null,
    );
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) {
      throw StateError('A login, restore or logout is already running');
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}

// The authorization request on its round trip through sessionStorage:
// what the answer is checked against and the code redeemed with.
final class _PendingRequest {
  _PendingRequest({
    required this.registrationId,
    required this.authorizationUri,
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
    required this.state,
    required this.codeVerifier,
    required this.nonce,
    required this.silent,
    required this.createdAt,
  });

  factory _PendingRequest.of(
    OAuth2AuthorizationRequest request,
    bool silent,
    DateTime now,
  ) => _PendingRequest(
    registrationId: request.registrationId!,
    authorizationUri: request.authorizationUri,
    clientId: request.clientId,
    redirectUri: request.redirectUri,
    scopes: request.scopes,
    state: request.state,
    codeVerifier: request.codeVerifier!,
    nonce: request.nonce,
    silent: silent,
    createdAt: now,
  );

  // Strict: every member of its type, or a FormatException.
  factory _PendingRequest.decode(String stored) {
    final json = jsonDecode(stored);
    if (json is! Map<String, Object?> || json['version'] != 1) {
      throw const FormatException('unknown authorization request');
    }
    String text(String name) => switch (json[name]) {
      final String value when value.isNotEmpty => value,
      _ => throw FormatException('no $name'),
    };
    final scopes = json['scopes'];
    final createdAt = json['createdAt'];
    final nonce = json['nonce'];
    final silent = json['silent'];
    if (scopes is! List<Object?> ||
        createdAt is! int ||
        silent is! bool ||
        (nonce != null && nonce is! String) ||
        // OpenID Connect: the ID token is checked against the nonce.
        (nonce == null && scopes.contains('openid'))) {
      throw const FormatException('malformed authorization request');
    }
    return _PendingRequest(
      registrationId: text('registrationId'),
      authorizationUri: text('authorizationUri'),
      clientId: text('clientId'),
      redirectUri: text('redirectUri'),
      scopes: {...scopes.cast<String>()},
      state: text('state'),
      codeVerifier: text('codeVerifier'),
      nonce: nonce as String?,
      silent: silent,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true),
    );
  }

  final String registrationId;
  final String authorizationUri;
  final String clientId;
  final String redirectUri;
  final Set<String> scopes;
  final String state;
  final String codeVerifier;
  final String? nonce;
  final bool silent;
  final DateTime createdAt;

  Map<String, Object?> encode() => {
    'version': 1,
    'registrationId': registrationId,
    'authorizationUri': authorizationUri,
    'clientId': clientId,
    'redirectUri': redirectUri,
    'scopes': scopes.toList(),
    'state': state,
    'codeVerifier': codeVerifier,
    'nonce': ?nonce,
    'silent': silent,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  // The request as it was sent, for the token request.
  OAuth2AuthorizationRequest request() => OAuth2AuthorizationRequest(
    authorizationUri: authorizationUri,
    clientId: clientId,
    redirectUri: redirectUri,
    state: state,
    scopes: scopes,
    attributes: {
      OAuth2ParameterNames.registrationId: registrationId,
      PkceParameterNames.codeVerifier: codeVerifier,
      OidcParameterNames.nonce: ?nonce,
    },
  );
}
