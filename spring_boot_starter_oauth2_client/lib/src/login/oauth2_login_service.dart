import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/src/authorization_browser.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client_manager.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/parameter_names.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/access_token_response.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/authorization_request.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/token_response_clients.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token_decoder.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token_validator.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration_repository.dart';
import 'package:spring_boot_starter_oauth2_client/src/token_store.dart';
import 'package:spring_boot_starter_oauth2_client/src/user/oauth2_user.dart';
import 'package:spring_boot_starter_oauth2_client/src/user/user_services.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.oauth2.client.login');

/// Logs the user of an app in with an OAuth 2.0 or OpenID Connect
/// provider (Keycloak, Google, Auth0, ...), keeps them logged in across
/// restarts, and logs them out.
///
/// An app cannot keep a client secret (anyone can extract it), so it logs
/// in as a public client with the authorization code flow and PKCE (RFC
/// 8252): [login] opens the provider's page in the system browser, the
/// user logs in there (the app never sees the password), the provider
/// redirects back with a code, and the code is exchanged for tokens.
/// Everything that can be forged is checked: the `state` against forged
/// redirects, the `iss` of the redirect against mixed-up providers, the
/// PKCE verifier binds the code to this app, the ID token's issuer,
/// audience, times and `nonce`, and the user info's subject. The user then
/// is an [OAuth2AuthenticationToken] in the `SecurityContextHolder` (so
/// `@PreAuthorize` and the Feign interceptor see them), the tokens are in
/// the [OAuth2AuthorizedClientService] (the `TokenStore`: the platform's
/// secure storage with the Flutter starter), and an
/// `AuthenticationSuccessEvent` is published.
///
/// [restore] brings the user back at startup from the stored tokens,
/// refreshing them when needed; [logout] revokes the tokens at the
/// provider (when it has a `revocation_endpoint`), forgets them, clears
/// the context and publishes a `LogoutSuccessEvent`.
///
/// ```dart
/// @Service()
/// class Account {
///   Account(this._login);
///   final OAuth2LoginService _login;
///
///   Future<void> start() => _login.restore(); // logged in from last time?
///   Future<void> signIn() => _login.login('keycloak'); // the system browser
///   Future<void> signOut() => _login.logout();
///   String? get who => _login.user?.name;
/// }
/// ```
///
/// The starter declares it when a registration is configured. In a web
/// page there is no [AuthorizationBrowser] and [login] throws: there the
/// server logs the user in (`oauth2Login()` of the security starter) and
/// the page only holds a session cookie.
///
/// Spring has no counterpart: Spring Security's `oauth2Login()` logs
/// browsers in on a server. The checks are those of its
/// `OAuth2LoginAuthenticationFilter`,
/// `OidcAuthorizationCodeAuthenticationProvider` and `OidcUserService`.
class OAuth2LoginService {
  /// A login service; the starter passes the beans.
  ///
  /// [browser] opens the provider's page (`null`: [login] throws).
  /// [baseUrl] fills `{baseUrl}` of the redirect URI templates
  /// (`http://127.0.0.1` by default, for a loopback redirect).
  OAuth2LoginService({
    required this.clientRegistrationRepository,
    required this.authorizedClientService,
    required this.tokenStore,
    required this.accessTokenResponseClient,
    required this.userService,
    required this.oidcUserService,
    this.browser,
    this.authorizedClientManager,
    this.revocationClient,
    OidcIdTokenDecoder? idTokenDecoder,
    this.authoritiesMapper = const NullAuthoritiesMapper(),
    this.eventPublisher,
    SecurityContextHolderStrategy? securityContextHolderStrategy,
    Uri? baseUrl,
  }) : idTokenDecoder = idTokenDecoder ?? TokenEndpointOidcIdTokenDecoder(),
       securityContextHolderStrategy =
           securityContextHolderStrategy ??
           SecurityContextHolder.getContextHolderStrategy(),
       baseUrl = baseUrl ?? Uri.parse('http://127.0.0.1');

  /// The key of the login record in the [tokenStore]: which registration
  /// and user are logged in, and what is needed to show them offline.
  static const sessionKey = 'oauth2.login';

  /// The registrations.
  final ClientRegistrationRepository clientRegistrationRepository;

  /// Where the tokens are kept.
  final OAuth2AuthorizedClientService authorizedClientService;

  /// Where the login record is kept (the same store as the tokens).
  final TokenStore tokenStore;

  /// Exchanges the code.
  final OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest>
  accessTokenResponseClient;

