import 'dart:typed_data';

/// SHA-256 (FIPS 180-4) and HMAC-SHA-256 (RFC 2104) in plain Dart, for the
/// framework's own needs on every platform (the VM, JavaScript and
/// WebAssembly): a digest of a key, a keyed hash of an address. It has no
/// dependency.
///
/// It is not made for passwords (use a `PasswordEncoder` of
/// `spring_security_core`), and it makes no promise about timing.
///
/// ```dart
/// final digest = Sha256.digest(utf8.encode('abc'));
/// final tag = Sha256.hmac(utf8.encode(secret), utf8.encode('203.0.113.7'));
/// print(Sha256.hex(tag)); // 64 hexadecimal digits
/// ```
///
/// Spring (Java): `MessageDigest.getInstance("SHA-256")` and
/// `Mac.getInstance("HmacSHA256")` of the JDK.
abstract final class Sha256 {
  /// The length of a digest, in bytes.
  static const digestLength = 32;

  static const _blockLength = 64;

  static final _k = Uint32List.fromList(const [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ]);

  /// The SHA-256 digest of [bytes]: 32 bytes.
  static Uint8List digest(List<int> bytes) {
    final length = bytes.length;
    // The message, a 0x80 byte, zeros, and its length in bits as 64 bits,
    // to a whole number of 64-byte blocks.
    final padded = Uint8List(((length + 8) ~/ _blockLength + 1) * _blockLength)
      ..setRange(0, length, bytes);
    padded[length] = 0x80;
    // The length as two 32-bit halves: a 64-bit integer does not exist in
    // JavaScript.
    final view = ByteData.sublistView(padded)
      ..setUint32(padded.length - 8, length ~/ 0x20000000)
      ..setUint32(padded.length - 4, (length & 0x1fffffff) << 3);

    final h = Uint32List.fromList(const [
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]);
    final w = Uint32List(64);
    for (var offset = 0; offset < padded.length; offset += _blockLength) {
      for (var i = 0; i < 16; i++) {
        w[i] = view.getUint32(offset + i * 4);
      }
      for (var i = 16; i < 64; i++) {
        final x = w[i - 15];
        final y = w[i - 2];
        final s0 = _rotr(x, 7) ^ _rotr(x, 18) ^ (x >>> 3);
        final s1 = _rotr(y, 17) ^ _rotr(y, 19) ^ (y >>> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
      }
      var a = h[0];
      var b = h[1];
      var c = h[2];
      var d = h[3];
      var e = h[4];
      var f = h[5];
      var g = h[6];
      var hh = h[7];
      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final t1 = (hh + s1 + ch + _k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = (s0 + maj) & 0xffffffff;
        hh = g;
        g = f;
        f = e;
        e = (d + t1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) & 0xffffffff;
      }
      h[0] += a;
      h[1] += b;
      h[2] += c;
      h[3] += d;
      h[4] += e;
      h[5] += f;
      h[6] += g;
      h[7] += hh;
    }
    final out = ByteData(digestLength);
    for (var i = 0; i < 8; i++) {
      out.setUint32(i * 4, h[i]);
    }
    return out.buffer.asUint8List();
  }

  /// The HMAC-SHA-256 of [message] under [key]: 32 bytes. Only who has
  /// the key can compute it, so the hash of a guessable value (an address)
  /// cannot be reversed by trying every value.
  static Uint8List hmac(List<int> key, List<int> message) {
    final block = Uint8List(_blockLength);
    final short = key.length > _blockLength ? digest(key) : key;
    block.setRange(0, short.length, short);
    final inner = Uint8List(_blockLength + message.length);
    final outer = Uint8List(_blockLength + digestLength);
    for (var i = 0; i < _blockLength; i++) {
      inner[i] = block[i] ^ 0x36;
      outer[i] = block[i] ^ 0x5c;
    }
    inner.setRange(_blockLength, inner.length, message);
    outer.setRange(_blockLength, outer.length, digest(inner));
    return digest(outer);
  }

  /// [bytes] as lower-case hexadecimal digits, two per byte.
  static String hex(List<int> bytes) {
    final text = StringBuffer();
    for (final byte in bytes) {
      text.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return text.toString();
  }

  static int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;
}
