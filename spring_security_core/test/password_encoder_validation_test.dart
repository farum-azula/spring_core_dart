// What the password encoders refuse and how they treat input that is not a
// valid hash: invalid parameters fail at construction (never a silently
// weak hash), PBKDF2 with every HMAC against values computed independently
// (Python's hashlib), scrypt/Argon2 upgrades, malformed hex and base64, and
// the argument checks and fallback of the DelegatingPasswordEncoder.
import 'dart:convert';

import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

// Small parameters: these tests are not about the cost.
Argon2PasswordEncoder argon2({
  int saltLength = 8,
  int hashLength = 16,
  int parallelism = 1,
  int memory = 8,
  int iterations = 1,
}) => Argon2PasswordEncoder(
  saltLength: saltLength,
  hashLength: hashLength,
  parallelism: parallelism,
  memory: memory,
  iterations: iterations,
);

SCryptPasswordEncoder scrypt({
  int cpuCost = 16,
  int memoryCost = 1,
  int parallelization = 1,
  int keyLength = 16,
  int saltLength = 8,
}) => SCryptPasswordEncoder(
  cpuCost: cpuCost,
  memoryCost: memoryCost,
  parallelization: parallelization,
  keyLength: keyLength,
  saltLength: saltLength,
);

Matcher invalid([String? message]) => throwsA(
  isA<ArgumentError>().having(
    (e) => '${e.message}',
    'message',
    message == null ? isNotEmpty : contains(message),
  ),
);

