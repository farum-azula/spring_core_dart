// The app's DPoP key seen from Dart: the channel of the Secure Enclave /
// Keychain / Android Keystore key (mocked here by a software key that
// answers as the platform does: the public key as a point or an X.509
// key, signatures in DER), the key kept in the SecretStore on Windows and
// Linux, the stored DPoP tokens, the key's deletion at logout, and the
// beans. The platform code itself runs in
// example/flutter_guide/integration_test/dpop_key_test.dart.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_flutter_security/src/dpop/method_channel_dpop_key.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner, MockHttpTransport, doesNotHaveBean;

import 'support/fake_provider.dart';

const _channel = MethodChannel('spring_boot_starter_flutter_security/dpop_key');

const _spkiPrefix = [
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, //
  0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, //
  0x42, 0x00,
];

List<int> _unb64(String text) => base64Url.decode(base64Url.normalize(text));

/// The uncompressed point `0x04 || X || Y` of [key].
Uint8List _point(DPoPKey key) => Uint8List.fromList([
  0x04,
  ..._unb64(key.publicJwk['x']! as String),
  ..._unb64(key.publicJwk['y']! as String),
]);

/// The DER `SEQUENCE { INTEGER r, INTEGER s }` of a raw `R || S`, as the
/// Secure Enclave and the Keystore write it.
Uint8List _der(Uint8List raw) {
  List<int> integer(List<int> bytes) {
    var value = bytes.skipWhile((b) => b == 0).toList();
    if (value.isEmpty || value.first & 0x80 != 0) {
      value = [0, ...value];
    }
    return [0x02, value.length, ...value];
  }

  final body = [...integer(raw.sublist(0, 32)), ...integer(raw.sublist(32))];
  return Uint8List.fromList([0x30, body.length, ...body]);
}

/// The platform's side of the channel, on a software key: what it was
/// asked, and switches for its failures.
final class FakePlatformKey {
  FakePlatformKey({this.spki = false, this.storage = 'secureEnclave'});

  /// Answer the X.509 key (Android) rather than the point (iOS, macOS).
  final bool spki;
  final String storage;
  SoftwareDPoPKey? key;
  final List<String> calls = [];
  PlatformException? failure;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      if (failure case final failure?) {
        throw failure;
      }
      switch (call.method) {
        case 'dpopPublicJwk':
          final current = key ??= SoftwareDPoPKey.generate();
          final point = _point(current);
          return {
            'publicKey': spki
                ? Uint8List.fromList([..._spkiPrefix, ...point])
                : point,
            'storage': storage,
          };
        case 'dpopSign':
          final current = key;
          if (current == null) {
            throw PlatformException(code: 'no_key', message: 'no DPoP key');
          }
          final data = (call.arguments as Map)['data'] as Uint8List;
          return _der(await current.sign(data));
        case 'dpopDelete':
          key = null;
          return null;
      }
      throw MissingPluginException();
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  }
}

/// The header and claims of [proof], after checking that [key] signed it
/// (the same signature: ES256 of the software key is deterministic).
Future<(Map<String, Object?>, Map<String, Object?>)> _open(
  String proof,
  SoftwareDPoPKey key,
) async {
  final parts = proof.split('.');
  expect(parts, hasLength(3));
  final expected = await key.sign(
    Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}')),
  );
  expect(_unb64(parts[2]), expected, reason: 'raw R || S of the key');
  Map<String, Object?> json(String part) =>
      jsonDecode(utf8.decode(_unb64(part))) as Map<String, Object?>;
  return (json(parts[0]), json(parts[1]));
}

