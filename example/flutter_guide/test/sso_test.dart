// Chapter 7, single sign-on (the `sso` profile): the native apps' own
// Keycloak login (OAuth2LoginService with the system's login window, the
// tokens in the SecretStore, Bearer on the server calls, restore at
// startup, logout), and the web app's login through the server (the page leaves
// for /oauth2/authorization/keycloak, comes back with a session cookie,
// sends the CSRF cookie back as a header). Keycloak is played by the
// fake server's MockHttpTransport, the system's login window by a fake
// that "logs in" at once, the browser page by a fake BrowserPage.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/app/home_page.dart';
import 'package:neon_books_app/src/api/shop_client.dart';
import 'package:neon_books_app/src/catalog/catalog_service.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

const issuer = 'http://localhost:8180/realms/neon';
const endpoints = '$issuer/protocol/openid-connect';

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

String _b64(Object json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// Keycloak's realm `neon` for the public client `neon-app`, on the fake
/// server's transport.
final class FakeKeycloak {
  FakeKeycloak(this.http);

  final MockHttpTransport http;

  /// Who logs in, with which realm roles.
  String user = 'root';
  List<String> roles = ['USER', 'ADMIN'];

  final _codes = <String, Map<String, String>>{};
  final revoked = <String>[];
  var _sequence = 0;

  void answer() => http
    ..when(HttpMethod.get, '$issuer/.well-known/openid-configuration').respond(
      200,
      json: {
        'issuer': issuer,
        'authorization_endpoint': '$endpoints/auth',
        'token_endpoint': '$endpoints/token',
        'userinfo_endpoint': '$endpoints/userinfo',
        'jwks_uri': '$endpoints/certs',
        'revocation_endpoint': '$endpoints/revoke',
        'end_session_endpoint': '$endpoints/logout',
      },
    )
    ..when(HttpMethod.post, '$endpoints/token').respondWith(_token)
    ..when(HttpMethod.get, '$endpoints/userinfo').respondWith(
      (_) => _json(200, {
        'sub': 'id-of-$user',
        'preferred_username': user,
        'roles': roles,
      }),
    )
    ..when(HttpMethod.post, '$endpoints/revoke').respondWith((request) {
      revoked.add(Uri.splitQueryString(utf8.decode(request.body!))['token']!);
      return HttpResponse(200);
    });

  /// The login page: the user logs in, Keycloak redirects back with a code
  /// bound to the PKCE challenge, the redirect URI and the nonce.
  Uri approve(Uri authorization) {
    final query = authorization.queryParameters;
    expect(query['client_id'], 'neon-app');
    expect(query['code_challenge_method'], 'S256');
    final code = 'code-${++_sequence}';
    _codes[code] = query;
    return Uri.parse(query['redirect_uri']!).replace(
      queryParameters: {'code': code, 'state': query['state']!},
    );
  }

  HttpResponse _token(HttpRequest request) {
    final form = Uri.splitQueryString(utf8.decode(request.body!));
    expect(form['client_id'], 'neon-app'); // a public client: no secret
    expect(request.headers['Authorization'], isNull);
    if (form['grant_type'] == 'authorization_code') {
      final grant = _codes.remove(form['code']);
      // (The PKCE check itself is the OAuth2 client's tested business.)
      if (grant == null ||
          form['redirect_uri'] != grant['redirect_uri'] ||
          (form['code_verifier'] ?? '').length < 43) {
        return _json(400, {'error': 'invalid_grant'});
      }
      return _tokens(grant['nonce']);
    }
    return _json(400, {'error': 'unsupported_grant_type'});
  }

  HttpResponse _tokens(String? nonce) {
    final now = DateTime.now();
    final idToken = [
      _b64({'alg': 'RS256', 'kid': 'k1'}),
      _b64({
        'iss': issuer,
        'sub': 'id-of-$user',
        'aud': 'neon-app',
        'azp': 'neon-app',
        'iat': _seconds(now),
        'exp': _seconds(now.add(const Duration(minutes: 5))),
        'nonce': ?nonce,
        'preferred_username': user,
        'roles': roles,
      }),
      'c2lnbmF0dXJl',
    ].join('.');
    return _json(200, {
      'access_token': 'access-of-$user',
      'token_type': 'Bearer',
      'expires_in': 300,
      'refresh_token': 'refresh-of-$user',
      'scope': 'openid profile email',
      'id_token': idToken,
    });
  }

  static HttpResponse _json(int status, Object body) => HttpResponse(
    status,
    headers: HttpHeaders({'Content-Type': 'application/json'}),
    body: utf8.encode(jsonEncode(body)),
  );
}

/// The login window: the user logs in at once (or closes the page).
final class FakeAuthorizationWindow implements AuthorizationWindow {
  FakeAuthorizationWindow(this.keycloak);

  final FakeKeycloak keycloak;
  final opened = <Uri>[];
  var cancel = false;

  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) async {
    final page = authorizationUri(redirectUri);
    opened.add(page);
    if (cancel) {
      throw const AuthorizationCancelledException();
    }
    if (page.path.endsWith('/logout')) {
      final query = page.queryParameters;
      return Uri.parse(
        query['post_logout_redirect_uri']!,
      ).replace(queryParameters: {'state': query['state']!});
    }
    return keycloak.approve(page);
  }
}

