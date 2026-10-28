import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_security_core/src/crypto/kdf_primitives.dart';

/// Turns a password into a hash you can store, and later checks a typed
/// password against that hash.
///
/// Passwords must never be stored as typed: if the database leaks, the
/// attacker would have them. An encoder applies a slow, salted one-way
/// function, so the stored text cannot be turned back into the password,
/// and the same password gives a different hash each time. Use it when a
/// user registers or changes their password ([encode]); logins call
/// [matches] for you through `DaoAuthenticationProvider`.
///
/// Inject the `PasswordEncoder` bean if the application declares one;
/// otherwise use
/// [PasswordEncoderFactories.createDelegatingPasswordEncoder], which is
/// also what logins use when there is no bean.
///
/// ```dart
/// // Registration: store the hash, never the password.
/// final encoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
/// final stored = encoder.encode(form.password); // {argon2}$argon2id$v=19$...
/// await accounts.create(form.email, passwordHash: stored);
///
/// encoder.matches(form.password, stored); // true
/// ```
///
/// Spring (Java): `PasswordEncoder`, the same three methods.
abstract interface class PasswordEncoder {
  /// A hash of [rawPassword] to store, with a new random salt each time,
  /// so two calls give different texts that both match.
  ///
  /// The hashing encoders are slow on purpose (up to hundreds of
  /// milliseconds): do not call [encode] in a loop on a request path.
  String encode(String rawPassword);

  /// Whether [rawPassword] is the password [encodedPassword] was made
  /// from.
  ///
  /// `false` for an empty [rawPassword] (an empty password never logs in)
  /// and for a missing, empty or malformed [encodedPassword], as in Spring
  /// Security 7. The comparison takes the same time wherever the hashes
  /// differ.
  bool matches(String rawPassword, String? encodedPassword);

  /// Whether [encodedPassword] was made with weaker settings than this
  /// encoder's and should be replaced.
  ///
  /// After a successful login `DaoAuthenticationProvider` then hashes the
  /// typed password again and stores it through a
  /// `UserDetailsPasswordService`. `false` for `null` and for text the
  /// encoder cannot read.
  bool upgradeEncoding(String? encodedPassword);
}

/// Whether [a] and [b] hold the same bytes, compared in a time that does
/// not depend on where they differ.
///
/// An ordinary comparison stops at the first different byte, so an
/// attacker who can measure the time learns how many leading bytes of a
/// guess were right. Use it to compare any secret: a hash, a token, an API
/// key. Lists of different lengths are never equal.
///
/// ```dart
/// // Check the key a webhook caller sent against the configured one.
/// final ok = constantTimeEquals(utf8.encode(sent), utf8.encode(expected));
/// ```
///
/// Java: `MessageDigest.isEqual`.
bool constantTimeEquals(List<int> a, List<int> b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ (i < b.length ? b[i] : 0);
  }
  return difference == 0;
}

final Random _random = Random.secure();

// Spring Security 7: nothing to check means no match.
bool _checkable(String rawPassword, String? encodedPassword) =>
    rawPassword.isNotEmpty &&
    encodedPassword != null &&
    encodedPassword.isNotEmpty;

/// [length] random bytes from `Random.secure()`, suitable for salts, keys
/// and tokens that an attacker must not guess.
Uint8List secureRandomBytes(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = _random.nextInt(256);
  }
  return bytes;
}

