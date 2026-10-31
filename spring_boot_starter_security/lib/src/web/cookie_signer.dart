import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_boot_starter_security/src/jwt/signature_primitives.dart'
    show hmacSha;
import 'package:spring_security_core/spring_security_core.dart'
    show constantTimeEquals;

/// Signs the values of the cookies the security starter keeps in the
/// browser instead of an HTTP session: the page to go back to after a
/// login (`CookieRequestCache`) and the OAuth 2.0 authorization request
/// of a login in progress (`CookieOAuth2AuthorizationRequestRepository`).
///
/// A signed value carries its cookie's name and an expiry, under an
/// HMAC-SHA-256 of a server key: the client can read it but neither change
/// it, move it to another cookie nor keep it past its expiry. [open]
/// checks the length, the characters and the signature before it reads
/// anything of the value, and answers `null` for any value it did not sign
/// itself, so code reading a cookie only ever sees what the server wrote.
///
/// The key comes from `spring.security.cookie.secret` (at least 32
/// characters); without it a random key is made at startup, which is
/// enough for one instance (a restart only fails the logins started just
/// before it). Several instances behind a proxy need the same secret.
///
/// Spring (Java): no equivalent; Spring Security keeps these in the
/// session.
final class CookieSigner {
  /// A signer with the [key] bytes (at least 32).
  CookieSigner(List<int> key) : _key = Uint8List.fromList(key) {
    if (key.length < 32) {
      throw ArgumentError.value(
        key.length,
        'key',
        'A cookie key needs at least 32 bytes',
      );
    }
  }

  /// A signer whose key is [secret], the value of
  /// `spring.security.cookie.secret` (at least 32 characters).
  factory CookieSigner.fromSecret(String secret) {
    if (secret.length < 32) {
      throw ArgumentError(
        'spring.security.cookie.secret must have at least 32 characters',
      );
    }
    return CookieSigner(utf8.encode(secret));
  }

  /// A signer with a random key of 32 bytes, known to this process only.
  factory CookieSigner.random() {
    final random = Random.secure();
    return CookieSigner([for (var i = 0; i < 32; i++) random.nextInt(256)]);
  }

  /// The signer of the process when no `CookieSigner` is configured.
  static final CookieSigner shared = CookieSigner.random();

  final Uint8List _key;

  /// The longest signed value [open] reads; browsers keep about 4096 bytes
  /// per cookie.
  static const maxLength = 4000;

  static final _characters = RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$');

  /// [value] signed for the cookie [cookieName], valid for [maxAge] from
  /// [now] (the current time by default).
  String sign(
    String cookieName,
    String value,
    Duration maxAge, {
    DateTime? now,
  }) {
    final expires = (now ?? DateTime.now()).add(maxAge).millisecondsSinceEpoch;
    final payload = utf8.encode('$expires\u0000$value');
    final encoded = base64Url.encode(payload).replaceAll('=', '');
    final mac = _mac(cookieName, encoded);
    return '$encoded.${base64Url.encode(mac).replaceAll('=', '')}';
  }

  /// The value [signed] carries when this signer signed it for
  /// [cookieName] and it has not expired at [now]; `null` for anything
  /// else (absent, too long, other characters, another signature or
  /// cookie, expired, not UTF-8).
  String? open(String cookieName, String? signed, {DateTime? now}) {
    if (signed == null ||
        signed.length > maxLength ||
        !_characters.hasMatch(signed)) {
      return null;
    }
    final dot = signed.indexOf('.');
    final encoded = signed.substring(0, dot);
    final List<int> mac;
    final List<int> payload;
    try {
      mac = base64Url.decode(base64Url.normalize(signed.substring(dot + 1)));
      if (!constantTimeEquals(mac, _mac(cookieName, encoded))) {
        return null;
      }
      payload = base64Url.decode(base64Url.normalize(encoded));
    } on FormatException {
      return null;
    }
    final String text;
    try {
      text = utf8.decode(payload);
    } on FormatException {
      return null;
    }
    final separator = text.indexOf('\u0000');
    final expires = separator < 0
        ? null
        : int.tryParse(text.substring(0, separator));
    if (expires == null ||
        (now ?? DateTime.now()).millisecondsSinceEpoch >= expires) {
      return null;
    }
    return text.substring(separator + 1);
  }

  // The name is signed too: a value cannot be moved to another cookie.
  Uint8List _mac(String cookieName, String encoded) => hmacSha(
    256,
    _key,
    Uint8List.fromList(utf8.encode('$cookieName\u0000$encoded')),
  );
}