/// The web app's page (localhost:5050): its cookies, and where it went.
final class FakePage implements BrowserPage {
  final cookies = <String, String>{};
  final opened = <Uri>[];

  @override
  Uri get location => Uri.parse('http://localhost:5050/');

  @override
  String? cookie(String name) => cookies[name];

  @override
  void navigate(Uri url) => opened.add(url);
}

Authentication? get current =>
    SecurityContextHolder.getContext().authentication;

/// Waits until [session] has finished the restore of the app's start
/// (the context publishes `ApplicationReadyEvent` right after it started).
Future<void> started(Session session) async {
  await pumpEventQueue();
  await session.restored;
}

/// The web app starts again (back from the server's login, or a reload)
/// once the fake server has its answers: the context of the test started
/// before them, so its restore found nobody.
Future<Session> startedAgain(SpringBootTestContext app) async {
  final session = app.getBean<Session>();
  await started(session);
  app.context.publishEvent(
    ApplicationReadyEvent(
      springApplication,
      const [],
      app.context,
      Duration.zero,
    ),
  );
  await started(session);
  return session;
}

Future<void> openLogin(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Log in'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(SecurityContextHolder.clearContext);

  group('native apps: their own Keycloak login', () {
    final server = FakeServer();
    final keycloak = FakeKeycloak(server.http);
    final browser = FakeAuthorizationWindow(keycloak);
    final tokens = _SecretStore();
    var keepTokens = false;
    final app = springBootTest(
      springApplication,
      profiles: ['mobile', 'android', 'sso'],
      overrides: [
        ...server.overrides,
        BeanOverride<AuthorizationWindow>(browser),
        BeanOverride<SecretStore>(tokens),
      ],
    );

    setUp(() {
      app.markDirty();
      server.http.reset();
      server.answerCatalog();
      keycloak
        ..answer()
        ..user = 'root'
        ..roles = ['USER', 'ADMIN'];
      browser
        ..opened.clear()
        ..cancel = false;
      if (!keepTokens) {
        tokens.values.clear(); // a fresh install
      }
      keepTokens = false;
      server.http
          .when(
            HttpMethod.get,
            '/api/basket',
          )
          .respond(200, json: {'items': []});
    });

    testWidgets('the Login screen has one button: Keycloak', (tester) async {
      await showPage(tester, app.context, const HomePage());
      await openLogin(tester);

      expect(find.byKey(const Key('login-keycloak')), findsOneWidget);
      expect(find.text('Sign in with Keycloak'), findsOneWidget);
      expect(find.byType(LoginForm), findsNothing);
    });

    testWidgets('root signs in: ADMIN from the realm roles, a Bearer token', (
      tester,
    ) async {
      await showPage(tester, app.context, const HomePage());
      await openLogin(tester);
      await tester.tap(find.byKey(const Key('login-keycloak')));
      // The login's requests (discovery, token, user info) take a few
      // turns of the fake clock.
      // The login's work runs outside the test's fake clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();

      // The app's own scheme, the system's login window, PKCE.
      final page = browser.opened.single;
      expect(
        page.queryParameters,
        containsPair('scope', 'openid profile email'),
      );
      expect(
        page.queryParameters['redirect_uri'],
        'books.neon.app:/oauth2/callback',
      );
      expect(current, isA<OAuth2AuthenticationToken>());
      expect(current!.name, 'root'); // preferred_username
      expect(
        current!.authorities.map((a) => a.authority),
        containsAll(['ROLE_USER', 'ROLE_ADMIN', 'OIDC_USER']),
      );
      expect(find.text('root'), findsOneWidget); // the app bar
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Admin'), findsOneWidget);

      // The tokens are in the SecretStore (the Keychain / Keystore on a
      // device), not somewhere the app chose.
      expect(await tokens.read(NativeOAuth2LoginService.sessionKey), isNotNull);
    });

    test('the server gets the access token, Keycloak no cookie', () async {
      await app.getBean<Session>().signInWithKeycloak();
      await app.getBean<ShopClient>().basket();

      final basket = server.http.requests.lastWhere(
        (r) => r.url.path == '/api/basket',
      );
      expect(basket.headers['Authorization'], 'Bearer access-of-root');
      final toKeycloak = server.http.requests.where((r) => r.url.port == 8180);
      expect(toKeycloak, isNotEmpty);
      // The server's session cookie is none of Keycloak's business.
      expect(toKeycloak.every((r) => r.headers['Cookie'] == null), isTrue);
    });

    test('anonymous calls go out without a token', () async {
      await app.getBean<CatalogService>().page('', 0);
      final catalog = server.http.requests.where(
        (r) => r.url.path == '/api/books',
      );
      expect(catalog.every((r) => r.headers['Authorization'] == null), isTrue);
    });

    test('ada is a USER only', () async {
      keycloak
        ..user = 'ada'
        ..roles = ['USER'];
      final session = app.getBean<Session>();
      await session.signInWithKeycloak();

      expect(session.user, 'ada');
      expect(session.isAdmin, isFalse);
    });

    test('a closed login page: nobody logged in, no error', () async {
      browser.cancel = true;
      await expectLater(
        app.getBean<Session>().signInWithKeycloak(),
        throwsA(isA<AuthorizationCancelledException>()),
      );
      expect(current, isNull);
    });

    // The secure storage outlives the app: these two tests are one
    // restart (every test starts a new context, setUp keeps the tokens).
    test('a login stays in the SecretStore ...', () async {
      await started(app.getBean<Session>());
      await app.getBean<Session>().signInWithKeycloak();
      keepTokens = true;
    });

    test('... and the next start restores the user', () async {
      final session = app.getBean<Session>();
      await started(session);

      expect(session.user, 'root');
      expect(session.isAdmin, isTrue);
      expect(browser.opened, isEmpty); // no login page this time
    });

    test('logout: revoked, forgotten, Keycloak session ended', () async {
      final session = app.getBean<Session>();
      await started(session);
      await session.signInWithKeycloak();

      await session.logout();

      expect(current, isNull);
      expect(
        keycloak.revoked,
        containsAll(['refresh-of-root', 'access-of-root']),
      );
      expect(await tokens.read(NativeOAuth2LoginService.sessionKey), isNull);
      final logout = browser.opened.last;
      expect(logout.path, Uri.parse('$endpoints/logout').path);
      expect(
        logout.queryParameters['post_logout_redirect_uri'],
        'books.neon.app:/oauth2/logout',
      );
    });
  });

  group('the web app: the server logs it in', () {
    final server = FakeServer();
    final page = FakePage();
    final app = springBootTest(
      springApplication,
      profiles: ['web', 'sso'],
      overrides: server.webOverrides(page),
    );

    setUp(() {
      app.markDirty();
      server.http.reset();
      server.answerCatalog();
      page
        ..opened.clear()
        ..cookies.clear();
    });

    test('no tokens in the browser: the server\'s login, no registration', () {
      expect(
        app.context.getBean<OAuth2LoginService>(),
        isA<ServerOAuth2LoginService>(),
      );
      expect(
        app.context.getBeanNamesForType(ClientRegistrationRepository),
        isEmpty,
      );
      expect(
        app.context.getBeanNamesForType(NativeOAuth2LoginService),
        isEmpty,
      );
    });

    test('"Sign in with Keycloak" leaves for the server', () async {
      server.http.when(HttpMethod.get, '/api/me').respond(401);
      final session = app.getBean<Session>();
      expect(session.usesKeycloak, isTrue);

      await session.signInWithKeycloak();

      expect(
        page.opened.single.toString(),
        'http://localhost:8080/oauth2/authorization/keycloak',
      );
    });

    test('back from Keycloak: the session cookie names the user', () async {
      server.http
        ..when(HttpMethod.get, '/api/me').respond(
          200,
          json: {
            'name': 'root',
            'roles': ['ADMIN', 'USER'],
            'authorities': ['OIDC_USER', 'ROLE_ADMIN', 'ROLE_USER'],
            'registrationId': 'keycloak',
          },
        )
        ..when(HttpMethod.get, '/api/basket').respond(200, json: {'items': []});

      final session = await startedAgain(app);

      expect(session.user, 'root');
      expect(session.isAdmin, isTrue);
      expect(current, isA<OAuth2AuthenticationToken>());
      final me = server.http.requests.firstWhere(
        (r) => r.url.path == '/api/me',
      );
      expect(me.url.toString(), 'http://localhost:8080/api/me');
    });

    test('a form login of the server is restored too', () async {
      server.http
        ..when(HttpMethod.get, '/api/me').respond(
          200,
          json: {
            'name': 'ada',
            'roles': ['USER'],
            'authorities': ['ROLE_USER'],
          },
        )
        ..when(HttpMethod.get, '/api/basket').respond(200, json: {'items': []});
      final session = await startedAgain(app);

      expect(session.user, 'ada');
      expect(session.isAdmin, isFalse);
      expect(current, isA<PreAuthenticatedAuthenticationToken>());
    });

    test('unsafe requests carry the page\'s CSRF cookie', () async {
      // The browser sends the session cookie by itself: the fake server
      // cannot see it, so it answers as if it did.
      server.http
        ..when(HttpMethod.get, '/api/me').respond(
          200,
          json: {
            'name': 'ada',
            'roles': ['USER'],
          },
        )
        ..when(HttpMethod.post, '/api/login').respond(204)
        ..when(HttpMethod.get, '/api/basket').respond(200, json: {'items': []});
      page.cookies['XSRF-TOKEN'] = 'token-of-the-page';

      await app.getBean<Session>().login('ada', 'ada-secret');

      final login = server.http.requests.lastWhere(
        (r) => r.url.path == '/api/login',
      );
      expect(login.headers['X-XSRF-TOKEN'], 'token-of-the-page');
      expect(login.headers['Cookie'], isNull); // the browser sends them
    });

    test('logout: the page goes on to Keycloak\'s logout', () async {
      server.http
        ..when(HttpMethod.get, '/api/me').respond(
          200,
          json: {
            'name': 'root',
            'roles': ['ADMIN', 'USER'],
            'authorities': ['OIDC_USER', 'ROLE_ADMIN', 'ROLE_USER'],
            'registrationId': 'keycloak',
          },
        )
        ..when(HttpMethod.get, '/api/basket').respond(200, json: {'items': []})
        ..when(HttpMethod.post, '/api/logout').respond(
          200,
          json: {'logoutUrl': '$endpoints/logout?id_token_hint=x'},
        );
      page.cookies['XSRF-TOKEN'] = 'token-of-the-page';
      final session = await startedAgain(app);
      expect(session.user, 'root');

      await session.logout();

      final logout = server.http.requests.lastWhere(
        (r) => r.url.path == '/api/logout',
      );
      expect(logout.headers['X-XSRF-TOKEN'], 'token-of-the-page');
      expect(current, isNull);
      expect(
        page.opened.single.toString(),
        '$endpoints/logout?id_token_hint=x',
      );
    });
  });

  group('the web app in spa mode (the optional spa profile)', () {
    final server = FakeServer();
    final keycloak = FakeKeycloak(server.http);
    final page = _SpaPage();
    final app = springBootTest(
      springApplication,
      profiles: ['web', 'sso', 'spa'],
      overrides: [
        BeanOverride<HttpTransport>(server.http, name: 'httpTransport'),
        BeanOverride<SpaBrowserPage>(page),
        BeanOverride<WebSocketTransport>(server.sockets),
      ],
    );

    setUp(() {
      app.markDirty();
      server.http.reset();
      server.answerCatalog();
      keycloak.answer();
      page.opened.clear();
    });

    test('the browser logs in itself, as neon-web, back to the page', () async {
      expect(
        app.context.getBean<OAuth2LoginService>(),
        isA<SpaOAuth2LoginService>(),
      );
      expect(app.context.getBean<DPoPKey>(), isA<WebCryptoDPoPKey>());
      final session = app.getBean<Session>();
      await started(session);
      expect(session.usesKeycloak, isTrue);

      await session.signInWithKeycloak();

      final login = page.opened.single;
      expect(login.toString(), startsWith('$endpoints/auth?'));
      expect(login.queryParameters['client_id'], 'neon-web');
      expect(login.queryParameters['redirect_uri'], 'http://localhost:5050/');
      expect(login.queryParameters['code_challenge_method'], 'S256');
      expect(page.sessionStorage.items, hasLength(1)); // the round trip
      expect(page.localStorage.items, isEmpty); // never a token
    });
  });
}

/// The web app's page in spa mode: its address and storages, and where
/// it went.
final class _SpaPage implements SpaBrowserPage {
  final opened = <Uri>[];

  @override
  Uri get location => Uri.parse('http://localhost:5050/');

  @override
  Uri get baseUri => Uri.parse('http://localhost:5050/');

  @override
  String? cookie(String name) => null;

  @override
  void navigate(Uri url) => opened.add(url);

  @override
  void replaceLocation(Uri url) {}

  @override
  final InMemoryBrowserStorage sessionStorage = InMemoryBrowserStorage();

  @override
  final InMemoryBrowserStorage localStorage = InMemoryBrowserStorage();
}

/// The secure storage of the device, in memory.
final class _SecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Set<String>> keys() async => values.keys.toSet();

  @override
  Future<void> deleteAll() async => values.clear();
}
