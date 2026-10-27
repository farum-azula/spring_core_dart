// The exact bounds of the stored hashes the encoders accept. A stored hash
// may come from a leaked or tampered database: its parameters must stay
// within limits (one check must stay cheap), and every valid hash must still
// be read. Whether a hash is read is seen through `upgradeEncoding`, which
// parses the hash without computing it: a hash with weaker parameters than
// the encoder's is "to upgrade" only when it was read.
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

String _b64(int length) => base64.encode(Uint8List(length)).replaceAll('=', '');

void main() {
  group('Argon2', () {
    final encoder = Argon2PasswordEncoder.defaultsForSpringSecurity();

    String hash({
      String version = 'v=19',
      int m = 8,
      int t = 1,
      int p = 1,
      int salt = 16,
      int length = 32,
    }) =>
        '\$argon2id\$$version\$m=$m,t=$t,p=$p\$${_b64(salt)}\$${_b64(length)}';

    bool read(String stored) => encoder.upgradeEncoding(stored);

    test('the two Argon2 versions, nothing else', () {
      expect(read(hash()), isTrue);
      expect(read(hash(version: 'v=16')), isTrue);
      for (final version in ['v=17', 'v=99', 'v=0', 'v=', 'x=19']) {
        expect(read(hash(version: version)), isFalse, reason: version);
      }
    });

    test('iterations: 1 to 1024', () {
      expect(read(hash(t: 1024)), isTrue);
      expect(read(hash(t: 1025)), isFalse);
      expect(read(hash(t: 0)), isFalse);
    });

    test('parallelism: 1 to 256, with 8 KiB of memory per lane', () {
      expect(read(hash(p: 256, m: 2048)), isTrue);
      expect(read(hash(p: 257, m: 4096)), isFalse);
      expect(read(hash(p: 0)), isFalse);
      expect(read(hash(p: 2, m: 15)), isFalse);
      expect(read(hash(p: 2, m: 16)), isTrue);
    });

    test('memory: up to 4 GiB', () {
      expect(read(hash(m: 1 << 22)), isTrue);
      expect(read(hash(m: (1 << 22) + 1)), isFalse);
    });

    test('salt of 8 bytes or more, hash of 4 bytes or more', () {
      expect(read(hash(salt: 8)), isTrue);
      expect(read(hash(salt: 7)), isFalse);
      expect(read(hash(length: 4)), isTrue);
      expect(read(hash(length: 3)), isFalse);
      expect(read(hash(salt: 7, length: 3)), isFalse);
    });

    test('a hash out of bounds never matches and never throws', () {
      for (final stored in [
        hash(t: 1025),
        hash(version: 'v=99'),
        hash(salt: 7),
      ]) {
        expect(encoder.matches('password', stored), isFalse, reason: stored);
      }
    });
  });

  group('scrypt', () {
    // Weaker than the encoder in r (8 < 9): read hashes are "to upgrade".
    final encoder = SCryptPasswordEncoder(
      cpuCost: 1 << 16,
      memoryCost: 9,
      parallelization: 1,
      keyLength: 32,
      saltLength: 16,
    );

    String hash(int log2n, {int r = 8, int p = 1, int length = 32}) {
      final params = (log2n << 16 | r << 8 | p).toRadixString(16);
      return '\$$params\$${base64.encode(Uint8List(16))}'
          '\$${base64.encode(Uint8List(length))}';
    }

    test('N from 2^1 to 2^16', () {
      expect(encoder.upgradeEncoding(hash(1)), isTrue);
      expect(encoder.upgradeEncoding(hash(16)), isTrue);
      expect(encoder.upgradeEncoding(hash(0)), isFalse);
      expect(encoder.upgradeEncoding(hash(17)), isFalse);
    });

    test('a derived key of up to 256 bytes', () {
      expect(encoder.upgradeEncoding(hash(14, length: 256)), isTrue);
      expect(encoder.upgradeEncoding(hash(14, length: 257)), isFalse);
    });

    test('the constructor accepts the largest r and p, and a 1-byte key', () {
      SCryptPasswordEncoder(
        cpuCost: 2,
        memoryCost: 255,
        parallelization: 255,
        keyLength: 1,
        saltLength: 8,
      );
      for (final bad in [
        () => SCryptPasswordEncoder(
          cpuCost: 2,
          memoryCost: 256,
          parallelization: 1,
          keyLength: 32,
          saltLength: 16,
        ),
        () => SCryptPasswordEncoder(
          cpuCost: 2,
          memoryCost: 8,
          parallelization: 256,
          keyLength: 32,
          saltLength: 16,
        ),
        () => SCryptPasswordEncoder(
          cpuCost: 2,
          memoryCost: 8,
          parallelization: 1,
          keyLength: 0,
          saltLength: 16,
        ),
      ]) {
        expect(bad, throwsArgumentError);
      }
    });
  });

  group('delegating', () {
    test('an empty {} id is an id, and none is mapped to it', () {
      final encoder =
          PasswordEncoderFactories.createDelegatingPasswordEncoder();
      expect(
        () => encoder.matches('password', '{}abc'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('id ""'),
          ),
        ),
      );
    });
  });
}
