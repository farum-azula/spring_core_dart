// The app's DPoP key on the real platform: the Secure Enclave or the
// Keychain (iOS, macOS; the simulator has no Secure Enclave, so its
// Keychain key runs there), the Android Keystore (StrongBox or the TEE),
// the SecretStore (Windows, Linux). Each proof's signature is checked
// against the public JWK in its header with pointycastle, not with the
// code tested. Run on a device, simulator or desktop with
//   flutter test integration_test/dpop_key_test.dart -d macos
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pointycastle/export.dart'
    show
        ECCurve_secp256r1,
        ECDSASigner,
        ECPublicKey,
        ECSignature,
        PublicKeyParameter,
        SHA256Digest;
import 'package:spring_boot_starter_flutter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

List<int> _unb64(String text) => base64Url.decode(base64Url.normalize(text));

BigInt _int(List<int> bytes) =>
    bytes.fold(BigInt.zero, (value, b) => (value << 8) | BigInt.from(b));

Map<String, Object?> _json(String part) =>
    jsonDecode(utf8.decode(_unb64(part))) as Map<String, Object?>;

/// The header and claims of [proof] after checking its ES256 signature
/// (raw R || S) by the public JWK in its own header.
(Map<String, Object?>, Map<String, Object?>) _verified(String proof) {
  final parts = proof.split('.');
  expect(parts, hasLength(3));
  final header = _json(parts[0]);
  final jwk = header['jwk']! as Map<String, Object?>;
  expect(jwk.keys.toSet(), {'kty', 'crv', 'x', 'y'}, reason: 'public only');
  final signature = _unb64(parts[2]);
  expect(signature, hasLength(64), reason: 'raw R || S, not DER');
  final domain = ECCurve_secp256r1();
  final point = domain.curve.createPoint(
    _int(_unb64(jwk['x']! as String)),
    _int(_unb64(jwk['y']! as String)),
  );
  final verifier = ECDSASigner(SHA256Digest())
    ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(point, domain)));
  expect(
    verifier.verifySignature(
      Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}')),
      ECSignature(_int(signature.sublist(0, 32)), _int(signature.sublist(32))),
    ),
    isTrue,
    reason: 'signed by the key in the header',
  );
  return (header, _json(parts[1]));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final key = PlatformDPoPKey(PlatformSecretStore());
  // Each test starts from no key, and leaves none behind.
  setUp(key.delete);
  tearDown(key.delete);

  testWidgets('makes the key at the first proof and signs with it', (
    _,
  ) async {
    final proof = await DPoPProofBuilder(key).build(
      method: 'POST',
      url: Uri.parse('https://sso.example/realms/neon/token?x=1'),
    );
    final (header, claims) = _verified(proof);
    expect(header['typ'], 'dpop+jwt');
    expect(header['alg'], 'ES256');
    expect(header['jwk'], key.publicJwk);
    expect(claims['htm'], 'POST');
    expect(claims['htu'], 'https://sso.example/realms/neon/token');

    final storage = key.storage;
    debugPrint('DPoP key on $defaultTargetPlatform: ${storage?.name}');
    expect(storage, switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => anyOf(
        DPoPKeyStorage.secureEnclave,
        DPoPKeyStorage.keychain,
      ),
      TargetPlatform.android => anyOf(
        DPoPKeyStorage.strongBox,
        DPoPKeyStorage.trustedEnvironment,
        DPoPKeyStorage.software,
      ),
      _ => DPoPKeyStorage.secretStore,
    });

    // API calls: a new proof each, with the token's hash; the same key.
    final call = await DPoPProofBuilder(key).build(
      method: 'GET',
      url: Uri.parse('https://api.example/orders'),
      accessToken: 'access-token',
    );
    final (callHeader, callClaims) = _verified(call);
    expect(callHeader['jwk'], header['jwk']);
    expect(callClaims['ath'], sha256Base64Url('access-token'));
    expect(callClaims['jti'], isNot(claims['jti']));
  });

  testWidgets('a WebSocket handshake: htu is the http(s) URL', (_) async {
    final headers = await OAuth2AccessTokenHeaders(dPoPKey: key).of(
      OAuth2AccessToken(TokenType.dpop, 'access-token'),
      method: 'GET',
      url: Uri.parse('wss://api.example/ws/support'),
    );
    expect(headers['Authorization'], 'DPoP access-token');
    final (_, claims) = _verified(headers['DPoP']!);
    expect(claims['htu'], 'https://api.example/ws/support');
  });

  testWidgets('the key survives: another object finds the same key', (
    _,
  ) async {
    await key.load();
    final again = PlatformDPoPKey(PlatformSecretStore());
    await again.load();
    expect(
      JwkThumbprint.of(again.publicJwk),
      JwkThumbprint.of(key.publicJwk),
    );
    _verified(
      await DPoPProofBuilder(
        again,
      ).build(method: 'GET', url: Uri.parse('https://api.example/')),
    );
  });

  testWidgets('delete: tokens of the old key are dropped, a new key', (
    _,
  ) async {
    await key.load();
    final old = JwkThumbprint.of(key.publicJwk);
    await key.delete();

    // Another object still holding the old public key: the platform has
    // no key to sign with, it says so and forgets it.
    final stale = PlatformDPoPKey(PlatformSecretStore());
    await key.load();
    final fresh = JwkThumbprint.of(key.publicJwk);
    expect(fresh, isNot(old));
    await stale.load();
    expect(JwkThumbprint.of(stale.publicJwk), fresh);
  });

  testWidgets('a key gone under the app: no_key, then a new key', (_) async {
    await key.load();
    final holder = PlatformDPoPKey(PlatformSecretStore());
    await holder.load();
    await key.delete(); // the Keystore wiped, as far as holder knows

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      // The desktop key signs in memory: it keeps working until restart.
      return;
    }
    await expectLater(
      holder.sign(Uint8List.fromList(utf8.encode('x'))),
      throwsA(
        isA<PlatformDPoPKeyException>().having((e) => e.code, 'code', 'no_key'),
      ),
    );
    _verified(
      await DPoPProofBuilder(
        holder,
      ).build(method: 'GET', url: Uri.parse('https://api.example/')),
    );
  });

  testWidgets('the application gets it as its DPoPKey bean', (_) async {
    final context =
        await SpringApplication(
          const [],
          // This package's module before the OAuth2 client's, as the
          // generated main.spring.dart orders them.
          autoConfigurations: [
            springBootAutoConfiguration,
            springBootStarterFeignAutoConfiguration,
            springSecurityCoreAutoConfiguration,
            springBootStarterFlutterSecurityAutoConfiguration,
            springBootStarterOauth2ClientAutoConfiguration,
          ],
          bannerMode: BannerMode.off,
        ).runAsync(const [
          // Only the classpath (see secret_store_test.dart).
          '--spring.config.location=optional:classpath:/',
          '--spring.security.oauth2.client.registration.it.client-id=neon-app',
          '--spring.security.oauth2.client.registration.it.authorization-grant-type=authorization_code',
          '--spring.security.oauth2.client.registration.it.redirect-uri=books.neon.app:/cb',
          '--spring.security.oauth2.client.provider.it.authorization-uri=https://sso.example/auth',
          '--spring.security.oauth2.client.provider.it.token-uri=https://sso.example/token',
        ]);
    addTearDown(context.close);

    expect(context.getBeanNamesForType(DPoPKey), ['platformDPoPKey']);
    final bean = context.getBean<DPoPKey>();
    _verified(
      await DPoPProofBuilder(
        bean,
      ).build(method: 'GET', url: Uri.parse('https://api.example/')),
    );
  });
}
