// SHA-256 against the vectors of FIPS 180-4 (the NIST examples), and the
// PKCE code challenge against RFC 7636, appendix B.
import 'dart:convert';

import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

void main() {
  group('sha256Digest', () {
    test('the empty message', () {
      expect(
        _hex(sha256Digest(const [])),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('one block: "abc"', () {
      expect(
        _hex(sha256Digest(utf8.encode('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('two blocks', () {
      expect(
        _hex(
          sha256Digest(
            utf8.encode(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
            ),
          ),
        ),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });

    test('a million times "a"', () {
      expect(
        _hex(sha256Digest(List.filled(1000000, 0x61))),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });

    test('32 bytes, and the argument is not changed', () {
      final bytes = [1, 2, 3];
      expect(sha256Digest(bytes), hasLength(32));
      expect(bytes, [1, 2, 3]);
    });
  });

  group('pkceS256Challenge', () {
    test('the vector of RFC 7636, appendix B', () {
      expect(
        pkceS256Challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('base64url without padding', () {
      final challenge = pkceS256Challenge('a' * 43);
      expect(challenge, hasLength(43));
      expect(challenge, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });
  });
}