/// A [PasswordEncoder] using Argon2id, the winner of the Password Hashing
/// Competition and the default for new hashes here.
///
/// Argon2 needs a lot of memory per hash, which makes guessing many
/// passwords on special hardware expensive. The hash text carries all
/// its parameters, in the PHC format Spring writes, so hashes move
/// between Java and Dart applications in both directions:
/// `$argon2id$v=19$m=16384,t=2,p=1$<salt>$<hash>`. [matches] reads
/// Argon2d, Argon2i and Argon2id hashes of versions 1.0 and 1.3, and
/// refuses parameters beyond 4 GiB of memory, 1 024 passes or 256 lanes,
/// so a corrupted stored hash cannot make one login run for hours.
///
/// Most applications get it through
/// [PasswordEncoderFactories.createDelegatingPasswordEncoder] as
/// `{argon2}`. Create one directly to choose stronger parameters.
///
/// ```dart
/// // 64 MiB and 3 passes; old hashes are upgraded at the next login.
/// final encoder = Argon2PasswordEncoder(
///   saltLength: 16,
///   hashLength: 32,
///   parallelism: 1,
///   memory: 65536,
///   iterations: 3,
/// );
/// ```
///
/// Spring (Java): `Argon2PasswordEncoder`, which also uses Bouncy
/// Castle:
/// ```java
/// new Argon2PasswordEncoder(16, 32, 1, 65536, 3);
/// ```
final class Argon2PasswordEncoder implements PasswordEncoder {
  /// An encoder with these parameters; [memory] is in KiB.
  ///
  /// Throws an [ArgumentError] when [saltLength] is below 8, [hashLength]
  /// below 16, [parallelism] or [iterations] below 1, or [memory] below
  /// 8 KiB per lane.
  Argon2PasswordEncoder({
    required this.saltLength,
    required this.hashLength,
    required this.parallelism,
    required this.memory,
    required this.iterations,
  }) {
    if (saltLength < 8 || hashLength < 16) {
      throw ArgumentError('Argon2 needs a salt of 8+ and a hash of 16+ bytes');
    }
    if (parallelism < 1 || iterations < 1 || memory < 8 * parallelism) {
      throw ArgumentError('Invalid Argon2 parameters');
    }
  }

  /// Spring Security's current defaults, from
  /// `defaultsForSpringSecurity_v5_8`: Argon2id with 16 MiB of memory, 2
  /// passes, 1 lane, a 16-byte salt and a 32-byte hash.
  factory Argon2PasswordEncoder.defaultsForSpringSecurity() =>
      Argon2PasswordEncoder(
        saltLength: 16,
        hashLength: 32,
        parallelism: 1,
        memory: 1 << 14,
        iterations: 2,
      );

  /// The length of the random salt of new hashes, in bytes.
  final int saltLength;

  /// The length of new hashes, in bytes.
  final int hashLength;

  /// The number of lanes (parallel memory blocks) of new hashes.
  final int parallelism;

  /// The memory of new hashes, in KiB; the main cost knob.
  final int memory;

  /// The number of passes over the memory of new hashes.
  final int iterations;

  @override
  String encode(String rawPassword) {
    final salt = secureRandomBytes(saltLength);
    final hash = _hash(
      utf8.encode(rawPassword),
      salt,
      type: Argon2Type.id,
      version: argon2Version13,
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      length: hashLength,
    );
    return '\$argon2id\$v=19\$m=$memory,t=$iterations,p=$parallelism'
        '\$${_b64(salt)}\$${_b64(hash)}';
  }

  @override
  bool matches(String rawPassword, String? encodedPassword) {
    final decoded = _checkable(rawPassword, encodedPassword)
        ? _Argon2Hash.parse(encodedPassword)
        : null;
    if (decoded == null) {
      return false;
    }
    final hash = _hash(
      utf8.encode(rawPassword),
      decoded.salt,
      type: decoded.type,
      version: decoded.version,
      memory: decoded.memory,
      iterations: decoded.iterations,
      parallelism: decoded.parallelism,
      length: decoded.hash.length,
    );
    return constantTimeEquals(hash, decoded.hash);
  }

  /// `true` when [encodedPassword] used less memory or fewer passes than
  /// this encoder, as in Spring; `false` for text that is not an Argon2
  /// hash.
  @override
  bool upgradeEncoding(String? encodedPassword) {
    final decoded = _Argon2Hash.parse(encodedPassword);
    return decoded != null &&
        (decoded.memory < memory || decoded.iterations < iterations);
  }

  static Uint8List _hash(
    List<int> password,
    Uint8List salt, {
    required Argon2Type type,
    required int version,
    required int memory,
    required int iterations,
    required int parallelism,
    required int length,
  }) => argon2(
    password,
    salt,
    type: type,
    version: version,
    memory: memory,
    iterations: iterations,
    parallelism: parallelism,
    length: length,
  );
}

