// The token store and the login browser seen from Dart: the messages they
// send to the platform code, how its errors come back, and the beans of
// the auto-configuration per platform. The platform code itself runs in
// example/flutter_guide/integration_test.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

const _tokenStore = MethodChannel('spring_boot_starter_flutter/token_store');
const _browser = MethodChannel(
  'spring_boot_starter_flutter/authorization_browser',
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

  group('SecureTokenStore on Android, iOS and macOS', () {
    test('reads, writes and deletes through the channel', () async {
      final values = <String, String>{};
      final calls = mockChannel(_tokenStore, (call) async {
        final arguments = (call.arguments as Map).cast<String, String>();
        return switch (call.method) {
          'read' => values[arguments['key']],
          'write' => values[arguments['key']!] = arguments['value']!,
          'delete' => values.remove(arguments['key']),
          _ => throw MissingPluginException(),
        };
      });
      final store = SecureTokenStore();

      expect(await store.read('oauth2.keycloak'), isNull);
      await store.write('oauth2.keycloak', '{"access_token":"a"}');
      expect(await store.read('oauth2.keycloak'), '{"access_token":"a"}');
      await store.delete('oauth2.keycloak');
      expect(await store.read('oauth2.keycloak'), isNull);

      expect(
        [for (final call in calls) call.method],
        [
          'read',
          'write',
          'read',
          'delete',
          'read',
        ],
      );
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
        final calls = mockChannel(_tokenStore, (_) async => 'v');
        expect(await SecureTokenStore().read('k'), 'v');
        expect(calls, hasLength(1));
      });
    }

    test('a platform error is a SecureTokenStoreException', () async {
      mockChannel(
        _tokenStore,
        (_) async => throw PlatformException(
          code: 'keychain',
          message: 'Keychain write failed: (OSStatus -25299)',
        ),
      );
      await expectLater(
        SecureTokenStore().write('k', 'secret'),
        throwsA(
          isA<SecureTokenStoreException>()
              .having((e) => e.code, 'code', 'keychain')
              .having((e) => e.message, 'message', contains('-25299'))
              .having((e) => '$e', 'text', isNot(contains('secret'))),
        ),
      );
    });

    test('without the platform code: an exception that says so', () async {
      await expectLater(
        SecureTokenStore().read('k'),
        throwsA(
          isA<SecureTokenStoreException>()
              .having((e) => e.code, 'code', 'no_plugin')
              .having((e) => e.message, 'message', contains('not registered')),
        ),
      );
    });

    test('an empty key is refused before the platform is called', () {
      final calls = mockChannel(_tokenStore, (_) async => null);
      expect(() => SecureTokenStore().read(''), throwsArgumentError);
      expect(calls, isEmpty);
    });

    test('is supported everywhere but the web and Fuchsia', () {
      expect(SecureTokenStore.isSupported, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(SecureTokenStore.isSupported, isFalse);
      expect(SecureTokenStore.new, throwsUnsupportedError);
    });
  });

  group('PlatformAuthorizationBrowser', () {
    final redirectUri = Uri.parse('neonbooks:/oauth2/callback');
    Uri authorizationUri(Uri redirect) => Uri.https('id.neon.books', '/auth', {
      'redirect_uri': '$redirect',
      'state': 's1',
    });

    test('sends the URIs and returns the redirect', () async {
      final calls = mockChannel(
        _browser,
        (_) async => 'neonbooks:/oauth2/callback?code=c1&state=s1',
      );
      const browser = PlatformAuthorizationBrowser();

      final result = await browser.authorize(
        redirectUri: redirectUri,
        authorizationUri: authorizationUri,
      );

      expect(result.queryParameters, {'code': 'c1', 'state': 's1'});
      expect(calls.single.method, 'authorize');
      expect(calls.single.arguments, {
        'url': 'https://id.neon.books/auth?redirect_uri=neonbooks%3A%2Foauth2%2Fcallback&state=s1',
        'redirectUri': 'neonbooks:/oauth2/callback',
        'preferEphemeralSession': false,
      });
    });

    test('passes the ephemeral session option', () async {
      final calls = mockChannel(_browser, (_) async => 'neonbooks:/x');
      await const PlatformAuthorizationBrowser(
        preferEphemeralSession: true,
      ).authorize(redirectUri: redirectUri, authorizationUri: authorizationUri);
      expect(
        (calls.single.arguments as Map)['preferEphemeralSession'],
        isTrue,
      );
    });

    Future<void> failsWith(String code, Matcher matcher) async {
      mockChannel(
        _browser,
        (_) async => throw PlatformException(code: code, message: 'm-$code'),
      );
      await expectLater(
        const PlatformAuthorizationBrowser().authorize(
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
      test('$code is an AuthorizationBrowserException', () async {
        await failsWith(
          code,
          isA<AuthorizationBrowserException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.message, 'message', 'm-$code'),
        );
      });
    }

    test('one login at a time, also before the platform answers', () async {
      final answer = Completer<Object?>();
      final calls = mockChannel(_browser, (_) => answer.future);
      const browser = PlatformAuthorizationBrowser();

      final first = browser.authorize(
        redirectUri: redirectUri,
        authorizationUri: authorizationUri,
      );
      await expectLater(
        browser.authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        ),
        throwsStateError,
      );
      answer.complete('neonbooks:/oauth2/callback?code=c1');
      expect((await first).queryParameters['code'], 'c1');
      expect(calls, hasLength(1));

      // The next login may start.
      mockChannel(_browser, (_) async => 'neonbooks:/again');
      expect(
        await browser.authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        ),
        Uri.parse('neonbooks:/again'),
      );
    });

    test('desktops and the web have none', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(PlatformAuthorizationBrowser.isSupported, isFalse);
      await expectLater(
        const PlatformAuthorizationBrowser().authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('the auto-configuration', () {
    Future<ConfigurableApplicationContext> start([
      List<BeanDefinition<Object>> beans = const [],
    ]) async {
      final context = await SpringApplication(
        [BeanModule('app', beans)],
        autoConfigurations: [springBootStarterFlutterAutoConfiguration],
        bannerMode: BannerMode.off,
      ).runAsync(const []);
      addTearDown(context.close);
      return context;
    }

    test('on a phone: the secure store and the platform browser', () async {
      final context = await start();
      expect(context.getBean<TokenStore>(), isA<SecureTokenStore>());
      expect(
        context.getBean<AuthorizationBrowser>(),
        isA<PlatformAuthorizationBrowser>(),
      );
    });

    test('on Windows: the secure store, no browser (loopback)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final context = await start();
      expect(context.getBeanNamesForType(TokenStore), ['secureTokenStore']);
      expect(context.getBeanNamesForType(AuthorizationBrowser), isEmpty);
    });

    test('on Fuchsia: neither', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final context = await start();
      expect(context.getBeanNamesForType(TokenStore), isEmpty);
      expect(context.getBeanNamesForType(AuthorizationBrowser), isEmpty);
    });

    test('they replace the OAuth2 client\'s defaults', () async {
      // Listed the wrong way round: the modules' before / after put the
      // starter's first, so the client's in-memory store yields.
      final modules = [
        springBootStarterOauth2ClientAutoConfiguration,
        springBootStarterFlutterAutoConfiguration,
      ];
      Future<ConfigurableApplicationContext> run() async {
        final context = await SpringApplication(
          const [],
          autoConfigurations: modules,
          autoConfigurationMetadata: {
            springBootStarterFlutterAutoConfiguration:
                const AutoConfigurationModule(
                  before: ['springBootStarterOauth2ClientAutoConfiguration'],
                ),
            springBootStarterOauth2ClientAutoConfiguration:
                const AutoConfigurationModule(
                  after: ['springBootStarterFlutterAutoConfiguration'],
                ),
          },
          bannerMode: BannerMode.off,
        ).runAsync(const []);
        addTearDown(context.close);
        return context;
      }

      final phone = await run();
      expect(phone.getBeanNamesForType(TokenStore), ['secureTokenStore']);
      expect(phone.getBeanNamesForType(AuthorizationBrowser), [
        'platformAuthorizationBrowser',
      ]);

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final desktop = await run();
      expect(desktop.getBeanNamesForType(TokenStore), ['secureTokenStore']);
      // The client's loopback browser serves the desktops.
      expect(desktop.getBeanNamesForType(AuthorizationBrowser), [
        'authorizationBrowser',
      ]);
    });

    test("the application's own store and browser win", () async {
      final context = await start([
        BeanDefinition<InMemoryTokenStore>(
          name: 'myStore',
          types: const [InMemoryTokenStore, TokenStore],
          create: (_) => InMemoryTokenStore(),
        ),
        BeanDefinition<_FakeBrowser>(
          name: 'myBrowser',
          types: const [_FakeBrowser, AuthorizationBrowser],
          create: (_) => _FakeBrowser(),
        ),
      ]);
      expect(context.getBeanNamesForType(TokenStore), ['myStore']);
      expect(context.getBeanNamesForType(AuthorizationBrowser), ['myBrowser']);
    });
  });
}

class _FakeBrowser implements AuthorizationBrowser {
  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) async => redirectUri;
}
