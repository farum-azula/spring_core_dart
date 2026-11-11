import 'dart:convert';

import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

void main() {
  String sha(String text) => Sha256.hex(Sha256.digest(utf8.encode(text)));

  group('Sha256.digest', () {
    test('the vectors of FIPS 180-4', () {
      expect(
        sha(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        sha('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });

    test('a message of a million bytes', () {
      expect(
        Sha256.hex(Sha256.digest(List.filled(1000000, 0x61))),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });

    test('messages around the block boundary', () {
      expect(
        sha('a' * 55),
        '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318',
      );
      expect(
        sha('a' * 56),
        'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a',
      );
      expect(
        sha('a' * 64),
        'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
      );
    });
  });

  group('Sha256.hmac', () {
    test('the vectors of RFC 4231', () {
      expect(
        Sha256.hex(
          Sha256.hmac(List.filled(20, 0x0b), utf8.encode('Hi There')),
        ),
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );
      expect(
        Sha256.hex(
          Sha256.hmac(
            utf8.encode('Jefe'),
            utf8.encode('what do ya want for nothing?'),
          ),
        ),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
    });

    test('a key longer than a block is hashed first', () {
      expect(
        Sha256.hex(
          Sha256.hmac(
            List.filled(131, 0xaa),
            utf8.encode(
              'Test Using Larger Than Block-Size Key - Hash Key First',
            ),
          ),
        ),
        '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
      );
    });
  });
}
