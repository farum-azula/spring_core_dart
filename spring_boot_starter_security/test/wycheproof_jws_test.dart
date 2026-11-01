// Project Wycheproof's signature and MAC vectors through the JWS verifier
// (verifySignatureBytes, the check under every JWT decoder and the DPoP
// proof decoder): the valid and the deliberately broken signatures that
// caught real attacks in other libraries (ECDSA with r = 0, malleable and
// truncated encodings, RSA PKCS#1 v1.5 padding forgeries, PSS salts and
// hashes, MACs with one bit changed).
//
// The vectors are in test/fixtures/wycheproof/ (README.md there). Every
// case must be answered as Wycheproof says: `valid` verifies, `invalid`
// does not. `acceptable` cases, where both answers are safe: the
// RSA signature whose DigestInfo lacks the NULL after the hash's OID
// (MissingNull) verifies, as pointycastle reads it (it cannot be made
// without the private key, so it forges nothing); the compressed points
// of the ECDH files are not JWK members and are skipped
// (wycheproof_ec_points_test.dart). The failure message names the file
// and tcId.
import 'dart:isolate';

import 'package:spring_boot_starter_security/src/jwt/jose.dart';
import 'package:spring_boot_starter_security/src/jwt/signature_primitives.dart'
    show hmacSha;
import 'package:test/test.dart';

import 'wycheproof_support.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Runs every case of [file] with [verify] and expects [expected]. The
/// cases are dealt to isolates: pure Dart big-number arithmetic is slow
/// (ES512 takes seconds), and the cases are independent.
Future<void> _check(
  String file,
  bool Function(Vector) verify, {
  required Map<String, int> counts,
  bool Function(Vector)? expected,
}) async {
  final vectors = loadVectors(file);
  expect(tally(vectors), counts, reason: '$file has changed');
  const isolates = 8;
  final size = (vectors.length / isolates).ceil();
  final answers = await Future.wait([
    for (var from = 0; from < vectors.length; from += size)
      Isolate.run(
        () => [
          for (final v in vectors.skip(from).take(size)) verify(v),
        ],
      ),
  ]);
  for (final (i, ok) in answers.expand((a) => a).indexed) {
    final v = vectors[i];
    expect(ok, expected?.call(v) ?? v.result == 'valid', reason: describe(v));
  }
}

