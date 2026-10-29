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