// `$argon2id$v=19$m=16384,t=2,p=1$<salt>$<hash>` (base64 without padding).
final class _Argon2Hash {
  _Argon2Hash(
    this.type,
    this.version,
    this.memory,
    this.iterations,
    this.parallelism,
    this.salt,
    this.hash,
  );

  final Argon2Type type;
  final int version;
  final int memory;
  final int iterations;
  final int parallelism;
  final Uint8List salt;
  final Uint8List hash;

  // Bounds: a stored hash comes from the application's own store, but a
  // corrupted or hostile one must not make one login take unbounded time.
  static const int _maxMemory = 1 << 22; // 4 GiB in KiB
  static const int _maxIterations = 1 << 10;
  static const int _maxParallelism = 1 << 8;

  static _Argon2Hash? parse(String? encoded) {
    if (encoded == null) {
      return null;
    }
    final parts = encoded.split(r'$');
    // '', type, [v=..], params, salt, hash
    if (parts.length != 6 && parts.length != 5) {
      return null;
    }
    final type = switch (parts[1]) {
      'argon2d' => Argon2Type.d,
      'argon2i' => Argon2Type.i,
      'argon2id' => Argon2Type.id,
      _ => null,
    };
    if (parts[0].isNotEmpty || type == null) {
      return null;
    }
    var index = 2;
    var version = argon2Version10;
    if (parts.length == 6) {
      final match = RegExp(r'^v=(\d+)$').firstMatch(parts[index++]);
      final value = match == null ? null : int.tryParse(match[1]!);
      if (value != argon2Version10 && value != argon2Version13) {
        return null;
      }
      version = value!;
    }
    final params = RegExp(r'^m=(\d{1,10}),t=(\d{1,10}),p=(\d{1,10})$')
        .firstMatch(parts[index++]);
    if (params == null) {
      return null;
    }
    final memory = int.parse(params[1]!);
    final iterations = int.parse(params[2]!);
    final parallelism = int.parse(params[3]!);
    if (iterations < 1 ||
        iterations > _maxIterations ||
        parallelism < 1 ||
        parallelism > _maxParallelism ||
        memory < 8 * parallelism ||
        memory > _maxMemory) {
      return null;
    }
    final salt = _unb64(parts[index++]);
    final hash = _unb64(parts[index]);
    if (salt == null || hash == null || salt.length < 8 || hash.length < 4) {
      return null;
    }
    return _Argon2Hash(
      type,
      version,
      memory,
      iterations,
      parallelism,
      salt,
      hash,
    );
  }
}

/// A [PasswordEncoder] using PBKDF2, the key derivation function required
/// by some standards (such as FIPS 140).
///
/// Choose it when a policy requires PBKDF2; otherwise prefer Argon2. The
/// hash is the hex text of the salt followed by the derived key, Spring's
/// format. Unlike Argon2 and scrypt, the text does not say which
/// iterations, HMAC or salt length made it: an encoder can only check
/// hashes made with its own settings, and [upgradeEncoding] cannot detect
/// weak ones.
///
/// ```dart
/// final encoder = Pbkdf2PasswordEncoder.defaultsForSpringSecurity();
/// // 96 hex digits: the 16-byte salt, then the 32-byte hash.
/// final stored = encoder.encode('secret');
/// ```
///
/// Spring (Java):
/// ```java
/// Pbkdf2PasswordEncoder.defaultsForSpringSecurity_v5_8();
/// ```
final class Pbkdf2PasswordEncoder implements PasswordEncoder {
  /// An encoder with these parameters.
  ///
  /// [secret] is a pepper: a value kept outside the password store (in the
  /// configuration) and appended to the salt, as Spring does, so a leaked
  /// store alone is not enough to test guesses. Throws an [ArgumentError]
  /// when [saltLength] is below 8 or [iterations] below 1.
  Pbkdf2PasswordEncoder({
    required this.saltLength,
    required this.iterations,
    this.secret = '',
    this.algorithm = Pbkdf2Algorithm.pbkdf2WithHmacSha256,
    this.encodeHashAsBase64 = false,
  }) {
    if (saltLength < 8 || iterations < 1) {
      throw ArgumentError('PBKDF2 needs a salt of 8+ bytes and iterations');
    }
  }

