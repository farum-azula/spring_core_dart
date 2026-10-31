// The ID token decoder that verifies signatures with the provider's JWK
// Set (for Sign in with Apple's identity token, which an app gets from the
// operating system, not from a TLS token endpoint): the RFC 7515 vectors
// of the primitives, RS256 and ES256 tokens signed with test keys, and the
// attacks (a changed token, alg none, HS256 with the public key, keys
// inside the token, an unknown kid, a weak RSA key, another issuer,
// audience or an expired token).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/crypto_primitives.dart'
    as primitives;
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

const _jwks = 'https://appleid.apple.test/auth/keys';
const _issuer = 'https://appleid.apple.test';
const _clientId = 'books.neon.app';

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int> _unb64(String text) => base64Url.decode(base64Url.normalize(text));

BigInt _int(List<int> bytes) =>
    bytes.fold(BigInt.zero, (value, b) => (value << 8) | BigInt.from(b));

Uint8List _bytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

HttpResponse _jsonResponse(int status, Object json) => HttpResponse(
  status,
  headers: HttpHeaders({HttpHeaders.contentTypeHeader: 'application/json'}),
  body: utf8.encode(jsonEncode(json)),
);

SecureRandom _random() {
  final random = Random.secure();
  return FortunaRandom()..seed(
    KeyParameter(
      Uint8List.fromList(List.generate(32, (_) => random.nextInt(256))),
    ),
  );
}

final class _RsaKey {
  _RsaKey(int bits, this.kid) {
    final pair =
        (RSAKeyGenerator()..init(
              ParametersWithRandom(
                RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
                _random(),
              ),
            ))
            .generateKeyPair();
    publicKey = pair.publicKey;
    privateKey = pair.privateKey;
  }

  final String kid;
  late final RSAPublicKey publicKey;
  late final RSAPrivateKey privateKey;

  Map<String, Object?> get jwk => {
    'kty': 'RSA',
    'kid': kid,
    'use': 'sig',
    'alg': 'RS256',
    'n': _b64(
      _bytes(publicKey.modulus!, (publicKey.modulus!.bitLength + 7) ~/ 8),
    ),
    'e': _b64(_bytes(publicKey.exponent!, 3)),
  };

  String sign(Map<String, Object?> header, Map<String, Object?> claims) {
    final input =
        '${_b64(utf8.encode(jsonEncode(header)))}.'
        '${_b64(utf8.encode(jsonEncode(claims)))}';
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final signature = signer.generateSignature(
      Uint8List.fromList(ascii.encode(input)),
    );
    return '$input.${_b64(signature.bytes)}';
  }
}

