// The password encoders against Spring Security itself: hashes written by
// Spring's encoders (test/vectors/spring_password_hashes.json, made by
// tool/security_reference) are checked here, and hashes written here
// (test/vectors/dart_password_hashes.json) are checked by Spring — see
// tool/security_reference/README.md. Plus the formats, upgrades, and hashes
// that are malformed or ask for unbounded work.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

/// [path] in this package (the tests also run from the workspace root).
File _packageFile(String path) => File.fromUri(
  Isolate.resolvePackageUriSync(Uri.parse('package:spring_security_core/'))!
      .resolve('../$path'),
);

List<Map<String, Object?>> _vectors(String file) =>
    (jsonDecode(_packageFile('test/vectors/$file').readAsStringSync()) as List)
        .cast<Map<String, Object?>>();

PasswordEncoder _encoder(String id) => switch (id) {
  'argon2' => Argon2PasswordEncoder.defaultsForSpringSecurity(),
  'pbkdf2' => Pbkdf2PasswordEncoder.defaultsForSpringSecurity(),
  'scrypt' => SCryptPasswordEncoder.defaultsForSpringSecurity(),
  _ => PasswordEncoderFactories.createDelegatingPasswordEncoder(),
};

void main() {
  group('hashes written by Spring Security', () {
    for (final vector in _vectors('spring_password_hashes.json')) {
      final id = vector['id']! as String;
      final password = vector['password']! as String;
      final hash = vector['hash']! as String;
      if (password.isEmpty) {
        // Spring Security 7 hashes an empty password but never matches it.
        test('$id: an empty password never matches, like Spring', () {
          expect(_encoder(id).matches(password, hash), isFalse);
        });
        continue;
      }
      if (hash.startsWith('{bcrypt}')) {
        test('$id: {bcrypt} fails with an error saying so', () {
          expect(
            () => _encoder(id).matches(password, hash),
            throwsA(
              isA<ArgumentError>().having(
                (e) => '${e.message}',
                'message',
                contains('bcrypt'),
              ),
            ),
          );
        });
        continue;
      }
      test('$id: "$password" matches, a wrong password does not', () {
        final encoder = _encoder(id);
        expect(encoder.matches(password, hash), isTrue);
        expect(encoder.matches('${password}x', hash), isFalse);
      });
    }
  });

  test('hashes written here still check here (sent to Spring by the '
      'reference tool)', () {
    for (final vector in _vectors('dart_password_hashes.json')) {
      if ((vector['password']! as String).isEmpty) {
        continue;
      }
      final encoder = _encoder(vector['id']! as String);
      expect(
        encoder.matches(
          vector['password']! as String,
          vector['hash']! as String,
        ),
        isTrue,
        reason: '${vector['id']}',
      );
    }
  });

  group('formats', () {
    test("Argon2: PHC string with Spring's parameters", () {
      final hash = Argon2PasswordEncoder.defaultsForSpringSecurity().encode(
        'x',
      );
      expect(
        hash,
        matches(
          r'^\$argon2id\$v=19\$m=16384,t=2,p=1\$[A-Za-z0-9+/]{22}\$[A-Za-z0-9+/]{43}$',
        ),
      );
    });

    test('a new salt every time', () {
      final encoder = Argon2PasswordEncoder.defaultsForSpringSecurity();
      expect(encoder.encode('x'), isNot(encoder.encode('x')));
    });

    test('PBKDF2: hex of salt and hash; base64 when asked', () {
      final encoder = Pbkdf2PasswordEncoder(saltLength: 16, iterations: 1000);
      final hex = encoder.encode('x');
      expect(hex, matches(r'^[0-9a-f]{96}$'));
      expect(encoder.matches('x', hex), isTrue);
      final b64 = Pbkdf2PasswordEncoder(
        saltLength: 16,
        iterations: 1000,
        encodeHashAsBase64: true,
      );
      expect(b64.matches('x', b64.encode('x')), isTrue);
      final peppered = Pbkdf2PasswordEncoder(
        secret: 'pepper',
        saltLength: 16,
        iterations: 1000,
      );
      expect(peppered.matches('x', hex), isFalse);
    });

    test('delegating: {id} prefix, every Spring id understood', () {
      final encoder =
          PasswordEncoderFactories.createDelegatingPasswordEncoder();
      final hash = encoder.encode('secret');
      expect(hash, startsWith('{argon2}'));
      expect(encoder.matches('secret', hash), isTrue);
      expect(encoder.matches('secret', '{noop}secret'), isTrue);
      expect(encoder.matches('secret', '{noop}other'), isFalse);
      expect(encoder.matches('secret', null), isFalse);
      expect(() => encoder.matches('secret', 'secret'), throwsArgumentError);
      expect(() => encoder.matches('secret', '{md5}x'), throwsArgumentError);
    });

    test('upgrades: another id, weaker parameters', () {
      final encoder =
          PasswordEncoderFactories.createDelegatingPasswordEncoder();
      expect(encoder.upgradeEncoding('{noop}x'), isTrue);
      expect(encoder.upgradeEncoding(encoder.encode('x')), isFalse);
      final weak = Argon2PasswordEncoder(
        saltLength: 16,
        hashLength: 32,
        parallelism: 1,
        memory: 1 << 12,
        iterations: 1,
      ).encode('x');
      expect(
        Argon2PasswordEncoder.defaultsForSpringSecurity().upgradeEncoding(weak),
        isTrue,
      );
    });
  });

  group('malformed and hostile stored hashes', () {
    final argon2 = Argon2PasswordEncoder.defaultsForSpringSecurity();
    final scrypt = SCryptPasswordEncoder.defaultsForSpringSecurity();
    final pbkdf2 = Pbkdf2PasswordEncoder.defaultsForSpringSecurity();

    test('never throw, never match', () {
      for (final hash in [
        '',
        r'$argon2id$',
        r'$argon2xx$v=19$m=16,t=1,p=1$c2FsdHNhbHQ$aGFzaA',
        r'$argon2id$v=99$m=16384,t=2,p=1$c2FsdHNhbHRzYWx0$aGFzaGhhc2g',
        r'$argon2id$v=19$m=x,t=2,p=1$c2FsdHNhbHRzYWx0$aGFzaGhhc2g',
        r'$argon2id$v=19$m=16384,t=2,p=1$***$aGFzaGhhc2g',
      ]) {
        expect(argon2.matches('x', hash), isFalse, reason: hash);
      }
      for (final hash in ['', r'$1$2', r'$zz$c2FsdA==$aGFzaA==', 'nothex']) {
        expect(scrypt.matches('x', hash), isFalse, reason: hash);
        expect(pbkdf2.matches('x', hash), isFalse, reason: hash);
      }
    });

    test('parameters asking for unbounded work are refused, not run', () {
      final watch = Stopwatch()..start();
      // 2^32 KiB of memory, 2^20 iterations, 2^30 scrypt cost.
      expect(
        argon2.matches(
          'x',
          r'$argon2id$v=19$m=4294967296,t=2,p=1$c2FsdHNhbHRzYWx0$aGFzaGhhc2g',
        ),
        isFalse,
      );
      expect(
        argon2.matches(
          'x',
          r'$argon2id$v=19$m=16384,t=1048576,p=1$c2FsdHNhbHRzYWx0$aGFzaGhhc2g',
        ),
        isFalse,
      );
      expect(scrypt.matches('x', r'$1e0801$c2FsdA==$aGFzaA=='), isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  test('long passwords are hashed whole, never truncated (ASVS 2.1.2, '
      '2.1.3; BCrypt would stop at 72 bytes)', () {
    final long = 'ü' * 100 + 'tail'; // 204 bytes in UTF-8
    for (final id in ['argon2', 'pbkdf2', 'scrypt']) {
      final encoder = _encoder(id);
      final hash = encoder.encode(long);
      expect(encoder.matches(long, hash), isTrue, reason: id);
      expect(
        encoder.matches('${long.substring(0, long.length - 1)}X', hash),
        isFalse,
        reason: '$id: only the last character differs',
      );
      expect(
        encoder.matches(long.substring(0, 72), hash),
        isFalse,
        reason: '$id: a prefix',
      );
    }
  });

  test('constant-time comparison compares everything', () {
    expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(constantTimeEquals([1, 2, 3], [1, 2]), isFalse);
    expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    expect(constantTimeEquals([], []), isTrue);
  });
}