  /// Loads OAuth 2.0 users.
  final OAuth2UserService<OAuth2UserRequest, OAuth2User> userService;

  /// Loads OpenID Connect users.
  final OAuth2UserService<OidcUserRequest, OidcUser> oidcUserService;

  /// Opens the provider's page, or `null` where there is none (the web).
  final AuthorizationBrowser? browser;

  /// Refreshes the tokens in [restore]; without one they are not
  /// refreshed there.
  final OAuth2AuthorizedClientManager? authorizedClientManager;

  /// Revokes the tokens in [logout]; without one they are not revoked.
  final OAuth2TokenRevocationClient? revocationClient;

  /// Decodes and checks the ID token.
  final OidcIdTokenDecoder idTokenDecoder;

  /// Maps the user's authorities.
  final GrantedAuthoritiesMapper authoritiesMapper;

  /// Receives the login and logout events, or `null`.
  final ApplicationEventPublisher? eventPublisher;

  /// Where the logged-in user is put.
  final SecurityContextHolderStrategy securityContextHolderStrategy;

  /// The value of `{baseUrl}` in the redirect URI templates.
  final Uri baseUrl;

  OAuth2AuthenticationToken? _authentication;
  bool _busy = false;
  final StreamController<OAuth2AuthenticationToken?> _changes =
      StreamController.broadcast(sync: true);

  /// The logged-in user's authentication, or `null`.
  OAuth2AuthenticationToken? get authentication => _authentication;

  /// The logged-in user ([OidcUser] with OpenID Connect), or `null`.
  OAuth2User? get user => _authentication?.principal;

  /// Whether someone is logged in.
  bool get isLoggedIn => _authentication != null;

  /// The authentication after each login, restore and logout (`null`):
  /// for a UI that shows who is logged in.
  Stream<OAuth2AuthenticationToken?> get authenticationChanges =>
      _changes.stream;

  /// Logs the user in with the registration [registrationId], in the
  /// system browser, and returns their authentication.
  ///
  /// [additionalParameters] go to the provider's page (`prompt=login`,
  /// `login_hint=ada@example.com`, `kc_idp_hint=google`). A user logged
  /// in before is replaced.
  ///
  /// Throws an [OAuth2AuthenticationException] when the login fails or
  /// is refused (its `error` says why), an
  /// [AuthorizationCancelledException] when the user closed the page, an
  /// [UnsupportedError] where there is no browser (a web page), and a
  /// [StateError] while another login, restore or logout runs.
  Future<OAuth2AuthenticationToken> login(
    String registrationId, {
    Map<String, String> additionalParameters = const {},
  }) => _exclusive(() => _login(registrationId, additionalParameters));

