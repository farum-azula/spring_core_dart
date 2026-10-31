// The loopback login window on a real socket (RFC 8252 §7.3): the opener plays
// the default browser and the provider, following the redirect with an
// HttpClient.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_flutter_security/src/window/loopback_platform_stub.dart'
    as web;

import 'support/fake_provider.dart';

void main() {
  late HttpClient http;

  setUp(() => http = HttpClient());
  tearDown(() => http.close(force: true));

  Future<(int, String)> get(Uri uri) async {
    final request = await http.getUrl(uri);
    final response = await request.close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  }

  test('receives the redirect on 127.0.0.1 and a free port', () async {
    late Uri pageAsked;
    final pages = <(int, String)>[];
    final window = LoopbackAuthorizationWindow(
      openBrowser: (uri) async {
        pageAsked = uri;
        final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
        // The browser's own request first: not the redirect.
        pages
          ..add(await get(redirect.replace(path: '/favicon.ico')))
          ..add(
            await get(
              redirect.replace(
                queryParameters: {'code': 'c&1', 'state': 's t'},
              ),
            ),
          );
      },
    );
    final redirected = await window.authorize(
      redirectUri: Uri.parse('http://127.0.0.1/oauth2/callback'),
      authorizationUri: (redirectUri) => Uri.parse(
        'https://sso.test/auth',
      ).replace(queryParameters: {'redirect_uri': '$redirectUri'}),
    );

    final used = Uri.parse(pageAsked.queryParameters['redirect_uri']!);
    expect(used.host, '127.0.0.1');
    expect(used.port, isNot(0));
    expect(used.path, '/oauth2/callback');
    expect(redirected.queryParameters, {'code': 'c&1', 'state': 's t'});
    expect(redirected.replace(query: ''), used.replace(query: ''));
    expect(pages.first.$1, 404);
    expect(pages.last.$1, 200);
    expect(pages.last.$2, contains('You can close this window'));
    expect(pages.last.$2, isNot(contains('c&1')), reason: 'nothing echoed');

    // The server is gone after the redirect.
    await expectLater(get(used), throwsA(isA<IOException>()));
  });

  test('a full login through the loopback', () async {
    final fixture = await LoginFixture.create();
    final window = LoopbackAuthorizationWindow(
      openBrowser: (uri) async {
        // The provider logs the user in and redirects the real browser.
        await get(fixture.provider.approve(uri));
      },
    );
    final authentication = await fixture
        .service(window: window)
        .login('keycloak');
    expect(authentication.name, 'user-1');
    final redirect = fixture.provider.tokenRequests.single['redirect_uri']!;
    expect(redirect, startsWith('http://127.0.0.1:'));
    expect(redirect, endsWith('/callback'));
  });

  test('only the redirect with the login\'s state ends the wait', () async {
    final answers = <int>[];
    final window = LoopbackAuthorizationWindow(
      openBrowser: (uri) async {
        final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
        // Another site sends the browser to the exact path: with another
        // state, without one, with two, and a malformed query.
        for (final forged in [
          redirect.replace(queryParameters: {'code': 'x', 'state': 'forged'}),
          redirect.replace(queryParameters: {'error': 'access_denied'}),
          redirect.replace(query: 'code=x&state=s1&state=forged'),
          redirect.replace(query: 'code=x&state=%zz'),
        ]) {
          answers.add((await get(forged)).$1);
        }
        answers.add(
          (await get(
            redirect.replace(queryParameters: {'code': 'c', 'state': 's1'}),
          )).$1,
        );
      },
    );
    final redirected = await window.authorize(
      redirectUri: Uri.parse('http://127.0.0.1/cb'),
      authorizationUri: (redirect) =>
          Uri.parse('https://sso.test/auth').replace(
            queryParameters: {'redirect_uri': '$redirect', 'state': 's1'},
          ),
    );
    expect(answers, [400, 400, 400, 400, 200]);
    expect(redirected.queryParameters, {'code': 'c', 'state': 's1'});
  });

  test("a forged redirect does not end the login's wait", () async {
    final fixture = await LoginFixture.create();
    final window = LoopbackAuthorizationWindow(
      openBrowser: (uri) async {
        final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
        await get(redirect.replace(queryParameters: {'error': 'x'}));
        await get(fixture.provider.approve(uri));
      },
    );
    final authentication = await fixture
        .service(window: window)
        .login('keycloak');
    expect(authentication.name, 'user-1');
  });

  test('an explicit localhost stays localhost', () async {
    late Uri used;
    final window = LoopbackAuthorizationWindow(
      openBrowser: (uri) async {
        used = Uri.parse(uri.queryParameters['redirect_uri']!);
        await get(
          used.replace(
            host: '127.0.0.1',
            queryParameters: {'code': 'c', 'state': 's'},
          ),
        );
      },
    );
    final redirected = await window.authorize(
      redirectUri: Uri.parse('http://localhost/cb'),
      authorizationUri: (redirect) => Uri.parse(
        'https://sso.test/auth',
      ).replace(queryParameters: {'redirect_uri': '$redirect', 'state': 's'}),
    );
    expect(used.host, 'localhost');
    expect(used.port, isNot(0));
    expect(redirected.host, 'localhost');
    expect(redirected.queryParameters['code'], 'c');
  });

  Future<bool> hasIPv6() async {
    try {
      await (await ServerSocket.bind(InternetAddress.loopbackIPv6, 0)).close();
      return true;
    } on SocketException {
      return false;
    }
  }

  test('localhost listens on ::1 too, on the same port', () async {
    if (!await hasIPv6()) {
      markTestSkipped('no IPv6 loopback here');
      return;
    }
    late Uri used;
    final window = LoopbackAuthorizationWindow(
      openBrowser: (uri) async {
        used = Uri.parse(uri.queryParameters['redirect_uri']!);
        // A browser that resolved localhost to ::1.
        await get(
          used.replace(
            host: '::1',
            queryParameters: {'code': 'c6', 'state': 's'},
          ),
        );
      },
    );
    final redirected = await window.authorize(
      redirectUri: Uri.parse('http://localhost/cb'),
      authorizationUri: (redirect) => Uri.parse(
        'https://sso.test/auth',
      ).replace(queryParameters: {'redirect_uri': '$redirect', 'state': 's'}),
    );
    expect(redirected.queryParameters['code'], 'c6');
  });

  test('an explicit localhost port held on ::1 by another program fails '
      'the login', () async {
    if (!await hasIPv6()) {
      markTestSkipped('no IPv6 loopback here');
      return;
    }
    // Another program on [::1]:port, port free on 127.0.0.1: a browser
    // resolving localhost to ::1 would hand it the redirect.
    final other = await ServerSocket.bind(
      InternetAddress.loopbackIPv6,
      0,
      v6Only: true,
    );
    addTearDown(other.close);
    final port = other.port;
    var opened = false;
    final window = LoopbackAuthorizationWindow(
      openBrowser: (_) async => opened = true,
    );
    await expectLater(
      window.authorize(
        redirectUri: Uri.parse('http://localhost:$port/cb'),
        authorizationUri: (redirect) => Uri.parse('https://sso.test/auth'),
      ),
      throwsA(
        isA<SocketException>().having(
          (e) => e.message,
          'message',
          contains('taken on ::1'),
        ),
      ),
    );
    expect(opened, isFalse);
    // 127.0.0.1 was given back.
    await (await ServerSocket.bind(InternetAddress.loopbackIPv4, port)).close();
  });

  test('no redirect in time is a cancelled login', () async {
    final window = LoopbackAuthorizationWindow(
      openBrowser: (_) async {},
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      window.authorize(
        redirectUri: Uri.parse('http://127.0.0.1/cb'),
        authorizationUri: (redirect) => Uri.parse('https://sso.test/auth'),
      ),
      throwsA(isA<AuthorizationCancelledException>()),
    );
  });

  test('a redirect URI with a port keeps it', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    late Uri used;
    final window = LoopbackAuthorizationWindow(
      openBrowser: (uri) async {
        used = Uri.parse(uri.queryParameters['redirect_uri']!);
        await get(used.replace(queryParameters: {'code': 'c'}));
      },
    );
    await window.authorize(
      redirectUri: Uri.parse('http://127.0.0.1:$port/cb'),
      authorizationUri: (redirect) => Uri.parse(
        'https://sso.test/auth',
      ).replace(queryParameters: {'redirect_uri': '$redirect'}),
    );
    expect(used.port, port);
  });

  test('the default opener opens http and https only', () {
    for (final uri in ['file:///etc/passwd', 'javascript:alert(1)', 'ms-x:y']) {
      expect(
        () => LoopbackAuthorizationWindow.openSystemBrowser(Uri.parse(uri)),
        throwsArgumentError,
        reason: uri,
      );
    }
  });

  test('the window of Windows and Linux', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        LoopbackAuthorizationWindow.isSupported,
        platform == TargetPlatform.windows || platform == TargetPlatform.linux,
        reason: platform.name,
      );
    }
    debugDefaultTargetPlatformOverride = null;
  });

  test('in a web page the loopback refuses and points to the server', () {
    expect(
      () => web.authorize(
        redirectUri: Uri.parse('http://127.0.0.1/cb'),
        authorizationUri: (redirect) => redirect,
        open: (_) async {},
        timeout: const Duration(seconds: 1),
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('oauth2Login()'),
        ),
      ),
    );
  });
}