  /// Spring Security's current defaults, from
  /// `defaultsForSpringSecurity_v5_8`: HMAC-SHA256, 310 000 iterations, a
  /// 16-byte salt, a 256-bit hash and no secret.
  factory Pbkdf2PasswordEncoder.defaultsForSpringSecurity() =>
      Pbkdf2PasswordEncoder(saltLength: 16, iterations: 310000);

  /// The pepper appended to the salt; `''` for none.
  final String secret;

  /// The length of the salt, in bytes; also used to split stored hashes,
  /// so it must match the encoder that made them.
  final int saltLength;

  /// How many times the HMAC is applied; more is slower to compute and to
  /// attack.
  final int iterations;

  /// The HMAC used by the derivation; HMAC-SHA256 by default.
  final Pbkdf2Algorithm algorithm;

  /// Whether hashes are written and read as Base64 instead of hex;
  /// Spring's `setEncodeHashAsBase64`.
  final bool encodeHashAsBase64;

  @override
  String encode(String rawPassword) {
    final salt = secureRandomBytes(saltLength);
    final hash = _derive(rawPassword, salt);
    final bytes = Uint8List.fromList([...salt, ...hash]);
    return encodeHashAsBase64 ? base64.encode(bytes) : _hex(bytes);
  }

  @override
  bool matches(String rawPassword, String? encodedPassword) {
    if (!_checkable(rawPassword, encodedPassword)) {
      return false;
    }
    final bytes = encodeHashAsBase64
        ? _tryBase64(encodedPassword!)
        : _unhex(encodedPassword!);
    if (bytes == null || bytes.length <= saltLength) {
      return false;
    }
    final salt = Uint8List.sublistView(bytes, 0, saltLength);
    final expected = Uint8List.sublistView(bytes, saltLength);
    if (expected.length != algorithm.hashBytes) {
      return false;
    }
    return constantTimeEquals(_derive(rawPassword, salt), expected);
  }

  @override
  bool upgradeEncoding(String? encodedPassword) => false;

  Uint8List _derive(String rawPassword, Uint8List salt) => pbkdf2(
    algorithm._hash,
    utf8.encode(rawPassword),
    Uint8List.fromList([...salt, ...utf8.encode(secret)]),
    iterations: iterations,
    length: algorithm.hashBytes,
  );
}

/// The HMAC that [Pbkdf2PasswordEncoder] derives keys with; it fixes the
/// hash length too.
///
/// Spring (Java): `Pbkdf2PasswordEncoder.SecretKeyFactoryAlgorithm`.
enum Pbkdf2Algorithm {
  /// HMAC-SHA1, giving a 20-byte hash; only to check old hashes.
  pbkdf2WithHmacSha1(20),

  /// HMAC-SHA256, giving a 32-byte hash; the default.
  pbkdf2WithHmacSha256(32),

  /// HMAC-SHA512, giving a 64-byte hash.
  pbkdf2WithHmacSha512(64);

  Pbkdf2Algorithm(this.hashBytes);

  /// The length of the derived key, in bytes.
  final int hashBytes;

  Pbkdf2Hash get _hash => switch (this) {
    pbkdf2WithHmacSha1 => Pbkdf2Hash.sha1,
    pbkdf2WithHmacSha256 => Pbkdf2Hash.sha256,
    pbkdf2WithHmacSha512 => Pbkdf2Hash.sha512,
  };
}