void on(TargetPlatform platform) {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformDPoPKey on Android, iOS and macOS (the channel)', () {
    for (final (name, spki, storage) in [
      ('iOS / macOS: the point', false, DPoPKeyStorage.secureEnclave),
      ('Android: the X.509 key', true, DPoPKeyStorage.strongBox),
    ]) {
      test('$name; signs proofs, DER turned into R || S', () async {
        final platform = FakePlatformKey(spki: spki, storage: storage.name)
          ..install();
        final key = PlatformDPoPKey(InMemorySecretStore());
        expect(key.algorithm, 'ES256');
        expect(platform.calls, isEmpty, reason: 'made at the first use');
        expect(() => key.publicJwk, throwsStateError);

        final proof = await DPoPProofBuilder(key).build(
          method: 'POST',
          url: Uri.parse('https://sso.test/token'),
        );
        final (header, claims) = await _open(proof, platform.key!);
        expect(header['jwk'], {
          'kty': 'EC',
          'crv': 'P-256',
          'x': platform.key!.publicJwk['x'],
          'y': platform.key!.publicJwk['y'],
        });
        expect(claims['htu'], 'https://sso.test/token');
        expect(key.storage, storage);
        expect(
          JwkThumbprint.of(key.publicJwk),
          platform.key!.thumbprint,
          reason: 'the same key',
        );

        await DPoPProofBuilder(key).build(
          method: 'GET',
          url: Uri.parse('https://api.test/orders'),
          accessToken: 'token',
        );
        expect(
          platform.calls.where((c) => c == 'dpopPublicJwk'),
          hasLength(1),
          reason: 'the public key is asked once',
        );
      });
    }

    test('concurrent first proofs ask the platform once', () async {
      final platform = FakePlatformKey()..install();
      final key = PlatformDPoPKey(InMemorySecretStore());
      await Future.wait([
        for (var i = 0; i < 5; i++)
          DPoPProofBuilder(
            key,
          ).build(method: 'GET', url: Uri.parse('https://api.test/$i')),
      ]);
      expect(platform.calls.where((c) => c == 'dpopPublicJwk'), hasLength(1));
    });

    test('a key that is gone: no_key, then a new key', () async {
      final platform = FakePlatformKey()..install();
      final key = PlatformDPoPKey(InMemorySecretStore());
      await key.load();
      final old = JwkThumbprint.of(key.publicJwk);

      platform.key = null; // the Keystore wiped
      await expectLater(
        DPoPProofBuilder(
          key,
        ).build(method: 'GET', url: Uri.parse('https://api.test/')),
        throwsA(
          isA<PlatformDPoPKeyException>().having(
            (e) => e.code,
            'code',
            'no_key',
          ),
        ),
      );
      expect(key.storage, isNull, reason: 'forgotten');

      final proof = await DPoPProofBuilder(
        key,
      ).build(method: 'GET', url: Uri.parse('https://api.test/'));
      await _open(proof, platform.key!);
      expect(JwkThumbprint.of(key.publicJwk), isNot(old));
    });

    test('delete removes the key; the next proof makes a new one', () async {
      final platform = FakePlatformKey()..install();
      final key = PlatformDPoPKey(InMemorySecretStore());
      await key.load();
      final old = JwkThumbprint.of(key.publicJwk);

      await key.delete();
      expect(platform.calls.last, 'dpopDelete');
      expect(platform.key, isNull);
      expect(() => key.publicJwk, throwsStateError);

      await key.load();
      expect(JwkThumbprint.of(key.publicJwk), isNot(old));
    });

    test('platform errors become PlatformDPoPKeyException', () async {
      final platform = FakePlatformKey()
        ..install()
        ..failure = PlatformException(
          code: 'dpop_key',
          message: 'DPoP key read failed (OSStatus -25308)',
        );
      final key = PlatformDPoPKey(InMemorySecretStore());
      await expectLater(
        key.load(),
        throwsA(
          isA<PlatformDPoPKeyException>()
              .having((e) => e.code, 'code', 'dpop_key')
              .having((e) => e.message, 'message', contains('-25308')),
        ),
      );
      // A later call tries again.
      platform.failure = null;
      await key.load();
      expect(key.publicJwk['kty'], 'EC');
    });

    test('without the platform code: no_plugin', () async {
      final key = PlatformDPoPKey(InMemorySecretStore());
      await expectLater(
        key.load(),
        throwsA(
          isA<PlatformDPoPKeyException>().having(
            (e) => e.code,
            'code',
            'no_plugin',
          ),
        ),
      );
    });

    test('an unusable public key or signature is refused', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Object? publicKey = Uint8List(65);
      Object? signature = Uint8List.fromList([0x30, 0x00]);
      final software = SoftwareDPoPKey.generate();
      messenger.setMockMethodCallHandler(_channel, (call) async {
        return switch (call.method) {
          'dpopPublicJwk' => {'publicKey': publicKey, 'storage': 'keychain'},
          _ => signature,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

      final key = PlatformDPoPKey(InMemorySecretStore());
      await expectLater(key.load(), throwsA(isA<PlatformDPoPKeyException>()));
      publicKey = 'not bytes';
      await expectLater(key.load(), throwsA(isA<PlatformDPoPKeyException>()));
      publicKey = _point(software);
      await key.load();
      await expectLater(
        key.sign(Uint8List(3)),
        throwsA(isA<PlatformDPoPKeyException>()),
        reason: 'not a DER signature',
      );
      signature = null;
      await expectLater(
        key.sign(Uint8List(3)),
        throwsA(isA<PlatformDPoPKeyException>()),
      );
    });

    test('toString shows the thumbprint and storage, no key', () async {
      final platform = FakePlatformKey(storage: 'keychain')..install();
      final key = PlatformDPoPKey(InMemorySecretStore());
      expect('$key', contains('not loaded'));
      await key.load();
      expect('$key', contains(platform.key!.thumbprint));
      expect('$key', contains('keychain'));
      expect('$key', isNot(contains(platform.key!.publicJwk['x']! as String)));
    });
  });

  group('p256PublicJwk', () {
    test('reads the point and the X.509 key alike', () {
      final key = SoftwareDPoPKey.generate();
      final point = _point(key);
      final jwk = {...key.publicJwk};
      expect(p256PublicJwk(point), jwk);
      expect(p256PublicJwk([..._spkiPrefix, ...point]), jwk);
    });

    test('refuses other keys, compressed points, points off the curve', () {
      final point = _point(SoftwareDPoPKey.generate());
      final otherCurve = [..._spkiPrefix]..[20] = 0x22; // not prime256v1
      expect(
        () => p256PublicJwk([...otherCurve, ...point]),
        throwsFormatException,
      );
      expect(
        () => p256PublicJwk([0x02, ...point.sublist(1, 33)]),
        throwsFormatException,
      );
      final off = Uint8List.fromList(point)..[64] ^= 1;
      expect(() => p256PublicJwk(off), throwsFormatException);
      expect(() => p256PublicJwk(const []), throwsFormatException);
    });
  });

  group('SecretStoreDPoPKey (Windows, Linux)', () {
    test('made on first use, kept in the store, read back later', () async {
      final store = InMemorySecretStore();
      final key = SecretStoreDPoPKey(store);
      expect(await store.keys(), isEmpty, reason: 'nothing at creation');
      expect(() => key.publicJwk, throwsStateError);

      final proof = await DPoPProofBuilder(
        key,
      ).build(method: 'GET', url: Uri.parse('https://api.test/'));
      expect(proof.split('.'), hasLength(3));
      expect(key.storage, DPoPKeyStorage.secretStore);
      final stored = jsonDecode(
        (await store.read('oauth2.dpop-key'))!,
      ) as Map<String, Object?>;
      expect(stored.keys, containsAll(['kty', 'crv', 'x', 'y', 'd']));

      // The next start: the same key.
      final again = SecretStoreDPoPKey(store);
      await again.load();
      expect(
        JwkThumbprint.of(again.publicJwk),
        JwkThumbprint.of(key.publicJwk),
      );
      expect('$again', isNot(contains(stored['d']! as String)));
    });

    test('an unreadable stored key is replaced', () async {
      final store = InMemorySecretStore();
      await store.write('oauth2.dpop-key', '{"kty":"EC"}');
      final key = SecretStoreDPoPKey(store);
      await key.load();
      expect(key.publicJwk['kty'], 'EC');
      expect(
        SoftwareDPoPKey.fromJwk(
          jsonDecode((await store.read('oauth2.dpop-key'))!)
              as Map<String, Object?>,
        ).thumbprint,
        JwkThumbprint.of(key.publicJwk),
      );
    });

    test('delete removes it; the next use makes a new key', () async {
      final store = InMemorySecretStore();
      final key = SecretStoreDPoPKey(store);
      await key.load();
      final old = JwkThumbprint.of(key.publicJwk);
      await key.delete();
      expect(await store.read('oauth2.dpop-key'), isNull);
      await key.load();
      expect(JwkThumbprint.of(key.publicJwk), isNot(old));
    });

    test('PlatformDPoPKey uses it on Windows and Linux', () async {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        on(platform);
        final store = InMemorySecretStore();
        final key = PlatformDPoPKey(store);
        await key.load();
        expect(key.storage, DPoPKeyStorage.secretStore);
        expect(await store.keys(), ['oauth2.dpop-key']);
      }
    });

    test('nothing on Fuchsia', () {
      on(TargetPlatform.fuchsia);
      expect(PlatformDPoPKey.isSupported, isFalse);
      expect(
        () => PlatformDPoPKey(InMemorySecretStore()),
        throwsUnsupportedError,
      );
    });
  });

  group('stored DPoP tokens', () {
    late LoginFixture fixture;
    late ClientRegistration registration;
    final principal = TestingAuthenticationToken('user-1', null);
    final key = SecretStoreOAuth2AuthorizedClientService.keyOf(
      'keycloak',
      'user-1',
    );

    setUp(() async {
      fixture = await LoginFixture.create();
      registration = (await fixture.repository.findByRegistrationId(
        'keycloak',
      ))!;
    });

    OAuth2AuthorizedClient client(TokenType type) => OAuth2AuthorizedClient(
      registration,
      'user-1',
      OAuth2AccessToken(
        type,
        'access-1',
        issuedAt: DateTime.utc(2026, 10, 29, 12),
        expiresAt: DateTime.utc(2026, 10, 29, 12, 5),
        scopes: {'openid'},
      ),
      refreshToken: OAuth2RefreshToken('refresh-1'),
    );

    SecretStoreOAuth2AuthorizedClientService service(DPoPKey? dPoPKey) =>
        SecretStoreOAuth2AuthorizedClientService(
          fixture.store,
          fixture.repository,
          dPoPKey: dPoPKey,
        );

    test('a DPoP token keeps its type and its key thumbprint', () async {
      final dPoPKey = SecretStoreDPoPKey(InMemorySecretStore());
      await service(dPoPKey).saveAuthorizedClient(
        client(TokenType.dpop),
        principal,
      );
      final stored =
          jsonDecode((await fixture.store.read(key))!) as Map<String, Object?>;
      final access = stored['accessToken']! as Map<String, Object?>;
      expect(access['tokenType'], 'DPoP');
      expect(access['jkt'], JwkThumbprint.of(dPoPKey.publicJwk));

      final loaded = await service(
        dPoPKey,
      ).loadAuthorizedClient('keycloak', 'user-1');
      expect(loaded!.accessToken.tokenType, TokenType.dpop);
      expect(loaded.accessToken.tokenValue, 'access-1');
      expect(loaded.refreshToken!.tokenValue, 'refresh-1');
    });

    test('a Bearer token stays Bearer, without a thumbprint', () async {
      final dPoPKey = SecretStoreDPoPKey(InMemorySecretStore());
      await service(dPoPKey).saveAuthorizedClient(
        client(TokenType.bearer),
        principal,
      );
      expect(await fixture.store.read(key), isNot(contains('jkt')));
      final loaded = await service(
        dPoPKey,
      ).loadAuthorizedClient('keycloak', 'user-1');
      expect(loaded!.accessToken.tokenType, TokenType.bearer);
      expect(dPoPKey.storage, isNull, reason: 'the key is not even made');
    });

    test('a record without a type (before DPoP) reads as Bearer', () async {
      await service(null).saveAuthorizedClient(
        client(TokenType.bearer),
        principal,
      );
      final stored =
          jsonDecode((await fixture.store.read(key))!) as Map<String, Object?>;
      (stored['accessToken']! as Map<String, Object?>).remove('tokenType');
      await fixture.store.write(key, jsonEncode(stored));

      final loaded = await service(
        null,
      ).loadAuthorizedClient('keycloak', 'user-1');
      expect(loaded!.accessToken.tokenType, TokenType.bearer);
    });

    test('an unknown type, or a thumbprint on Bearer, is removed', () async {
      for (final change in <void Function(Map<String, Object?>)>[
        (access) => access['tokenType'] = 'MAC',
        (access) => access['jkt'] = 'abc',
      ]) {
        await service(null).saveAuthorizedClient(
          client(TokenType.bearer),
          principal,
        );
        final stored = jsonDecode(
          (await fixture.store.read(key))!,
        ) as Map<String, Object?>;
        change(stored['accessToken']! as Map<String, Object?>);
        await fixture.store.write(key, jsonEncode(stored));
        expect(
          await service(null).loadAuthorizedClient('keycloak', 'user-1'),
          isNull,
        );
        expect(await fixture.store.read(key), isNull);
      }
    });

    test('tokens bound to another key are removed: log in again', () async {
      final keys = InMemorySecretStore();
      final dPoPKey = SecretStoreDPoPKey(keys);
      await service(dPoPKey).saveAuthorizedClient(
        client(TokenType.dpop),
        principal,
      );
      await dPoPKey.delete(); // lost, or rotated at logout

      expect(
        await service(dPoPKey).loadAuthorizedClient('keycloak', 'user-1'),
        isNull,
      );
      expect(await fixture.store.read(key), isNull);
    });

    test('a key that cannot be loaded does not judge', () async {
      final dPoPKey = SecretStoreDPoPKey(InMemorySecretStore());
      await service(dPoPKey).saveAuthorizedClient(
        client(TokenType.dpop),
        principal,
      );
      final broken = FakePlatformKey()
        ..install()
        ..failure = PlatformException(code: 'dpop_key');
      final platformKey = PlatformDPoPKey(InMemorySecretStore());
      final loaded = await service(
        platformKey,
      ).loadAuthorizedClient('keycloak', 'user-1');
      expect(loaded!.accessToken.tokenType, TokenType.dpop);
      expect(broken.calls, ['dpopPublicJwk']);
      // Without a key the tokens are kept as they are.
      expect(
        await service(null).loadAuthorizedClient('keycloak', 'user-1'),
        isNotNull,
      );
    });
  });

  group('logout', () {
    test('deletes the DPoP key, so the next login gets a new one', () async {
      final platform = FakePlatformKey()..install();
      final fixture = await LoginFixture.create();
      final dPoPKey = PlatformDPoPKey(fixture.store);
      await dPoPKey.load();
      final service = fixture.service(dPoPKey: dPoPKey);
      await service.login('keycloak');

      await service.logout();
      expect(platform.calls, contains('dpopDelete'));
      expect(platform.key, isNull);
      expect(service.isLoggedIn, isFalse);
    });

    test('a failing deletion does not stop the logout', () async {
      final platform = FakePlatformKey()..install();
      final fixture = await LoginFixture.create();
      final service = fixture.service(
        dPoPKey: PlatformDPoPKey(fixture.store),
      );
      await service.login('keycloak');
      platform.failure = PlatformException(code: 'dpop_key');

      await service.logout();
      expect(service.isLoggedIn, isFalse);
      expect(
        await fixture.store.read(NativeOAuth2LoginService.sessionKey),
        isNull,
      );
    });

    test('nobody logged in: the key stays', () async {
      final platform = FakePlatformKey()..install();
      final fixture = await LoginFixture.create();
      await fixture.service(dPoPKey: PlatformDPoPKey(fixture.store)).logout();
      expect(platform.calls, isNot(contains('dpopDelete')));
    });
  });

  group('the platformDPoPKey bean', () {
    const registration = [
      'spring.security.oauth2.client.registration.keycloak.client-id=neon-app',
      'spring.security.oauth2.client.registration.keycloak.authorization-grant-type=authorization_code',
      'spring.security.oauth2.client.registration.keycloak.redirect-uri=neonbooks:/oauth2/callback',
      'spring.security.oauth2.client.provider.keycloak.authorization-uri=https://sso.test/auth',
      'spring.security.oauth2.client.provider.keycloak.token-uri=https://sso.test/token',
    ];
    final runner = const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withAutoConfiguration(springSecurityCoreAutoConfiguration)
        .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
        .withAutoConfiguration(
          springBootStarterFlutterSecurityAutoConfiguration,
          const AutoConfigurationModule(
            before: [
              'springBootStarterOauth2ClientAutoConfiguration',
              'springBootStarterFeignAutoConfiguration',
            ],
          ),
        )
        .withBean<HttpTransport>(MockHttpTransport.new);

    test('replaces the client\'s key of one run, and is used', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        on(platform);
        runner.withPropertyValues(registration).run((context) {
          expect(context.startupFailure, isNull);
          expect(context.getBeanNamesForType<DPoPKey>(), ['platformDPoPKey']);
          final key = context.getBean<PlatformDPoPKey>();
          expect(
            context.getBean<SecretStoreOAuth2AuthorizedClientService>().dPoPKey,
            same(key),
          );
          expect(
            context.getBean<NativeOAuth2LoginService>().dPoPKey,
            same(key),
          );
        });
      }
    });

    test('none without a registration, none in a browser', () {
      on(TargetPlatform.iOS);
      runner.run((context) {
        expect(context, doesNotHaveBean<DPoPKey>());
      });
      // A browser: the web profile (the WebCrypto key of the spa mode is
      // not this one).
      runner
          .withPropertyValues(registration)
          .withPropertyValues(['spring.profiles.active=web'])
          .withBean<BrowserPage>(_FakePage.new)
          .run((context) {
            expect(context.startupFailure, isNull);
            expect(context, doesNotHaveBean<PlatformDPoPKey>());
          });
    });

    test('the application\'s own key wins and is not deleted', () {
      on(TargetPlatform.android);
      final own = SoftwareDPoPKey.generate();
      runner.withPropertyValues(registration).withBean<DPoPKey>(() => own).run((
        context,
      ) {
        expect(context.getBean<DPoPKey>(), same(own));
        expect(context, doesNotHaveBean<PlatformDPoPKey>());
        expect(context.getBean<NativeOAuth2LoginService>().dPoPKey, isNull);
      });
    });
  });
}

class _FakePage implements BrowserPage {
  @override
  Uri get location => Uri.parse('http://localhost:5050/');

  @override
  String? cookie(String name) => null;

  @override
  void navigate(Uri url) {}
}
