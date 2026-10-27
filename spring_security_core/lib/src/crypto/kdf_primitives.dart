// The key derivation functions of the password encoders, and the only file
// of this package that imports `pointycastle`: Bouncy Castle's Dart port, a
// third-party package allowed as an exception until a Dart team package
// covers Argon2 and scrypt (docs/dependencies.md). Replacing it means
// rewriting this file alone; the hashes written by Spring Security
// (test/vectors/) and the encoder tests check the result.
import 'dart:typed_data';

import 'package:pointycastle/export.dart'
    show
        Argon2BytesGenerator,
        Argon2Parameters,
        Digest,
        HMac,
        PBKDF2KeyDerivator,
        Pbkdf2Parameters,
        SHA1Digest,
        SHA256Digest,
        SHA512Digest,
        Scrypt,
        ScryptParameters;

/// The Argon2 variants (RFC 9106).
enum Argon2Type {
  /// Argon2d.
  d(Argon2Parameters.ARGON2_d),

  /// Argon2i.
  i(Argon2Parameters.ARGON2_i),

  /// Argon2id.
  id(Argon2Parameters.ARGON2_id);

  Argon2Type(this._value);

  final int _value;
}

/// Argon2 version 1.0 (`v=16`).
const argon2Version10 = 0x10;

/// Argon2 version 1.3 (`v=19`), the current one.
const argon2Version13 = 0x13;

/// Argon2 of [password] with [salt]: [length] bytes.
Uint8List argon2(
  List<int> password,
  Uint8List salt, {
  required Argon2Type type,
  required int version,
  required int memory,
  required int iterations,
  required int parallelism,
  required int length,
}) =>
    (Argon2BytesGenerator()..init(
          Argon2Parameters(
            type._value,
            salt,
            desiredKeyLength: length,
            iterations: iterations,
            memory: memory,
            lanes: parallelism,
            version: version,
          ),
        ))
        .process(Uint8List.fromList(password));

/// The hash functions of PBKDF2's HMAC.
enum Pbkdf2Hash {
  /// SHA-1.
  sha1,

  /// SHA-256.
  sha256,

  /// SHA-512.
  sha512,
}

/// PBKDF2 with HMAC-[hash] of [password] and [salt]: [length] bytes.
Uint8List pbkdf2(
  Pbkdf2Hash hash,
  List<int> password,
  Uint8List salt, {
  required int iterations,
  required int length,
}) {
  final (Digest digest, blockSize) = switch (hash) {
    Pbkdf2Hash.sha1 => (SHA1Digest(), 64),
    Pbkdf2Hash.sha256 => (SHA256Digest(), 64),
    Pbkdf2Hash.sha512 => (SHA512Digest(), 128),
  };
  return (PBKDF2KeyDerivator(HMac(digest, blockSize))
        ..init(Pbkdf2Parameters(salt, iterations, length)))
      .process(Uint8List.fromList(password));
}

/// scrypt of [password] with [salt] (cost [n], block size [r],
/// parallelization [p]): [length] bytes.
Uint8List scrypt(
  List<int> password,
  Uint8List salt, {
  required int n,
  required int r,
  required int p,
  required int length,
}) => (Scrypt()..init(ScryptParameters(n, r, p, length, salt))).process(
  Uint8List.fromList(password),
);
