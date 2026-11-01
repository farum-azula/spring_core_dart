// Project Wycheproof's ECDSA P-256 and RSA PKCS#1 v1.5 vectors through the
// signature code of this package, and its signing paths over the same
// messages:
//
// - verification, as the ID token decoder uses it for tokens that did not
//   come from the token endpoint (p256Verify for ES256 and
//   rsaPkcs1Sha256Verify for RS256, after the decoder's own checks of the
//   key and of the signature length);
// - the DER to `R || S` conversion for platform keys (the Secure Enclave,
//   the Android Keystore, OpenSSL), ECDSA.transcodeSignatureToConcat, then
//   verification: an invalid DER signature must not become a valid one;
// - signing, by the software DPoP key and the JWT client secret (Sign in
//   with Apple): `R || S` of 64 bytes, `r` and `s` in range, verified by
//   this package's verifier and by pointycastle itself.
//
// The vectors are in test/fixtures/wycheproof/ (README.md there). The
// failure message names the file and tcId.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart'
    show
        ECCurve_secp256r1,
        ECDSASigner,
        ECPublicKey,
        ECSignature,
        PublicKeyParameter,
        SHA256Digest;
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/crypto_primitives.dart';
import 'package:test/test.dart';

import 'wycheproof_support.dart';

const _p1363 = 'ecdsa_secp256r1_sha256_p1363_test.json';
const _der = 'ecdsa_secp256r1_sha256_test.json';
const _rsa = 'rsa_signature_2048_sha256_test.json';

/// The key of a group: its point, and whether it is on the curve (the
/// decoder drops a JWK that is not).
({BigInt x, BigInt y, bool onCurve}) _key(Vector v) {
  final point = v.group['publicKey']! as Map<String, Object?>;
  final x = hexBigInt(point['wx']! as String);
  final y = hexBigInt(point['wy']! as String);
  return (x: x, y: y, onCurve: p256IsOnCurve(x, y));
}

/// What the ID token decoder does with an ES256 signature: refuse one that
/// is not 64 bytes, then verify `R || S`.
bool _es256(Vector v, Uint8List signature) {
  final key = _key(v);
  if (!key.onCurve || signature.length != 64) {
    return false;
  }
  return p256Verify(
    key.x,
    key.y,
    hexBytes(v.test['msg']! as String),
    unsignedBigInt(signature.sublist(0, 32)),
    unsignedBigInt(signature.sublist(32)),
  );
}

bool _pointycastle(BigInt x, BigInt y, Uint8List message, BigInt r, BigInt s) {
  final curve = ECCurve_secp256r1();
  return (ECDSASigner(SHA256Digest())..init(
        false,
        PublicKeyParameter<ECPublicKey>(
          ECPublicKey(curve.curve.createPoint(x, y), curve),
        ),
      ))
      .verifySignature(message, ECSignature(r, s));
}

