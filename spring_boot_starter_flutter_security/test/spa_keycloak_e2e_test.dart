// The spa login against a real Keycloak (example/keycloak, realm `neon`,
// client `neon-web`), over real sockets: the service is the real one, the
// "browser" a script with a cookie jar that follows the provider's pages
// (the login form, the redirects) the way a browser would. The tab's
// address and storages are the fake page. DPoP with the WebCrypto key's
// code path (a software key in the vault): Keycloak issues DPoP tokens.
// Also checks that Keycloak allows the page's origin (CORS) on the
// endpoints the browser calls.
//
// Tagged `e2e`: it needs Keycloak, and is skipped without it.
//
//   (cd ../example/keycloak && docker compose up) &
//   flutter test --tags e2e
//
// E2E_KEYCLOAK names another Keycloak (default http://localhost:8180).
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

import 'support/spa_fakes.dart';

const _origin = 'http://localhost:5050';

/// A browser for the provider's pages: cookies per host, no automatic
/// redirects (the script decides where to go).
final class _ScriptedBrowser {
  final HttpClient _client = HttpClient();
  final Map<String, Map<String, String>> _cookies = {};

  Future<({int status, String? location, String body})> request(
    String method,
    Uri url, {
    Map<String, String>? form,
  }) async {
    final request = await _client.openUrl(method, url);
    request.followRedirects = false;
    final jar = _cookies[url.host] ?? const {};
    if (jar.isNotEmpty) {
      request.headers.set(
        HttpHeaders.cookieHeader,
        [for (final MapEntry(:key, :value) in jar.entries) '$key=$value'].join(
          '; ',
        ),
      );
    }
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(Uri(queryParameters: form).query);
    }
    final response = await request.close();
    for (final cookie in response.cookies) {
      final host = _cookies.putIfAbsent(url.host, () => {});
      if (cookie.value.isEmpty ||
          (cookie.maxAge != null && cookie.maxAge! <= 0)) {
        host.remove(cookie.name);
      } else {
        host[cookie.name] = cookie.value;
      }
    }
    final body = await response.transform(utf8.decoder).join();
    final location = response.headers.value(HttpHeaders.locationHeader);
    return (
      status: response.statusCode,
      location: location == null ? null : url.resolve(location).toString(),
      body: body,
    );
  }

  /// Opens the provider's login page at [authorizationUrl] and submits
  /// the user's name and password: the redirect back to the app.
  Future<Uri> logIn(Uri authorizationUrl, String user, String password) async {
    final page = await request('GET', authorizationUrl);
    expect(page.status, 200, reason: 'the login page');
    final action = RegExp(
      r'action="([^"]+)"',
    ).firstMatch(page.body)?.group(1)?.replaceAll('&amp;', '&');
    expect(action, isNotNull, reason: 'the login form');
    final submitted = await request(
      'POST',
      Uri.parse(action!),
      form: {'username': user, 'password': password, 'credentialId': ''},
    );
    expect(submitted.status, 302, reason: 'the redirect after the login');
    return Uri.parse(submitted.location!);
  }

  /// Follows [url] once (a provider page that answers at once with a
  /// redirect): where it sends the browser.
  Future<Uri> follow(Uri url) async {
    final answer = await request('GET', url);
    expect(answer.status, 302, reason: 'an immediate redirect from $url');
    return Uri.parse(answer.location!);
  }

  void forgetCookies() => _cookies.clear();

  void close() => _client.close(force: true);
}

