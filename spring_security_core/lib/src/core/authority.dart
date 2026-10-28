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

/// Turns the authorities a login produced into the ones the application
/// checks.
///
/// A login through another system brings that system's names: an OAuth 2.0
/// login gives `OIDC_USER` and `SCOPE_profile`, a Keycloak token may carry
/// the realm roles `admin` and `user`. A mapper renames, adds or drops
/// them, so `@PreAuthorize("hasRole('ADMIN')")` works whatever the
/// provider called it. Declare one as a bean; the OAuth2 login applies it
/// to every user it logs in. Most applications need none: the default,
/// [NullAuthoritiesMapper], keeps the authorities as they are.
///
/// ```dart
/// // Users of the provider's group "admins" are ROLE_ADMIN here.
/// final class AdminMapper implements GrantedAuthoritiesMapper {
///   @override
///   List<GrantedAuthority> mapAuthorities(
///     Iterable<GrantedAuthority> authorities,
///   ) => [
///     ...authorities,
///     if (authorities.any((a) => a.authority == 'GROUP_admins'))
///       SimpleGrantedAuthority('ROLE_ADMIN'),
///   ];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// GrantedAuthoritiesMapper adminMapper() {
///   return authorities -> { ... };
/// }
/// ```
abstract interface class GrantedAuthoritiesMapper {
  /// The authorities to keep for [authorities]; may be empty.
  List<GrantedAuthority> mapAuthorities(Iterable<GrantedAuthority> authorities);
}

/// The [GrantedAuthoritiesMapper] that changes nothing: the default.
///
/// Spring (Java): `NullAuthoritiesMapper`.
final class NullAuthoritiesMapper implements GrantedAuthoritiesMapper {
  /// The mapper; it has no state.
  const NullAuthoritiesMapper();

  @override
  List<GrantedAuthority> mapAuthorities(
    Iterable<GrantedAuthority> authorities,
  ) => List.of(authorities);
}