void main() {
  group('Argon2 parameters', () {
    test('valid minimums are accepted', () {
      expect(argon2, returnsNormally);
      expect(() => argon2(parallelism: 2, memory: 16), returnsNormally);
    });

    test('a short salt or hash is refused', () {
      expect(() => argon2(saltLength: 7), invalid('salt of 8+'));
      expect(() => argon2(hashLength: 15), invalid('hash of 16+'));
    });

    test('lanes, passes and memory must make sense', () {
      expect(() => argon2(parallelism: 0), invalid('Invalid Argon2'));
      expect(() => argon2(iterations: 0), invalid('Invalid Argon2'));
      expect(() => argon2(memory: 7), invalid('Invalid Argon2'));
      // Memory is at least 8 KiB per lane.
      expect(
        () => argon2(parallelism: 2, memory: 15),
        invalid('Invalid Argon2'),
      );
    });

    test('a hash made with small parameters checks', () {
      final encoder = argon2();
      final hash = encoder.encode('secret');
      expect(hash, startsWith(r'$argon2id$v=19$m=8,t=1,p=1$'));
      expect(encoder.matches('secret', hash), isTrue);
      expect(encoder.matches('Secret', hash), isFalse);
    });
  });

  group('Argon2 upgrades', () {
    test('weaker memory or fewer passes than the encoder: upgrade', () {
      final strong = argon2(memory: 16, iterations: 2);
      expect(strong.upgradeEncoding(argon2(iterations: 2).encode('x')), isTrue);
      expect(strong.upgradeEncoding(argon2(memory: 16).encode('x')), isTrue);
    });

    test('the same or stronger: no upgrade', () {
      final encoder = argon2(memory: 16, iterations: 2);
      expect(encoder.upgradeEncoding(encoder.encode('x')), isFalse);
      expect(
        encoder.upgradeEncoding(argon2(memory: 32, iterations: 3).encode('x')),
        isFalse,
      );
    });

    test('nothing to upgrade in a missing or unreadable hash', () {
      final encoder = argon2();
      expect(encoder.upgradeEncoding(null), isFalse);
      expect(encoder.upgradeEncoding(''), isFalse);
      expect(encoder.upgradeEncoding('plain text'), isFalse);
    });
  });

  group('PBKDF2', () {
    test('parameters: a salt of 8+ bytes and at least one iteration', () {
      expect(
        () => Pbkdf2PasswordEncoder(saltLength: 7, iterations: 1),
        invalid('salt of 8+'),
      );
      expect(
        () => Pbkdf2PasswordEncoder(saltLength: 8, iterations: 0),
        invalid('iterations'),
      );
      expect(
        () => Pbkdf2PasswordEncoder(saltLength: 8, iterations: 1),
        returnsNormally,
      );
    });

    // hashlib.pbkdf2_hmac(name, b'password', b'saltsalt' [+ pepper], 1000)
    final knownAnswers = {
      Pbkdf2Algorithm.pbkdf2WithHmacSha1: (
        'e9febff54bfce668fde301acc85563cc9dc71ef6',
        '697dc0652b49cdd0191460e9998b856e45e187a3',
      ),
      Pbkdf2Algorithm.pbkdf2WithHmacSha256: (
        '135f7a66144fcf0fb003ce048f31f024ed5cbff30525d3ba0bfb3199479362a6',
        '923aef6e6518463d2306ad58fd53ac6c8243980bd514a0020c263a0078d473b0',
      ),
      Pbkdf2Algorithm.pbkdf2WithHmacSha512: (
        '43abf8c7027c6bd9d63e9d81784a006188474a8db14663d60114f5eef4e94b1b'
            '76aba88da7b04ea335b9e7baaa6bde5e36350ee202acd02caf25b6061a4bb5b4',
        'be727d8a7a9c86502ff5b1a34091ada1b50140c1f5ced269880d59b8cc70937a'
            'ee865644e1810f5087d4c6d34120114a29999b4b36ff197eabfa4091a337a76e',
      ),
    };
    final saltHex = utf8
        .encode('saltsalt')
        .map((b) => b.toRadixString(16))
        .join();

    knownAnswers.forEach((algorithm, answers) {
      final (plain, peppered) = answers;

      test('${algorithm.name} matches a hash computed independently', () {
        final encoder = Pbkdf2PasswordEncoder(
          saltLength: 8,
          iterations: 1000,
          algorithm: algorithm,
        );
        expect(encoder.matches('password', '$saltHex$plain'), isTrue);
        expect(encoder.matches('passwore', '$saltHex$plain'), isFalse);
        expect(encoder.matches('password', '$saltHex$peppered'), isFalse);
      });

      test('${algorithm.name} with a secret mixes it into the salt', () {
        final encoder = Pbkdf2PasswordEncoder(
          secret: 'pepper',
          saltLength: 8,
          iterations: 1000,
          algorithm: algorithm,
        );
        expect(encoder.matches('password', '$saltHex$peppered'), isTrue);
        expect(encoder.matches('password', '$saltHex$plain'), isFalse);
      });

      test(
        '${algorithm.name} encodes to salt + ${algorithm.hashBytes} bytes',
        () {
          final encoder = Pbkdf2PasswordEncoder(
            saltLength: 8,
            iterations: 10,
            algorithm: algorithm,
          );
          final hash = encoder.encode('password');
          expect(hash, hasLength((8 + algorithm.hashBytes) * 2));
          expect(encoder.matches('password', hash), isTrue);
          expect(encoder.matches('other', hash), isFalse);
        },
      );
    });

    test('a hash of another HMAC has the wrong length: no match', () {
      final sha1 = Pbkdf2PasswordEncoder(
        saltLength: 8,
        iterations: 10,
        algorithm: Pbkdf2Algorithm.pbkdf2WithHmacSha1,
      );
      final sha256 = Pbkdf2PasswordEncoder(saltLength: 8, iterations: 10);
      expect(sha256.matches('x', sha1.encode('x')), isFalse);
      expect(sha1.matches('x', sha256.encode('x')), isFalse);
    });

    test('a hash that is only a salt, or shorter, never matches', () {
      final encoder = Pbkdf2PasswordEncoder(saltLength: 8, iterations: 10);
      expect(encoder.matches('x', '0011223344556677'), isFalse);
      expect(encoder.matches('x', '0011'), isFalse);
    });

    test('malformed hex: odd length, non-hex characters', () {
      final encoder = Pbkdf2PasswordEncoder(saltLength: 8, iterations: 10);
      final good = encoder.encode('x');
      expect(encoder.matches('x', '${good}0'), isFalse);
      expect(encoder.matches('x', 'zz${good.substring(2)}'), isFalse);
      expect(
        encoder.matches('x', '${good.substring(0, 10)} ${good.substring(11)}'),
        isFalse,
      );
    });

    test('malformed base64 never matches and never throws', () {
      final encoder = Pbkdf2PasswordEncoder(
        saltLength: 8,
        iterations: 10,
        encodeHashAsBase64: true,
      );
      final good = encoder.encode('x');
      expect(encoder.matches('x', good), isTrue);
      for (final bad in [
        'not base64!',
        'a',
        '${good}A',
        '%%%%',
        good.substring(1),
      ]) {
        expect(encoder.matches('x', bad), isFalse, reason: bad);
      }
    });

    test('hashes are never upgraded (the parameters are not in them)', () {
      final encoder = Pbkdf2PasswordEncoder(saltLength: 8, iterations: 10);
      expect(encoder.upgradeEncoding(encoder.encode('x')), isFalse);
      expect(encoder.upgradeEncoding(null), isFalse);
    });

    test('an empty password or an empty or missing hash never matches', () {
      final encoder = Pbkdf2PasswordEncoder(saltLength: 8, iterations: 10);
      final hash = encoder.encode('x');
      expect(encoder.matches('', hash), isFalse);
      expect(encoder.matches('x', ''), isFalse);
      expect(encoder.matches('x', null), isFalse);
    });
  });

  group('scrypt parameters', () {
    test('valid ones are accepted', () {
      expect(scrypt, returnsNormally);
      expect(() => scrypt(cpuCost: 65536), returnsNormally);
    });

    test('the cost is a power of 2 from 2 to 65536', () {
      for (final cost in [-16, 0, 1, 3, 17, 65535, 131072, 1 << 30]) {
        expect(
          () => scrypt(cpuCost: cost),
          invalid('power of 2'),
          reason: '$cost',
        );
      }
    });

    test('block size, parallelism, key and salt lengths are bounded', () {
      expect(() => scrypt(memoryCost: 0), invalid('Invalid scrypt'));
      expect(() => scrypt(memoryCost: 256), invalid('Invalid scrypt'));
      expect(() => scrypt(parallelization: 0), invalid('Invalid scrypt'));
      expect(() => scrypt(parallelization: 256), invalid('Invalid scrypt'));
      expect(() => scrypt(keyLength: 0), invalid('Invalid scrypt'));
      expect(() => scrypt(saltLength: 7), invalid('Invalid scrypt'));
    });
  });

  group('scrypt upgrades', () {
    final base = scrypt();

    test('a hash with a lower N, r or p than the encoder: upgrade', () {
      expect(scrypt(cpuCost: 32).upgradeEncoding(base.encode('x')), isTrue);
      expect(scrypt(memoryCost: 2).upgradeEncoding(base.encode('x')), isTrue);
      expect(
        scrypt(parallelization: 2).upgradeEncoding(base.encode('x')),
        isTrue,
      );
    });

    test('the same or stronger parameters: no upgrade', () {
      expect(base.upgradeEncoding(base.encode('x')), isFalse);
      expect(base.upgradeEncoding(scrypt(cpuCost: 32).encode('x')), isFalse);
      expect(base.upgradeEncoding(scrypt(memoryCost: 2).encode('x')), isFalse);
      expect(
        base.upgradeEncoding(scrypt(parallelization: 2).encode('x')),
        isFalse,
      );
    });

    test('nothing to upgrade in a missing or unreadable hash', () {
      expect(base.upgradeEncoding(null), isFalse);
      expect(base.upgradeEncoding(''), isFalse);
      expect(base.upgradeEncoding('x'), isFalse);
      expect(base.upgradeEncoding(r'$zz$c2FsdA==$aGFzaA=='), isFalse);
    });
  });

  group('scrypt hashes that are not valid', () {
    final encoder = scrypt();
    final good = encoder.encode('x');
    final parts = good.split(r'$'); // '', params, salt, hash

    test("the encoder's own hash matches (control)", () {
      expect(encoder.matches('x', good), isTrue);
      expect(encoder.matches('y', good), isFalse);
    });

    test('malformed base64 for salt or hash', () {
      expect(encoder.matches('x', '\$${parts[1]}\$***\$${parts[3]}'), isFalse);
      expect(encoder.matches('x', '\$${parts[1]}\$${parts[2]}\$***'), isFalse);
      expect(encoder.matches('x', '\$${parts[1]}\$a\$${parts[3]}'), isFalse);
    });

    test('wrong structure, parameters or an empty hash', () {
      for (final bad in [
        '',
        r'$',
        'x',
        '${parts[1]}\$${parts[2]}\$${parts[3]}', // no leading $
        '$good\$extra',
        '\$${parts[1]}\$${parts[2]}\$',
        r'$0$c2FsdA==$aGFzaA==', // N = 2^0
        r'$110801$c2FsdA==$aGFzaA==', // N = 2^17: more than allowed
        r'$100001$c2FsdA==$aGFzaA==', // r = 0
        r'$100100$c2FsdA==$aGFzaA==', // p = 0
        '\$${parts[1]}\$${parts[2]}\$${base64.encode(List.filled(257, 1))}',
      ]) {
        expect(encoder.matches('x', bad), isFalse, reason: bad);
      }
    });
  });

  group('NoOpPasswordEncoder', () {
    const encoder = NoOpPasswordEncoder();

    test('compares the text; nothing empty ever matches', () {
      expect(encoder.encode('secret'), 'secret');
      expect(encoder.matches('secret', 'secret'), isTrue);
      expect(encoder.matches('secret', 'Secret'), isFalse);
      expect(encoder.matches('secret', 'secre'), isFalse);
      expect(encoder.matches('', ''), isFalse);
      expect(encoder.matches('secret', null), isFalse);
    });

    test('has nothing to upgrade', () {
      expect(encoder.upgradeEncoding('secret'), isFalse);
    });
  });

  group('DelegatingPasswordEncoder', () {
    const noop = NoOpPasswordEncoder();

    test('the encoder for new passwords must be one of the encoders', () {
      expect(
        () => DelegatingPasswordEncoder('md5', {'noop': noop}),
        invalid('md5'),
      );
      expect(() => DelegatingPasswordEncoder('noop', {}), invalid('noop'));
    });

    test('ids cannot contain braces (the prefix would be ambiguous)', () {
      for (final id in ['a{b', 'a}b', '{x}']) {
        expect(
          () => DelegatingPasswordEncoder('noop', {'noop': noop, id: noop}),
          invalid('cannot contain'),
          reason: id,
        );
      }
    });

    test('the map is copied and cannot be changed afterwards', () {
      final given = <String, PasswordEncoder>{'noop': noop};
      final encoder = DelegatingPasswordEncoder('noop', given);
      given['other'] = noop;
      expect(encoder.encoders.keys, ['noop']);
      expect(() => encoder.encoders['x'] = noop, throwsUnsupportedError);
    });

    test('encodes with the {id} of idForEncode', () {
      expect(
        DelegatingPasswordEncoder('noop', {'noop': noop}).encode('pw'),
        '{noop}pw',
      );
    });

    test('checks with the encoder named in the prefix', () {
      final encoder = DelegatingPasswordEncoder('a', {
        'a': noop,
        'b': const _AlwaysMatches(),
      });
      expect(encoder.matches('pw', '{a}pw'), isTrue);
      expect(encoder.matches('pw', '{a}other'), isFalse);
      expect(encoder.matches('pw', '{b}anything'), isTrue);
    });

    test('nothing to check: no match, no error', () {
      final encoder = DelegatingPasswordEncoder('noop', {'noop': noop});
      expect(encoder.matches('', '{noop}'), isFalse);
      expect(encoder.matches('pw', ''), isFalse);
      expect(encoder.matches('pw', null), isFalse);
    });

    test('an unknown id or no id is an error naming it (a misconfiguration '
        'is not a wrong password)', () {
      final encoder = DelegatingPasswordEncoder('noop', {'noop': noop});
      expect(() => encoder.matches('pw', '{md5}abc'), invalid('"md5"'));
      expect(() => encoder.matches('pw', 'abc'), invalid('"null"'));
      expect(() => encoder.matches('pw', '{unclosed'), invalid('"null"'));
      expect(() => encoder.matches('pw', '{bcrypt}abc'), invalid('BCrypt'));
    });

    test('a default encoder for matches takes what has no known id, '
        'with the whole stored text', () {
      final fallback = _Recording();
      final encoder = DelegatingPasswordEncoder('noop', {
        'noop': noop,
      }, defaultPasswordEncoderForMatches: fallback);
      expect(encoder.matches('pw', 'plain'), isTrue);
      expect(encoder.matches('pw', '{md5}abc'), isTrue);
      expect(encoder.matches('pw', '{unclosed'), isTrue);
      expect(fallback.asked, ['plain', '{md5}abc', '{unclosed']);
      // A known id is still handled by its own encoder.
      expect(encoder.matches('pw', '{noop}other'), isFalse);
      expect(fallback.asked, hasLength(3));
    });

    test('an upgrade is wanted for another id, no prefix, or by the '
        'encoder of the id', () {
      final encoder = DelegatingPasswordEncoder('a', {
        'a': const _Upgradable(),
        'b': noop,
      });
      expect(encoder.upgradeEncoding(null), isFalse);
      expect(encoder.upgradeEncoding('{b}x'), isTrue);
      expect(encoder.upgradeEncoding('no prefix'), isTrue);
      expect(encoder.upgradeEncoding('{unknown}x'), isTrue);
      expect(encoder.upgradeEncoding('{a}old:x'), isTrue);
      expect(encoder.upgradeEncoding('{a}new:x'), isFalse);
    });
  });

  group('secureRandomBytes', () {
    test('gives the length asked and different bytes each time', () {
      expect(secureRandomBytes(0), isEmpty);
      expect(secureRandomBytes(17), hasLength(17));
      expect(secureRandomBytes(16), isNot(secureRandomBytes(16)));
    });
  });
}

final class _AlwaysMatches implements PasswordEncoder {
  const _AlwaysMatches();

  @override
  String encode(String rawPassword) => rawPassword;

  @override
  bool matches(String rawPassword, String? encodedPassword) => true;

  @override
  bool upgradeEncoding(String? encodedPassword) => false;
}

final class _Recording implements PasswordEncoder {
  final asked = <String?>[];

  @override
  String encode(String rawPassword) => rawPassword;

  @override
  bool matches(String rawPassword, String? encodedPassword) {
    asked.add(encodedPassword);
    return true;
  }

  @override
  bool upgradeEncoding(String? encodedPassword) => false;
}

final class _Upgradable implements PasswordEncoder {
  const _Upgradable();

  @override
  String encode(String rawPassword) => 'new:$rawPassword';

  @override
  bool matches(String rawPassword, String? encodedPassword) =>
      encodedPassword?.endsWith(rawPassword) ?? false;

  @override
  bool upgradeEncoding(String? encodedPassword) =>
      encodedPassword?.startsWith('old:') ?? false;
}
