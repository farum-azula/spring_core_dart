import 'package:spring_boot_starter_supabase/src/auth/supabase_user.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// The access token of a signed-in user: what is sent as the bearer token
/// of their calls, with when it was received and when it expires.
///
/// The [tokenValue] is a credential: [toString] never shows it.
final class SupabaseAccessToken implements OAuth2Token {
  /// The token [tokenValue], received at [issuedAt], accepted until
  /// [expiresAt].
  const SupabaseAccessToken(this.tokenValue, {this.issuedAt, this.expiresAt});

  @override
  final String tokenValue;

  /// When the application received the token (UTC), by its own clock.
  @override
  final DateTime? issuedAt;

  @override
  final DateTime? expiresAt;

  @override
  String toString() =>
      'SupabaseAccessToken([PROTECTED], expiresAt: '
      '${expiresAt?.toIso8601String()})';
}

/// The `Authentication` of a user signed in through Supabase Auth: what
/// `SupabaseAuth` puts into the `SecurityContextHolder`, so `@PreAuthorize`
/// and everything else that reads the security context see the user.
///
/// - [name] is the user's id;
/// - [principal] is the [SupabaseUser];
/// - [credentials] is the access token, an `OAuth2Token`;
/// - [authorities] are `ROLE_<role>` for each of [SupabaseUser.roles]
///   (the strings of `app_metadata.roles`), the rule a server applies to
///   the same user's token. Nothing of `user_metadata` is read: a user
///   can write it.
///
/// ```dart
/// @PreAuthorize("hasRole('editor')")
/// Future<void> publish(Post post) async { ... }
/// ```
///
/// Spring (Java): no counterpart; closest is `JwtAuthenticationToken`.
final class SupabaseAuthenticationToken extends AbstractAuthenticationToken {
  /// The authentication of [principal] holding the token [credentials].
  SupabaseAuthenticationToken(this.principal, this.credentials)
    : super(authoritiesOf(principal)) {
    isAuthenticated = true;
  }

  /// The prefix of every authority made from a role.
  static const rolePrefix = 'ROLE_';

  /// The authorities of [user]: [rolePrefix] and each of its
  /// [SupabaseUser.roles].
  static List<GrantedAuthority> authoritiesOf(SupabaseUser user) => [
    for (final role in user.roles) SimpleGrantedAuthority('$rolePrefix$role'),
  ];

  @override
  final SupabaseUser principal;

  @override
  final SupabaseAccessToken credentials;

  /// The user's id.
  @override
  String get name => principal.id;

  @override
  String toString() =>
      'SupabaseAuthenticationToken [Principal=$name, '
      'Credentials=[PROTECTED], Authenticated=$isAuthenticated, '
      'Granted Authorities=$authorities]';
}
