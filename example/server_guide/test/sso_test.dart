// Chapter 4, single sign-on (the `sso` profile): the browser's Keycloak
// login (oauth2Login), the realm roles as ROLE_*, the native apps' bearer
// tokens, the logout that ends the Keycloak session too. Keycloak is
// played by a MockHttpTransport (its metadata, token and user-info
// endpoints); the signatures of its tokens are the starter's business
// (spring_boot_starter_security's own tests check them), so the decoders
// are replaced by ones that trust what they read.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:neon_books_server/src/security/sso_config.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/app.dart';

const issuer = 'http://localhost:8180/realms/neon';
const endpoints = '$issuer/protocol/openid-connect';

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

String _b64(Map<String, Object?> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// A JWT whose signature nobody checks here.
String token(Map<String, Object?> claims) =>
    '${_b64({'alg': 'RS256', 'kid': 'test'})}.${_b64(claims)}.c2lnbmF0dXJl';

/// Keycloak's realm `neon`, as much of it as the login needs.
final class FakeKeycloak {
  FakeKeycloak() {
    http
      ..when(
        HttpMethod.get,
        '$issuer/.well-known/openid-configuration',
      ).respond(
        200,
        json: {
          'issuer': issuer,
          'authorization_endpoint': '$endpoints/auth',
          'token_endpoint': '$endpoints/token',
          'userinfo_endpoint': '$endpoints/userinfo',
          'jwks_uri': '$endpoints/certs',
          'end_session_endpoint': '$endpoints/logout',
        },
      )
      ..when(HttpMethod.post, '$endpoints/token').respondWith(_token)
      ..when(HttpMethod.get, '$endpoints/userinfo').respondWith(
        (_) => _json({'sub': 'id-of-$user', ..._claims}),
      );
  }

  final http = MockHttpTransport();

  /// Who logs in next, with which realm roles.
  String user = 'root';
  List<String> roles = ['USER', 'ADMIN'];

  /// The nonce of the authorization request (the ID token must name it).
  String? nonce;

  Map<String, Object?> get _claims => {
    'preferred_username': user,
    'roles': roles,
  };

  HttpResponse _token(HttpRequest request) {
    final now = DateTime.now();
    return _json({
      'access_token': 'access-of-$user',
      'token_type': 'Bearer',
      'expires_in': 300,
      'scope': 'openid profile email',
      'id_token': token({
        'iss': issuer,
        'sub': 'id-of-$user',
        'aud': 'neon-server',
        'iat': _seconds(now),
        'exp': _seconds(now.add(const Duration(minutes: 5))),
        'nonce': nonce,
        ..._claims,
      }),
    });
  }

  static HttpResponse _json(Map<String, Object?> body) => HttpResponse(
    200,
    headers: HttpHeaders({'Content-Type': 'application/json'}),
    body: utf8.encode(jsonEncode(body)),
  );
}

/// Reads the ID token without checking its signature (the real one checks
/// it with the realm's keys).
final class TrustingIdTokenDecoder implements OidcIdTokenDecoder {
  @override
  Future<OidcIdToken> decode(ClientRegistration registration, String value) =>
      Future.value(OidcIdToken.parse(value));
}

/// The native apps' access tokens: a few known ones, as Keycloak would
/// have signed them (issuer, audience `neon-api`, realm roles).
final class FakeJwtDecoder implements JwtDecoder {
  static final _users = {
    'root-token': ['USER', 'ADMIN'],
    'ada-token': ['USER'],
  };

  @override
  Future<Jwt> decode(String value) async {
    final roles = _users[value];
    if (roles == null) {
      throw BadJwtException('An unknown token');
    }
    final name = value.replaceFirst('-token', '');
    final now = _seconds(DateTime.now());
    return Jwt(
      value,
      headers: const {'alg': 'RS256'},
      claims: {
        'iss': issuer,
        'aud': ['neon-api'],
        'sub': 'id-of-$name',
        'preferred_username': name,
        'roles': roles,
        'iat': now,
        'exp': now + 300,
      },
    );
  }
}

void main() {
  final keycloak = FakeKeycloak();
  final app = neonBooks(
    profiles: ['dev', 'test', 'sso'],
    overrides: [
      BeanOverride<HttpTransport>(keycloak.http),
      BeanOverride<OidcIdTokenDecoder>(
        TrustingIdTokenDecoder(),
        name: 'oidcIdTokenDecoder',
      ),
      BeanOverride<JwtDecoder>(FakeJwtDecoder()),
    ],
  );

  /// The browser's way in: the app's button opens
  /// /oauth2/authorization/keycloak, Keycloak's page sends it back to the
  /// callback, the callback sends it on to the web app.
  Future<ApiClient> logInAtKeycloak(String user, List<String> roles) async {
    keycloak
      ..user = user
      ..roles = roles;
    final browser = ApiClient(app.mockMvc);
    final start = await browser.get('/oauth2/authorization/keycloak');
    expect(start.response.statusCode, 302);
    final authorization = Uri.parse(start.response.headers['Location']!);
    final query = authorization.queryParameters;
    keycloak.nonce = query['nonce'];
    final callback = await browser.get(
      Uri(
        path: '/login/oauth2/code/keycloak',
        queryParameters: {'code': 'code-1', 'state': query['state']},
      ).toString(),
    );
    expect(callback.response.statusCode, 302);
    expect(callback.response.headers['Location'], 'http://localhost:5050/');
    return browser;
  }

  MockRequestBuilder bearer(String token, HttpMethod method, String path) =>
      MockRequestBuilder(method, path)
        ..headers['Authorization'] = 'Bearer $token';

  group('the browser (Flutter web): oauth2Login', () {
    test('the login starts at Keycloak, with PKCE, state and nonce', () async {
      final start = await app.mockMvc
          .get('/oauth2/authorization/keycloak')
          .andExpect(status: 302);
      final location = Uri.parse(start.response.headers['Location']!);
      expect('${location.replace(query: '')}', '$endpoints/auth?');
      expect(location.queryParameters, {
        'response_type': 'code',
        'client_id': 'neon-server',
        'scope': 'openid profile email',
        'state': isNotEmpty,
        'redirect_uri': 'http://localhost/login/oauth2/code/keycloak',
        'nonce': isNotEmpty,
        'code_challenge': isNotEmpty,
        'code_challenge_method': 'S256',
      });
    });

    test('root comes back to the web app with ADMIN from Keycloak', () async {
      final root = await logInAtKeycloak('root', ['USER', 'ADMIN']);
      // What the web app's starter restores (its user endpoint).
      expect(jsonOf(await root.get('/api/me')), {
        'name': 'root', // preferred_username, not Keycloak's id
        'roles': ['ADMIN', 'USER'],
        'authorities': [
          'OIDC_USER',
          'ROLE_ADMIN',
          'ROLE_USER',
          'SCOPE_email',
          'SCOPE_openid',
          'SCOPE_profile',
        ],
        'registrationId': 'keycloak',
      });
      expect((await root.get('/api/admin/logs')).response.statusCode, 200);
    });

    test('ada is a USER: no admin API, CSRF still checked', () async {
      final ada = await logInAtKeycloak('ada', ['USER']);
      expect((await ada.get('/api/admin/logs')).response.statusCode, 403);
      final quantity = {'quantity': 1};
      const item = '/api/basket/items/9780441013593';
      final forged = await ada.send(
        HttpMethod.put,
        item,
        json: quantity,
        withCsrf: false,
      );
      expect(forged.response.statusCode, 403);
      final real = await ada.send(HttpMethod.put, item, json: quantity);
      expect(real.response.statusCode, 200);
    });

    test('logout: 200 with the URL that ends the Keycloak session', () async {
      final root = await logInAtKeycloak('root', ['USER', 'ADMIN']);
      // The web app starts with /api/me, which brings the CSRF cookie of
      // the new session (the token changes at login).
      await root.get('/api/me');
      final logout = await root.send(HttpMethod.post, '/api/logout');
      expect(logout.response.statusCode, 200);
      final url = Uri.parse((jsonOf(logout)! as Map)['logoutUrl'] as String);
      expect(url.path, Uri.parse('$endpoints/logout').path);
      expect(url.queryParameters, {
        'id_token_hint': isNotEmpty,
        'post_logout_redirect_uri': 'http://localhost:5050/',
      });
      expect((await root.get('/api/me')).response.statusCode, 401);
    });

    test('the API still answers 401, never a redirect to Keycloak', () async {
      await app.mockMvc.get('/api/me').andExpect(status: 401);
      await app.mockMvc.get('/api/books').andExpect(status: 200);
    });
  });

  group('native apps: bearer tokens', () {
    test('roles from the token: root reads the logs, ada may not', () async {
      await app.mockMvc
          .perform(bearer('root-token', HttpMethod.get, '/api/me'))
          .andExpect(
            status: 200,
            json: {
              'name': 'root',
              'roles': ['ADMIN', 'USER'],
              'authorities': ['ROLE_ADMIN', 'ROLE_USER'],
            },
          );
      await app.mockMvc
          .perform(bearer('root-token', HttpMethod.get, '/api/admin/logs'))
          .andExpect(status: 200);
      await app.mockMvc
          .perform(bearer('ada-token', HttpMethod.get, '/api/admin/logs'))
          .andExpect(status: 403);
    });

    test('a token Keycloak did not issue: 401', () async {
      await app.mockMvc
          .perform(bearer('forged', HttpMethod.get, '/api/me'))
          .andExpect(status: 401);
    });
  });

  test('the realm roles become ROLE_*, the rest stays', () {
    final user = OidcUserAuthority(
      OidcIdToken(
        'id-token',
        claims: {
          'sub': '1',
          'roles': ['USER', 'ADMIN'],
        },
      ),
    );
    final mapped = const KeycloakRolesMapper().mapAuthorities([
      user,
      SimpleGrantedAuthority('SCOPE_profile'),
    ]);
    expect(mapped.map((a) => a.authority), [
      'OIDC_USER',
      'SCOPE_profile',
      'ROLE_USER',
      'ROLE_ADMIN',
    ]);
  });
}
