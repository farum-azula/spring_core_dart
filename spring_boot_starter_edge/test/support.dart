import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart'
    show sha256Digest;

/// The secret the function of the tests checks tokens with.
const jwtSecret = '0123456789abcdef0123456789abcdef';

Uint8List _hmacSha256(List<int> key, List<int> message) {
  final padded = Uint8List(64)..setAll(0, key);
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

/// A token with [claims], signed with [secret] (HS256, or what [header]
/// says).
String token(
  Map<String, Object?> claims, {
  String secret = jwtSecret,
  Map<String, Object?> header = const {'alg': 'HS256', 'typ': 'JWT'},
}) {
  final input =
      '${_part(utf8.encode(jsonEncode(header)))}'
      '.${_part(utf8.encode(jsonEncode(claims)))}';
  final signature = _hmacSha256(utf8.encode(secret), ascii.encode(input));
  return '$input.${_part(signature)}';
}

/// A token of the user [name] with [roles], valid for an hour (or expired
/// an hour ago).
String userToken(
  String name, {
  List<String> roles = const [],
  bool expired = false,
  String secret = jwtSecret,
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return token({
    'sub': name,
    'roles': roles,
    'iat': now - 7200,
    'exp': expired ? now - 3600 : now + 3600,
  }, secret: secret);
}

/// The JSON body of [response].
Future<Object?> jsonOf(FetchResponse response) async =>
    jsonDecode(utf8.decode(await response.readBytes()));

/// The text body of [response].
Future<String> textOf(FetchResponse response) async =>
    utf8.decode(await response.readBytes());