/// A [PasswordEncoder] using scrypt, a memory-hard function older than
/// Argon2.
///
/// Use it to keep checking `{scrypt}` hashes, for example of users moved
/// from a Java application; new hashes are better made with Argon2. The
/// hash is in Spring's format, `$<parameters in hex>$<salt>$<hash>` in
/// Base64, and carries its parameters. [matches] refuses a cost N above
/// 65 536 or a hash longer than 256 bytes, so a corrupted stored hash
/// cannot make one login run for long.
///
/// ```dart
/// final encoder = SCryptPasswordEncoder.defaultsForSpringSecurity();
/// encoder.matches('secret', storedScryptHash);
/// ```
///
/// Spring (Java):
/// ```java
/// SCryptPasswordEncoder.defaultsForSpringSecurity_v5_8();
/// ```
final class SCryptPasswordEncoder implements PasswordEncoder {
  /// An encoder with these parameters.
  ///
  /// Throws an [ArgumentError] unless [cpuCost] is a power of two from 2
  /// to 65 536, [memoryCost] and [parallelization] are from 1 to 255,
  /// [keyLength] is at least 1 and [saltLength] at least 8.
  SCryptPasswordEncoder({
    required this.cpuCost,
    required this.memoryCost,
    required this.parallelization,
    required this.keyLength,
    required this.saltLength,
  }) {
    if (cpuCost <= 1 || cpuCost & (cpuCost - 1) != 0 || cpuCost > 65536) {
      throw ArgumentError('cpuCost must be a power of 2 up to 65536');
    }
    if (memoryCost < 1 ||
        memoryCost > 255 ||
        parallelization < 1 ||
        parallelization > 255 ||
        keyLength < 1 ||
        saltLength < 8) {
      throw ArgumentError('Invalid scrypt parameters');
    }
  }

  /// Spring Security's current defaults, from
  /// `defaultsForSpringSecurity_v5_8`: N = 65 536, r = 8, p = 1, a
  /// 32-byte hash and a 16-byte salt.
  factory SCryptPasswordEncoder.defaultsForSpringSecurity() =>
      SCryptPasswordEncoder(
        cpuCost: 65536,
        memoryCost: 8,
        parallelization: 1,
        keyLength: 32,
        saltLength: 16,
      );

  /// The CPU and memory cost N of new hashes.
  final int cpuCost;

  /// The block size r of new hashes.
  final int memoryCost;

  /// The parallelization p of new hashes.
  final int parallelization;

  /// The length of new hashes, in bytes.
  final int keyLength;

  /// The length of the random salt of new hashes, in bytes.
  final int saltLength;

  @override
  String encode(String rawPassword) {
    final salt = secureRandomBytes(saltLength);
    final hash = _derive(
      rawPassword,
      salt,
      cpuCost,
      memoryCost,
      parallelization,
      keyLength,
    );
    final params = (_log2(cpuCost) << 16) | (memoryCost << 8) | parallelization;
    return '\$${params.toRadixString(16)}\$${base64.encode(salt)}'
        '\$${base64.encode(hash)}';
  }

  @override
  bool matches(String rawPassword, String? encodedPassword) {
    final decoded = _checkable(rawPassword, encodedPassword)
        ? _decode(encodedPassword)
        : null;
    if (decoded == null) {
      return false;
    }
    final (n, r, p, salt, expected) = decoded;
    return constantTimeEquals(
      _derive(rawPassword, salt, n, r, p, expected.length),
      expected,
    );
  }

  @override
  bool upgradeEncoding(String? encodedPassword) {
    final decoded = _decode(encodedPassword);
    if (decoded == null) {
      return false;
    }
    final (n, r, p, _, _) = decoded;
    return n < cpuCost || r < memoryCost || p < parallelization;
  }

  static (int, int, int, Uint8List, Uint8List)? _decode(String? encoded) {
    if (encoded == null || encoded.length < 2) {
      return null;
    }
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0].isNotEmpty) {
      return null;
    }
    final params = int.tryParse(parts[1], radix: 16);
    final salt = _tryBase64(parts[2]);
    final hash = _tryBase64(parts[3]);
    if (params == null || salt == null || hash == null || hash.isEmpty) {
      return null;
    }
    final log2n = params >> 16 & 0xffff;
    final r = params >> 8 & 0xff;
    final p = params & 0xff;
    // Bounded: N up to 2^16 (Spring's default), so one check stays cheap.
    if (log2n < 1 || log2n > 16 || r < 1 || p < 1 || hash.length > 256) {
      return null;
    }
    return (1 << log2n, r, p, salt, hash);
  }

  static Uint8List _derive(
    String rawPassword,
    Uint8List salt,
    int n,
    int r,
    int p,
    int length,
  ) {
    return scrypt(
      utf8.encode(rawPassword),
      salt,
      n: n,
      r: r,
      p: p,
      length: length,
    );
  }

  static int _log2(int value) => value.bitLength - 1;
}

