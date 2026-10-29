// oauth2Login() with response_mode=form_post against a real Keycloak
// (example/keycloak, realm `neon`, the confidential client `neon-server`):
// the chain runs in memory as http://localhost:8080 (the client's
// registered redirect URI), Keycloak over real sockets. A scripted browser
// logs in on Keycloak's page, gets Keycloak's auto-submitting form, and
// posts it to the callback with the session cookie, as a browser does. The
// code is exchanged at Keycloak's token endpoint and the ID token checked
// with Keycloak's keys. Also: a GET of the same response is refused and
// the post is accepted only once.
//
// Tagged `e2e`: it needs Keycloak, and is skipped without it.
//
//   (cd ../example/keycloak && docker compose up) &
//   dart test --tags e2e
//
// E2E_KEYCLOAK names another Keycloak (default http://localhost:8180).
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

import 'chain_support.dart';

const _app = 'http://localhost:8080';

/// Keycloak's pages for a script: cookies per host, no automatic
/// redirects.
final class _ScriptedBrowser {
  final io.HttpClient _client = io.HttpClient();
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
        io.HttpHeaders.cookieHeader,
        [for (final MapEntry(:key, :value) in jar.entries) '$key=$value'].join(
          '; ',
        ),
      );
    }
    if (form != null) {
      request.headers.contentType = io.ContentType(
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
    final location = response.headers.value(io.HttpHeaders.locationHeader);
    return (
      status: response.statusCode,
      location: location == null ? null : url.resolve(location).toString(),
      body: body,
    );
  }

  void close() => _client.close(force: true);
}

String _unescape(String html) => html
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#x2F;', '/')
    .replaceAll('&#x3D;', '=')
    .replaceAll('&#43;', '+')
    .replaceAll('&#61;', '=')
    .replaceAll('&#47;', '/');

void main() {
  final keycloak =
      io.Platform.environment['E2E_KEYCLOAK'] ?? 'http://localhost:8180';
  final issuer = '$keycloak/realms/neon';

  test('form_post login against Keycloak', () async {
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
              .clientId('neon-server')
              .clientSecret('neon-server-dev-secret')
              .clientAuthenticationMethod(
                ClientAuthenticationMethod.clientSecretBasic,
              )
              .scope({'openid', 'profile', 'email'})
              .redirectUri('{baseUrl}/login/oauth2/code/{registrationId}')
              .userNameAttributeName('preferred_username')
              .responseMode(ResponseMode.formPost)
              .build();
    } on Object catch (e) {
      markTestSkipped('No Keycloak at $issuer ($e)');
      return;
    }
    final http = HttpSecurity(null)
      ..authorizeHttpRequests((auth) => auth.anyRequest().authenticated())
      ..oauth2Login(
        (login) => login
            .clientRegistrationRepository(
              InMemoryClientRegistrationRepository([registration]),
            )
            .tokenEndpoint(
              (token) => token.accessTokenResponseClient(
                DefaultAuthorizationCodeTokenResponseClient(transport),
              ),
            )
            .userInfoEndpoint(
              (userInfo) => userInfo
                  .userService(DefaultOAuth2UserService(transport))
                  .oidcUserService(OidcUserService(transport)),
            )
            .idTokenDecoder(
              OidcIdTokenDecoderFactory(
                fetcher: transportJwkFetcher(transport),
              ),
            ),
      );
    final app = ChainClient(http.build());
    final browser = _ScriptedBrowser();
    addTearDown(browser.close);

    // The app sends the browser to Keycloak, asking for a form post.
    final start = await app.get('$_app/oauth2/authorization/keycloak');
    expect(start.status, 302);
    final authorization = Uri.parse(start.header('location')!);
    expect(authorization.queryParameters['response_mode'], 'form_post');
    expect(
      authorization.queryParameters['redirect_uri'],
      '$_app/login/oauth2/code/keycloak',
    );

    // The user logs in on Keycloak's page.
    final page = await browser.request('GET', authorization);
    expect(page.status, 200, reason: 'the login page');
    final action = RegExp('action="([^"]+)"').firstMatch(page.body)?.group(1);
    expect(action, isNotNull, reason: 'the login form');
    final answer = await browser.request(
      'POST',
      Uri.parse(_unescape(action!)),
      form: {'username': 'ada', 'password': 'ada-secret', 'credentialId': ''},
    );

    // form_post: no redirect, a page whose form posts the response.
    expect(answer.status, 200, reason: 'the form post page, not a redirect');
    final formAction = RegExp(
      '<form[^>]*action="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(answer.body)?.group(1);
    expect(_unescape(formAction!), '$_app/login/oauth2/code/keycloak');
    expect(answer.body.toLowerCase(), contains('method="post"'));
    final fields = {
      for (final match in RegExp(
        'name="([^"]+)"[^>]*value="([^"]*)"',
        caseSensitive: false,
      ).allMatches(answer.body))
        match.group(1)!: _unescape(match.group(2)!),
    };
    expect(fields.keys, containsAll(['code', 'state']));
    expect(
      fields['iss'],
      issuer,
      reason: 'Keycloak sends RFC 9207 iss in the post',
    );

    // The same response as a GET is refused, and leaves the login alone.
    final asGet = await app.get(
      Uri.parse(
        '$_app/login/oauth2/code/keycloak',
      ).replace(queryParameters: fields).toString(),
    );
    expect(asGet.status, 302);
    expect(asGet.header('location'), '/login?error');

    // The browser posts the form, with the app's session cookie.
    final callback = await app.post(
      '$_app/login/oauth2/code/keycloak',
      fields,
    );
    expect(callback.status, 302);
    expect(callback.header('location'), isNot(contains('error')));
    final me = await app.get('$_app/private');
    expect(me.reached, isTrue);
    final user = me.authentication! as OAuth2AuthenticationToken;
    expect(user.name, 'ada');
    expect(user.principal, isA<OidcUser>());

    // Posted again (a replay): refused.
    final again = await app.post('$_app/login/oauth2/code/keycloak', fields);
    expect(again.header('location'), '/login?error');
  });
}
