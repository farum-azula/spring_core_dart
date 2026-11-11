/// A user of the project's Auth, as Auth describes them: the principal of
/// a login made by `SupabaseAuth`, and what `SupabaseAuthAdmin` manages.
///
/// ```dart
/// final user = auth.user;
/// if (user != null) {
///   print('${user.id} ${user.email} ${user.userMetadata['name']}');
/// }
/// ```
///
/// [appMetadata] is written by the project (its service role) only;
/// [userMetadata] is written by the user themselves (`updateUser(data:)`),
/// so it never decides what a user may do: roles are read from
/// [appMetadata] alone.
final class SupabaseUser {
  /// A user with [id]; every other field is optional.
  SupabaseUser({
    required this.id,
    this.email,
    this.phone,
    this.role,
    Map<String, Object?> appMetadata = const {},
    Map<String, Object?> userMetadata = const {},
    this.createdAt,
    this.updatedAt,
    this.emailConfirmedAt,
    this.phoneConfirmedAt,
    this.lastSignInAt,
    this.isAnonymous = false,
  }) : appMetadata = Map.unmodifiable(appMetadata),
       userMetadata = Map.unmodifiable(userMetadata);

  /// The user in Auth's JSON (the `user` of a session, the answer of
  /// `/user` and of the admin API); `null` when [json] has no `id`.
  static SupabaseUser? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    return SupabaseUser(
      id: id,
      email: _text(json['email']),
      phone: _text(json['phone']),
      role: _text(json['role']),
      appMetadata: _object(json['app_metadata']),
      userMetadata: _object(json['user_metadata']),
      createdAt: _time(json['created_at']),
      updatedAt: _time(json['updated_at']),
      emailConfirmedAt: _time(json['email_confirmed_at']),
      phoneConfirmedAt: _time(json['phone_confirmed_at']),
      lastSignInAt: _time(json['last_sign_in_at']),
      isAnonymous: json['is_anonymous'] == true,
    );
  }

  /// The user's id (a UUID): the `sub` of their tokens and what
  /// `auth.uid()` gives in a policy of row-level security.
  final String id;

  /// The user's email address, when they have one.
  final String? email;

  /// The user's phone number, when they have one.
  final String? phone;

  /// The database role of the user's tokens: `authenticated` for a
  /// signed-in user.
  final String? role;

  /// What the project says about the user (`app_metadata`): the provider,
  /// and whatever the service role put there, such as `roles`. A user
  /// cannot change it.
  final Map<String, Object?> appMetadata;

  /// What the user says about themselves (`user_metadata`): a name, an
  /// avatar. The user can change all of it, so nothing here may grant
  /// anything.
  final Map<String, Object?> userMetadata;

  /// When the user was created.
  final DateTime? createdAt;

  /// When the user was last changed.
  final DateTime? updatedAt;

  /// When the email address was confirmed; `null` while it is not.
  final DateTime? emailConfirmedAt;

  /// When the phone number was confirmed; `null` while it is not.
  final DateTime? phoneConfirmedAt;

  /// When the user last signed in.
  final DateTime? lastSignInAt;

  /// Whether the user signed in anonymously (no email, no phone).
  final bool isAnonymous;

  /// The roles the project gave the user: the strings of
  /// `app_metadata.roles` (a list, or one text with spaces between them),
  /// trimmed, blank ones left out. A server reads the same claim of the
  /// user's token, so both sides see the same roles.
  ///
  /// Never anything from [userMetadata].
  List<String> get roles {
    final values = switch (appMetadata['roles']) {
      final String text => text.split(' '),
      final List<Object?> list => [
        for (final value in list)
          if (value is String) value,
      ],
      _ => const <String>[],
    };
    return [
      for (final value in values)
        if (value.trim().isNotEmpty) value.trim(),
    ];
  }

  /// The user in Auth's JSON, as [fromJson] reads it.
  Map<String, Object?> toJson() => {
    'id': id,
    'email': ?email,
    'phone': ?phone,
    'role': ?role,
    'app_metadata': appMetadata,
    'user_metadata': userMetadata,
    'created_at': ?createdAt?.toUtc().toIso8601String(),
    'updated_at': ?updatedAt?.toUtc().toIso8601String(),
    'email_confirmed_at': ?emailConfirmedAt?.toUtc().toIso8601String(),
    'phone_confirmed_at': ?phoneConfirmedAt?.toUtc().toIso8601String(),
    'last_sign_in_at': ?lastSignInAt?.toUtc().toIso8601String(),
    'is_anonymous': isAnonymous,
  };

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static Map<String, Object?> _object(Object? value) =>
      value is Map<String, Object?> ? value : const {};

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  /// The id only: an address or a phone number does not belong in a log.
  @override
  String toString() => 'SupabaseUser($id)';
}