/// A [PasswordEncoder] that stores the password as typed, without
/// hashing.
///
/// Only for tests and the `{noop}secret` passwords of demos: anyone who
/// reads the store reads the passwords. Never use it for real users. The
/// comparison still takes constant time.
///
/// Spring (Java): `NoOpPasswordEncoder.getInstance()` (deprecated there
/// as a warning).
final class NoOpPasswordEncoder implements PasswordEncoder {
  /// The stateless encoder.
  const NoOpPasswordEncoder();

  @override
  String encode(String rawPassword) => rawPassword;

  @override
  bool matches(String rawPassword, String? encodedPassword) =>
      _checkable(rawPassword, encodedPassword) &&
      constantTimeEquals(
        utf8.encode(rawPassword),
        utf8.encode(encodedPassword!),
      );

  @override
  bool upgradeEncoding(String? encodedPassword) => false;
}

/// A [PasswordEncoder] that stores the algorithm's name in front of each
/// hash, as `{id}`, and checks every hash with the encoder of its id.
///
/// It lets an application change its hashing algorithm without breaking
/// existing passwords: new hashes get the [idForEncode] encoder, old ones
/// keep working with theirs, and [upgradeEncoding] reports every hash of
/// another id so the login can re-hash it. A stored hash with no `{id}`,
/// or an id with no encoder, throws an [ArgumentError] from [matches],
/// unless [defaultPasswordEncoderForMatches] is set. That is a
/// configuration error, not a wrong password; a
/// `DaoAuthenticationProvider` refuses the login.
/// `{bcrypt}` hashes get an error message of their own: BCrypt is not
/// available here.
///
/// Most applications use the one from
/// [PasswordEncoderFactories.createDelegatingPasswordEncoder]. Build one
/// to choose the ids yourself.
///
/// ```dart
/// final encoder = DelegatingPasswordEncoder('argon2', {
///   'argon2': Argon2PasswordEncoder.defaultsForSpringSecurity(),
///   'noop': const NoOpPasswordEncoder(),
/// });
/// encoder.encode('secret'); // {argon2}$argon2id$...
/// encoder.matches('secret', '{noop}secret'); // true
/// ```
///
/// Spring (Java):
/// ```java
/// new DelegatingPasswordEncoder("argon2", Map.of(
///     "argon2", Argon2PasswordEncoder.defaultsForSpringSecurity_v5_8(),
///     "noop", NoOpPasswordEncoder.getInstance()));
/// ```
final class DelegatingPasswordEncoder implements PasswordEncoder {
  /// An encoder writing new hashes with `encoders[idForEncode]` and
  /// checking stored ones with the encoder of their `{id}`.
  ///
  /// Throws an [ArgumentError] when [idForEncode] is not a key of
  /// [encoders] or an id contains `{` or `}`.
  DelegatingPasswordEncoder(
    this.idForEncode,
    Map<String, PasswordEncoder> encoders, {
    this.defaultPasswordEncoderForMatches,
  }) : encoders = Map.unmodifiable(encoders) {
    if (!encoders.containsKey(idForEncode)) {
      throw ArgumentError('idForEncode $idForEncode is not in the encoders');
    }
    for (final id in encoders.keys) {
      if (id.contains('{') || id.contains('}')) {
        throw ArgumentError('The id $id cannot contain { or }');
      }
    }
  }

  /// The id written in front of new hashes, such as `argon2`.
  final String idForEncode;

  /// The encoders by id, without the braces; cannot be modified.
  final Map<String, PasswordEncoder> encoders;

  /// Checks stored hashes with no `{id}` or an unknown one, given the whole
  /// stored text; `null` by default, and then [matches] throws an
  /// [ArgumentError] naming the id (a misconfiguration, not a wrong
  /// password).
  final PasswordEncoder? defaultPasswordEncoderForMatches;

  @override
  String encode(String rawPassword) =>
      '{$idForEncode}${encoders[idForEncode]!.encode(rawPassword)}';

