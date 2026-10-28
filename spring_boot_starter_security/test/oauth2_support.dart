// A fake OpenID Connect provider on a MockHttpTransport: discovery, the
// authorization endpoint (approve), the token endpoint (client secret, PKCE,
// redirect URI, one use per code), user info and the JWK Set. Its ID tokens
// are signed with the test keys of test/app/jwt/keys.dart; tests change its
// fields to make it misbehave (another issuer, a wrong nonce, another key).
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'chain_support.dart';

const clientId = 'neon-web';
const clientSecret = 'web-secret';

/// A key the provider does not publish: tokens it signs must fail.
final otherKeys = TokenFactory(
  RsaTestKey.generate(kid: testKeys.rsa.kid),
  testKeys.ec,
  testKeys.secret,
);

int seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

final class _Grant {
  _Grant(this.challenge, this.redirectUri, this.nonce, this.scope);
  final String challenge;
  final String redirectUri;
  final String? nonce;
  final String scope;
}

/// A provider at [base] (`https://sso.test`) whose issuer is
/// `$base/realms/neon`, answering on [transport].
final class FakeOidcProvider {
  FakeOidcProvider({
    MockHttpTransport? transport,
    this.base = 'https://sso.test',
    this.publishedKeys,
  }) : transport = transport ?? MockHttpTransport() {
    this.transport
      ..when(
        HttpMethod.get,
        '$issuer/.well-known/openid-configuration',
      ).respondWith((_) => _json(200, metadata()))
      ..when(HttpMethod.post, '$base/token').respondWith(_token)
      ..when(HttpMethod.get, '$base/userinfo').respondWith(_userInfo)
      ..when(HttpMethod.get, '$base/certs').respondWith((_) {
        jwkFetches++;
        return _json(200, {
          'keys': publishedKeys ?? [testKeys.rsa.jwk],
        });
      });
  }

  final MockHttpTransport transport;
  final String base;

  /// The JWKs published; the test RSA key by default.
  List<Map<String, Object?>>? publishedKeys;

  String get issuer => '$base/realms/neon';

  // What the provider answers; tests change them.
  String? issuedIssuer;
  Object? audience;
  String? authorizedParty;
  String subject = 'user-1';
  String? userInfoSubject;
  bool sendIdToken = true;
  String? forcedNonce;
  bool omitNonce = false;
  Duration idTokenAge = Duration.zero;
  Duration idTokenLifetime = const Duration(minutes: 5);
  String? tokenError;
  bool includeIss = true;
  String? issParameter;
  bool advertiseIss = false;
  bool endSession = true;

  /// Signs the ID tokens: the published key by default.
  TokenFactory signer = testKeys;
  String alg = 'RS256';
  String? kid;
  bool unsigned = false;

  // What the provider saw.
  final List<Map<String, String>> tokenRequests = [];
  int jwkFetches = 0;
  int _sequence = 0;
  final Map<String, _Grant> _codes = {};
  final Set<String> _accessTokens = {};
  String? lastIdToken;

  Map<String, Object?> metadata() => {
    'issuer': issuer,
    'authorization_endpoint': '$base/auth',
    'token_endpoint': '$base/token',
    'userinfo_endpoint': '$base/userinfo',
    'jwks_uri': '$base/certs',
    if (endSession) 'end_session_endpoint': '$base/logout',
    'token_endpoint_auth_methods_supported': ['client_secret_basic'],
    'authorization_response_iss_parameter_supported': advertiseIss,
  };

  /// The provider's page after the user logged in: a code bound to the
  /// PKCE challenge, the redirect URI and the nonce, and the redirect back.
  Uri approve(Uri authorizationUri) {
    final query = authorizationUri.queryParameters;
    expect(authorizationUri.path, Uri.parse('$base/auth').path);
    expect(query['response_type'], 'code');
    expect(query['code_challenge_method'], 'S256');
    expect(query['client_id'], clientId);
    final code = 'code-${++_sequence}';
    _codes[code] = _Grant(
      query['code_challenge']!,
      query['redirect_uri']!,
      query['nonce'],
      query['scope'] ?? '',
    );
    return Uri.parse(query['redirect_uri']!).replace(
      queryParameters: {
        'code': code,
        'state': ?query['state'],
        if (includeIss) 'iss': issParameter ?? issuer,
      },
    );
  }

  /// The ID token for [nonce] (the hash the authorization request sent).
  String idToken({String? nonce}) {
    final issuedAt = DateTime.now().toUtc().subtract(idTokenAge);
    final claims = <String, Object?>{
      'iss': issuedIssuer ?? issuer,
      'sub': subject,
      'aud': audience ?? clientId,
      'azp': ?authorizedParty,
      'iat': seconds(issuedAt),
      'exp': seconds(issuedAt.add(idTokenLifetime)),
      if (!omitNonce) 'nonce': forcedNonce ?? nonce,
      'name': 'Ada Lovelace',
      'preferred_username': 'ada',
    };
    final String token;
    if (unsigned) {
      token = '${b64Json({'alg': 'none'})}.${b64Json(claims)}.';
    } else {
      token = signer.token(alg: alg, claims: claims, kid: kid);
    }
    return lastIdToken = token;
  }

  static HttpResponse _json(int status, Object body) => HttpResponse(
    status,
    headers: HttpHeaders({'Content-Type': 'application/json'}),
    body: utf8.encode(jsonEncode(body)),
  );