void main() {
  group('the primitives (RFC 7515 vectors)', () {
    test('A.2: RS256', () {
      const n =
          'ofgWCuLjybRlzo0tZWJjNiuSfb4p4fAkd_wWJcyQoTbji9k0l8W26mPddxHmfHQp-'
          'Vaw-4qPCJrcS2mJPMEzP1Pt0Bm4d4QlL-yRT-SFd2lZS-pCgNMsD1W_YpRPEwOWvG6'
          'b32690r2jZ47soMZo9wGzjb_7OMg0LOL-bSf63kpaSHSXndS5z5rexMdbBYUsLA9e'
          '-KXBdQOS-UTo7WTBEMa2R2CapHg665xsmtdVMTBQY4uDZlxvb3qCo5ZwKh9kG4LT6'
          '_I5IhlJH7aGhyxXFvUK-DWNmoudF8NAco9_h9iaGNj8q2ethFkMLs91kzk2PAcDTW'
          '9gb54h4FRWyuXpoQ';
      const jws =
          'eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzOD'
          'AsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.cC4hiUPoj9'
          'Eetdgtv3hF80EGrhuB__dzERat0XF9g2VtQgr9PJbu3XOiZj5RZmh7AAuHIm4Bh-'
          '0Qc_lF5YKt_O8W2Fp5jujGbds9uJdbF9CUAr7t1dnZcAcQjbKBYNX4BAynRFdiuB'
          '--f_nZLgrnbyTyWzO75vRK5h6xBArLIARNPvkSjtQBMHlb1L07Qe7K0GarZRmB_eS'
          'N9383LcOLn6_dO--xi12jzDwusC-eOkHWEsqtFZESc6BfI7noOPqvhJ1phCnvWh6I'
          'eYI2w9QOYEUipUTI8np6LbgGY9Fs98rqVt5AXLIhWkWywlVmtVrBp0igcN_IoypGl'
          'UPQGe77Rw';
      final parts = jws.split('.');
      final input = Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}'));
      final signature = Uint8List.fromList(_unb64(parts[2]));
      final modulus = _int(_unb64(n));
      final exponent = BigInt.from(65537);
      expect(
        primitives.rsaPkcs1Sha256Verify(modulus, exponent, input, signature),
        isTrue,
      );
      final changed = Uint8List.fromList(signature)..[10] ^= 1;
      expect(
        primitives.rsaPkcs1Sha256Verify(modulus, exponent, input, changed),
        isFalse,
      );
    });

    test('A.3: ES256', () {
      final x = _int(_unb64('f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU'));
      final y = _int(_unb64('x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0'));
      const jws =
          'eyJhbGciOiJFUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzOD'
          'AsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.DtEhU3ljbE'
          'g8L38VWAfUAqOyKAM6-Xx-F4GawxaepmXFCgfTjDxw5djxLa8ISlSApmWQxfKTUJ'
          'qPP3-Kg6NU1Q';
      final parts = jws.split('.');
      final input = Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}'));
      final signature = _unb64(parts[2]);
      expect(primitives.p256IsOnCurve(x, y), isTrue);
      expect(primitives.p256IsOnCurve(x, y + BigInt.one), isFalse);
      expect(
        primitives.p256Verify(
          x,
          y,
          input,
          _int(signature.sublist(0, 32)),
          _int(signature.sublist(32)),
        ),
        isTrue,
      );
      expect(
        primitives.p256Verify(
          x,
          y,
          input,
          _int(signature.sublist(0, 32)) + BigInt.one,
          _int(signature.sublist(32)),
        ),
        isFalse,
      );
    });
  });

  group('JwkSetOidcIdTokenDecoder', () {
    late _RsaKey key;
    late _RsaKey rotated;
    late MockHttpTransport transport;
    late List<Map<String, Object?>> published;
    var now = DateTime.utc(2026, 10, 29, 12);

    final registration = CommonOAuth2Provider.apple
        .getBuilder('apple')
        .clientId(_clientId)
        .issuerUri(_issuer)
        .jwkSetUri(_jwks)
        .build();

    setUpAll(() {
      key = _RsaKey(2048, 'apple-1');
      rotated = _RsaKey(2048, 'apple-2');
    });

    setUp(() {
      now = DateTime.utc(2026, 10, 29, 12);
      published = [key.jwk];
      transport = MockHttpTransport();
      transport
          .when(HttpMethod.get, _jwks)
          .respondWith((_) => _jsonResponse(200, {'keys': published}));
    });

    Map<String, Object?> claims({
      String iss = _issuer,
      Object aud = _clientId,
      Duration age = Duration.zero,
    }) {
      final iat = now.subtract(age).millisecondsSinceEpoch ~/ 1000;
      return {
        'iss': iss,
        'aud': aud,
        'sub': '000123.abc',
        'iat': iat,
        'exp': iat + 600,
        'nonce': 'n',
      };
    }

    JwkSetOidcIdTokenDecoder decoder({Set<String> algorithms = const {}}) =>
        JwkSetOidcIdTokenDecoder(
          transport,
          algorithms: algorithms.isEmpty ? const {'RS256'} : algorithms,
          clock: () => now,
        );

    Matcher refused([String? text]) => throwsA(
      isA<OAuth2AuthenticationException>().having(
        (e) => e.error.errorCode,
        'errorCode',
        OAuth2ErrorCodes.invalidIdToken,
      ),
    );

    test('a token signed by a key of the set is accepted', () async {
      final token = key.sign({'alg': 'RS256', 'kid': 'apple-1'}, claims());
      final idToken = await decoder().decode(registration, token);
      expect(idToken.subject, '000123.abc');
      expect(transport.requests, hasLength(1));
      // The keys are cached.
      await decoder().decode(registration, token);
    });

    test('a changed token, another key or a removed signature is '
        'refused', () async {
      final token = key.sign({'alg': 'RS256', 'kid': 'apple-1'}, claims());
      final parts = token.split('.');
      final forgedClaims = _b64(
        utf8.encode(jsonEncode({...claims(), 'sub': 'victim'})),
      );
      await expectLater(
        decoder().decode(
          registration,
          '${parts[0]}.$forgedClaims.${parts[2]}',
        ),
        refused(),
      );
      final other = _RsaKey(2048, 'apple-1');
      await expectLater(
        decoder().decode(
          registration,
          other.sign({'alg': 'RS256', 'kid': 'apple-1'}, claims()),
        ),
        refused(),
      );
      await expectLater(
        decoder().decode(registration, '${parts[0]}.${parts[1]}.'),
        refused(),
      );
    });

    test('alg none and HS256 signed with the public key are refused', () async {
      String unsigned(String alg) =>
          '${_b64(utf8.encode(jsonEncode({'alg': alg, 'kid': 'apple-1'})))}.'
          '${_b64(utf8.encode(jsonEncode(claims())))}.';
      await expectLater(
        decoder().decode(registration, unsigned('none')),
        refused(),
      );
      final header = _b64(
        utf8.encode(jsonEncode({'alg': 'HS256', 'kid': 'apple-1'})),
      );
      final body = _b64(utf8.encode(jsonEncode(claims())));
      final mac = HMac(SHA256Digest(), 64)
        ..init(KeyParameter(Uint8List.fromList(utf8.encode('${key.jwk}'))));
      final tag = mac.process(
        Uint8List.fromList(ascii.encode('$header.$body')),
      );
      await expectLater(
        decoder().decode(registration, '$header.$body.${_b64(tag)}'),
        refused(),
      );
    });

    // It accepted any typ: a logout token (or an access token) the
    // provider signed with the same keys passed as an ID token, while the
    // server's OidcIdTokenDecoderFactory (JwtTypeValidator.jwt(), as in
    // Spring Security 7.1) refuses it.
    test('the typ must be JWT (any case), blank or missing, as on a '
        'server', () async {
      for (final typ in <Object?>[null, 'JWT', 'jwt', 'Jwt', '', '  ']) {
        final token = key.sign({
          'alg': 'RS256',
          'kid': 'apple-1',
          'typ': ?typ,
        }, claims());
        expect(
          (await decoder().decode(registration, token)).subject,
          '000123.abc',
          reason: '$typ',
        );
      }
      for (final typ in <Object?>[
        'logout+jwt',
        'at+jwt',
        'secevent+jwt',
        'dpop+jwt',
        'application/jwt',
        'JOSE',
        'id_token+jwt',
        ' JWT ',
        42,
      ]) {
        await expectLater(
          decoder().decode(
            registration,
            key.sign({'alg': 'RS256', 'kid': 'apple-1', 'typ': typ}, claims()),
          ),
          throwsA(
            isA<OAuth2AuthenticationException>().having(
              (e) => e.error.description,
              'description',
              'An error occurred while attempting to decode the Jwt: the '
                  'given typ value needs to be one of [JWT]',
            ),
          ),
          reason: '$typ',
        );
      }
    });

    test('keys inside the token are never used', () async {
      final attacker = _RsaKey(2048, 'apple-1');
      for (final extra in [
        {'jwk': attacker.jwk},
        {'jku': 'https://evil.test/keys'},
        {'x5u': 'https://evil.test/cert'},
        {
          'crit': ['exp'],
        },
      ]) {
        await expectLater(
          decoder().decode(
            registration,
            attacker.sign({
              'alg': 'RS256',
              'kid': 'apple-1',
              ...extra,
            }, claims()),
          ),
          refused(),
          reason: '$extra',
        );
      }
    });

    test('an unknown kid fetches the keys once more (rotation), at most '
        'once a minute', () async {
      final shared = decoder();
      await shared.decode(
        registration,
        key.sign({'alg': 'RS256', 'kid': 'apple-1'}, claims()),
      );
      expect(transport.requests, hasLength(1));
      published = [key.jwk, rotated.jwk];
      now = now.add(const Duration(minutes: 2));
      final token = rotated.sign(
        {'alg': 'RS256', 'kid': 'apple-2'},
        claims(),
      );
      expect((await shared.decode(registration, token)).subject, isNotNull);
      expect(transport.requests, hasLength(2));
      final fetches = transport.requests.length;
      // A flood of unknown kids does not flood the provider.
      for (var i = 0; i < 5; i++) {
        await expectLater(
          shared.decode(
            registration,
            rotated.sign({'alg': 'RS256', 'kid': 'unknown-$i'}, claims()),
          ),
          refused(),
        );
      }
      expect(transport.requests.length, fetches);
    });

    // The minute between fetches was measured on the wall clock alone:
    // set back 2 h, the keys of a rotation were not fetched for 2 h.
    test('a clock set back does not hold off the keys of a rotation', () async {
      final shared = decoder();
      await shared.decode(
        registration,
        key.sign({'alg': 'RS256', 'kid': 'apple-1'}, claims()),
      );
      expect(transport.requests, hasLength(1));
      published = [key.jwk, rotated.jwk];
      now = now.subtract(const Duration(hours: 2));
      final token = rotated.sign({'alg': 'RS256', 'kid': 'apple-2'}, claims());
      expect((await shared.decode(registration, token)).subject, isNotNull);
      expect(transport.requests, hasLength(2));
      // Still at most once a minute after that.
      await expectLater(
        shared.decode(
          registration,
          rotated.sign({'alg': 'RS256', 'kid': 'unknown'}, claims()),
        ),
        refused(),
      );
      expect(transport.requests, hasLength(2));
    });

    test('a weak RSA key in the set is never used', () async {
      final weak = _RsaKey(1024, 'weak');
      published = [weak.jwk];
      await expectLater(
        decoder().decode(
          registration,
          weak.sign({'alg': 'RS256', 'kid': 'weak'}, claims()),
        ),
        refused(),
      );
    });

    // With e = 1, s^e mod n is s: the padded hash itself "verifies", so
    // anyone forges a token for a key published with it.
    test('an RSA key with an exponent of 1, an even or a huge one is never '
        'used', () async {
      final modulus = key.publicKey.modulus!;
      final length = (modulus.bitLength + 7) ~/ 8;
      Map<String, Object?> jwk(BigInt e, String kid) => {
        ...key.jwk,
        'kid': kid,
        'e': _b64(_bytes(e, (e.bitLength + 7) ~/ 8)),
      };
      final input =
          '${_b64(utf8.encode(jsonEncode({'alg': 'RS256', 'kid': 'e1'})))}.'
          '${_b64(utf8.encode(jsonEncode({...claims(), 'sub': 'victim'})))}';
      // EMSA-PKCS1-v1_5 of the input: 00 01 FF.. 00 DigestInfo(SHA-256).
      final digestInfo = [
        ...[0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01],
        ...[0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20],
        ...SHA256Digest().process(Uint8List.fromList(ascii.encode(input))),
      ];
      final padded = [
        0x00,
        0x01,
        ...List.filled(length - digestInfo.length - 3, 0xff),
        0x00,
        ...digestInfo,
      ];
      expect(
        primitives.rsaPkcs1Sha256Verify(
          modulus,
          BigInt.one,
          Uint8List.fromList(ascii.encode(input)),
          Uint8List.fromList(padded),
        ),
        isTrue,
        reason: 'the forgery works on the primitive itself',
      );
      published = [jwk(BigInt.one, 'e1')];
      await expectLater(
        decoder().decode(registration, '$input.${_b64(padded)}'),
        refused(),
      );
      for (final (e, kid) in [
        (BigInt.from(65538), 'even'),
        ((BigInt.one << 64) + BigInt.one, 'huge'),
      ]) {
        published = [jwk(e, kid)];
        await expectLater(
          decoder().decode(
            registration,
            key.sign({'alg': 'RS256', 'kid': kid}, claims()),
          ),
          refused(),
          reason: kid,
        );
      }
    });

    test('ES256 only when allowed; a DER signature is refused', () async {
      final ec = SoftwareDPoPKey.generate();
      published = [
        {...ec.publicJwk, 'kid': 'ec-1', 'use': 'sig'},
      ];
      final input =
          '${_b64(utf8.encode(jsonEncode({'alg': 'ES256', 'kid': 'ec-1'})))}.'
          '${_b64(utf8.encode(jsonEncode(claims())))}';
      final signature = await ec.sign(Uint8List.fromList(ascii.encode(input)));
      final token = '$input.${_b64(signature)}';
      await expectLater(decoder().decode(registration, token), refused());
      final es = decoder(algorithms: const {'RS256', 'ES256'});
      expect((await es.decode(registration, token)).subject, '000123.abc');
      final der = [0x30, 0x44, 0x02, 0x20, ...signature];
      await expectLater(
        es.decode(registration, '$input.${_b64(der)}'),
        refused(),
      );
    });

    test('the claims are checked: issuer, audience, expiry', () async {
      for (final bad in [
        claims(iss: 'https://evil.test'),
        claims(aud: 'books.neon.other'),
        claims(age: const Duration(hours: 1)),
      ]) {
        await expectLater(
          decoder().decode(
            registration,
            key.sign({'alg': 'RS256', 'kid': 'apple-1'}, bad),
          ),
          throwsA(isA<OAuth2AuthenticationException>()),
          reason: '$bad',
        );
      }
    });

    test('no JWK Set URI or an unreachable one refuses the token', () async {
      final without = ClientRegistration.withClientRegistration(
        registration,
      ).jwkSetUri(null).build();
      await expectLater(
        decoder().decode(
          without,
          key.sign({'alg': 'RS256', 'kid': 'apple-1'}, claims()),
        ),
        refused(),
      );
      transport = MockHttpTransport();
      transport
          .when(HttpMethod.get, _jwks)
          .respondWith((_) => _jsonResponse(500, {'error': 'down'}));
      await expectLater(
        decoder().decode(
          registration,
          key.sign({'alg': 'RS256', 'kid': 'apple-1'}, claims()),
        ),
        refused(),
      );
    });

    test('unknown algorithms cannot be configured', () {
      expect(
        () => JwkSetOidcIdTokenDecoder(transport, algorithms: const {'HS256'}),
        throwsArgumentError,
      );
      expect(
        () => JwkSetOidcIdTokenDecoder(transport, algorithms: const {}),
        throwsArgumentError,
      );
    });
  });
}
