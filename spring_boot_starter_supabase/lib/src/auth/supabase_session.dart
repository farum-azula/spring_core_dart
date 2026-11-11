import 'dart:convert';

import 'package:spring_boot_starter_supabase/src/auth/supabase_authentication_token.dart';
import 'package:spring_boot_starter_supabase/src/auth/supabase_user.dart';

/// The session of a signed-in user as `SupabaseAuth` keeps it: the two
/// tokens, when the access token was received and when it expires, and
/// the user.
///
/// Both tokens are credentials. The session is written, as JSON
/// ([encode]), only to the application's `SecretStore`, and [toString]
/// shows neither token.
final class SupabaseSession {
  /// A session of [user].
  SupabaseSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    required this.issuedAt,
    this.expiresAt,
    this.tokenType = 'bearer',
  });

  /// The session in an answer of Auth
  /// (`{access_token, token_type, expires_in, expires_at, refresh_token,
  /// user}`), received at [now]; `null` when [json] is not a session.
  ///
  /// The expiry is counted from [now] by `expires_in`, so a clock of the
  /// device that is wrong does not expire the token early or late; only
  /// without `expires_in` is `expires_at` (seconds since 1970) taken.
  /// [user] is the user when the answer has none (a refresh may not
  /// repeat them).
  static SupabaseSession? fromResponse(
    Object? json,
    DateTime now, {
    SupabaseUser? user,
  }) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final accessToken = json['access_token'];
    final refreshToken = json['refresh_token'];
    final sessionUser = SupabaseUser.fromJson(json['user']) ?? user;
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty ||
        sessionUser == null) {
      return null;
    }
    final issuedAt = now.toUtc();
    return SupabaseSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: sessionUser,
      issuedAt: issuedAt,
      expiresAt: switch (json) {
        {'expires_in': final num seconds} => issuedAt.add(
          Duration(seconds: seconds.toInt()),
        ),
        {'expires_at': final num seconds} =>
          DateTime.fromMillisecondsSinceEpoch(
            seconds.toInt() * 1000,
            isUtc: true,
          ),
        _ => null,
      },
      tokenType: switch (json['token_type']) {
        final String type when type.isNotEmpty => type,
        _ => 'bearer',
      },
    );
  }

  /// The session written by [encode]; `null` when [text] is not one (a
  /// damaged value, another version).
  static SupabaseSession? decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?> || json['version'] != _version) {
      return null;
    }
    final accessToken = json['access_token'];
    final refreshToken = json['refresh_token'];
    final issuedAt = json['issued_at'];
    final expiresAt = json['expires_at'];
    final user = SupabaseUser.fromJson(json['user']);
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty ||
        issuedAt is! int ||
        (expiresAt != null && expiresAt is! int) ||
        user == null) {
      return null;
    }
    return SupabaseSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: user,
      issuedAt: DateTime.fromMillisecondsSinceEpoch(issuedAt, isUtc: true),
      expiresAt: expiresAt is int
          ? DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true)
          : null,
      tokenType: switch (json['token_type']) {
        final String type when type.isNotEmpty => type,
        _ => 'bearer',
      },
    );
  }

  static const _version = 1;

  /// The user's access token (a JWT): the bearer token of their calls.
  final String accessToken;

  /// The refresh token: exchanged, once, for the next pair of tokens.
  final String refreshToken;

  /// The kind of token; `bearer`.
  final String tokenType;

  /// When the access token was received (UTC), by the application's
  /// clock.
  final DateTime issuedAt;

  /// When the access token stops being accepted (UTC); `null` when Auth
  /// did not say.
  final DateTime? expiresAt;

  /// The signed-in user.
  final SupabaseUser user;

  /// The same session with another [user] (after `updateUser`).
  SupabaseSession withUser(SupabaseUser user) => SupabaseSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    user: user,
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    tokenType: tokenType,
  );

  /// Whether the access token expires within [margin] of [now]. A margin
  /// longer than half of the token's life counts as that half, so a
  /// short-lived token is not refreshed at every use.
  bool expiresWithin(Duration margin, DateTime now) {
    final expiresAt = this.expiresAt;
    return expiresAt != null && !now.isBefore(refreshAt(margin) ?? expiresAt);
  }

  /// When the access token should be refreshed: [margin] before its
  /// expiry (at most half of its life before); `null` when the expiry is
  /// unknown.
  DateTime? refreshAt(Duration margin) {
    final expiresAt = this.expiresAt;
    if (expiresAt == null) {
      return null;
    }
    final half = expiresAt.difference(issuedAt) ~/ 2;
    final effective = half < margin ? half : margin;
    return expiresAt.subtract(
      effective.isNegative ? Duration.zero : effective,
    );
  }

  /// The `Authentication` of this session.
  SupabaseAuthenticationToken toAuthentication() => SupabaseAuthenticationToken(
    user,
    SupabaseAccessToken(
      accessToken,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    ),
  );

  /// The session as JSON, for the `SecretStore` only; read by [decode].
  String encode() => jsonEncode({
    'version': _version,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': tokenType,
    'issued_at': issuedAt.millisecondsSinceEpoch,
    'expires_at': ?expiresAt?.millisecondsSinceEpoch,
    'user': user.toJson(),
  });

  @override
  String toString() =>
      'SupabaseSession(user: ${user.id}, expiresAt: '
      '${expiresAt?.toIso8601String()}, tokens: [PROTECTED])';
}
