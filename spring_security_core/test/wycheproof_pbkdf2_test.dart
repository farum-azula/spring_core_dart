// Project Wycheproof's PBKDF2 vectors (HMAC-SHA-1, -256 and -512) through
// the key derivation of the password encoders: the primitive of
// lib/src/crypto/kdf_primitives.dart on every vector, and Pbkdf2PasswordEncoder
// (what a login runs) on the vectors it can express: a password that is
// UTF-8, a salt of 8 bytes or more and a key as long as the hash.
//
// The vectors are in test/fixtures/wycheproof/ (README.md there). All of
// them are `valid`: PBKDF2 has no invalid inputs, only a result to match.
// One vector is skipped: SHA-1 with 16 777 216 iterations (tcId 4), whose
// run takes minutes in pure Dart; every other count is at most 80 000.
// The failure message names the file and tcId.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_security_core/src/crypto/kdf_primitives.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> _vectors(String file) {
  final path = Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_security_core/'),
  )!.resolve('../test/fixtures/wycheproof/$file');
  final json =
      jsonDecode(File.fromUri(path).readAsStringSync()) as Map<String, Object?>;
  final tests = [
    for (final group
        in (json['testGroups']! as List).cast<Map<String, Object?>>())
      ...(group['tests']! as List).cast<Map<String, Object?>>(),
  ];
  expect(tests.length, json['numberOfTests'], reason: '$file has changed');
  return tests;
}

Uint8List _bytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _describe(String file, Map<String, Object?> v) =>
    '$file tcId ${v['tcId']} (${v['comment']}) ${v['flags']}';

void main() {
  for (final (file, hash, algorithm, hashBytes, total, skipped, encoderVectors)
      in [
        (
          'pbkdf2_hmacsha1_test.json',
          Pbkdf2Hash.sha1,
          Pbkdf2Algorithm.pbkdf2WithHmacSha1,
          20,
          64,
          1,
          0,
        ),
        (
          'pbkdf2_hmacsha256_test.json',
          Pbkdf2Hash.sha256,
          Pbkdf2Algorithm.pbkdf2WithHmacSha256,
          32,
          60,
          0,
          4,
        ),
        (
          'pbkdf2_hmacsha512_test.json',
          Pbkdf2Hash.sha512,
          Pbkdf2Algorithm.pbkdf2WithHmacSha512,
          64,
          58,
          0,
          0,
        ),
      ]) {
    group(file, () {
      late final List<Map<String, Object?>> vectors;
      setUpAll(() {
        vectors = _vectors(file)
            .where((v) => (v['iterationCount']! as int) <= 1000000)
            .toList();
      });

      test('$total vectors, all valid, $skipped skipped: pbkdf2()', () async {
        expect(vectors.length, total - skipped);
        // One isolate for each vector: pure Dart SHA-2 is slow, and the
        // vectors are independent.
        final keys = await Future.wait([
          for (final v in vectors)
            Isolate.run(() {
              return pbkdf2(
                hash,
                _bytes(v['password']! as String),
                _bytes(v['salt']! as String),
                iterations: v['iterationCount']! as int,
                length: v['dkLen']! as int,
              );
            }),
        ]);
        for (final (i, v) in vectors.indexed) {
          expect(v['result'], 'valid');
          expect(
            keys[i],
            _bytes(v['dk']! as String),
            reason: _describe(file, v),
          );
        }
      });

      // Only SHA-256 has vectors the encoder can express (a salt of 8
      // bytes or more and a key as long as the hash): four of them. The
      // others have other key lengths (16, 25, 32, 42, 65 bytes) or short
      // salts.
      test(
        'Pbkdf2PasswordEncoder.matches the vectors it can express '
        '($encoderVectors) and refuses them with another password or key',
        () {
          var run = 0;
          for (final v in vectors) {
            final password = _bytes(v['password']! as String);
            final salt = _bytes(v['salt']! as String);
            final dk = _bytes(v['dk']! as String);
            final String text;
            try {
              text = utf8.decode(password);
            } on FormatException {
              continue; // the encoder takes a String
            }
            if (salt.length < 8 || dk.length != hashBytes) {
              continue;
            }
            run++;
            final encoder = Pbkdf2PasswordEncoder(
              saltLength: salt.length,
              iterations: v['iterationCount']! as int,
              algorithm: algorithm,
            );
            String stored(List<int> k) => [
              ...salt,
              ...k,
            ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();
            // An empty password never matches (Spring Security 7: nothing
            // to check means no match), whatever the hash.
            expect(
              encoder.matches(text, stored(dk)),
              text.isNotEmpty,
              reason: _describe(file, v),
            );
            expect(
              encoder.matches('$text!', stored(dk)),
              isFalse,
              reason: _describe(file, v),
            );
            final flipped = Uint8List.fromList(dk)..[dk.length - 1] ^= 1;
            expect(
              encoder.matches(text, stored(flipped)),
              isFalse,
              reason: _describe(file, v),
            );
          }
          expect(run, encoderVectors);
        },
      );
    });
  }
}