  Future<HttpResponse> _token(HttpRequest request) async {
    final form = Uri.splitQueryString(utf8.decode(request.body!));
    tokenRequests.add(form);
    if (tokenError case final error?) {
      return _json(400, {'error': error, 'error_description': 'refused'});
    }
    final basic = request.headers['Authorization'] ?? '';
    final expected =
        'Basic ${base64.encode(utf8.encode('$clientId:$clientSecret'))}';
    if (basic != expected) {
      return _json(401, {'error': 'invalid_client'});
    }
    final grant = _codes.remove(form['code']);
    if (form['grant_type'] != 'authorization_code' ||
        grant == null ||
        form['redirect_uri'] != grant.redirectUri ||
        form['code_verifier'] == null ||
        sha256Base64Url(form['code_verifier']!) != grant.challenge) {
      return _json(400, {'error': 'invalid_grant'});
    }
    final access = 'access-${++_sequence}';
    _accessTokens.add(access);
    return _json(200, {
      'access_token': access,
      'token_type': 'Bearer',
      'expires_in': 300,
      'refresh_token': 'refresh-${++_sequence}',
      'scope': grant.scope,
      if (sendIdToken && grant.scope.split(' ').contains('openid'))
        'id_token': idToken(nonce: grant.nonce),
    });
  }

  Future<HttpResponse> _userInfo(HttpRequest request) async {
    final header = request.headers['Authorization'] ?? '';
    if (!_accessTokens.contains(header.replaceFirst('Bearer ', ''))) {
      return HttpResponse(401);
    }
    return _json(200, {
      'sub': userInfoSubject ?? subject,
      'email': 'ada@example.com',
      'login': 'ada-gh',
    });
  }

  /// The OpenID Connect registration [id] of this provider, as discovery
  /// builds it.
  Future<ClientRegistration> registration({
    String id = 'keycloak',
    Set<String> scopes = const {'openid', 'profile', 'email'},
    String? clientName,
  }) async =>
      (await ClientRegistrations.fromIssuerLocation(
            issuer,
            transport: transport,
          ))
          .registrationId(id)
          .clientId(clientId)
          .clientSecret(clientSecret)
          .clientAuthenticationMethod(
            ClientAuthenticationMethod.clientSecretBasic,
          )
          .scope(scopes)
          .redirectUri('{baseUrl}/login/oauth2/code/{registrationId}')
          .clientName(clientName)
          .build();

  /// A plain OAuth 2.0 registration of this provider (no `openid`): the
  /// user comes from the user-info endpoint, named by `login`.
  ClientRegistration oauth2Registration({String id = 'github'}) =>
      ClientRegistration.withRegistrationId(id)
          .clientId(clientId)
          .clientSecret(clientSecret)
          .authorizationGrantType(AuthorizationGrantType.authorizationCode)
          .redirectUri('{baseUrl}/login/oauth2/code/{registrationId}')
          .scope({'read:user'})
          .authorizationUri('$base/auth')
          .tokenUri('$base/token')
          .userInfoUri('$base/userinfo')
          .userNameAttributeName('login')
          .clientName('GitHub')
          .build();
}

/// An HttpSecurity whose login goes over [provider]'s transport: the
/// token client, the user services and the JWK-checking ID token decoder,
/// all explicit (the chain has no beans).
HttpSecurity oauth2Http(
  FakeOidcProvider provider,
  ClientRegistrationRepository registrations, {
  Customizer<OAuth2LoginConfigurer>? customizer,
  String contextPath = '',
  bool authorize = true,
}) {
  final http = HttpSecurity(null, contextPath: contextPath);
  if (authorize) {
    http.authorizeHttpRequests(
      (auth) => auth
          .requestMatchers('/public/**')
          .permitAll()
          .anyRequest()
          .authenticated(),
    );
  }
  return http.oauth2Login((login) {
    login
        .clientRegistrationRepository(registrations)
        .tokenEndpoint(
          (token) => token.accessTokenResponseClient(
            DefaultAuthorizationCodeTokenResponseClient(provider.transport),
          ),
        )
        .userInfoEndpoint(
          (userInfo) => userInfo
              .userService(DefaultOAuth2UserService(provider.transport))
              .oidcUserService(OidcUserService(provider.transport)),
        )
        .idTokenDecoder(
          OidcIdTokenDecoderFactory(
            fetcher: transportJwkFetcher(provider.transport),
          ),
        );
    customizer?.call(login);
  });
}

/// A browser's steps through an OAuth 2.0 login on a [ChainClient].
extension OAuth2Steps on ChainClient {
  /// `GET /oauth2/authorization/[registrationId]`: the provider's
  /// authorization URI the browser is sent to.
  Future<Uri> startLogin(String registrationId) async {
    final reply = await get(
      '$contextPath/oauth2/authorization/$registrationId',
    );
    expect(reply.status, 302, reason: 'the redirect to the provider');
    return Uri.parse(reply.header('location')!);
  }

  /// Follows [callback], the provider's redirect back.
  Future<Reply> callback(Uri callback) => get(
    callback.hasQuery ? '${callback.path}?${callback.query}' : callback.path,
  );

  /// The whole login: start, the provider approves, the callback.
  Future<Reply> loginWith(
    FakeOidcProvider provider,
    String registrationId,
  ) async => await callback(provider.approve(await startLogin(registrationId)));
}
