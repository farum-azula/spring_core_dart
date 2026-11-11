import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

Uint8List _hmacSha256(List<int> key, List<int> message) {
  var block = Uint8List.fromList(key);
  if (block.length > 64) {
    block = sha256Digest(block);
  }
  final padded = Uint8List(64)..setAll(0, block);
  final inner = Uint8List.fromList([
    for (final byte in padded) byte ^ 0x36,
    ...message,
  ]);
  return sha256Digest([
    for (final byte in padded) byte ^ 0x5c,
    ...sha256Digest(inner),
  ]);
}

String _part(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// A token with [claims], signed with [secret] (HS256), as a project with
/// a legacy secret (and a bare PostgREST) signs them.
String hs256Token(String secret, Map<String, Object?> claims) {
  final input =
      '${_part(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})))}'
      '.${_part(utf8.encode(jsonEncode(claims)))}';
  final signature = _hmacSha256(utf8.encode(secret), ascii.encode(input));
  return '$input.${_part(signature)}';
}
