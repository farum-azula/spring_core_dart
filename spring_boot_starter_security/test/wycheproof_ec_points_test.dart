// Project Wycheproof's ECDH public keys, whose invalid ones are the
// invalid-curve attacks (points of a weaker curve, off the curve, with
// coordinates out of range), as keys a JWT verifier must refuse: the JWK
// of the JWK Set (parseJwk), EcVerificationKey and the `jwk` header of a
// DPoP proof, which an attacker chooses.
//
// The vectors are in test/fixtures/wycheproof/ (README.md there). Only the
// uncompressed encodings (04 || x || y of the right length) are keys a
// JWK can hold; the other cases are encodings, not keys (compressed
// points, the point at infinity, a wrong length), and are counted and
// skipped. The DPoP proofs run all the invalid points and the first 20
// valid ones: those only reach the signature check, which is slow.
import 'dart:typed_data';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_security/src/jwt/jose.dart'
    show base64UrlToBigInt;
import 'package:test/test.dart';

import 'app/jwt/keys.dart' show b64, b64Json;
import 'wycheproof_support.dart';

/// The curve, its JWS algorithm, the bytes of a coordinate, how many cases
/// the file has by result, and how many of them are uncompressed points.
const List<
  (
    String,
    String,
    JwsAlgorithm,
    int,
    Map<String, int>,
    Map<String, int>,
  )
>
_curves = [
  (
    'ecdh_secp256r1_ecpoint_test.json',
    'P-256',
    JwsAlgorithm.es256,
    32,
    {'valid': 330, 'invalid': 24, 'acceptable': 1},
    {'valid': 330, 'invalid': 16},
  ),
  (
    'ecdh_secp384r1_ecpoint_test.json',
    'P-384',
    JwsAlgorithm.es384,
    48,
    {'valid': 771, 'invalid': 18, 'acceptable': 1},
    {'valid': 771, 'invalid': 16},
  ),
  (
    'ecdh_secp521r1_ecpoint_test.json',
    'P-521',
    JwsAlgorithm.es512,
    66,
    {'valid': 632, 'invalid': 28, 'acceptable': 1},
    {'valid': 632, 'invalid': 16},
  ),
];

/// The public key of [v] as JWK members, or `null` when it is not an
/// uncompressed point of [coordinate] bytes.
({Uint8List x, Uint8List y})? _point(Vector v, int coordinate) {
  final bytes = hexBytes(v.test['public']! as String);
  if (bytes.length != 1 + 2 * coordinate || bytes[0] != 4) {
    return null;
  }
  return (
    x: bytes.sublist(1, 1 + coordinate),
    y: bytes.sublist(1 + coordinate),
  );
}

void main() {
  for (final (file, crv, alg, size, counts, uncompressed) in _curves) {
    group('$crv ($file)', () {
      late final List<Vector> vectors;
      late final List<(Vector, ({Uint8List x, Uint8List y}))> points;

      setUpAll(() {
        vectors = loadVectors(file);
        points = [
          for (final v in vectors)
            if (_point(v, size) case final point?) (v, point),
        ];
      });

      test('has the vectors it was written for', () {
        expect(tally(vectors), counts);
        expect(tally([for (final (v, _) in points) v]), uncompressed);
      });

      test('a point is a key exactly when Wycheproof says it is valid', () {
        for (final (v, point) in points) {
          if (v.result == 'acceptable') {
            continue;
          }
          final jwk = {
            'kty': 'EC',
            'crv': crv,
            'x': b64(point.x),
            'y': b64(point.y),
          };
          final key = EcVerificationKey(
            crv,
            base64UrlToBigInt(jwk['x']!),
            base64UrlToBigInt(jwk['y']!),
          );
          final valid = v.result == 'valid';
          expect(key.isOnCurve, valid, reason: describe(v));
          expect(key.fits(alg), valid, reason: describe(v));
          // The JWK Set skips an invalid key; it never reads one.
          expect(parseJwk(jwk) != null, valid, reason: describe(v));
        }
      });

      test('a DPoP proof with that key in its jwk header is refused: the '
          'key before the signature', () async {
        final factory = DPoPProofJwtDecoderFactory();
        var valid = 0;
        for (final (v, point) in points) {
          // Every invalid point; of the valid ones, which only reach the
          // (slow) signature check, the first few.
          if (v.result == 'acceptable' ||
              (v.result == 'valid' && ++valid > 20)) {
            continue;
          }
          final header = {
            'typ': 'dpop+jwt',
            'alg': alg.name,
            'jwk': {
              'kty': 'EC',
              'crv': crv,
              'x': b64(point.x),
              'y': b64(point.y),
            },
          };
          final claims = {
            'jti': 'wycheproof-${v.tcId}',
            'htm': 'GET',
            'htu': 'http://localhost/api',
            'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          };
          final input = '${b64Json(header)}.${b64Json(claims)}';
          // A signature of the right length; no key made it.
          final proof = '$input.${b64(List.filled(2 * size, 1))}';
          final decoder = factory.createDecoder(
            DPoPProofContext(
              proof,
              method: 'GET',
              targetUri: Uri.parse('http://localhost/api'),
            ),
          );
          await expectLater(
            decoder.decode(proof),
            throwsA(
              isA<BadJwtException>().having(
                (e) => e.message,
                'message',
                v.result == 'valid'
                    ? 'The DPoP proof signature is not valid'
                    : 'The DPoP proof jwk is not a supported public key',
              ),
            ),
            reason: describe(v),
          );
        }
      });
    });
  }
}
