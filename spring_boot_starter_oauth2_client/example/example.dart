// An app that logs its user in with OpenID Connect (authorization code and
// PKCE, the redirect to a loopback server), calls an API with the user's
// token through Feign, and logs out. The generator writes example.spring.dart
// (`dart run build_runner build`).
//
//   dart run example/example.dart
//
// A local server stands in for the identity provider (Keycloak, Auth0, ...)
// and the API, and a scripted "user" stands in for the system browser, so
// the example runs without anything else.

import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

import 'example.spring.dart';

/// The API, called with the logged-in user's token (the starter's Feign
/// interceptor adds it).
@FeignClient('api', url: r'${api.url}')
abstract interface class ApiClient {
  @GetMapping('/me')
  Future<Map<String, Object?>> me();
}

@Service()
class Account {
  Account(this._login, this._api);
  final OAuth2LoginService _login;
  final ApiClient _api;

  /// Logged in from last time? (Tokens in the TokenStore.)
  Future<bool> start() async => await _login.restore() != null;

  /// The system browser opens the provider's page.
  Future<String> signIn() async {
    final authentication = await _login.login('local');
    final user = authentication.principal as OidcUser;
    return '${user.fullName} <${user.email}>';
  }

  Future<Object?> whoAmI() async => (await _api.me())['sub'];

  Future<void> signOut() => _login.logout();
}

/// In a real app the starter's LoopbackAuthorizationBrowser opens the
/// system browser; here a scripted user "logs in" instead.
@Configuration()
class BrowserSetup {
  @Bean()
  AuthorizationBrowser authorizationBrowser() => LoopbackAuthorizationBrowser(
    openBrowser: (page) async {
      // The provider's page logs the user in and redirects the browser
      // to the loopback server (the client follows the redirect).
      final http = io.HttpClient();
      try {
        await (await http.getUrl(page)).close();
      } finally {
        http.close();
      }
    },
  );
}

/// Walks through the login and logs what happened; `@Log` gives it the
/// `log` getter.
@Component()
@Log(topic: 'example')
class LoginTour implements CommandLineRunner {
  LoginTour(this.account);

  final Account account;

  @override
  Future<void> run(List<String> args) async {
    final restored = await account.start();
    final user = await account.signIn();
    final seen = await account.whoAmI();
    await account.signOut();
    log
      ..info('restored: $restored') // restored: false
      ..info('signed in: $user') // Ada Lovelace <ada@...>
      ..info('the API sees: $seen') // user-1
      ..info('signed out; tokens revoked: $_revoked'); // 2
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final provider = await _provider();
  final base = 'http://127.0.0.1:${provider.port}';
  final context = await springApplication.runAsync(
    args,
    properties: {
      'spring.security.oauth2.client.registration.local.client-id': 'demo-app',
      'spring.security.oauth2.client.registration.local.scope':
          'openid,profile,email',
      'spring.security.oauth2.client.registration.local.redirect-uri':
          'http://127.0.0.1/callback',
      'spring.security.oauth2.client.provider.local.issuer-uri': base,
      'spring.cloud.openfeign.oauth2.enabled': 'true',
      'spring.cloud.openfeign.oauth2.client-registration-id': 'local',
      'api.url': base,
    },
  );

  await context.closeAsync();
  await provider.close(force: true);
}

var _revoked = 0;

/// A tiny OpenID Connect provider and API on 127.0.0.1 (no signatures:
/// the app trusts the token endpoint over TLS, here plain HTTP for the
/// demo).
Future<io.HttpServer> _provider() async {
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  final issuer = 'http://127.0.0.1:${server.port}';
  final codes = <String, Map<String, String>>{};
  final tokens = <String>{};
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  server.listen((request) async {
    final response = request.response;
    void json(Object body) => response
      ..headers.contentType = io.ContentType.json
      ..write(jsonEncode(body));
    final form = request.method == 'POST'
        ? Uri.splitQueryString(await utf8.decodeStream(request))
        : request.uri.queryParameters;
    switch (request.uri.path) {
      case '/.well-known/openid-configuration':
        json({
          'issuer': issuer,
          'authorization_endpoint': '$issuer/auth',
          'token_endpoint': '$issuer/token',
          'userinfo_endpoint': '$issuer/userinfo',
          'jwks_uri': '$issuer/certs',
          'revocation_endpoint': '$issuer/revoke',
          'token_endpoint_auth_methods_supported': ['none'],
        });
      case '/auth': // the user logged in: back to the app with a code
        final code = 'code-${codes.length}';
        codes[code] = form;
        response
          ..statusCode = io.HttpStatus.found
          ..headers.set(
            io.HttpHeaders.locationHeader,
            Uri.parse(form['redirect_uri']!).replace(
              queryParameters: {'code': code, 'state': ?form['state']},
            ),
          );
      case '/token':
        final asked = codes.remove(form['code']);
        if (asked == null ||
            sha256Base64Url(form['code_verifier'] ?? '') !=
                asked['code_challenge']) {
          response.statusCode = io.HttpStatus.badRequest;
          json({'error': 'invalid_grant'});
          break;
        }
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final access = 'access-$now-${tokens.length}';
        tokens.add(access);
        json({
          'access_token': access,
          'token_type': 'Bearer',
          'expires_in': 300,
          'refresh_token': 'refresh-$access',
          'scope': asked['scope'],
          'id_token':
              '${part({'alg': 'RS256'})}.${part({
                'iss': issuer,
                'sub': 'user-1',
                'aud': 'demo-app',
                'iat': now,
                'exp': now + 300,
                'nonce': asked['nonce'],
                'name': 'Ada Lovelace',
              })}.signature',
        });
      case '/userinfo' || '/me':
        final token = request.headers
            .value(io.HttpHeaders.authorizationHeader)
            ?.replaceFirst('Bearer ', '');
        if (!tokens.contains(token)) {
          response.statusCode = io.HttpStatus.unauthorized;
          break;
        }
        json({'sub': 'user-1', 'email': 'ada@example.com'});
      case '/revoke':
        _revoked++;
      default:
        response.statusCode = io.HttpStatus.notFound;
    }
    await response.close();
  });
  return server;
}
