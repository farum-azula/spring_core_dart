// A fake OpenID Connect provider on the MockHttpTransport: discovery,
// authorization (through FakeAuthorizationWindow), the token endpoint with
// PKCE and client authentication checks, user info and revocation. Tests
// change its fields to make it misbehave (another issuer, a wrong nonce, ...).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

const issuer = 'https://sso.test/realms/neon';
const clientId = 'neon-app';

/// A JWT whose signature nobody checks here (the app trusts TLS).
String jwt(Map<String, Object?> claims, {String alg = 'RS256'}) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': alg, 'kid': 'k1'})}.${part(claims)}.c2ln';
}

int seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

final class _Grant {
  _Grant(this.challenge, this.redirectUri, this.nonce, this.scope);
  final String challenge;
  final String redirectUri;
  final String? nonce;
  final String scope;
}

final class FakeProvider {
  FakeProvider({DateTime? now}) : now = now ?? DateTime.now().toUtc() {
    transport
      ..when(
        HttpMethod.get,
        '$issuer/.well-known/openid-configuration',
      ).respondWith((_) => _json(200, metadata()))
      ..when(HttpMethod.post, 'https://sso.test/token').respondWith(_token)
      ..when(HttpMethod.get, 'https://sso.test/userinfo').respondWith(_userInfo)
      ..when(HttpMethod.post, 'https://sso.test/revoke').respondWith(_revoke)
      ..when(HttpMethod.get, 'https://api.test/me').respondWith(_api);
  }

  final MockHttpTransport transport = MockHttpTransport();
  DateTime now;

  // What the provider answers; tests change them.
  String issuedIssuer = issuer;
  Object? audience = clientId;
  String? authorizedParty;
  String subject = 'user-1';
  String? userInfoSubject;
  bool sendIdToken = true;
  bool corruptNonce = false;
  Duration idTokenAge = Duration.zero;
  Duration idTokenLifetime = const Duration(minutes: 5);
  int expiresIn = 300;
  bool issueRefreshToken = true;
  bool rotateRefreshToken = true;
  String? tokenError;
  bool tokenUnreachable = false;
  bool includeIssParameter = true;
  bool advertiseIssParameter = false;
  bool revocation = true;
  bool endSession = true;
  Duration tokenDelay = Duration.zero;

  // What the provider saw.
  final List<Map<String, String>> tokenRequests = [];
  final List<Map<String, String>> revoked = [];
  final List<String> rejectedAccessTokens = [];
  int _sequence = 0;
  final Map<String, _Grant> _codes = {};
  final Set<String> _refreshTokens = {};
  final Set<String> _accessTokens = {};
  String? lastIdToken;

  Map<String, Object?> metadata() => {
    'issuer': issuer,
    'authorization_endpoint': 'https://sso.test/auth',
    'token_endpoint': 'https://sso.test/token',
    'userinfo_endpoint': 'https://sso.test/userinfo',
    'jwks_uri': 'https://sso.test/certs',
    if (revocation) 'revocation_endpoint': 'https://sso.test/revoke',
    if (endSession) 'end_session_endpoint': 'https://sso.test/logout',
    'token_endpoint_auth_methods_supported': ['client_secret_basic', 'none'],
    'authorization_response_iss_parameter_supported': advertiseIssParameter,
  };

  /// What the provider's login page does once the user logged in: a code
  /// bound to the PKCE challenge, the redirect URI and the nonce.
  Uri approve(Uri authorizationUri) {
    final query = authorizationUri.queryParameters;
    final code = 'code-${++_sequence}';
    _codes[code] = _Grant(
      query['code_challenge']!,
      query['redirect_uri']!,
      query['nonce'],
      query['scope'] ?? '',
    );
    expect(query['code_challenge_method'], 'S256');
    expect(query['response_type'], 'code');
    expect(query['client_id'], clientId);
    return Uri.parse(query['redirect_uri']!).replace(
      queryParameters: {
        'code': code,
        'state': ?query['state'],
        if (includeIssParameter) 'iss': issuer,
      },
    );
  }

  String idToken({String? nonce}) {
    final issuedAt = now.subtract(idTokenAge);
    final token = jwt({
      'iss': issuedIssuer,
      'sub': subject,
      'aud': audience,
      'azp': ?authorizedParty,
      'iat': seconds(issuedAt),
      'exp': seconds(issuedAt.add(idTokenLifetime)),
      'nonce': ?(corruptNonce ? 'replayed' : nonce),
      'name': 'Ada Lovelace',
      'preferred_username': 'ada',
    });
    lastIdToken = token;
    return token;
  }

