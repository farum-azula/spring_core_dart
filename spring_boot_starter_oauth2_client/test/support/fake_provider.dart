// A fake OpenID Connect provider on the MockHttpTransport: discovery,
// authorization (approve), the token endpoint with PKCE and client
// authentication checks, and user info. Tests change its fields to make it
// misbehave (another issuer, an unreachable token endpoint, ...).
import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

const issuer = 'https://sso.test/realms/neon';
const clientId = 'neon-app';

/// A JWT whose signature nobody checks here (the client trusts TLS).
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
  Duration tokenDelay = Duration.zero;

  // What the provider saw.
  final List<Map<String, String>> tokenRequests = [];
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
    'revocation_endpoint': 'https://sso.test/revoke',
    'end_session_endpoint': 'https://sso.test/logout',
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

/// An authorized client manager on the fake provider, and [signIn], the
/// authorization code login of a user as a server's `oauth2Login()` does
/// it: the authorization request, the provider's redirect, the code
/// exchange, the ID token check, the user in the security context and the
/// tokens in the authorized client service.
final class ClientFixture {
  ClientFixture._(this.provider, this.clientRegistration)
    : repository = InMemoryClientRegistrationRepository([clientRegistration]);

  static Future<ClientFixture> create({FakeProvider? provider}) async {
    final fake = provider ?? FakeProvider();
    return ClientFixture._(fake, await registration(fake));
  }

  final FakeProvider provider;
  final ClientRegistration clientRegistration;
  final InMemoryClientRegistrationRepository repository;
  final SecurityContextHolderStrategy strategy =
      GlobalSecurityContextHolderStrategy();

  late final InMemoryOAuth2AuthorizedClientService clients =
      InMemoryOAuth2AuthorizedClientService(repository);

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

  /// Logs `user-1` in and returns their authentication.
  Future<OAuth2AuthenticationToken> signIn() async {
    final request = OAuth2AuthorizationRequest.forRegistration(
      clientRegistration,
      redirectUri: expandRedirectUri(clientRegistration),
    );
    final redirect = provider.approve(request.authorizationRequestUri);
    final response = OAuth2AuthorizationResponse.fromRedirect(redirect);
    expect(response.state, request.state);
    final tokens =
        await DefaultAuthorizationCodeTokenResponseClient(
          provider.transport,
          clock: () => provider.now,
        ).getTokenResponse(
          OAuth2AuthorizationCodeGrantRequest(
            clientRegistration,
            OAuth2AuthorizationExchange(request, response),
          ),
        );
    final idToken =
        await TokenEndpointOidcIdTokenDecoder(
          clock: () => provider.now,
        ).decode(
          clientRegistration,
          tokens.additionalParameters['id_token']! as String,
        );
    final user = await OidcUserService(provider.transport).loadUser(
      OidcUserRequest(clientRegistration, tokens.accessToken, idToken),
    );
    final authentication = OAuth2AuthenticationToken(
      user,
      user.authorities,
      clientRegistration.registrationId,
    );
    await clients.saveAuthorizedClient(
      OAuth2AuthorizedClient(
        clientRegistration,
        authentication.name,
        tokens.accessToken,
        refreshToken: tokens.refreshToken,
        idToken: idToken,
      ),
      authentication,
    );
    strategy.setContext(
      strategy.createEmptyContext()..authentication = authentication,
    );
    return authentication;
  }
}
