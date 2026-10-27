// The JOSE primitives under the JWT decoder: which keys may verify, the
// checks that come before any signature maths (key size, exponent, curve
// point, `alg` / `use` restrictions, signature length), the strict base64url
// and size limits of parsing, and verifyCompactJws refusing what it cannot
// verify.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/ecc/ecc_fp.dart' as fp;
import 'package:pointycastle/export.dart'
    show
        ECCurve_secp256r1,
        ECCurve_secp384r1,
        ECCurve_secp521r1,
        ECDomainParameters,
        SHA256Digest;
import 'package:spring_boot_starter_security/src/jwt/jose.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt_decoder.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';

final RsaTestKey _rsa = testKeys.rsa;
final EcTestKey _ec = testKeys.ec;

SecretVerificationKey get _secret => SecretVerificationKey(testKeys.secret);

bool _verifies(String token, String alg, VerificationKey key) =>
    verifySignature(parseJws(token), JwsAlgorithm.from(alg)!, key);

String _withSignature(String token, List<int> signature) {
  final parts = token.split('.');
  return '${parts[0]}.${parts[1]}.${b64(signature)}';
}

Uint8List _signatureOf(String token) =>
    base64Url.decode(base64Url.normalize(token.split('.')[2]));

/// An HS256 token of exactly [length] characters, validly signed.
String _signedTokenOfLength(int length) {
  for (var extra = 0; extra < 4; extra++) {
    final header = b64Json({'alg': 'HS256', 'x': 'a' * extra});
    final want = length - header.length - 2 - 43;
    for (var n = want * 3 ~/ 4 - 12; n < want * 3 ~/ 4; n++) {
      final payload = b64Json({'pad': 'a' * n});
      if (payload.length == want) {
        final input = '$header.$payload';
        return '$input.'
            '${b64(testKeys.signature('HS256', ascii.encode(input)))}';
      }
    }
  }
  throw StateError('No token of $length characters');
}

ECDomainParameters _domain(String curve) => switch (curve) {
  'P-256' => ECCurve_secp256r1(),
  'P-384' => ECCurve_secp384r1(),
  _ => ECCurve_secp521r1(),
};

final Matcher _joseError = throwsA(isA<JoseException>());