  static HttpResponse _json(int status, Object body) => HttpResponse(
    status,
    headers: HttpHeaders({'Content-Type': 'application/json'}),
    body: utf8.encode(jsonEncode(body)),
  );

  Future<HttpResponse> _token(HttpRequest request) async {
    if (tokenDelay > Duration.zero) {
      await Future<void>.delayed(tokenDelay);
    }
    if (tokenUnreachable) {
      throw HttpTransportException('connection refused', request: request);
    }
    final form = Uri.splitQueryString(utf8.decode(request.body!));
    tokenRequests.add(form);
    if (tokenError case final error?) {
      return _json(400, {'error': error, 'error_description': 'refused'});
    }
    String? nonce;
    var scope = 'openid profile email';
    switch (form['grant_type']) {
      case 'authorization_code':
        final grant = _codes.remove(form['code']);
        if (grant == null ||
            form['redirect_uri'] != grant.redirectUri ||
            form['code_verifier'] == null ||
            sha256Base64Url(form['code_verifier']!) != grant.challenge ||
            form['client_id'] != clientId) {
          return _json(400, {'error': 'invalid_grant'});
        }
        nonce = grant.nonce;
        scope = grant.scope;
      case 'refresh_token':
        final presented = form['refresh_token'];
        if (!_refreshTokens.contains(presented)) {
          return _json(400, {'error': 'invalid_grant'});
        }
        if (rotateRefreshToken) {
          _refreshTokens.remove(presented);
        }
      case 'client_credentials':
        scope = form['scope'] ?? '';
      default:
        return _json(400, {'error': 'unsupported_grant_type'});
    }
    final access = 'access-${++_sequence}';
    _accessTokens.add(access);
    final refresh =
        issueRefreshToken && form['grant_type'] != 'client_credentials'
        ? (rotateRefreshToken || form['grant_type'] == 'authorization_code'
              ? 'refresh-${++_sequence}'
              : form['refresh_token']!)
        : null;
    if (refresh != null) {
      _refreshTokens.add(refresh);
    }
    return _json(200, {
      'access_token': access,
      'token_type': 'Bearer',
      'expires_in': expiresIn,
      'refresh_token': ?refresh,
      'scope': scope,
      if (sendIdToken && scope.split(' ').contains('openid'))
        'id_token': idToken(nonce: nonce),
    });
  }

  Future<HttpResponse> _userInfo(HttpRequest request) async {
    final header = request.headers['Authorization'] ?? '';
    if (!_accessTokens.contains(header.replaceFirst('Bearer ', ''))) {
      return HttpResponse(
        401,
        headers: HttpHeaders({
          'WWW-Authenticate': 'Bearer error="invalid_token"',
        }),
      );
    }
    return _json(200, {
      'sub': userInfoSubject ?? subject,
      'email': 'ada@example.com',
      'email_verified': true,
    });
  }

  Future<HttpResponse> _revoke(HttpRequest request) async {
    final form = Uri.splitQueryString(utf8.decode(request.body!));
    revoked.add(form);
    _refreshTokens.remove(form['token']);
    _accessTokens.remove(form['token']);
    return HttpResponse(200);
  }

  Future<HttpResponse> _api(HttpRequest request) async {
    final token = (request.headers['Authorization'] ?? '').replaceFirst(
      'Bearer ',
      '',
    );
    if (!_accessTokens.contains(token) ||
        rejectedAccessTokens.contains(token)) {
      return HttpResponse(401, request: request);
    }
    return _json(200, {'token': token});
  }

  /// Forgets every token, as a provider whose user was removed.
  void revokeEverything() {
    _refreshTokens.clear();
    _accessTokens.clear();
  }
}

/// An AuthorizationWindow that "logs in" at the [provider] (or answers
/// with [respond], to forge redirects), recording what it was asked.
final class FakeAuthorizationWindow implements AuthorizationWindow {
  FakeAuthorizationWindow(this.provider, {this.redirectPort});

  final FakeProvider provider;

  /// A port the window puts into the redirect URI, as a loopback server.
  final int? redirectPort;

