/// One permission held by a logged-in user, named by a string such as
/// `ROLE_ADMIN` (a role), `SCOPE_read` (an OAuth scope) or any name the
/// application chooses.
///
/// Every access check compares these names: `hasRole('ADMIN')` looks for
/// `ROLE_ADMIN` among the user's authorities, `hasAuthority('SCOPE_read')`
/// for `SCOPE_read`. An application rarely implements this interface: it
/// gives users roles (`User.withUsername('ada').roles(['ADMIN'])`), and the
/// framework creates [SimpleGrantedAuthority]s for them.
///
/// Spring (Java): `GrantedAuthority`, the same interface.
abstract interface class GrantedAuthority {
  /// The name the checks compare, such as `ROLE_ADMIN`.
  ///
  /// `null` means the authority has no name a string check can match: the
  /// built-in role and authority checks ignore it, and only a custom
  /// `AuthorizationManager` that knows the class can use it.
  String? get authority;
}

/// The usual [GrantedAuthority]: nothing but its name.
///
/// Two of them are equal when their names are equal. Build one when you
/// create an `Authentication` by hand, for example in a custom login or a
/// test; users built with `User.withUsername(...)` get theirs already.
///
/// ```dart
/// // A service account authenticated by an API key gets one fixed role.
/// final token = UsernamePasswordAuthenticationToken.authenticated(
///   'billing-job',
///   null,
///   [SimpleGrantedAuthority('ROLE_SYSTEM')],
/// );
/// ```
///
/// Spring (Java): `new SimpleGrantedAuthority("ROLE_SYSTEM")`.
final class SimpleGrantedAuthority implements GrantedAuthority {
  /// An authority named [authority].
  ///
  /// Throws an [ArgumentError] when [authority] is empty.
  SimpleGrantedAuthority(String authority) : authority = _checked(authority);

  @override
  final String authority;

  static String _checked(String authority) {
    if (authority.isEmpty) {
      throw ArgumentError('A granted authority needs a non-empty name');
    }
    return authority;
  }

  @override
  bool operator ==(Object other) =>
      other is SimpleGrantedAuthority && other.authority == authority;

  @override
  int get hashCode => authority.hashCode;

  @override
  String toString() => authority;
}

/// Helpers that turn authority names into [GrantedAuthority] lists and
/// back.
///
/// Useful when authorities come as plain strings, for example from a
/// database column or a configuration property.
///
/// ```dart
/// // The roles column holds 'ROLE_USER, ROLE_BILLING'.
/// final authorities =
///     AuthorityUtils.commaSeparatedStringToAuthorityList(row.roles);
/// ```
///
/// Spring (Java): `AuthorityUtils`, with the same method names.
abstract final class AuthorityUtils {
  /// An empty, constant list of authorities.
  static const List<GrantedAuthority> noAuthorities = [];

  /// One [SimpleGrantedAuthority] per name in [authorities], in order.
  ///
  /// The names are used as they are (no `ROLE_` prefix is added). Throws an
  /// [ArgumentError] for an empty name.
  ///
  /// ```dart
  /// AuthorityUtils.createAuthorityList(['ROLE_USER', 'SCOPE_read']);
  /// ```
  static List<GrantedAuthority> createAuthorityList(
    Iterable<String> authorities,
  ) => [for (final name in authorities) SimpleGrantedAuthority(name)];

  /// One [SimpleGrantedAuthority] per name in a comma-separated string such
  /// as `'ROLE_A, ROLE_B'`.
  ///
  /// Spaces around each name are trimmed and empty entries are skipped, so
  /// `''` gives an empty list.
  static List<GrantedAuthority> commaSeparatedStringToAuthorityList(
    String authorities,
  ) => createAuthorityList([
    for (final name in authorities.split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ]);

  /// The names of [authorities], as a set.
  ///
  /// Authorities whose name is `null` are left out.
  static Set<String> authorityListToSet(
    Iterable<GrantedAuthority> authorities,
  ) => {for (final authority in authorities) ?authority.authority};
}
