// The secret store and the login window seen from Dart: the messages they
// send to the platform code and how its errors come back. The platform
// code itself runs in example/flutter_guide/integration_test.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/linux_secret_service_store.dart';

const _secretStore = MethodChannel(
  'spring_boot_starter_flutter_security/secret_store',
);
const _window = MethodChannel(
  'spring_boot_starter_flutter_security/authorization_window',
);

/// Answers [channel]'s calls with [handler] and records them.
List<MethodCall> mockChannel(
  MethodChannel channel,
  Future<Object?> Function(MethodCall call) handler,
) {
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) {
    calls.add(call);
    return handler(call);
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformSecretStore on Android, iOS and macOS', () {
    test('reads, writes and deletes through the channel', () async {
      final values = <String, String>{};
      final calls = mockChannel(_secretStore, (call) async {
        final arguments = (call.arguments as Map? ?? const {})
            .cast<String, String>();
        return switch (call.method) {
          'read' => values[arguments['key']],
          'write' => values[arguments['key']!] = arguments['value']!,
          'delete' => values.remove(arguments['key']),
          'keys' => values.keys.toList(),
          'deleteAll' => values.clear(),
          _ => throw MissingPluginException(),
        };
      });
      final store = PlatformSecretStore();

      expect(await store.read('oauth2.keycloak'), isNull);
      await store.write('oauth2.keycloak', '{"access_token":"a"}');
      expect(await store.read('oauth2.keycloak'), '{"access_token":"a"}');
      await store.delete('oauth2.keycloak');
      expect(await store.read('oauth2.keycloak'), isNull);
      await store.write('app.pin', '1');
      await store.write('app.key', '2');
      expect(await store.keys(), {'app.pin', 'app.key'});
      await store.deleteAll();
      expect(await store.keys(), isEmpty);

      expect(
        [for (final call in calls) call.method],
        [
          'read',
          'write',
          'read',
          'delete',
          'read',
          'write',
          'write',
          'keys',
          'deleteAll',
          'keys',
        ],
      );
      expect(calls[8].arguments, isNull);
      expect(calls[1].arguments, {
        'key': 'oauth2.keycloak',
        'value': '{"access_token":"a"}',
      });
      expect(calls[3].arguments, {'key': 'oauth2.keycloak'});
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      test('uses the channel on ${platform.name}', () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final calls = mockChannel(_secretStore, (_) async => 'v');
        expect(await PlatformSecretStore().read('k'), 'v');
        expect(calls, hasLength(1));
      });
    }

    test('a platform error is a PlatformSecretStoreException', () async {
      mockChannel(
        _secretStore,
        (_) async => throw PlatformException(
          code: 'keychain',
          message: 'Keychain write failed: (OSStatus -25299)',
        ),
      );
      await expectLater(
        PlatformSecretStore().write('k', 'secret'),
        throwsA(
          isA<PlatformSecretStoreException>()
              .having((e) => e.code, 'code', 'keychain')
              .having((e) => e.message, 'message', contains('-25299'))
              .having((e) => '$e', 'text', isNot(contains('secret'))),
        ),
      );
    });

    test('without the platform code: an exception that says so', () async {
      await expectLater(
        PlatformSecretStore().read('k'),
        throwsA(
          isA<PlatformSecretStoreException>()
              .having((e) => e.code, 'code', 'no_plugin')
              .having((e) => e.message, 'message', contains('not registered')),
        ),
      );
    });

    test('an empty key is refused before the platform is called', () {
      final calls = mockChannel(_secretStore, (_) async => null);
      expect(() => PlatformSecretStore().read(''), throwsArgumentError);
      expect(calls, isEmpty);
    });

    test('is supported everywhere but the web and Fuchsia', () {
      expect(PlatformSecretStore.isSupported, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(PlatformSecretStore.isSupported, isFalse);
      expect(PlatformSecretStore.new, throwsUnsupportedError);
    });

    test("a blank application id is none: the app's own", () {
      // As the property: `spring.flutter.security.application-id=` set
      // empty must not name every app's values ''.
      expect(PlatformSecretStore(applicationId: '').applicationId, isNull);
      expect(PlatformSecretStore(applicationId: ' \t').applicationId, isNull);
      expect(PlatformSecretStore(applicationId: 'neon').applicationId, 'neon');
      // The Linux store (no libsecret call here): the default id, and no
      // 0.4.x name to move from.
      final linux = LinuxSecretServiceStore(
        application: '  ',
        legacyApplication: '',
      );
      expect(linux.application, LinuxSecretServiceStore.defaultApplication());
      expect(linux.application, isNotEmpty);
      expect(linux.legacyApplication, isNull);
    });
  });

  group('PlatformAuthorizationWindow', () {
    final redirectUri = Uri.parse('neonbooks:/oauth2/callback');
    Uri authorizationUri(Uri redirect) => Uri.https('id.neon.books', '/auth', {
      'redirect_uri': '$redirect',
      'state': 's1',
    });

    // Each test starts as a fresh isolate does (after a hot restart too).
    setUp(PlatformAuthorizationWindow.debugResetIsolate);

    test('sends the URIs and returns the redirect', () async {
      final calls = mockChannel(
        _window,
        (_) async => 'neonbooks:/oauth2/callback?code=c1&state=s1',
      );
      const window = PlatformAuthorizationWindow();

      final result = await window.authorize(
        redirectUri: redirectUri,
        authorizationUri: authorizationUri,
      );

      expect(result.queryParameters, {'code': 'c1', 'state': 's1'});
      expect(calls.single.method, 'authorize');
      expect(calls.single.arguments, {
        'url': 'https://id.neon.books/auth?redirect_uri=neonbooks%3A%2Foauth2%2Fcallback&state=s1',
        'redirectUri': 'neonbooks:/oauth2/callback',
        'preferEphemeralSession': false,
        'replaceStale': true,
      });
    });

    test('only the first call of an isolate replaces a stale login', () async {
      // The platform still runs a login of the isolate a hot restart
      // replaced: the first call says so, later ones never cancel a login.
      final calls = mockChannel(_window, (_) async => 'neonbooks:/x');
      const window = PlatformAuthorizationWindow();
      for (var i = 0; i < 3; i++) {
        await window.authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        );
      }
      expect(
        calls.map((call) => (call.arguments as Map)['replaceStale']),
        [true, false, false],
      );
      PlatformAuthorizationWindow.debugResetIsolate(); // a hot restart
      await window.authorize(
        redirectUri: redirectUri,
        authorizationUri: authorizationUri,
      );
      expect((calls.last.arguments as Map)['replaceStale'], isTrue);
    });

    test('a background isolate never replaces the login of the app', () async {
      // An isolate with BackgroundIsolateBinaryMessenger shares the engine:
      // its first login must not cancel the root isolate's.
      final calls = mockChannel(_window, (_) async => 'neonbooks:/x');
      PlatformAuthorizationWindow.debugRootIsolate = false;
      addTearDown(() => PlatformAuthorizationWindow.debugRootIsolate = null);
      await const PlatformAuthorizationWindow().authorize(
        redirectUri: redirectUri,
        authorizationUri: authorizationUri,
      );
      expect((calls.single.arguments as Map)['replaceStale'], isFalse);
    });

    test('a window closed without an answer frees the next login', () async {
      // Android answers `cancelled` when the window is destroyed (a
      // singleTask main activity, CLEAR_TOP) or the engine detaches.
      mockChannel(
        _window,
        (_) async => throw PlatformException(code: 'cancelled'),
      );
      const window = PlatformAuthorizationWindow();
      await expectLater(
        window.authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        ),
        throwsA(isA<AuthorizationCancelledException>()),
      );
      mockChannel(_window, (_) async => 'neonbooks:/oauth2/callback?code=c');
      expect(
        (await window.authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        )).queryParameters['code'],
        'c',
      );
    });

    test('passes the ephemeral session option', () async {
      final calls = mockChannel(_window, (_) async => 'neonbooks:/x');
      await const PlatformAuthorizationWindow(
        preferEphemeralSession: true,
      ).authorize(redirectUri: redirectUri, authorizationUri: authorizationUri);
      expect(
        (calls.single.arguments as Map)['preferEphemeralSession'],
        isTrue,
      );
    });

    Future<void> failsWith(String code, Matcher matcher) async {
      mockChannel(
        _window,
        (_) async => throw PlatformException(code: code, message: 'm-$code'),
      );
      await expectLater(
        const PlatformAuthorizationWindow().authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        ),
        throwsA(matcher),
      );
    }

    test('the user closing the page is a cancel', () async {
      await failsWith(
        'cancelled',
        isA<AuthorizationCancelledException>().having(
          (e) => e.message,
          'message',
          'm-cancelled',
        ),
      );
    });

    test('a login already running is a StateError', () async {
      await failsWith('in_progress', isA<StateError>());
    });

    test('a redirect the OS cannot catch is unsupported', () async {
      await failsWith('unsupported', isA<UnsupportedError>());
    });

    for (final code in ['redirect_not_configured', 'no_browser', 'failed']) {
      test('$code is an AuthorizationWindowException', () async {
        await failsWith(
          code,
          isA<AuthorizationWindowException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.message, 'message', 'm-$code'),
        );
      });
    }

    test('one login at a time, also before the platform answers', () async {
      final answer = Completer<Object?>();
      final calls = mockChannel(_window, (_) => answer.future);
      const window = PlatformAuthorizationWindow();

      final first = window.authorize(
        redirectUri: redirectUri,
        authorizationUri: authorizationUri,
      );
      await expectLater(
        window.authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        ),
        throwsStateError,
      );
      answer.complete('neonbooks:/oauth2/callback?code=c1');
      expect((await first).queryParameters['code'], 'c1');
      expect(calls, hasLength(1));

      // The next login may start.
      mockChannel(_window, (_) async => 'neonbooks:/again');
      expect(
        await window.authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        ),
        Uri.parse('neonbooks:/again'),
      );
    });

    test('desktops and the web have none', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(PlatformAuthorizationWindow.isSupported, isFalse);
      await expectLater(
        const PlatformAuthorizationWindow().authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        ),
        throwsUnsupportedError,
      );
    });
  });
}
