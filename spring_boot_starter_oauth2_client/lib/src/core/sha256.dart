// SHA-256 of the PKCE code challenge, the OpenID Connect nonce, RFC 7638
// thumbprints and DPoP's `ath`, computed by crypto_primitives.dart (the
// only file of this package that imports `pointycastle`).
import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/src/core/crypto_primitives.dart';

export 'package:spring_boot_starter_oauth2_client/src/core/crypto_primitives.dart'
    show sha256;

/// The SHA-256 digest of the UTF-8 (here: ASCII) [value], in base64url
/// without padding: the `S256` code challenge of a PKCE code verifier
/// (RFC 7636 §4.2), the nonce hash Spring Security sends to the provider,
/// and the `ath` of a DPoP proof (RFC 9449 §4.2).
///
/// ```dart
/// // RFC 7636, appendix B.
/// sha256Base64Url('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk');
/// // 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'
/// ```
String sha256Base64Url(String value) =>
    base64UrlEncode(sha256(utf8.encode(value))).replaceAll('=', '');
