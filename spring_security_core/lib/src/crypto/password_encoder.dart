import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_security_core/src/crypto/kdf_primitives.dart';

/// Encodes passwords for storage and checks a typed password against a
/// stored one, like Spring's `PasswordEncoder`.
///
/// ```dart
/// final encoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
/// final stored = encoder.encode('secret'); // {argon2}$argon2id$v=19$...
/// encoder.matches('secret', stored); // true
/// ```
abstract interface class PasswordEncoder {
  /// The encoded form of [rawPassword] (a new random salt each time).
  String encode(String rawPassword);

  /// Whether [rawPassword] is the password [encodedPassword] was made
  /// from; `false` for an empty [rawPassword] and for a missing, empty or
  /// malformed [encodedPassword] (like Spring Security 7's
  /// `AbstractValidatingPasswordEncoder`: an empty password never logs in).
  bool matches(String rawPassword, String? encodedPassword);

  /// Whether [encodedPassword] should be encoded again (made with weaker
  /// settings than this encoder's); `DaoAuthenticationProvider` then stores
  /// the new hash after a successful login.
  bool upgradeEncoding(String? encodedPassword);
}

/// Compares two byte lists in time independent of where they differ, like
/// Java's `MessageDigest.isEqual`: a check of a secret must not tell how
/// many leading bytes were right.
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

/// [length] cryptographically random bytes (`Random.secure`).
Uint8List secureRandomBytes(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = _random.nextInt(256);
  }
  return bytes;
}

/// Argon2 (the winner of the Password Hashing Competition), like Spring's
/// `Argon2PasswordEncoder` — which also uses Bouncy Castle. Hashes are in
/// the PHC format Spring writes, so hashes move between Java and Dart:
/// `$argon2id$v=19$m=16384,t=2,p=1$<salt>$<hash>`.
///
/// [Argon2PasswordEncoder.defaultsForSpringSecurity] are Spring Security's
/// current defaults (Argon2id, 16 MiB, 2 iterations, 1 lane, 16-byte salt,
/// 32-byte hash).
final class Argon2PasswordEncoder implements PasswordEncoder {
  /// An encoder with these parameters; [memory] in KiB.
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

  /// Spring Security's defaults (`defaultsForSpringSecurity_v5_8`).
  factory Argon2PasswordEncoder.defaultsForSpringSecurity() =>
      Argon2PasswordEncoder(
        saltLength: 16,
        hashLength: 32,
        parallelism: 1,
        memory: 1 << 14,
        iterations: 2,
      );

  /// Salt length in bytes.
  final int saltLength;

  /// Hash length in bytes.
  final int hashLength;

  /// Lanes.
  final int parallelism;

  /// Memory in KiB.
  final int memory;

  /// Passes over the memory.
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

  /// `true` when [encodedPassword] used less memory or fewer iterations
  /// than this encoder, like Spring.
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

/// PBKDF2, like Spring's `Pbkdf2PasswordEncoder`: hex of the salt followed
/// by the derived key (Spring's format, so hashes move between Java and
/// Dart). [Pbkdf2PasswordEncoder.defaultsForSpringSecurity] are Spring
/// Security's current defaults: HMAC-SHA256, 310 000 iterations, a 16-byte
/// salt, a 256-bit hash.
final class Pbkdf2PasswordEncoder implements PasswordEncoder {
  /// An encoder with these parameters; [secret] (a pepper kept outside
  /// the store) is mixed into the salt, like Spring's.
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

  /// Spring Security's defaults (`defaultsForSpringSecurity_v5_8`).
  factory Pbkdf2PasswordEncoder.defaultsForSpringSecurity() =>
      Pbkdf2PasswordEncoder(saltLength: 16, iterations: 310000);

  /// The pepper.
  final String secret;

  /// Salt length in bytes.
  final int saltLength;

  /// Iterations.
  final int iterations;

  /// The HMAC of the derivation.
  final Pbkdf2Algorithm algorithm;

