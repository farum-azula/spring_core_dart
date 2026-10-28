/// The names of the claims of an OpenID Connect ID token (OpenID Connect
/// Core 1.0 §2).
///
/// Spring (Java): `IdTokenClaimNames`.
abstract final class IdTokenClaimNames {
  /// `iss`: who issued the token.
  static const iss = 'iss';

  /// `sub`: the user's id at the issuer.
  static const sub = 'sub';

  /// `aud`: the clients the token is for.
  static const aud = 'aud';

  /// `exp`: when the token expires.
  static const exp = 'exp';

  /// `iat`: when the token was issued.
  static const iat = 'iat';

  /// `auth_time`: when the user last entered credentials.
  static const authTime = 'auth_time';

  /// `nonce`: the value the client sent, against replays.
  static const nonce = 'nonce';

  /// `acr`: the authentication context class.
  static const acr = 'acr';

  /// `amr`: the authentication methods used.
  static const amr = 'amr';

  /// `azp`: the client the token was issued to.
  static const azp = 'azp';

  /// `at_hash`: the hash of the access token.
  static const atHash = 'at_hash';

  /// `c_hash`: the hash of the authorization code.
  static const cHash = 'c_hash';
}

/// The names of the standard claims about the user (OpenID Connect Core
/// 1.0 §5.1).
///
/// Spring (Java): `StandardClaimNames`.
abstract final class StandardClaimNames {
  /// `sub`.
  static const sub = 'sub';

  /// `name`.
  static const name = 'name';

  /// `given_name`.
  static const givenName = 'given_name';

  /// `family_name`.
  static const familyName = 'family_name';

  /// `middle_name`.
  static const middleName = 'middle_name';

  /// `nickname`.
  static const nickname = 'nickname';

  /// `preferred_username`.
  static const preferredUsername = 'preferred_username';

  /// `profile`.
  static const profile = 'profile';

  /// `picture`.
  static const picture = 'picture';

  /// `website`.
  static const website = 'website';

  /// `email`.
  static const email = 'email';

  /// `email_verified`.
  static const emailVerified = 'email_verified';

  /// `gender`.
  static const gender = 'gender';

  /// `birthdate`.
  static const birthdate = 'birthdate';

  /// `zoneinfo`.
  static const zoneinfo = 'zoneinfo';

  /// `locale`.
  static const locale = 'locale';

  /// `phone_number`.
  static const phoneNumber = 'phone_number';

  /// `phone_number_verified`.
  static const phoneNumberVerified = 'phone_number_verified';

  /// `address`.
  static const address = 'address';

  /// `updated_at`.
  static const updatedAt = 'updated_at';
}

/// Typed reading of a claim map: text, booleans, lists and times.
///
/// The ID token, the user info and the OIDC user mix it in; read claims
/// of your own with the same getters:
///
/// ```dart
/// final tenant = user.getClaimAsString('tenant');
/// final groups = user.getClaimAsStringList('groups') ?? const [];
/// ```
///
/// Spring (Java): `ClaimAccessor`.
mixin ClaimAccessor {
  /// The claims, by name; cannot be modified.
  Map<String, Object?> get claims;

  /// Whether the claim [name] is present (even with a `null` value).
  bool hasClaim(String name) => claims.containsKey(name);

  /// The claim [name] as text (`toString()` of a number); `null` when
  /// absent.
  String? getClaimAsString(String name) => switch (claims[name]) {
    null => null,
    final String text => text,
    final num number => '$number',
    final bool flag => '$flag',
    final other => '$other',
  };

  /// The claim [name] as a boolean: `true` / `false` or the strings
  /// `"true"` / `"false"`; `null` when absent or anything else.
  bool? getClaimAsBoolean(String name) => switch (claims[name]) {
    final bool flag => flag,
    'true' => true,
    'false' => false,
    _ => null,
  };

  /// The claim [name] as a list of text: a single string gives a list of
  /// one; `null` when absent.
  List<String>? getClaimAsStringList(String name) => switch (claims[name]) {
    null => null,
    final String one => [one],
    final List<Object?> many => [
      for (final value in many)
        if (value != null) '$value',
    ],
    final other => ['$other'],
  };

  /// The claim [name] as a time: seconds since 1970 (a NumericDate), in
  /// UTC; `null` when absent or not a number.
  DateTime? getClaimAsInstant(String name) => switch (claims[name]) {
    final num seconds when seconds.isFinite =>
      DateTime.fromMillisecondsSinceEpoch(
        (seconds * 1000).round(),
        isUtc: true,
      ),
    final String text => switch (num.tryParse(text)) {
      final num seconds when seconds.isFinite =>
        DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000).round(),
          isUtc: true,
        ),
      _ => null,
    },
    _ => null,
  };

  /// The claim [name] as a JSON object; `null` when absent or not an
  /// object.
  Map<String, Object?>? getClaimAsMap(String name) => switch (claims[name]) {
    final Map<String, Object?> map => map,
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries) '$key': value,
    },
    _ => null,
  };
}

