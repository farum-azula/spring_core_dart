import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_flutter_security/src/dpop/platform_dpop_key.dart';
import 'package:spring_boot_starter_flutter_security/src/login/apple_id_sign_in.dart';
import 'package:spring_boot_starter_flutter_security/src/login/oauth2_login_service.dart';
import 'package:spring_boot_starter_flutter_security/src/login/oauth2_token_revocation_client.dart';
import 'package:spring_boot_starter_flutter_security/src/login/secret_store_oauth2_authorized_client_service.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/window/authorization_window.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

const _log = SpringLog('spring.security.oauth2.client.login');

/// The [OAuth2LoginService] of phones and desktops: the app logs its user
/// in by itself with an OAuth 2.0 or OpenID Connect provider (Keycloak,
/// Google, Auth0, ...), keeps them logged in across restarts, and logs
/// them out.
///
/// An app cannot keep a client secret (anyone can extract it), so it logs
/// in as a public client with the authorization code flow and PKCE (RFC
/// 8252, "OAuth 2.0 for Native Apps"): [login] opens the provider's page
/// in the system's login window (a Safari sheet, a Chrome tab, the
/// default browser), the user logs in there (the app never sees the
/// password), the provider redirects back with a code, and the code is
/// exchanged for tokens. Everything that can be forged is checked: the
/// `state` against forged redirects, the `iss` of the redirect against
/// mixed-up providers, the PKCE verifier binds the code to this app, the
/// ID token's issuer, audience, times and `nonce`, and the user info's
/// subject. The user then is an [OAuth2AuthenticationToken] in the
/// `SecurityContextHolder` (so `@PreAuthorize` and the Feign interceptor
/// see them), the tokens are in the [OAuth2AuthorizedClientService] (the
/// `SecretStoreOAuth2AuthorizedClientService` on the platform's secure
/// storage), and an `AuthenticationSuccessEvent` is published.
///
/// [restore] brings the user back at startup from the stored tokens,
/// refreshing them when needed; [logout] revokes the tokens at the
/// provider (when it has a `revocation_endpoint`), forgets them, clears
/// the context and publishes a `LogoutSuccessEvent`. With DPoP it also
/// deletes the app's [PlatformDPoPKey], so the next login is bound to a
/// new key.
///
/// A registration with `native-sign-in=apple` ([NativeSignIn]; the
/// default of the `apple` provider) signs in with Sign in with Apple's
/// sheet on iOS and macOS ([appleIdSignIn]) instead of the browser: the
/// sheet's `state` must come back, its identity token (from the
/// operating system, not from a TLS connection of the app) must verify
/// with Apple's keys ([nativeIdTokenDecoder]: the registration's
/// `jwk-set-uri`, issuer, audience = the client id, expiry) and carry the
/// `nonce` sent, and its `sub` must be the sheet's user. The code is then
/// exchanged at the registration's `token-uri`, which for an app must be
/// its own server: only a server can sign Apple's client secret (Apple's
/// own flow for apps: the app hands the code to its server, which checks
/// it with Apple and keeps the session). The name and e-mail Apple sends
/// on the first authorization only go into the user's info and are kept
/// in the login record (and carried to the next sign-ins of the same
/// user).
///
/// Apps use it through [OAuth2LoginService]: the package declares it as
/// the `oauth2LoginService` bean on Android, iOS, macOS, Windows and
/// Linux when a registration is configured, with the platform's
/// [AuthorizationWindow] (`PlatformAuthorizationWindow` on Android, iOS
/// and macOS, `LoopbackAuthorizationWindow` on Windows and Linux). A web
/// page gets the `ServerOAuth2LoginService` instead, where the server
/// logs the user in.
///
/// Spring has no counterpart: Spring Security's `oauth2Login()` logs
/// browsers in on a server. The checks are those of its
/// `OAuth2LoginAuthenticationFilter`,
/// `OidcAuthorizationCodeAuthenticationProvider` and `OidcUserService`.
class NativeOAuth2LoginService implements OAuth2LoginService {
  /// A login service; the package's auto-configuration passes the beans.
  ///
  /// [authorizationWindow] opens the provider's page (`null`: [login]
  /// throws).
  /// [baseUrl] fills `{baseUrl}` of the redirect URI templates
  /// (`http://127.0.0.1` by default, for a loopback redirect).
  /// [dPoPKey] is deleted at [logout] (`null`: no key is deleted).
  NativeOAuth2LoginService({
    required this.clientRegistrationRepository,
    required this.authorizedClientService,
    required this.secretStore,
    required this.accessTokenResponseClient,
    required this.userService,
    required this.oidcUserService,
    this.authorizationWindow,
    this.authorizedClientManager,
    this.revocationClient,
    this.dPoPKey,
    this.appleIdSignIn,
    this.nativeSignIn = const {},
    this.nativeIdTokenDecoder,
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

  /// The key of the login record in the [secretStore]: which registration
  /// and user are logged in, and what is needed to show them offline.
  static const sessionKey = 'oauth2.login';

  /// The registrations.
  final ClientRegistrationRepository clientRegistrationRepository;

  /// Where the tokens are kept.
  final OAuth2AuthorizedClientService authorizedClientService;

  /// Where the login record is kept (the same store as the tokens).
  final SecretStore secretStore;

  /// Exchanges the code.
  final OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest>
  accessTokenResponseClient;

  /// Loads OAuth 2.0 users.
  final OAuth2UserService<OAuth2UserRequest, OAuth2User> userService;

  /// Loads OpenID Connect users.
  final OAuth2UserService<OidcUserRequest, OidcUser> oidcUserService;

  /// Opens the provider's login page and waits for the redirect back, or
  /// `null` (then [login] throws).
  final AuthorizationWindow? authorizationWindow;

  /// Refreshes the tokens in [restore]; without one they are not
  /// refreshed there.
  final OAuth2AuthorizedClientManager? authorizedClientManager;

  /// Revokes the tokens in [logout]; without one they are not revoked.
  final OAuth2TokenRevocationClient? revocationClient;

  /// The app's DPoP key, deleted at [logout] so the next login gets a
  /// new one; `null` when the app has no [PlatformDPoPKey] (a key of its
  /// own is left alone).
  final PlatformDPoPKey? dPoPKey;

  /// Decodes and checks the ID token.
  final OidcIdTokenDecoder idTokenDecoder;

  /// Sign in with Apple's sheet (iOS, macOS), or `null` where there is
  /// none: then every registration logs in in the [authorizationWindow].
  final AppleIdSignIn? appleIdSignIn;

  /// The registrations that sign in with a sheet of the system instead
  /// of the browser, by id ([NativeSignIn.of] the properties).
  final Map<String, NativeSignIn> nativeSignIn;

  /// Checks the identity tokens of the sheets, signatures included (a
  /// `JwkSetOidcIdTokenDecoder` in the package's bean); without one a
  /// native sign-in is refused.
  final OidcIdTokenDecoder? nativeIdTokenDecoder;

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

  @override
  OAuth2AuthenticationToken? get authentication => _authentication;

  /// The logged-in user ([OidcUser] with OpenID Connect), or `null`.
  OAuth2User? get user => _authentication?.principal;

  @override
  bool get isLoggedIn => _authentication != null;

  @override
  Stream<OAuth2AuthenticationToken?> get authenticationChanges =>
      _changes.stream;

  /// Logs the user in with the registration [registrationId], in the
  /// system's login window, and returns their authentication.
  ///
  /// [additionalParameters] go to the provider's page (`prompt=login`,
  /// `login_hint=ada@example.com`, `kc_idp_hint=google`). A user logged
  /// in before is replaced.
  ///
  /// Throws an [OAuth2AuthenticationException] when the login fails or
  /// is refused (its `error` says why), an
  /// [AuthorizationCancelledException] when the user closed the page, an
  /// [UnsupportedError] when it has no [authorizationWindow], and a
  /// [StateError] while another login, restore or logout runs.
  @override
  Future<OAuth2AuthenticationToken> login(
    String registrationId, {
    Map<String, String> additionalParameters = const {},
  }) => _exclusive(() => _login(registrationId, additionalParameters));

  Future<OAuth2AuthenticationToken> _login(
    String registrationId,
    Map<String, String> additionalParameters,
  ) async {
    final sheet = appleIdSignIn;
    if (sheet != null && nativeSignIn[registrationId] == NativeSignIn.apple) {
      return _signInWithApple(registrationId, sheet);
    }
    final window =
        authorizationWindow ??
        (throw UnsupportedError(
          'No AuthorizationWindow: an app logs in in the system login '
          'window. In a browser the ServerOAuth2LoginService logs in on the '
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
    if (registration.responseMode == ResponseMode.formPost) {
      throw OAuth2AuthenticationException(
        OAuth2Error(
          OAuth2ErrorCodes.invalidRequest,
          'The registration $registrationId asks for response_mode=form_post, '
          "which only a server can receive: an app's login window needs "
          'response-mode=query',
        ),
      );
    }
    final redirectTemplate = expandRedirectUri(registration, baseUrl: baseUrl);
    OAuth2AuthorizationRequest? request;
    final redirected = await window.authorize(
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
          'The AuthorizationWindow never asked for the authorization URI',
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
    return _complete(registration, tokens, user, idToken);
  }

  // Sign in with Apple's sheet: the state, the identity token checked
  // with Apple's keys and the nonce, then the code exchanged at the
  // registration's token endpoint (the app's server).
  Future<OAuth2AuthenticationToken> _signInWithApple(
    String registrationId,
    AppleIdSignIn sheet,
  ) async {
    Never fail(String code, String description) =>
        throw OAuth2AuthenticationException(OAuth2Error(code, description));
    final registration = await clientRegistrationRepository
        .findByRegistrationId(registrationId);
    if (registration == null) {
      fail(
        OAuth2ErrorCodes.clientRegistrationNotFound,
        'Client Registration not found with Id: $registrationId',
      );
    }
    final decoder =
        nativeIdTokenDecoder ??
        (throw StateError(
          'Sign in with Apple needs a nativeIdTokenDecoder that verifies '
          "the identity token's signature",
        ));
    final state = generateSecureKey();
    final nonce = generateSecureKey();
    final request = OAuth2AuthorizationRequest(
      authorizationUri: registration.providerDetails.authorizationUri ?? '',
      clientId: registration.clientId,
      // The sheet has no redirect: the token request sends none.
      redirectUri: '',
      state: state,
      scopes: registration.scopes,
      additionalParameters: {
        OidcParameterNames.nonce: sha256Base64Url(nonce),
      },
      attributes: {
        OAuth2ParameterNames.registrationId: registrationId,
        OidcParameterNames.nonce: nonce,
      },
    );
    final credential = await sheet.signIn(
      scopes: registration.scopes,
      nonce: sha256Base64Url(nonce),
      state: state,
    );
    final returned = credential.state;
    if (returned == null ||
        !constantTimeEquals(utf8.encode(returned), utf8.encode(state))) {
      fail(
        OAuth2ErrorCodes.invalidStateParameter,
        'The state of the sign-in does not match the request',
      );
    }
    final identity = await decoder.decode(
      registration,
      credential.identityToken,
    );
    final nonceResult = OidcIdTokenValidator.validateNonce(identity, nonce);
    if (nonceResult.hasErrors) {
      throw OAuth2AuthenticationException(nonceResult.errors.first);
    }
    if (identity.subject != credential.user) {
      fail(
        OAuth2ErrorCodes.invalidIdToken,
        'The identity token names another user than the sign-in',
      );
    }
    final OAuth2AccessTokenResponse tokens;
    try {
      tokens = await accessTokenResponseClient.getTokenResponse(
        OAuth2AuthorizationCodeGrantRequest(
          registration,
          OAuth2AuthorizationExchange(
            request,
            OAuth2AuthorizationResponse(
              redirectUri: request.redirectUri,
              code: credential.authorizationCode,
              state: state,
            ),
          ),
        ),
      );
    } on OAuth2AuthorizationException catch (e) {
      if (e.error.errorCode == OAuth2ErrorCodes.invalidClient) {
        _log.warning(
          "The token endpoint of registration '$registrationId' refused "
          'the client: the code of a native sign-in is exchanged by the '
          "app's server (its token-uri), which signs the client secret",
        );
      }
      throw OAuth2AuthenticationException(e.error, e.message, e);
    }
    // An ID token the server sent along must be about the same user.
    final raw = tokens.additionalParameters[OidcParameterNames.idToken];
    if (raw is String && raw.isNotEmpty) {
      final fromServer = await idTokenDecoder.decode(registration, raw);
      if (fromServer.subject != identity.subject) {
        fail(
          OAuth2ErrorCodes.invalidIdToken,
          'The token endpoint answered for another user than the sign-in',
        );
      }
    }
    final loaded = await oidcUserService.loadUser(
      OidcUserRequest(
        registration,
        tokens.accessToken,
        identity,
        additionalParameters: tokens.additionalParameters,
      ),
    );
    final user = await _withFirstSignInInfo(
      registrationId,
      loaded,
      identity,
      credential,
    );
    return _complete(registration, tokens, user, identity);
  }

  // Apple sends the name (and the e-mail) on the first authorization of
  // the app only: they go into the user info, and a later sign-in of the
  // same user keeps the ones stored. The identity token's claims win over
  // them (DefaultOidcUser), so they can never change who the user is.
  Future<OidcUser> _withFirstSignInInfo(
    String registrationId,
    OidcUser user,
    OidcIdToken identity,
    AppleIdCredential credential,
  ) async {
    final given = credential.givenName;
    final family = credential.familyName;
    var info = <String, Object?>{
      StandardClaimNames.givenName: ?given,
      StandardClaimNames.familyName: ?family,
      if (given != null || family != null)
        StandardClaimNames.name: [?given, ?family].join(' '),
      if (credential.email case final email?
          when identity.claims[StandardClaimNames.email] == null)
        StandardClaimNames.email: email,
    };
    if (info.isEmpty) {
      final previous = await _readSession();
      if (previous != null &&
          previous.registrationId == registrationId &&
          previous.userInfo?[IdTokenClaimNames.sub] == identity.subject) {
        info = {...?previous.userInfo};
      }
    }
    if (info.isEmpty) {
      return user;
    }
    final userInfo = OidcUserInfo({
      ...info,
      IdTokenClaimNames.sub: identity.subject,
    });
    // The attribute that named the user, when the new user still has it.
    final named = _Session._nameKeyOf(user);
    final nameKey =
        named != null && {...userInfo.claims, ...identity.claims}[named] != null
        ? named
        : IdTokenClaimNames.sub;
    return DefaultOidcUser(
      [
        for (final authority in user.authorities)
          if (authority is OidcUserAuthority)
            OidcUserAuthority(
              identity,
              userInfo: userInfo,
              authority: authority.authority,
              userNameAttributeName: nameKey,
            )
          else
            authority,
      ],
      identity,
      userInfo: userInfo,
      nameAttributeKey: nameKey,
    );
  }

  // The end of every login: the user in the context, the tokens and the
  // login record stored, the event published.
  Future<OAuth2AuthenticationToken> _complete(
    ClientRegistration registration,
    OAuth2AccessTokenResponse tokens,
    OAuth2User user,
    OidcIdToken? idToken,
  ) async {
    final registrationId = registration.registrationId;
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
    final session = _Session.of(authentication);
    if (!session.restorable) {
      // An application's user service whose user's name is in none of
      // its attributes: the login works, restore() cannot rebuild them.
      _log.warning(
        "The user of registration '$registrationId' is named by none of "
        'their attributes; restore() will not bring them back (their '
        'tokens are removed then)',
      );
    }
    try {
      await _writeSession(session);
    } on JsonUnsupportedObjectError {
      // A user service of the application put values JSON cannot hold
      // into the user: the login works, restore() will not bring it back.
      // The record without them still names the login, so restore() and
      // logout() find its tokens and remove them.
      _log.warning(
        "The user of registration '$registrationId' cannot be stored; "
        'restore() will not bring them back',
      );
      await _writeSession(session.withoutUser());
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
        'The login window came back to another URI than the redirect URI',
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

  /// Brings back the user of the stored tokens and returns their
  /// authentication; `null` when nobody is stored.
  ///
  /// Call it once at startup. The user comes back from the login record
  /// written at the end of the last [login]: the ID token and user info
  /// (OpenID Connect) or the attributes (OAuth 2.0), as a
  /// `DefaultOidcUser` or `DefaultOAuth2User`, with the authorities the
  /// user service gave them then (the roles an application's own
  /// `OAuth2UserService` added included; any authority comes back as one
  /// of that name), mapped again by the [authoritiesMapper]. The user
  /// service is not called again, as a Spring session keeps the
  /// authentication of its login: that would need the provider's user
  /// info endpoint at every start (no offline start) and run the
  /// application's service, which may call its own server. What follows
  /// the tokens: the `SCOPE_` authorities are those of the current access
  /// token, and a refreshed ID token replaces the stored one. An app that
  /// needs roles decided anew logs the user in again.
  ///
  /// An access token that expires soon is refreshed; when the provider
  /// refuses the refresh token (`invalid_grant`: revoked, expired, the
  /// user removed), the tokens are forgotten and the result is `null`.
  /// When the provider cannot be reached, the user is restored all the
  /// same (an app starts offline), and the tokens are refreshed at their
  /// next use. A login record of a registration that no longer exists
  /// is removed with its tokens, and so is one that cannot be read
  /// (damaged, of another version) or cannot rebuild its user (an
  /// application's user named by none of their attributes; logged as a
  /// warning at the login and here). Publishes an
  /// `AuthenticationSuccessEvent`, as Spring's remember-me login does.
  ///
  /// Throws a [StateError] while a login or logout runs.
  @override
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
        // The registration was removed from the configuration: its
        // tokens can never be used again.
        await authorizedClientService.removeAuthorizedClient(
          session.registrationId,
          session.principalName,
        );
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
          // invalid_dpop_proof: the refresh token is bound to a key the
          // app no longer has.
          if (e.error.errorCode == OAuth2ErrorCodes.invalidGrant ||
              e.error.errorCode == OAuth2ErrorCodes.invalidToken ||
              e.error.errorCode == OAuth2ErrorCodes.invalidIdToken ||
              e.error.errorCode == OAuth2ErrorCodes.invalidDPoPProof) {
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
    } on Object catch (e) {
      // The record names a login but cannot rebuild its user (a user
      // named by no attribute, a damaged ID token): its tokens can never
      // be used again.
      _log.warning(
        "The stored login of registration '${session.registrationId}' "
        'cannot be restored (${e.runtimeType}); removing it and its tokens',
      );
      await authorizedClientService.removeAuthorizedClient(
        session.registrationId,
        session.principalName,
      );
      await _forget(session);
      return null;
    }
    _authenticated(authentication);
    return authentication;
  }

  /// Logs the user out: revokes their tokens at the provider (refresh
  /// token first, when it has a `revocation_endpoint`), forgets the
  /// tokens, deletes the [dPoPKey] (the next login makes a new one),
  /// clears the security context and publishes a `LogoutSuccessEvent`.
  /// Nothing happens when nobody is logged in.
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
  /// logout happens whatever they answer. When the [secretStore] cannot
  /// forget the tokens or the login record, the user is logged out of
  /// the running app all the same (the context cleared, the event
  /// published) and the store's error is rethrown: the stored login may
  /// come back at the next [restore], so tell the user.
  ///
  /// Throws a [StateError] while a login or restore runs.
  @override
  Future<void> logout({bool endSession = false, Uri? postLogoutRedirectUri}) =>
      _exclusive(() => _logout(endSession, postLogoutRedirectUri));

  Future<void> _logout(bool endSession, Uri? postLogoutRedirectUri) async {
    final authentication = _authentication;
    _Session? session;
    ClientRegistration? registration;
    OAuth2AuthorizedClient? client;
    try {
      session = await _readSession();
      if (session != null) {
        try {
          registration = await clientRegistrationRepository
              .findByRegistrationId(session.registrationId);
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
        // Each step runs even when one before failed; the first error is
        // rethrown once the user is logged out of the app.
        Object? failure;
        StackTrace? failureTrace;
        Future<void> attempt(Future<void> Function() step) async {
          try {
            await step();
          } on Object catch (e, trace) {
            failure ??= e;
            failureTrace ??= trace;
          }
        }

        final stored = session;
        await attempt(
          () => authorizedClientService.removeAuthorizedClient(
            stored.registrationId,
            stored.principalName,
          ),
        );
        await attempt(() => secretStore.delete(sessionKey));
        await _rotateDPoPKey();
        if (failure case final error?) {
          _log.warning(
            'The stored login could not be removed at logout '
            '(${error.runtimeType}); it may come back at the next restore',
          );
          Error.throwWithStackTrace(error, failureTrace!);
        }
      }
    } finally {
      // Logged out of the running app whatever the store did: failing
      // open (still logged in after a logout) is worse.
      _authentication = null;
      securityContextHolderStrategy.clearContext();
      _changes.add(null);
      if (authentication != null) {
        eventPublisher?.publishEvent(LogoutSuccessEvent(authentication));
      }
    }
    final idToken = client?.idToken?.tokenValue ?? session?.idToken;
    if (endSession && registration != null && idToken != null) {
      await _endSession(registration, idToken, postLogoutRedirectUri);
    }
  }

  // A new key for the next login: nothing bound to this one is usable
  // any more. Best effort, as the revocation: the logout happens anyway.
  Future<void> _rotateDPoPKey() async {
    try {
      await dPoPKey?.delete();
    } on Object catch (e) {
      _log.debug('The DPoP key could not be deleted (${e.runtimeType})');
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
    final window = authorizationWindow;
    if (endpoint == null || window == null) {
      return;
    }
    final target =
        postLogoutRedirectUri ??
        Uri.parse(expandRedirectUri(registration, baseUrl: baseUrl));
    try {
      // No `state`: nothing is decided on the way back (the local logout
      // is done), and a window waits for a request's `state` only when
      // the page carries one, so a provider that does not send it back
      // after a logout never keeps the window waiting.
      await window.authorize(
        redirectUri: target,
        authorizationUri: (redirectUri) {
          final base = Uri.parse(endpoint);
          return base.replace(
            queryParameters: {
              ...base.queryParameters,
              OidcParameterNames.idTokenHint: idToken,
              OAuth2ParameterNames.clientId: registration.clientId,
              OidcParameterNames.postLogoutRedirectUri: '$redirectUri',
            },
          );
        },
      );
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
    await secretStore.delete(sessionKey);
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
    final stored = await secretStore.read(sessionKey);
    if (stored == null) {
      return null;
    }
    try {
      return _Session.decode(stored);
    } on Object {
      // Never log the value: it holds an ID token.
      _log.warning('Removing an unreadable login record and its tokens');
      await _removeTokensOf(stored);
      await secretStore.delete(sessionKey);
      return null;
    }
  }

  // The tokens of an unreadable login record: those of the registration
  // and user it still names (a record of another version), else every
  // stored client of the store, which no login record can lead to any
  // more. Best effort: the record goes anyway.
  Future<void> _removeTokensOf(String record) async {
    Object? json;
    try {
      json = jsonDecode(record);
    } on FormatException {
      json = null;
    }
    try {
      if (json case {
        'registrationId': final String registrationId,
        'principalName': final String principalName,
      }) {
        await authorizedClientService.removeAuthorizedClient(
          registrationId,
          principalName,
        );
        return;
      }
      for (final key in await secretStore.keys()) {
        if (key.startsWith(
          SecretStoreOAuth2AuthorizedClientService.keyPrefix,
        )) {
          await secretStore.delete(key);
        }
      }
    } on Object catch (e) {
      _log.warning(
        'The tokens of the unreadable login record could not be removed '
        '(${e.runtimeType})',
      );
    }
  }

  Future<void> _writeSession(_Session session) =>
      secretStore.write(sessionKey, jsonEncode(session.encode()));
}

// What restore() needs to show the user without the network: the
// registration, the name, the ID token and user info (OpenID Connect) or
// the attributes (OAuth 2.0), the scopes of the access token, and the
// user's authorities as the user service gave them.
final class _Session {
  _Session({
    required this.registrationId,
    required this.principalName,
    required this.nameAttributeKey,
    required this.scopes,
    this.idToken,
    this.userInfo,
    this.attributes,
    this.authorities,
    this.restorable = true,
  });

  factory _Session.of(OAuth2AuthenticationToken authentication) {
    final user = authentication.principal;
    final nameKey = _nameKeyOf(user);
    final scopes = {
      for (final authority in user.authorities)
        if (authority.authority case final name? when name.startsWith('SCOPE_'))
          name.substring('SCOPE_'.length),
    };
    return _Session(
      registrationId: authentication.authorizedClientRegistrationId,
      principalName: authentication.name,
      nameAttributeKey: nameKey ?? IdTokenClaimNames.sub,
      restorable: nameKey != null,
      scopes: scopes,
      idToken: user is OidcUser ? user.idToken.tokenValue : null,
      userInfo: user is OidcUser ? user.userInfo?.claims : null,
      attributes: user is OidcUser ? null : user.attributes,
      // Before the mapper, as the login maps them: restore maps again.
      // An authority without a name cannot be checked, nor stored.
      authorities: [
        for (final authority in user.authorities)
          if (authority.authority case final name? when name.isNotEmpty)
            (name: name, user: authority is OAuth2UserAuthority),
      ],
    );
  }

  // The attribute that names [user] as restore() rebuilds them (the ID
  // token's claims over the user info, or the attributes): the
  // `DefaultOAuth2User`'s own, else for a user of an application's own
  // class `sub` or the first attribute holding the name; `null` when
  // none does.
  static String? _nameKeyOf(OAuth2User user) {
    if (user is DefaultOAuth2User) {
      return user.nameAttributeKey;
    }
    final attributes = user is OidcUser
        ? {...?user.userInfo?.claims, ...user.idToken.claims}
        : user.attributes;
    bool names(String key) =>
        attributes[key] != null && '${attributes[key]}' == user.name;
    if (names(IdTokenClaimNames.sub)) {
      return IdTokenClaimNames.sub;
    }
    for (final key in attributes.keys) {
      if (names(key)) {
        return key;
      }
    }
    return null;
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
      // Absent in the records of 0.4.x: the authorities are rebuilt as
      // the default user services give them.
      authorities: switch (json['authorities']) {
        null => null,
        final List<Object?> list => [
          for (final entry in list.cast<Map<String, Object?>>())
            (
              name: entry['authority']! as String,
              user: entry['user'] == true,
            ),
        ],
        _ => throw const FormatException('bad authorities'),
      },
    );
  }

  final String registrationId;
  final String principalName;
  final String nameAttributeKey;
  final Set<String> scopes;
  final String? idToken;
  final Map<String, Object?>? userInfo;
  final Map<String, Object?>? attributes;

  // The user's authorities in order: `user` marks the OAuth2UserAuthority
  // / OidcUserAuthority (rebuilt with the attributes or the ID token).
  final List<({String name, bool user})>? authorities;

  // Whether [authentication] can rebuild the user (known at the login
  // only; a stored record finds out at restore).
  final bool restorable;

  // This record without what describes the user beyond the ID token (for
  // a user JSON cannot hold): it still names the login and its tokens.
  _Session withoutUser() => _Session(
    registrationId: registrationId,
    principalName: principalName,
    nameAttributeKey: nameAttributeKey,
    scopes: scopes,
    idToken: idToken,
    authorities: authorities,
    restorable: false,
  );

  Map<String, Object?> encode() => {
    'version': 1,
    'registrationId': registrationId,
    'principalName': principalName,
    'nameAttributeKey': nameAttributeKey,
    'scopes': scopes.toList(),
    'idToken': ?idToken,
    'userInfo': ?userInfo,
    'attributes': ?attributes,
    if (authorities case final list?)
      'authorities': [
        for (final authority in list)
          {'authority': authority.name, if (authority.user) 'user': true},
      ],
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
      authorities: authorities,
    );
  }

  // The user as the login built it: the stored authorities (the `SCOPE_`
  // ones those of the current access token), then mapped again.
  OAuth2AuthenticationToken authentication(GrantedAuthoritiesMapper mapper) {
    final scopeAuthorities = [
      for (final scope in scopes) SimpleGrantedAuthority('SCOPE_$scope'),
    ];
    List<GrantedAuthority> rebuild(GrantedAuthority Function(String) userOf) {
      final stored = authorities;
      if (stored == null) {
        // A record of 0.4.x: as the default user services build them.
        return [userOf(''), ...scopeAuthorities];
      }
      // The `SCOPE_` ones go where the first was; none when the user
      // service gave none.
      final rebuilt = <GrantedAuthority>[];
      var scopesPlaced = false;
      for (final authority in stored) {
        if (authority.user) {
          rebuilt.add(userOf(authority.name));
        } else if (!authority.name.startsWith('SCOPE_')) {
          rebuilt.add(SimpleGrantedAuthority(authority.name));
        } else if (!scopesPlaced) {
          scopesPlaced = true;
          rebuilt.addAll(scopeAuthorities);
        }
      }
      return rebuilt;
    }

    final OAuth2User user;
    if (idToken case final raw?) {
      final token = OidcIdToken.parse(raw);
      final info = userInfo == null ? null : OidcUserInfo(userInfo!);
      user = DefaultOidcUser(
        rebuild(
          (name) => name.isEmpty
              ? OidcUserAuthority(
                  token,
                  userInfo: info,
                  userNameAttributeName: nameAttributeKey,
                )
              : OidcUserAuthority(
                  token,
                  userInfo: info,
                  authority: name,
                  userNameAttributeName: nameAttributeKey,
                ),
        ),
        token,
        userInfo: info,
        nameAttributeKey: nameAttributeKey,
      );
    } else {
      final values = attributes ?? (throw const FormatException('no user'));
      user = DefaultOAuth2User(
        rebuild(
          (name) => name.isEmpty
              ? OAuth2UserAuthority(
                  values,
                  userNameAttributeName: nameAttributeKey,
                )
              : OAuth2UserAuthority(
                  values,
                  authority: name,
                  userNameAttributeName: nameAttributeKey,
                ),
        ),
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
