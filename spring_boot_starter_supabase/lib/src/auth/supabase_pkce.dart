import 'dart:convert';
import 'dart:math';

import 'package:spring_security_core/spring_security_core.dart';

/// A login that waits for its redirect: the PKCE code verifier
/// (RFC 7636) made when the login started, and the address the answer
/// was asked to come back to.
///
/// Auth gets only the [challenge], the SHA-256 of the verifier; the code
/// that comes back in the redirect is worth nothing without the verifier,
/// which never leaves the application except, once, to Auth itself. The
/// [verifier] is a credential: it is kept only in the `SecretStore` and
/// [toString] does not show it.
final class SupabasePkceFlow {
  /// A flow with [verifier], asked to come back to [redirectTo].
  SupabasePkceFlow(this.verifier, {this.redirectTo});

  /// A new flow with a verifier of 256 random bits, from the platform's
  /// cryptographically secure generator.
  factory SupabasePkceFlow.start({String? redirectTo}) {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return SupabasePkceFlow(
      base64UrlEncode(bytes).replaceAll('=', ''),
      redirectTo: redirectTo,
    );
  }

  /// The flow written by [encode]; `null` when [text] is not one.
  static SupabasePkceFlow? decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json
        case {
          'verifier': final String verifier,
        }
        when verifier.isNotEmpty) {
      return SupabasePkceFlow(
        verifier,
        redirectTo: switch (json['redirect_to']) {
          final String redirect when redirect.isNotEmpty => redirect,
          _ => null,
        },
      );
    }
    return null;
  }

  /// The code challenge method sent to Auth.
  static const method = 's256';

  /// The code verifier: 43 characters of base64url.
  final String verifier;

  /// The address the login was asked to come back to; `null` when none
  /// was (a code typed by the user needs none).
  final String? redirectTo;

  /// The `S256` code challenge of [verifier]: base64url(SHA-256).
  String get challenge => pkceS256Challenge(verifier);

  /// The flow as JSON, for the `SecretStore` only; read by [decode].
  String encode() =>
      jsonEncode({'verifier': verifier, 'redirect_to': ?redirectTo});

  @override
  String toString() =>
      'SupabasePkceFlow(redirectTo: $redirectTo, verifier: [PROTECTED])';
}