  @override
  bool matches(String rawPassword, String? encodedPassword) {
    if (!_checkable(rawPassword, encodedPassword)) {
      return false;
    }
    final (id, encoded) = _split(encodedPassword!);
    final delegate = id == null ? null : encoders[id];
    if (delegate != null) {
      return delegate.matches(rawPassword, encoded);
    }
    final fallback = defaultPasswordEncoderForMatches;
    if (fallback != null) {
      return fallback.matches(rawPassword, encodedPassword);
    }
    throw ArgumentError(
      id == 'bcrypt'
          ? 'There is no PasswordEncoder mapped for the id "bcrypt": BCrypt '
                'is not available in Dart without a vetted implementation; '
                'reset the password or re-hash it with {argon2} at login'
          : 'There is no PasswordEncoder mapped for the id "$id"',
    );
  }

  @override
  bool upgradeEncoding(String? encodedPassword) {
    if (encodedPassword == null) {
      return false;
    }
    final (id, encoded) = _split(encodedPassword);
    if (id != idForEncode) {
      return true;
    }
    return encoders[id]!.upgradeEncoding(encoded);
  }

  static (String?, String) _split(String encoded) {
    if (!encoded.startsWith('{')) {
      return (null, encoded);
    }
    final end = encoded.indexOf('}');
    if (end < 0) {
      return (null, encoded);
    }
    return (encoded.substring(1, end), encoded.substring(end + 1));
  }
}

/// Creates the recommended [PasswordEncoder] for an application.
///
/// This is the encoder logins use when the application declares no
/// `PasswordEncoder` bean, so hashes it writes are the ones the login
/// code expects.
///
/// ```dart
/// @Bean()
/// PasswordEncoder passwordEncoder() =>
///     PasswordEncoderFactories.createDelegatingPasswordEncoder();
/// ```
///
/// Spring (Java): `PasswordEncoderFactories`, with BCrypt as default
/// there.
abstract final class PasswordEncoderFactories {
  /// A [DelegatingPasswordEncoder] that writes Argon2 hashes (`{argon2}`)
  /// with Spring Security's defaults and checks `{argon2}`, `{pbkdf2}`,
  /// `{scrypt}`, their `@SpringSecurity_v5_8` variants and `{noop}`.
  ///
  /// Each id and its `@SpringSecurity_v5_8` variant use the same encoder,
  /// with the v5_8 defaults. For Argon2 and scrypt that makes no
  /// difference (the hash carries its parameters); `{pbkdf2}` hashes must
  /// have been made with the v5_8 PBKDF2 settings.
  ///
  /// Spring's default id is `bcrypt`. BCrypt is not here (there is no
  /// vetted Dart implementation), so new hashes are `{argon2}`, which
  /// Spring checks too. A `{bcrypt}` hash fails with an error saying so.
  static PasswordEncoder createDelegatingPasswordEncoder() {
    final argon2 = Argon2PasswordEncoder.defaultsForSpringSecurity();
    final pbkdf2 = Pbkdf2PasswordEncoder.defaultsForSpringSecurity();
    final scrypt = SCryptPasswordEncoder.defaultsForSpringSecurity();
    return DelegatingPasswordEncoder('argon2', {
      'argon2': argon2,
      'argon2@SpringSecurity_v5_8': argon2,
      'pbkdf2': pbkdf2,
      'pbkdf2@SpringSecurity_v5_8': pbkdf2,
      'scrypt': scrypt,
      'scrypt@SpringSecurity_v5_8': scrypt,
      'noop': const NoOpPasswordEncoder(),
    });
  }
}

String _b64(List<int> bytes) => base64.encode(bytes).replaceAll('=', '');

Uint8List? _unb64(String text) {
  if (!RegExp(r'^[A-Za-z0-9+/]*$').hasMatch(text)) {
    return null;
  }
  return _tryBase64(text.padRight((text.length + 3) & ~3, '='));
}

Uint8List? _tryBase64(String text) {
  try {
    return base64.decode(text);
  } on FormatException {
    return null;
  }
}

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

Uint8List? _unhex(String text) {
  if (text.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(text)) {
    return null;
  }
  return Uint8List.fromList([
    for (var i = 0; i < text.length; i += 2)
      int.parse(text.substring(i, i + 2), radix: 16),
  ]);
}