void main() {
  group('ES256 verification (P1363)', () {
    test('$_p1363: 173 valid, 89 invalid', () {
      final vectors = loadVectors(_p1363);
      expect(tally(vectors), {'valid': 173, 'invalid': 89});
      for (final v in vectors) {
        expect(
          _es256(v, hexBytes(v.test['sig']! as String)),
          v.result == 'valid',
          reason: describe(v),
        );
      }
    });
  });

  group('DER to R || S, then verification', () {
    test('$_der: 174 valid, 310 invalid', () {
      final vectors = loadVectors(_der);
      expect(tally(vectors), {'valid': 174, 'invalid': 310});
      var converted = 0;
      for (final v in vectors) {
        final Uint8List signature;
        try {
          signature = ECDSA.transcodeSignatureToConcat(
            hexBytes(v.test['sig']! as String),
            64,
          );
        } on FormatException {
          // Only an invalid signature may be refused here: a valid one
          // always has a strict DER encoding.
          expect(v.result, 'invalid', reason: describe(v));
          continue;
        }
        converted++;
        expect(_es256(v, signature), v.result == 'valid', reason: describe(v));
      }
      // The strict parser keeps every valid signature and some invalid
      // ones, which then fail in the verification (ranges, values).
      expect(converted, greaterThanOrEqualTo(174));
    });
  });

  group('RS256 verification', () {
    test('$_rsa: 9 valid, 249 invalid, 1 acceptable (MissingNull)', () {
      final vectors = loadVectors(_rsa);
      expect(tally(vectors), {'valid': 9, 'invalid': 249, 'acceptable': 1});
      for (final v in vectors) {
        final key = v.group['publicKey']! as Map<String, Object?>;
        final ok = rsaPkcs1Sha256Verify(
          hexBigInt(key['modulus']! as String),
          hexBigInt(key['publicExponent']! as String),
          hexBytes(v.test['msg']! as String),
          hexBytes(v.test['sig']! as String),
        );
        // `acceptable`: a DigestInfo without the NULL verifies, as
        // pointycastle reads it (only the key's owner can make it).
        expect(
          ok,
          v.result == 'valid' || v.flags.contains('MissingNull'),
          reason: describe(v),
        );
      }
    });
  });

  group('signing', () {
    final messages = {
      for (final file in [_p1363, _der])
        for (final v in loadVectors(file)) v.test['msg']! as String,
    }.map(hexBytes).toList();

    void checkSignature(Uint8List signature, Uint8List message, String who) {
      expect(signature, hasLength(64), reason: who);
      final r = unsignedBigInt(signature.sublist(0, 32));
      final s = unsignedBigInt(signature.sublist(32));
      final inRange =
          r > BigInt.zero && r < p256Order && s > BigInt.zero && s < p256Order;
      expect(inRange, isTrue, reason: '$who: r and s are in [1, n - 1]');
    }

    test('the software DPoP key signs every message of the vectors in the '
        'JOSE form, deterministically, and the signatures verify', () async {
      expect(messages.length, greaterThan(50));
      for (var k = 0; k < 2; k++) {
        final key = SoftwareDPoPKey.generate();
        final jwk = key.publicJwk;
        final x = unsignedBigInt(
          base64Url.decode(base64Url.normalize('${jwk['x']}')),
        );
        final y = unsignedBigInt(
          base64Url.decode(base64Url.normalize('${jwk['y']}')),
        );
        for (final message in messages) {
          final signature = await key.sign(message);
          checkSignature(signature, message, 'key $k, ${message.length} bytes');
          final r = unsignedBigInt(signature.sublist(0, 32));
          final s = unsignedBigInt(signature.sublist(32));
          expect(
            p256Verify(x, y, message, r, s),
            isTrue,
            reason: 'key $k, message ${hex(message)}',
          );
          expect(_pointycastle(x, y, message, r, s), isTrue);
          expect(await key.sign(message), signature, reason: 'RFC 6979');
          // A changed message never verifies under the signature.
          final changed = Uint8List.fromList([...message, 0]);
          expect(p256Verify(x, y, changed, r, s), isFalse);
        }
      }
    });

    test('the JWT client secret of Sign in with Apple is signed in the same '
        'form by every key', () {
      for (var k = 0; k < 20; k++) {
        final d = p256GeneratePrivateKey();
        final public = p256PublicKey(d);
        final registration = CommonOAuth2Provider.apple
            .getBuilder('apple')
            .clientId('books.neon.$k')
            .build();
        final jwt = JwtClientSecret(
          issuer: 'TEAM',
          keyId: 'KEY',
          privateKey: d,
        ).clientSecret(registration);
        final parts = jwt.split('.');
        final message = Uint8List.fromList(
          ascii.encode('${parts[0]}.${parts[1]}'),
        );
        final signature = Uint8List.fromList(
          base64Url.decode(base64Url.normalize(parts[2])),
        );
        checkSignature(signature, message, 'secret $k');
        expect(
          p256Verify(
            public.x,
            public.y,
            message,
            unsignedBigInt(signature.sublist(0, 32)),
            unsignedBigInt(signature.sublist(32)),
          ),
          isTrue,
          reason: 'secret $k',
        );
      }
    });

    test('signatures are not low-s: nothing here asks for it', () async {
      // JWS (RFC 7518 §3.4) accepts both s and n - s; the verifiers of
      // this framework accept both (the Wycheproof "signature
      // malleability" case is valid), and the signer does not normalize:
      // about half of the signatures have a high s. Pinned so that a
      // change of the signer, or a verifier that starts to demand low-s,
      // is a decision.
      final key = SoftwareDPoPKey.generate();
      final half = p256Order >> 1;
      var high = 0;
      for (final message in messages.take(60)) {
        final signature = await key.sign(message);
        if (unsignedBigInt(signature.sublist(32)) > half) {
          high++;
        }
      }
      expect(high, inInclusiveRange(1, 59));
    });
  });
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