  /// Replaces the provider's answer: gets the authorization URI.
  Uri Function(Uri authorizationUri)? respond;

  final List<Uri> opened = [];
  bool cancel = false;

  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) async {
    if (cancel) {
      throw const AuthorizationCancelledException('closed');
    }
    final actual = redirectPort == null
        ? redirectUri
        : redirectUri.replace(port: redirectPort);
    final uri = authorizationUri(actual);
    opened.add(uri);
    if (uri.path == '/logout') {
      return Uri.parse(uri.queryParameters['post_logout_redirect_uri']!)
          .replace(queryParameters: {'state': ?uri.queryParameters['state']});
    }
    return (respond ?? provider.approve)(uri);
  }
}

/// The registration of the fake provider, as discovery builds it.
Future<ClientRegistration> registration(
  FakeProvider provider, {
  Set<String> scopes = const {'openid', 'profile', 'email'},
  String redirectUri = 'http://127.0.0.1/callback',
}) async =>
    (await ClientRegistrations.fromIssuerLocation(
          issuer,
          transport: provider.transport,
        ))
        .registrationId('keycloak')
        .clientId(clientId)
        .clientSecret(null)
        .clientAuthenticationMethod(ClientAuthenticationMethod.none)
        .scope(scopes)
        .redirectUri(redirectUri)
        .build();

/// Everything a NativeOAuth2LoginService needs, on the fake provider.
final class LoginFixture {
  LoginFixture._(this.provider, this.repository, this.window, this.store);

  static Future<LoginFixture> create({
    FakeProvider? provider,
    Set<String> scopes = const {'openid', 'profile', 'email'},
  }) async {
    final fake = provider ?? FakeProvider();
    final reg = await registration(fake, scopes: scopes);
    return LoginFixture._(
      fake,
      InMemoryClientRegistrationRepository([reg]),
      FakeAuthorizationWindow(fake, redirectPort: 49152),
      InMemorySecretStore(),
    );
  }

  final FakeProvider provider;
  final InMemoryClientRegistrationRepository repository;
  final FakeAuthorizationWindow window;
  final InMemorySecretStore store;
  final List<Object> events = [];
  final SecurityContextHolderStrategy strategy =
      GlobalSecurityContextHolderStrategy();

  late final SecretStoreOAuth2AuthorizedClientService clients =
      SecretStoreOAuth2AuthorizedClientService(store, repository);

  late final AuthorizedClientServiceOAuth2AuthorizedClientManager manager =
      AuthorizedClientServiceOAuth2AuthorizedClientManager(
        repository,
        clients,
        authorizedClientProvider:
            OAuth2AuthorizedClientProviderBuilder.builder(
                  transport: provider.transport,
                )
                .authorizationCode()
                .refreshToken(clock: () => provider.now)
                .clientCredentials(clock: () => provider.now)
                .build(),
      );

  NativeOAuth2LoginService service({
    AuthorizationWindow? window,
    bool withWindow = true,
    GrantedAuthoritiesMapper mapper = const NullAuthoritiesMapper(),
    PlatformDPoPKey? dPoPKey,
    OAuth2UserService<OidcUserRequest, OidcUser>? oidcUserService,
    OAuth2UserService<OAuth2UserRequest, OAuth2User>? userService,
    SecretStore? secretStore,
  }) => NativeOAuth2LoginService(
    clientRegistrationRepository: repository,
    authorizedClientService: clients,
    secretStore: secretStore ?? store,
    accessTokenResponseClient: DefaultAuthorizationCodeTokenResponseClient(
      provider.transport,
      clock: () => provider.now,
    ),
    userService: userService ?? DefaultOAuth2UserService(provider.transport),
    oidcUserService: oidcUserService ?? OidcUserService(provider.transport),
    authorizationWindow: withWindow ? (window ?? this.window) : null,
    authorizedClientManager: manager,
    revocationClient: OAuth2TokenRevocationClient(provider.transport),
    dPoPKey: dPoPKey,
    idTokenDecoder: TokenEndpointOidcIdTokenDecoder(clock: () => provider.now),
    authoritiesMapper: mapper,
    eventPublisher: _Events(events),
    securityContextHolderStrategy: strategy,
  );
}

final class _Events implements ApplicationEventPublisher {
  _Events(this.events);
  final List<Object> events;

  @override
  void publishEvent<T extends Object>(T event) => events.add(event);
}