  Future<OAuth2AuthenticationToken> _login(
    String registrationId,
    Map<String, String> additionalParameters,
  ) async {
    final browser =
        this.browser ??
        (throw UnsupportedError(
          'No AuthorizationBrowser: an app logs in in the system browser, '
          'which a web page does not have. In a browser, log in on the '
          'server instead (oauth2Login() of spring_boot_starter_security).',
        ));
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
    final redirectTemplate = expandRedirectUri(registration, baseUrl: baseUrl);
    OAuth2AuthorizationRequest? request;
    final redirected = await browser.authorize(
      redirectUri: Uri.parse(redirectTemplate),
      authorizationUri: (redirectUri) {
        final built = OAuth2AuthorizationRequest.forRegistration(
          registration,
          redirectUri: redirectUri.toString(),
          additionalParameters: additionalParameters,
        );
        request = built;
        return built.authorizationRequestUri;
      },
    );
    final sent =
        request ??
        (throw StateError(
          'The AuthorizationBrowser never asked for the authorization URI',
        ));
    final response = _checkRedirect(registration, sent, redirected);
    final OAuth2AccessTokenResponse tokens;
    try {
      tokens = await accessTokenResponseClient.getTokenResponse(
        OAuth2AuthorizationCodeGrantRequest(
          registration,
          OAuth2AuthorizationExchange(sent, response),
        ),
      );
    } on OAuth2AuthorizationException catch (e) {
      throw OAuth2AuthenticationException(e.error, e.message, e);
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
    final previous = await _readSession();
    if (previous != null &&
        (previous.registrationId != registrationId ||
            previous.principalName != authentication.name)) {
      await authorizedClientService.removeAuthorizedClient(
        previous.registrationId,
        previous.principalName,
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
    try {
      await _writeSession(_Session.of(authentication));
    } on JsonUnsupportedObjectError {
      // A user service of the application put values JSON cannot hold
      // into the user: the login works, restore() will not bring it back.
      _log.warning(
        "The user of registration '$registrationId' cannot be stored; "
        'restore() will not bring them back',
      );
    }
    _authenticated(authentication);
    _log.debug(
      "Logged in '${authentication.name}' with registration "
      "'$registrationId'",
    );
    return authentication;
  }

  // The redirect must come back to the redirect URI, carry the state sent
  // and, when it names an issuer, the registration's; then it must carry a
  // code or an error.
  OAuth2AuthorizationResponse _checkRedirect(
    ClientRegistration registration,
    OAuth2AuthorizationRequest request,
    Uri redirected,
  ) {
    Never fail(String code, String description) =>
        throw OAuth2AuthenticationException(OAuth2Error(code, description));
    final expected = Uri.parse(request.redirectUri);
    if (redirected.scheme.toLowerCase() != expected.scheme.toLowerCase() ||
        redirected.host.toLowerCase() != expected.host.toLowerCase() ||
        redirected.port != expected.port ||
        redirected.path != expected.path) {
      fail(
        OAuth2ErrorCodes.invalidRedirectUri,
        'The browser came back to another URI than the redirect URI',
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

  /// Brings back the user of the stored tokens, as at the end of their
  /// last [login], and returns their authentication; `null` when nobody
  /// is stored.
  ///
  /// Call it once at startup. An access token that expires soon is
  /// refreshed; when the provider refuses the refresh token
  /// (`invalid_grant`: revoked, expired, the user removed), the tokens
  /// are forgotten and the result is `null`. When the provider cannot be
  /// reached, the user is restored all the same (an app starts offline),
  /// and the tokens are refreshed at their next use. Publishes an
  /// `AuthenticationSuccessEvent`, as Spring's remember-me login does.
  ///
  /// Throws a [StateError] while a login or logout runs.
  Future<OAuth2AuthenticationToken?> restore() => _exclusive(_restore);

  Future<OAuth2AuthenticationToken?> _restore() async {
    final session = await _readSession();
    if (session == null) {
      return null;
    }
    var restored = session;
    ClientRegistration? registration;
    var reachable = true;
    try {
      registration = await clientRegistrationRepository.findByRegistrationId(
        session.registrationId,
      );
    } on Object catch (e) {
      reachable = false;
      _log.debug(
        "Registration '${session.registrationId}' unavailable at restore "
        '(${e.runtimeType}); restoring offline',
      );
    }
    if (reachable) {
      if (registration == null) {
        await _forget(session);
        return null;
      }
      final stored = await authorizedClientService.loadAuthorizedClient(
        session.registrationId,
        session.principalName,
      );
      if (stored == null) {
        await _forget(session);
        return null;
      }
      var client = stored;
      final manager = authorizedClientManager;
      if (manager != null) {
        try {
          client =
              await manager.authorize(
                OAuth2AuthorizeRequest.withAuthorizedClient(
                  stored,
                ).principalName(session.principalName).build(),
              ) ??
              client;
        } on OAuth2AuthorizationException catch (e) {
          if (e.error.errorCode == OAuth2ErrorCodes.invalidGrant ||
              e.error.errorCode == OAuth2ErrorCodes.invalidToken ||
              e.error.errorCode == OAuth2ErrorCodes.invalidIdToken) {
            _log.debug(
              "The stored login of registration '${session.registrationId}' "
              'was refused (${e.error.errorCode})',
            );
            await authorizedClientService.removeAuthorizedClient(
              session.registrationId,
              session.principalName,
            );
            await _forget(session);
            return null;
          }
          _log.debug(
            'The tokens could not be refreshed at restore '
            '(${e.error.errorCode}); restoring offline',
          );
        }
      }
      restored = session.withTokens(client.accessToken, client.idToken);
      if (!identical(restored, session)) {
        await _writeSession(restored);
      }
    }
    final OAuth2AuthenticationToken authentication;
    try {
      authentication = restored.authentication(authoritiesMapper);
    } on Object {
      await _forget(session);
      return null;
    }
    _authenticated(authentication);
    return authentication;
  }

  /// Logs the user out: revokes their tokens at the provider (refresh
  /// token first, when it has a `revocation_endpoint`), forgets the
  /// tokens, clears the security context and publishes a
  /// `LogoutSuccessEvent`. Nothing happens when nobody is logged in.
  ///
  /// With [endSession], the provider's own session ends too (OpenID
  /// Connect RP-initiated logout, when its metadata has an
  /// `end_session_endpoint`): its logout page opens in the browser with
  /// the ID token as `id_token_hint`, and comes back to
  /// [postLogoutRedirectUri] (the registration's redirect URI by default;
  /// the provider must allow it). Without it, the next [login] may pass
  /// without a password, as the browser is still logged in at the
  /// provider.
  ///
  /// Revocation and the provider's logout page are best effort: the local
  /// logout happens whatever they answer.
  ///
  /// Throws a [StateError] while a login or restore runs.
  Future<void> logout({bool endSession = false, Uri? postLogoutRedirectUri}) =>
      _exclusive(() => _logout(endSession, postLogoutRedirectUri));

  Future<void> _logout(bool endSession, Uri? postLogoutRedirectUri) async {
    final session = await _readSession();
    final authentication = _authentication;
    ClientRegistration? registration;
    OAuth2AuthorizedClient? client;
    if (session != null) {
      try {
        registration = await clientRegistrationRepository.findByRegistrationId(
          session.registrationId,
        );
        if (registration != null) {
          client = await authorizedClientService.loadAuthorizedClient(
            session.registrationId,
            session.principalName,
          );
        }
      } on Object catch (e) {
        _log.debug('No revocation at logout (${e.runtimeType})');
      }
      if (registration != null && client != null) {
        await _revoke(registration, client);
      }
      await authorizedClientService.removeAuthorizedClient(
        session.registrationId,
        session.principalName,
      );
      await tokenStore.delete(sessionKey);
    }
    _authentication = null;
    securityContextHolderStrategy.clearContext();
    _changes.add(null);
    if (authentication != null) {
      eventPublisher?.publishEvent(LogoutSuccessEvent(authentication));
    }
    final idToken = client?.idToken?.tokenValue ?? session?.idToken;
    if (endSession && registration != null && idToken != null) {
      await _endSession(registration, idToken, postLogoutRedirectUri);
    }
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
        // Best effort: the local logout happens anyway.
        _log.debug('Token revocation failed (${e.runtimeType})');
      }
    }
  }

  Future<void> _endSession(
    ClientRegistration registration,
    String idToken,
    Uri? postLogoutRedirectUri,
  ) async {
    final endpoint = registration.providerDetails.endSessionEndpoint;
    final browser = this.browser;
    if (endpoint == null || browser == null) {
      return;
    }
    final state = generateSecureKey();
    final target =
        postLogoutRedirectUri ??
        Uri.parse(expandRedirectUri(registration, baseUrl: baseUrl));
    try {
      final back = await browser.authorize(
        redirectUri: target,
        authorizationUri: (redirectUri) {
          final base = Uri.parse(endpoint);
          return base.replace(
            queryParameters: {
              ...base.queryParameters,
              OidcParameterNames.idTokenHint: idToken,
              OAuth2ParameterNames.clientId: registration.clientId,
              OidcParameterNames.postLogoutRedirectUri: '$redirectUri',
              OAuth2ParameterNames.state: state,
            },
          );
        },
      );
      final returned = back.queryParameters[OAuth2ParameterNames.state];
      if (returned != null &&
          !constantTimeEquals(utf8.encode(returned), utf8.encode(state))) {
        _log.warning('The provider logout came back with another state');
      }
    } on Object catch (e) {
      _log.warning('The provider logout did not complete (${e.runtimeType})');
    }
  }

  void _authenticated(OAuth2AuthenticationToken authentication) {
    _authentication = authentication;
    securityContextHolderStrategy.setContext(
      securityContextHolderStrategy.createEmptyContext()
        ..authentication = authentication,
    );
    _changes.add(authentication);
    eventPublisher?.publishEvent(AuthenticationSuccessEvent(authentication));
  }

  Future<void> _forget(_Session session) async {
    await tokenStore.delete(sessionKey);
    if (_authentication != null) {
      _authentication = null;
      securityContextHolderStrategy.clearContext();
      _changes.add(null);
    }
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

  Future<_Session?> _readSession() async {
    final stored = await tokenStore.read(sessionKey);
    if (stored == null) {
      return null;
    }
    try {
      return _Session.decode(stored);
    } on Object {
      // Never log the value: it holds an ID token.
      _log.warning('Removing an unreadable login record');
      await tokenStore.delete(sessionKey);
      return null;
    }
  }

  Future<void> _writeSession(_Session session) =>
      tokenStore.write(sessionKey, jsonEncode(session.encode()));
}

// What restore() needs to show the user without the network: the
// registration, the name, the ID token and user info (OpenID Connect) or
// the attributes (OAuth 2.0), and the scopes of the access token.
final class _Session {
  _Session({
    required this.registrationId,
    required this.principalName,
    required this.nameAttributeKey,
    required this.scopes,
    this.idToken,
    this.userInfo,
    this.attributes,
  });

  factory _Session.of(OAuth2AuthenticationToken authentication) {
    final user = authentication.principal;
    final nameKey = user is DefaultOAuth2User ? user.nameAttributeKey : 'sub';
    final scopes = {
      for (final authority in user.authorities)
        if (authority.authority case final name? when name.startsWith('SCOPE_'))
          name.substring('SCOPE_'.length),
    };
    return _Session(
      registrationId: authentication.authorizedClientRegistrationId,
      principalName: authentication.name,
      nameAttributeKey: nameKey,
      scopes: scopes,
      idToken: user is OidcUser ? user.idToken.tokenValue : null,
      userInfo: user is OidcUser ? user.userInfo?.claims : null,
      attributes: user is OidcUser ? null : user.attributes,
    );
  }

  factory _Session.decode(String stored) {
    final json = jsonDecode(stored) as Map<String, Object?>;
    if (json['version'] != 1) {
      throw const FormatException('unknown login record');
    }
    return _Session(
      registrationId: json['registrationId']! as String,
      principalName: json['principalName']! as String,
      nameAttributeKey: json['nameAttributeKey']! as String,
      scopes: {...(json['scopes']! as List<Object?>).cast<String>()},
      idToken: json['idToken'] as String?,
      userInfo: json['userInfo'] as Map<String, Object?>?,
      attributes: json['attributes'] as Map<String, Object?>?,
    );
  }

  final String registrationId;
  final String principalName;
  final String nameAttributeKey;
  final Set<String> scopes;
  final String? idToken;
  final Map<String, Object?>? userInfo;
  final Map<String, Object?>? attributes;

  Map<String, Object?> encode() => {
    'version': 1,
    'registrationId': registrationId,
    'principalName': principalName,
    'nameAttributeKey': nameAttributeKey,
    'scopes': scopes.toList(),
    'idToken': ?idToken,
    'userInfo': ?userInfo,
    'attributes': ?attributes,
  };

  // This record with the scopes of [accessToken] and the (refreshed) ID
  // token; itself when nothing changed.
  _Session withTokens(OAuth2AccessToken accessToken, OidcIdToken? fresh) {
    final freshValue = fresh?.tokenValue;
    final sameScopes =
        accessToken.scopes.length == scopes.length &&
        accessToken.scopes.containsAll(scopes);
    if (sameScopes && (freshValue == null || freshValue == idToken)) {
      return this;
    }
    return _Session(
      registrationId: registrationId,
      principalName: principalName,
      nameAttributeKey: nameAttributeKey,
      scopes: accessToken.scopes,
      idToken: freshValue ?? idToken,
      userInfo: userInfo,
      attributes: attributes,
    );
  }

  // The user as the login built it (the authorities are rebuilt the same
  // way, then mapped again).
  OAuth2AuthenticationToken authentication(GrantedAuthoritiesMapper mapper) {
    final scopeAuthorities = [
      for (final scope in scopes) SimpleGrantedAuthority('SCOPE_$scope'),
    ];
    final OAuth2User user;
    if (idToken case final raw?) {
      final token = OidcIdToken.parse(raw);
      final info = userInfo == null ? null : OidcUserInfo(userInfo!);
      user = DefaultOidcUser(
        [
          OidcUserAuthority(
            token,
            userInfo: info,
            userNameAttributeName: nameAttributeKey,
          ),
          ...scopeAuthorities,
        ],
        token,
        userInfo: info,
        nameAttributeKey: nameAttributeKey,
      );
    } else {
      final values = attributes ?? (throw const FormatException('no user'));
      user = DefaultOAuth2User(
        [
          OAuth2UserAuthority(values, userNameAttributeName: nameAttributeKey),
          ...scopeAuthorities,
        ],
        values,
        nameAttributeKey,
      );
    }
    if (user.name != principalName) {
      throw const FormatException('the record names another user');
    }
    return OAuth2AuthenticationToken(
      user,
      mapper.mapAuthorities(user.authorities),
      registrationId,
    );
  }
}
