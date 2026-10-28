// SHA-256 of the PKCE code challenge and the OpenID Connect nonce, and the
// only file of this package that imports `pointycastle`: Bouncy Castle's
// Dart port, a third-party package allowed as an exception until a Dart
// team package covers what the security packages need
// (docs/dependencies.md). It comes with spring_security_core anyway.
// Replacing it means rewriting this file alone; the RFC 7636 vector of
// test/pkce_test.dart checks the result.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show SHA256Digest;

/// The SHA-256 digest of [bytes].
Uint8List sha256(List<int> bytes) =>
    SHA256Digest().process(Uint8List.fromList(bytes));

/// The SHA-256 digest of the UTF-8 (here: ASCII) [value], in base64url
/// without padding: the `S256` code challenge of a PKCE code verifier
/// (RFC 7636 §4.2) and the nonce hash Spring Security sends to the
/// provider.
///
/// ```dart
/// // RFC 7636, appendix B.
/// sha256Base64Url('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk');
/// // 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'
/// ```
String sha256Base64Url(String value) =>
    base64UrlEncode(sha256(utf8.encode(value))).replaceAll('=', '');
