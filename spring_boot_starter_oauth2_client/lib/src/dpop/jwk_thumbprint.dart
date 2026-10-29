import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/src/core/sha256.dart';

/// The thumbprint of a public key (RFC 7638): a short, stable name of the
/// key, the same wherever and however the key is written.
///
/// DPoP (RFC 9449) needs it: a DPoP-bound access token names the key it
/// is bound to by this thumbprint in its `cnf.jkt` claim, and the server
/// compares it with the thumbprint of the key that signed the request's
/// proof. Apps and servers rarely call it themselves: the DPoP code of the
/// resource server and of the client does.
///
/// The thumbprint is the base64url SHA-256 of an exact JSON text: only
/// the key's required public members (`crv`, `kty`, `x`, `y` for EC;
/// `e`, `kty`, `n` for RSA), sorted, without spaces. That is why it is
/// written by hand here and not with a JSON serializer, which guarantees
/// neither the order nor the spacing.
///
/// ```dart
/// // RFC 9449's example key: the thumbprint a token bound to it carries.
/// JwkThumbprint.of({
///   'kty': 'EC',
///   'crv': 'P-256',
///   'x': 'l8tFrhx-34tV3hRICRDY9zCkDlpBhF42UQUfWVAWBFs',
///   'y': '9VE4jf_Ok_o64zbTTlcuNJajHmt6v9TDVrU0CdvGRDA',
/// }); // '0ZcOCORZNYy-DWpqq30jZyJGHTN0d2HglBV3uiguA4I'
/// ```
///
/// Spring (Java): Nimbus' `JWK.computeThumbprint()` (SHA-256), which
/// Spring Security's DPoP support uses.
abstract final class JwkThumbprint {
  /// The RFC 7638 SHA-256 thumbprint of [jwk], base64url without padding.
  ///
  /// Other members of [jwk] (`kid`, `alg`, `use`, private members) do not
  /// change the result. Throws a [FormatException] when `kty` is neither
  /// `EC` nor `RSA`, or a required member is missing or not a string.
  static String of(Map<String, Object?> jwk) {
    final members = switch (jwk['kty']) {
      'EC' => const ['crv', 'kty', 'x', 'y'],
      'RSA' => const ['e', 'kty', 'n'],
      _ => throw const FormatException(
        'A JWK thumbprint needs an EC or RSA key',
      ),
    };
    final text = StringBuffer('{');
    for (final (i, name) in members.indexed) {
      final value = jwk[name];
      if (value is! String) {
        throw FormatException('The JWK member "$name" is missing');
      }
      if (i > 0) {
        text.write(',');
      }
      // jsonEncode of a string escapes only what JSON requires, as RFC
      // 7638 §3 asks (the members are base64url or a curve name anyway).
      text
        ..write(jsonEncode(name))
        ..write(':')
        ..write(jsonEncode(value));
    }
    text.write('}');
    return sha256Base64Url(text.toString());
  }
}