void main() {
  // flutter_test answers every HttpClient with 400: this test talks to a
  // real Keycloak.
  setUpAll(() => HttpOverrides.global = null);

  final keycloak =
      Platform.environment['E2E_KEYCLOAK'] ?? 'http://localhost:8180';
  final issuer = '$keycloak/realms/neon';

  test('login, replay, silent login, logout, login_required', () async {
    final transport = platformHttpTransport();
    addTearDown(transport.close);
    final ClientRegistration registration;
    try {
      registration =
          (await ClientRegistrations.fromIssuerLocation(
                issuer,
                transport: transport,
              ))
              .registrationId('keycloak')
              .clientId('neon-web')
              .clientSecret(null)
              .clientAuthenticationMethod(ClientAuthenticationMethod.none)
              .scope({'openid', 'profile', 'email'})
              .redirectUri('{baseUrl}/')
              .userNameAttributeName('preferred_username')
              .dpop(DPoPMode.auto)
              .build();
    } on Object catch (e) {
      markTestSkipped('No Keycloak at $issuer ($e)');
      return;
    }
    final repository = InMemoryClientRegistrationRepository([registration]);
    final vault = FakeVault();
    final key = WebCryptoDPoPKey(vault: vault);
    final page = FakeSpaPage('$_origin/');
    final browser = _ScriptedBrowser();
    addTearDown(browser.close);
    final strategy = GlobalSecurityContextHolderStrategy();
    late TabOAuth2AuthorizedClientService clients;

    // One page load of the app.
    SpaOAuth2LoginService app() {
      clients = TabOAuth2AuthorizedClientService(repository);
      return SpaOAuth2LoginService(
        clientRegistrationRepository: repository,
        authorizedClientService: clients,
        accessTokenResponseClient: DefaultAuthorizationCodeTokenResponseClient(
          transport,
          dPoPKey: key,
        ),
        userService: DefaultOAuth2UserService(transport, dPoPKey: key),
        oidcUserService: OidcUserService(transport, dPoPKey: key),
        page: page,
        revocationClient: OAuth2TokenRevocationClient(transport),
        dPoPKey: key,
        securityContextHolderStrategy: strategy,
      );
    }

    // The login: the page leaves for Keycloak, the user logs in there.
    await app().login('keycloak');
    final authorization = page.visited.last;
    if (!(await browser.request('GET', authorization)).body.contains(
      'kc-form-login',
    )) {
      markTestSkipped(
        'The realm has no neon-web client: import example/keycloak/'
        'neon-realm.json again',
      );
      return;
    }
    browser.forgetCookies();
    page.location = await browser.logIn(authorization, 'ada', 'ada-secret');
    expect(page.location.queryParameters['iss'], issuer);

    final loggedIn = await app().restore();
    expect(loggedIn?.name, 'ada');
    expect(
      (loggedIn!.principal as OidcUser).claims['roles'],
      contains('USER'),
    );
    expect(page.location.toString(), '$_origin/');
    final client = (await clients.loadAuthorizedClient('keycloak', 'ada'))!;
    // Keycloak announces ES256 for DPoP: the token is bound to the key.
    expect(client.accessToken.tokenType, TokenType.dpop);
    final claims = jsonDecode(
      utf8.decode(
        base64Url.decode(
          base64Url.normalize(
            client.accessToken.tokenValue.split('.')[1],
          ),
        ),
      ),
    ) as Map<String, Object?>;
    expect((claims['cnf']! as Map)['jkt'], vault.key.thumbprint);
    expect(page.stored, isNot(contains(client.accessToken.tokenValue)));

    // The answer again (a reload, a replay): nobody.
    final answer = Uri.parse(
      '$_origin/?state=x&code=replayed&iss=${Uri.encodeComponent(issuer)}',
    );
    page.location = answer;
    expect(await app().restore(), isNull);

    // A reload: no tokens, the hint; prompt=none at Keycloak, which
    // answers at once from its session cookie.
    page
      ..location = Uri.parse('$_origin/#/books')
      ..visited.clear();
    expect(await app().restore(), isNull);
    expect(page.visited.single.queryParameters['prompt'], 'none');
    page.location = await browser.follow(page.visited.single);
    final silent = app();
    expect((await silent.restore())?.name, 'ada');

    // The logout: Keycloak's logout page with the ID token, back to the
    // app.
    page.visited.clear();
    await silent.logout();
    final logout = page.visited.single;
    expect(logout.queryParameters['post_logout_redirect_uri'], '$_origin/');
    expect(
      (await browser.follow(logout)).toString(),
      startsWith('$_origin/'),
    );

    // Keycloak's session is gone: prompt=none answers login_required,
    // which is nobody, not an error.
    page.localStorage.setItem(SpaOAuth2LoginService.loginHintKey, 'keycloak');
    page
      ..location = Uri.parse('$_origin/')
      ..visited.clear();
    expect(await app().restore(), isNull);
    page.location = await browser.follow(page.visited.single);
    expect(page.location.queryParameters['error'], 'login_required');
    expect(await app().restore(), isNull);
    expect(page.localStorage.items, isEmpty);
    expect(page.location.toString(), '$_origin/');
  });

  test(
    "Keycloak allows the page's origin on the browser's endpoints",
    () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final Map<String, Object?> metadata;
      try {
        final request = await client.getUrl(
          Uri.parse('$issuer/.well-known/openid-configuration'),
        );
        final response = await request.close();
        metadata = jsonDecode(
          await response.transform(utf8.decoder).join(),
        ) as Map<String, Object?>;
      } on Object catch (e) {
        markTestSkipped('No Keycloak at $issuer ($e)');
        return;
      }
      for (final endpoint in [
        'token_endpoint',
        'userinfo_endpoint',
        'revocation_endpoint',
      ]) {
        final request = await client.openUrl(
          'OPTIONS',
          Uri.parse(metadata[endpoint]! as String),
        );
        request.headers
          ..set('Origin', _origin)
          ..set('Access-Control-Request-Method', 'POST')
          ..set('Access-Control-Request-Headers', 'content-type,dpop');
        final response = await request.close();
        await response.drain<void>();
        expect(
          response.headers.value('Access-Control-Allow-Origin'),
          _origin,
          reason: endpoint,
        );
      }
    },
  );
}