void main() {
  group('ECDSA P1363 (ES256, ES384, ES512)', () {
    for (final (file, alg, counts) in [
      (
        'ecdsa_secp256r1_sha256_p1363_test.json',
        JwsAlgorithm.es256,
        {'valid': 173, 'invalid': 89},
      ),
      (
        'ecdsa_secp384r1_sha384_p1363_test.json',
        JwsAlgorithm.es384,
        {'valid': 193, 'invalid': 87},
      ),
      (
        'ecdsa_secp521r1_sha512_p1363_test.json',
        JwsAlgorithm.es512,
        {'valid': 231, 'invalid': 87},
      ),
    ]) {
      test(
        '$file: ${counts['valid']} valid, ${counts['invalid']} invalid',
        () async {
          await _check(
            file,
            (v) {
              // Some groups hold keys off the curve (no JWK for them): the
              // verifier must refuse their signatures.
              final point = v.group['publicKey']! as Map<String, Object?>;
              final key = EcVerificationKey(
                alg.curve!,
                hexBigInt(point['wx']! as String),
                hexBigInt(point['wy']! as String),
              );
              return verifySignatureBytes(
                alg,
                key,
                hexBytes(v.test['msg']! as String),
                hexBytes(v.test['sig']! as String),
              );
            },
            counts: counts,
          );
        },
      );
    }

    test('a signature does not verify under another algorithm', () {
      // The same r || s, a key of the same curve, the hash of ES384: the
      // verifier never reads the algorithm from the key or the signature.
      final v = loadVectors(
        'ecdsa_secp256r1_sha256_p1363_test.json',
      ).firstWhere((v) => v.result == 'valid');
      final jwk = v.group['publicKeyJwk']! as Map<String, Object?>;
      final key = EcVerificationKey(
        jwk['crv']! as String,
        base64UrlToBigInt(jwk['x']! as String),
        base64UrlToBigInt(jwk['y']! as String),
      );
      final message = hexBytes(v.test['msg']! as String);
      final signature = hexBytes(v.test['sig']! as String);
      expect(
        verifySignatureBytes(JwsAlgorithm.es256, key, message, signature),
        isTrue,
      );
      for (final other in [JwsAlgorithm.es384, JwsAlgorithm.es512]) {
        expect(
          verifySignatureBytes(other, key, message, signature),
          isFalse,
          reason: other.name,
        );
      }
    });
  });

  group('RSASSA-PKCS1-v1_5 (RS256, RS384, RS512)', () {
    for (final (file, alg, counts) in [
      (
        'rsa_signature_2048_sha256_test.json',
        JwsAlgorithm.rs256,
        {'valid': 9, 'invalid': 249, 'acceptable': 1},
      ),
      (
        'rsa_signature_3072_sha256_test.json',
        JwsAlgorithm.rs256,
        {'valid': 8, 'invalid': 250, 'acceptable': 1},
      ),
      (
        'rsa_signature_4096_sha256_test.json',
        JwsAlgorithm.rs256,
        {'valid': 7, 'invalid': 250, 'acceptable': 1},
      ),
      (
        'rsa_signature_2048_sha384_test.json',
        JwsAlgorithm.rs384,
        {'valid': 7, 'invalid': 250, 'acceptable': 1},
      ),
      (
        'rsa_signature_2048_sha512_test.json',
        JwsAlgorithm.rs512,
        {'valid': 8, 'invalid': 250, 'acceptable': 1},
      ),
    ]) {
      test('$file: ${counts['valid']} valid, ${counts['invalid']} invalid, '
          '1 acceptable (MissingNull: verifies)', () async {
        await _check(
          file,
          (v) {
            final key = v.group['publicKey']! as Map<String, Object?>;
            return verifySignatureBytes(
              alg,
              RsaVerificationKey(
                hexBigInt(key['modulus']! as String),
                hexBigInt(key['publicExponent']! as String),
              ),
              hexBytes(v.test['msg']! as String),
              hexBytes(v.test['sig']! as String),
            );
          },
          counts: counts,
          expected: (v) =>
              v.result == 'valid' || v.flags.contains('MissingNull'),
        );
      });
    }
  });

  group('RSASSA-PSS (PS256, PS384, PS512)', () {
    for (final (file, alg, counts) in [
      (
        'rsa_pss_2048_sha256_mgf1_32_test.json',
        JwsAlgorithm.ps256,
        {'valid': 63, 'invalid': 45},
      ),
      (
        'rsa_pss_3072_sha256_mgf1_32_test.json',
        JwsAlgorithm.ps256,
        {'valid': 63, 'invalid': 45},
      ),
      (
        'rsa_pss_2048_sha384_mgf1_48_test.json',
        JwsAlgorithm.ps384,
        {'valid': 95, 'invalid': 46},
      ),
      (
        'rsa_pss_4096_sha512_mgf1_64_test.json',
        JwsAlgorithm.ps512,
        {'valid': 132, 'invalid': 47},
      ),
    ]) {
      test(
        '$file: ${counts['valid']} valid, ${counts['invalid']} invalid',
        () async {
          await _check(
            file,
            (v) {
              final key = v.group['publicKey']! as Map<String, Object?>;
              return verifySignatureBytes(
                alg,
                RsaVerificationKey(
                  hexBigInt(key['modulus']! as String),
                  hexBigInt(key['publicExponent']! as String),
                ),
                hexBytes(v.test['msg']! as String),
                hexBytes(v.test['sig']! as String),
              );
            },
            counts: counts,
          );
        },
      );
    }
  });

  group('HMAC (HS256, HS384, HS512)', () {
    // A JWS carries the whole tag, and the verifier takes keys of at
    // least the hash's size: of the cases that are valid for Wycheproof,
    // a truncated tag or a shorter key is refused here, by policy.
    for (final (file, alg, bits, counts) in [
      (
        'hmac_sha256_test.json',
        JwsAlgorithm.hs256,
        256,
        {'valid': 66, 'invalid': 108},
      ),
      (
        'hmac_sha384_test.json',
        JwsAlgorithm.hs384,
        384,
        {'valid': 66, 'invalid': 108},
      ),
      (
        'hmac_sha512_test.json',
        JwsAlgorithm.hs512,
        512,
        {'valid': 66, 'invalid': 108},
      ),
    ]) {
      test(
        '$file: ${counts['valid']} valid, ${counts['invalid']} invalid',
        () async {
          bool policy(Vector v) =>
              v.result == 'valid' &&
              (v.group['tagSize']! as int) == bits &&
              (v.group['keySize']! as int) >= bits;
          await _check(
            file,
            (v) => verifySignatureBytes(
              alg,
              SecretVerificationKey(hexBytes(v.test['key']! as String)),
              hexBytes(v.test['msg']! as String),
              hexBytes(v.test['tag']! as String),
            ),
            counts: counts,
            expected: policy,
          );
          // Full tags under keys that are long enough are not an empty set.
          expect(loadVectors(file).where(policy), isNotEmpty);
        },
      );

      // The primitive under the JWS check and the signed cookies
      // (CookieSigner), on every vector, truncated tags and short keys
      // included: its output starts with the tag exactly for the valid
      // cases.
      test('$file: hmacSha computes the tag of every valid case', () {
        for (final v in loadVectors(file)) {
          final mac = hmacSha(
            bits,
            hexBytes(v.test['key']! as String),
            hexBytes(v.test['msg']! as String),
          );
          final tag = hexBytes(v.test['tag']! as String);
          final matches =
              tag.length <= mac.length &&
              hex(mac.sublist(0, tag.length)) == hex(tag);
          expect(matches, v.result == 'valid', reason: describe(v));
        }
      });
    }
  });
}