void main() {
  group('RSA keys', () {
    test('an exponent of 1 never verifies, even a forged signature', () {
      final modulus = _rsa.publicKey.modulus!;
      final weak = RsaVerificationKey(modulus, BigInt.one);
      expect(weak.fits(JwsAlgorithm.rs256), isFalse);
      expect(weak.fits(JwsAlgorithm.ps256), isFalse);
      expect(
        RsaVerificationKey(
          modulus,
          BigInt.from(65537),
        ).fits(JwsAlgorithm.rs256),
        isTrue,
      );

      // With e = 1 the "signature" is the padded digest itself.
      final input = '${b64Json({'alg': 'RS256'})}.${b64Json({'sub': 'root'})}';
      final hash = SHA256Digest().process(ascii.encode(input));
      final digestInfo = [
        ...[0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01],
        ...[0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20],
        ...hash,
      ];
      final size = (modulus.bitLength + 7) ~/ 8;
      final forged = [
        0,
        1,
        ...List.filled(size - 3 - digestInfo.length, 0xff),
        0,
        ...digestInfo,
      ];
      final token = '$input.${b64(forged)}';
      expect(_verifies(token, 'RS256', weak), isFalse);
      expect(
        _verifies(token, 'RS256', RsaVerificationKey(modulus, BigInt.from(3))),
        isFalse,
      );
    });

    test('a modulus under 2048 bits never verifies', () {
      final small = RsaTestKey.generate(bits: 1024);
      final factory = TokenFactory(small, _ec, testKeys.secret);
      for (final alg in ['RS256', 'PS256']) {
        final token = factory.token(alg: alg);
        expect(
          _verifies(token, alg, small.verificationKey),
          isFalse,
          reason: alg,
        );
        expect(_verifies(token, alg, _rsa.verificationKey), isFalse);
      }
      expect(
        _verifies(testKeys.token(), 'RS256', _rsa.verificationKey),
        isTrue,
      );
    });

    test('RS* and PS* keys do not verify ES* or HS* tokens', () {
      for (final alg in ['ES256', 'HS256']) {
        expect(_rsa.verificationKey.fits(JwsAlgorithm.from(alg)!), isFalse);
      }
    });
  });

  group('EC keys', () {
    test('a key fits its own curve and nothing else', () {
      expect(_ec.verificationKey.fits(JwsAlgorithm.es256), isTrue);
      expect(_ec.verificationKey.fits(JwsAlgorithm.es384), isFalse);
      expect(_ec.verificationKey.fits(JwsAlgorithm.es512), isFalse);
      final p384 = EcTestKey.generate(crv: 'P-384');
      expect(p384.verificationKey.fits(JwsAlgorithm.es384), isTrue);
      expect(p384.verificationKey.fits(JwsAlgorithm.es256), isFalse);
    });

    test('an EC key never verifies RS*, PS* or HS* tokens', () {
      for (final alg in ['RS256', 'PS256', 'HS256']) {
        expect(_ec.verificationKey.fits(JwsAlgorithm.from(alg)!), isFalse);
      }
    });

    test('a point off the curve is refused', () {
      final key = _ec.verificationKey;
      expect(key.isOnCurve, isTrue);
      final off = EcVerificationKey('P-256', key.x, key.y + BigInt.one);
      expect(off.isOnCurve, isFalse);
      expect(off.fits(JwsAlgorithm.es256), isFalse);
    });

    test('an unknown curve is refused', () {
      final key = EcVerificationKey('P-192', BigInt.one, BigInt.two);
      expect(key.isOnCurve, isFalse);
      for (final algorithm in JwsAlgorithm.values) {
        expect(key.fits(algorithm), isFalse, reason: algorithm.name);
      }
      expect(
        parseJwk({
          'kty': 'EC',
          'crv': 'P-192',
          'x': b64([1]),
          'y': b64([2]),
        }),
        isNull,
      );
    });

    for (final curve in ['P-256', 'P-384', 'P-521']) {
      test('$curve: coordinates are reduced, congruent ones are refused', () {
        final domain = _domain(curve);
        final p = (domain.curve as fp.ECCurve).q!;
        final good = EcTestKey.generate(crv: curve).verificationKey;
        expect(good.isOnCurve, isTrue);

        EcVerificationKey with_(BigInt x, BigInt y) =>
            EcVerificationKey(curve, x, y);
        expect(with_(good.x - p, good.y).isOnCurve, isFalse, reason: 'x < 0');
        expect(with_(good.x, good.y - p).isOnCurve, isFalse, reason: 'y < 0');
        expect(with_(good.x + p, good.y).isOnCurve, isFalse, reason: 'x > p');
        expect(with_(good.x, good.y + p).isOnCurve, isFalse, reason: 'y > p');

        // x = p is x = 0, where y^2 = b has a solution on these curves.
        final b = domain.curve.b!.toBigInteger()!;
        final y = b.modPow((p + BigInt.one) >> 2, p);
        expect(with_(BigInt.zero, y).isOnCurve, isTrue);
        expect(with_(p, y).isOnCurve, isFalse, reason: 'x = p');
      });
    }
  });

  group('verifySignature', () {
    test('a key restricted to another alg does not verify', () {
      final token = testKeys.token();
      RsaVerificationKey key(String? algorithm) => RsaVerificationKey(
        _rsa.publicKey.modulus!,
        _rsa.publicKey.exponent!,
        algorithm: algorithm,
      );
      expect(_verifies(token, 'RS256', key(null)), isTrue);
      expect(_verifies(token, 'RS256', key('RS256')), isTrue);
      expect(_verifies(token, 'RS256', key('RS384')), isFalse);
      expect(_verifies(token, 'RS256', key('PS256')), isFalse);
    });

    test('a key meant for encryption does not verify', () {
      final token = testKeys.token();
      RsaVerificationKey key(String? use) => RsaVerificationKey(
        _rsa.publicKey.modulus!,
        _rsa.publicKey.exponent!,
        use: use,
      );
      expect(_verifies(token, 'RS256', key('sig')), isTrue);
      expect(_verifies(token, 'RS256', key(null)), isTrue);
      expect(_verifies(token, 'RS256', key('enc')), isFalse);
    });

    test('a secret under the hash size does not verify', () {
      final short = List.generate(16, (i) => i);
      final token = TokenFactory(_rsa, _ec, short).token(alg: 'HS256');
      expect(_verifies(token, 'HS256', SecretVerificationKey(short)), isFalse);
      final enough = List.generate(32, (i) => i);
      expect(
        _verifies(
          TokenFactory(_rsa, _ec, enough).token(alg: 'HS256'),
          'HS256',
          SecretVerificationKey(enough),
        ),
        isTrue,
      );
    });

    test('HS384 and HS512 need 384 and 512 bits', () {
      final secret = List.generate(32, (i) => i);
      final factory = TokenFactory(_rsa, _ec, secret);
      for (final alg in ['HS384', 'HS512']) {
        expect(
          _verifies(
            factory.token(alg: alg),
            alg,
            SecretVerificationKey(secret),
          ),
          isFalse,
          reason: alg,
        );
      }
    });

    for (final alg in ['RS256', 'PS256', 'ES256']) {
      test('$alg: a signature of the wrong length is not verified', () {
        final token = testKeys.token(alg: alg);
        final key = alg.startsWith('ES')
            ? _ec.verificationKey
            : _rsa.verificationKey;
        final signature = _signatureOf(token);
        expect(_verifies(token, alg, key), isTrue);
        expect(
          _verifies(_withSignature(token, [0, ...signature]), alg, key),
          isFalse,
          reason: 'a byte too long',
        );
        expect(
          _verifies(_withSignature(token, signature.sublist(1)), alg, key),
          isFalse,
          reason: 'a byte too short',
        );
        expect(_verifies(_withSignature(token, []), alg, key), isFalse);
      });
    }

    test('a signature that makes the primitives throw is not verified', () {
      final token = testKeys.token();
      final tooBig = List.filled(256, 0xff);
      for (final alg in ['RS256', 'PS256']) {
        expect(
          _verifies(_withSignature(token, tooBig), alg, _rsa.verificationKey),
          isFalse,
          reason: alg,
        );
      }
      final zeros = List.filled(64, 0);
      expect(
        _verifies(
          _withSignature(testKeys.token(alg: 'ES256'), zeros),
          'ES256',
          _ec.verificationKey,
        ),
        isFalse,
      );
    });

    test('a key of the wrong family does not verify the token', () {
      expect(_verifies(testKeys.token(), 'RS256', _secret), isFalse);
      expect(
        _verifies(testKeys.token(), 'RS256', _ec.verificationKey),
        isFalse,
      );
      expect(
        _verifies(testKeys.token(alg: 'HS256'), 'HS256', _rsa.verificationKey),
        isFalse,
      );
    });
  });

  group('parseJws', () {
    test('accepts a token of the longest size, refuses one character more', () {
      final longest = _signedTokenOfLength(maxTokenLength);
      expect(longest.length, maxTokenLength);
      expect(parseJws(longest).algorithmName, 'HS256');
      final tooLong = _signedTokenOfLength(maxTokenLength + 1);
      expect(
        () => parseJws(tooLong),
        throwsA(
          isA<JoseException>().having(
            (e) => e.message,
            'message',
            'The token is too long',
          ),
        ),
      );
    });

    test('base64url is the URL alphabet without padding', () {
      final token = testKeys.token(alg: 'HS256');
      final parts = token.split('.');
      expect(parseJws(token).signature, hasLength(32));

      // 32 bytes are 43 characters; the standard encoding pads to 44.
      expect(
        () => parseJws('${parts[0]}.${parts[1]}.${parts[2]}='),
        _joseError,
      );
      expect(
        () => parseJws('${parts[0]}=.${parts[1]}.${parts[2]}'),
        _joseError,
      );
      expect(() => parseJws('${parts[0]}.${parts[1]}.AAAAA'), _joseError);
      expect(() => parseJws('${parts[0]}.${parts[1]}.A A='), _joseError);

      // A payload whose encoding has '_' or '-': the '/' and '+' of the
      // standard alphabet decode to the same bytes, and are refused.
      for (var i = 1; i < 64; i++) {
        final payload = b64Json({'x': '?' * i});
        final swapped = payload.replaceAll('_', '/').replaceAll('-', '+');
        if (swapped == payload) {
          continue;
        }
        expect(
          parseJws('${parts[0]}.$payload.${parts[2]}').claims['x'],
          isNotNull,
        );
        expect(
          () => parseJws('${parts[0]}.$swapped.${parts[2]}'),
          _joseError,
          reason: swapped,
        );
        return;
      }
      fail('no payload with a character outside the standard alphabet');
    });

    test('the header must be a safe JWS header', () {
      String token(Map<String, Object?> header) =>
          '${b64Json(header)}.${b64Json({'sub': 'a'})}.${b64([1, 2, 3])}';
      expect(parseJws(token({'alg': 'HS256', 'kid': 'k'})).keyId, 'k');
      for (final header in [
        {
          'alg': 'HS256',
          'crit': ['exp'],
        },
        {'alg': 'HS256', 'cty': 'jwt'},
        <String, Object?>{},
        {'alg': 5},
        {'alg': 'HS256', 'kid': 5},
        {'alg': 'HS256', 'kid': null},
      ]) {
        expect(() => parseJws(token(header)), _joseError, reason: '$header');
      }
    });
  });

  group('verifyCompactJws', () {
    final token = testKeys.token(alg: 'HS256');

    test('verifies a token and only a token with three parts', () {
      expect(verifyCompactJws(token, _secret), isTrue);
      expect(verifyCompactJws('$token.extra', _secret), isFalse);
      expect(verifyCompactJws('$token.', _secret), isFalse);
      expect(
        verifyCompactJws(token.substring(0, token.lastIndexOf('.')), _secret),
        isFalse,
      );
      expect(verifyCompactJws('', _secret), isFalse);
    });

    test('verifies a token of the longest size, not one character more', () {
      expect(
        verifyCompactJws(_signedTokenOfLength(maxTokenLength), _secret),
        isTrue,
      );
      expect(
        verifyCompactJws(_signedTokenOfLength(maxTokenLength + 1), _secret),
        isFalse,
      );
    });

    test('an unknown algorithm or none is not verified', () {
      for (final alg in ['none', 'HS257', 'hs256']) {
        final input = '${b64Json({'alg': alg})}.${b64Json({'sub': 'a'})}';
        final signature = testKeys.signature('HS256', ascii.encode(input));
        expect(
          verifyCompactJws('$input.${b64(signature)}', _secret),
          isFalse,
          reason: alg,
        );
        expect(verifyCompactJws('$input.', _secret), isFalse, reason: alg);
      }
      final noAlg = '${b64Json({'typ': 'JWT'})}.${b64Json({})}';
      expect(
        verifyCompactJws(
          '$noAlg.${b64(testKeys.signature('HS256', ascii.encode(noAlg)))}',
          _secret,
        ),
        isFalse,
      );
    });

    test('a critical header is not verified, even signed', () {
      final input =
          '${b64Json({
            'alg': 'HS256',
            'crit': ['exp'],
          })}.${b64Json({'sub': 'a'})}';
      final signature = testKeys.signature('HS256', ascii.encode(input));
      expect(verifyCompactJws('$input.${b64(signature)}', _secret), isFalse);
    });

    test('malformed parts are not verified', () {
      final [header, payload, signature] = token.split('.');
      for (final bad in [
        '@@@.$payload.$signature',
        '$header.$payload.@@@',
        '$header.$payload.$signature=',
        '${b64(utf8.encode('[1]'))}.$payload.$signature',
        '${b64(utf8.encode('{'))}.$payload.$signature',
      ]) {
        expect(verifyCompactJws(bad, _secret), isFalse, reason: bad);
      }
    });

    test('a signature that does not match is not verified', () {
      final [header, payload, _] = token.split('.');
      expect(
        verifyCompactJws(
          '$header.$payload.${b64(List.filled(32, 1))}',
          _secret,
        ),
        isFalse,
      );
      expect(verifyCompactJws(token, _rsa.verificationKey), isFalse);
    });
  });
}