  /// Base64 instead of hex (Spring's `setEncodeHashAsBase64`).
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

/// The HMACs of [Pbkdf2PasswordEncoder], like Spring's
/// `Pbkdf2PasswordEncoder.SecretKeyFactoryAlgorithm`.
enum Pbkdf2Algorithm {
  /// HMAC-SHA1 (20-byte hash; only for old hashes).
  pbkdf2WithHmacSha1(20),

  /// HMAC-SHA256 (32-byte hash; the default).
  pbkdf2WithHmacSha256(32),

  /// HMAC-SHA512 (64-byte hash).
  pbkdf2WithHmacSha512(64);

  Pbkdf2Algorithm(this.hashBytes);

  /// The derived key's length.
  final int hashBytes;

  Pbkdf2Hash get _hash => switch (this) {
    pbkdf2WithHmacSha1 => Pbkdf2Hash.sha1,
    pbkdf2WithHmacSha256 => Pbkdf2Hash.sha256,
    pbkdf2WithHmacSha512 => Pbkdf2Hash.sha512,
  };
}

/// scrypt, like Spring's `SCryptPasswordEncoder`, in Spring's format
/// (`$<params in hex>$<salt>$<hash>`, base64), so `{scrypt}` hashes of a
/// Java application keep working.
/// [SCryptPasswordEncoder.defaultsForSpringSecurity] are Spring Security's
/// current defaults (N = 65 536, r = 8, p = 1, 32-byte hash, 16-byte salt).
final class SCryptPasswordEncoder implements PasswordEncoder {
  /// An encoder with these parameters; [cpuCost] is a power of two.
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

  /// Spring Security's defaults (`defaultsForSpringSecurity_v5_8`).
  factory SCryptPasswordEncoder.defaultsForSpringSecurity() =>
      SCryptPasswordEncoder(
        cpuCost: 65536,
        memoryCost: 8,
        parallelization: 1,
        keyLength: 32,
        saltLength: 16,
      );

  /// N.
  final int cpuCost;

  /// r.
  final int memoryCost;

  /// p.
  final int parallelization;

  /// Hash length in bytes.
  final int keyLength;

  /// Salt length in bytes.
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

/// The password as given, like Spring's `NoOpPasswordEncoder`: only for
/// tests and `{noop}` passwords of demos; never for real users.
final class NoOpPasswordEncoder implements PasswordEncoder {
  /// The encoder.
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

/// Picks the encoder by the `{id}` prefix of a stored password, like
/// Spring's `DelegatingPasswordEncoder`: new passwords get the default
/// encoder's id, old ones keep working with theirs and are upgraded at
/// the next login.
///
/// ```dart
/// final encoder = DelegatingPasswordEncoder('argon2', {
///   'argon2': Argon2PasswordEncoder.defaultsForSpringSecurity(),
///   'noop': const NoOpPasswordEncoder(),
/// });
/// encoder.encode('secret'); // {argon2}$argon2id$...
/// encoder.matches('secret', '{noop}secret'); // true
/// ```
final class DelegatingPasswordEncoder implements PasswordEncoder {
  /// Encodes with the encoder named [idForEncode] among [encoders].
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

  /// The id of new hashes.
  final String idForEncode;

  /// The encoders by id.
  final Map<String, PasswordEncoder> encoders;

  /// Checks stored passwords without a known `{id}`; by default they are
  /// refused with an error naming the id (a misconfiguration, not a
  /// wrong password).
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

/// The application's default [PasswordEncoder], like Spring's
/// `PasswordEncoderFactories`.
abstract final class PasswordEncoderFactories {
  /// A [DelegatingPasswordEncoder] encoding with Argon2 (`{argon2}`) and
  /// checking `{argon2}`, `{pbkdf2}`, `{pbkdf2@SpringSecurity_v5_8}`,
  /// `{scrypt}`, `{scrypt@SpringSecurity_v5_8}`,
  /// `{argon2@SpringSecurity_v5_8}` and `{noop}` hashes.
  ///
  /// Spring's default id is `bcrypt`; BCrypt is not here (no vetted Dart
  /// implementation), so new hashes are `{argon2}` — which Spring checks
  /// too. A `{bcrypt}` hash fails with an error saying so.
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
