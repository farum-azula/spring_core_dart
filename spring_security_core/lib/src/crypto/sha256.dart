import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_security_core/src/crypto/kdf_primitives.dart';

/// The SHA-256 digest of [bytes] (FIPS 180-4): 32 bytes.
///
/// For what a login needs a plain hash for: the `S256` code challenge of
/// a PKCE code verifier (RFC 7636 §4.2), the hash of a nonce, a
/// thumbprint. Not for passwords: those go through a `PasswordEncoder`
/// (Argon2, PBKDF2, scrypt), which is slow on purpose.
///
/// ```dart
/// final digest = sha256Digest(utf8.encode('abc'));
/// // ba7816bf 8f01cfea 414140de 5dae2223 b00361a3 96177a9c b410ff61 f20015ad
/// ```
///
/// Spring (Java): `MessageDigest.getInstance("SHA-256").digest(bytes)`.
Uint8List sha256Digest(List<int> bytes) => sha256(bytes);

/// The `S256` code challenge of the PKCE code verifier [verifier]
/// (RFC 7636 §4.2): the SHA-256 digest of its ASCII bytes in base64url
/// without padding.
///
/// ```dart
/// // RFC 7636, appendix B.
/// pkceS256Challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk');
/// // 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'
/// ```
///
/// Spring (Java): what `DefaultOAuth2AuthorizationRequestResolver` sends
/// as `code_challenge`.
String pkceS256Challenge(String verifier) =>
    base64UrlEncode(sha256Digest(ascii.encode(verifier))).replaceAll('=', '');
