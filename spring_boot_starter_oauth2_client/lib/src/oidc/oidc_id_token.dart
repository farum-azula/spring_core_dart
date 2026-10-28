import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/claims.dart';

/// The OpenID Connect ID token: the provider's signed statement of who
/// logged in, for which client, and when.
///
/// The token endpoint returns it next to the access token when the login
/// asked for the `openid` scope. The login checks it (issuer, audience,
/// expiry, nonce) and builds the [claims] of the user from it. It is also
/// the `id_token_hint` that ends the provider's session on logout. Its
/// value is a JWT (`header.payload.signature`).
///
/// ```dart
/// final user = login.user as OidcUser;
/// final idToken = user.idToken;
/// log.info('${idToken.subject} logged in at ${idToken.authenticatedAt}');
/// ```
///
/// Spring (Java): `OidcIdToken`.
class OidcIdToken extends AbstractOAuth2Token
    with ClaimAccessor, StandardClaimAccessor, IdTokenClaimAccessor {
  /// An ID token with [tokenValue] and its [claims], issued at
  /// [issuedAt] and expiring at [expiresAt].
  ///
  /// Nothing is checked here: build one by hand only in tests, or after
  /// checking the token yourself. [OidcIdToken.parse] reads a raw token.
  OidcIdToken(
    super.tokenValue, {
    required Map<String, Object?> claims,
    super.issuedAt,
    super.expiresAt,
  }) : claims = Map.unmodifiable(claims);

  /// Reads the JWT [tokenValue]: its header must be a JSON object whose
  /// `alg` is not `none`, its payload a JSON object of claims.
  ///
  /// The signature is **not** checked: an app trusts the ID token it got
  /// straight from the token endpoint over TLS (OpenID Connect Core
  /// §3.1.3.7); a server checks it with the provider's keys before (the
  /// security starter's `OidcIdTokenDecoder`). Neither are the claims:
  /// run `OidcIdTokenValidator` on the result.
  ///
  /// Throws a [FormatException] for anything that is not such a JWT,
  /// longer than 100 000 characters, or with `alg: none`.
  factory OidcIdToken.parse(String tokenValue) {
    if (tokenValue.length > maxLength) {
      throw const FormatException('The ID token is too long');
    }
    final parts = tokenValue.split('.');
    if (parts.length != 3 || parts[0].isEmpty || parts[1].isEmpty) {
      throw const FormatException('The ID token is not a signed JWT');
    }
    final header = _json(parts[0], 'header');
    final algorithm = header['alg'];
    if (algorithm is! String ||
        algorithm.isEmpty ||
        algorithm.toLowerCase() == 'none') {
      throw const FormatException(
        'The ID token is not signed (alg is missing or none)',
      );
    }
    if (parts[2].isEmpty) {
      throw const FormatException('The ID token has no signature');
    }
    final claims = _json(parts[1], 'payload');
    final times = _Claims(claims);
    final issuedAt = times.getClaimAsInstant(IdTokenClaimNames.iat);
    final expiresAt = times.getClaimAsInstant(IdTokenClaimNames.exp);
    return OidcIdToken(
      tokenValue,
      claims: claims,
      issuedAt: issuedAt,
      // AbstractOAuth2Token wants expiresAt after issuedAt; a token that
      // breaks it is refused by the validator, so it is kept apart here.
      expiresAt:
          issuedAt != null && expiresAt != null && !expiresAt.isAfter(issuedAt)
          ? null
          : expiresAt,
    );
  }

  /// The longest raw token [OidcIdToken.parse] reads.
  static const maxLength = 100000;

  @override
  final Map<String, Object?> claims;

  static Map<String, Object?> _json(String part, String what) {
    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(part))),
      );
    } on FormatException {
      throw FormatException('The ID token $what is not base64url JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw FormatException('The ID token $what is not a JSON object');
    }
    return decoded;
  }
}

/// What the provider's user-info endpoint says about the logged-in user:
/// name, email, picture and other claims the ID token may leave out.
///
/// `OidcUserService` loads it after the login when the provider has the
/// endpoint and the scopes allow it, and checks that its `sub` is the ID
/// token's. Read it through the user:
///
/// ```dart
/// final info = (login.user as OidcUser).userInfo;
/// log.info(info?.email);
/// ```
///
/// Spring (Java): `OidcUserInfo`.
final class OidcUserInfo with ClaimAccessor, StandardClaimAccessor {
  /// User info made of [claims].
  ///
  /// Throws an [ArgumentError] when [claims] is empty.
  OidcUserInfo(Map<String, Object?> claims)
    : claims = Map.unmodifiable(claims) {
    if (claims.isEmpty) {
      throw ArgumentError('claims cannot be empty');
    }
  }

  @override
  final Map<String, Object?> claims;
}

final class _Claims with ClaimAccessor {
  _Claims(this.claims);

  @override
  final Map<String, Object?> claims;
}