/// The standard claims about a user, read from a claim map (OpenID
/// Connect Core 1.0 §5.1): name, email, picture, and so on.
///
/// An OIDC user, its ID token and its user info all have them:
///
/// ```dart
/// final user = login.user as OidcUser;
/// log.info('${user.fullName} <${user.email}>');
/// ```
///
/// Spring (Java): `StandardClaimAccessor`.
mixin StandardClaimAccessor on ClaimAccessor {
  /// `sub`: the user's id at the provider; never changes for one user.
  String? get subject => getClaimAsString(StandardClaimNames.sub);

  /// `name`: the full name.
  String? get fullName => getClaimAsString(StandardClaimNames.name);

  /// `given_name`.
  String? get givenName => getClaimAsString(StandardClaimNames.givenName);

  /// `family_name`.
  String? get familyName => getClaimAsString(StandardClaimNames.familyName);

  /// `middle_name`.
  String? get middleName => getClaimAsString(StandardClaimNames.middleName);

  /// `nickname`.
  String? get nickName => getClaimAsString(StandardClaimNames.nickname);

  /// `preferred_username`: the name the user goes by, not unique.
  String? get preferredUsername =>
      getClaimAsString(StandardClaimNames.preferredUsername);

  /// `profile`: the URL of the profile page.
  String? get profile => getClaimAsString(StandardClaimNames.profile);

  /// `picture`: the URL of the picture.
  String? get picture => getClaimAsString(StandardClaimNames.picture);

  /// `website`.
  String? get website => getClaimAsString(StandardClaimNames.website);

  /// `email`.
  String? get email => getClaimAsString(StandardClaimNames.email);

  /// `email_verified`: whether the provider checked the email.
  bool? get emailVerified =>
      getClaimAsBoolean(StandardClaimNames.emailVerified);

  /// `gender`.
  String? get gender => getClaimAsString(StandardClaimNames.gender);

  /// `birthdate`, as written (`YYYY-MM-DD`, or a year alone).
  String? get birthdate => getClaimAsString(StandardClaimNames.birthdate);

  /// `zoneinfo`: the time zone, such as `Europe/Paris`.
  String? get zoneInfo => getClaimAsString(StandardClaimNames.zoneinfo);

  /// `locale`, such as `en-US`.
  String? get locale => getClaimAsString(StandardClaimNames.locale);

  /// `phone_number`.
  String? get phoneNumber => getClaimAsString(StandardClaimNames.phoneNumber);

  /// `phone_number_verified`.
  bool? get phoneNumberVerified =>
      getClaimAsBoolean(StandardClaimNames.phoneNumberVerified);

  /// `address`: a JSON object (`street_address`, `locality`, ...).
  Map<String, Object?>? get address =>
      getClaimAsMap(StandardClaimNames.address);

  /// `updated_at`: when the profile last changed.
  DateTime? get updatedAt => getClaimAsInstant(StandardClaimNames.updatedAt);
}

/// The claims of an ID token: who issued it, for whom, until when, and
/// the `nonce`.
///
/// Spring (Java): `IdTokenClaimAccessor`.
mixin IdTokenClaimAccessor on StandardClaimAccessor {
  /// `iss`: the provider that issued the token.
  String? get issuer => getClaimAsString(IdTokenClaimNames.iss);

  /// `aud`: the clients the token is for; it must name this one.
  List<String> get audience =>
      getClaimAsStringList(IdTokenClaimNames.aud) ?? const [];

  /// `exp`: when the token expires (UTC).
  DateTime? get expiresAt => getClaimAsInstant(IdTokenClaimNames.exp);

  /// `iat`: when the token was issued (UTC).
  DateTime? get issuedAt => getClaimAsInstant(IdTokenClaimNames.iat);

  /// `auth_time`: when the user last entered credentials (UTC).
  DateTime? get authenticatedAt =>
      getClaimAsInstant(IdTokenClaimNames.authTime);

  /// `nonce`: what the client sent in the authorization request (here,
  /// its SHA-256 hash).
  String? get nonce => getClaimAsString(IdTokenClaimNames.nonce);

  /// `acr`.
  String? get authenticationContextClass =>
      getClaimAsString(IdTokenClaimNames.acr);

  /// `amr`.
  List<String>? get authenticationMethods =>
      getClaimAsStringList(IdTokenClaimNames.amr);

  /// `azp`: the client the token was issued to.
  String? get authorizedParty => getClaimAsString(IdTokenClaimNames.azp);

  /// `at_hash`.
  String? get accessTokenHash => getClaimAsString(IdTokenClaimNames.atHash);

  /// `c_hash`.
  String? get authorizationCodeHash =>
      getClaimAsString(IdTokenClaimNames.cHash);
}
