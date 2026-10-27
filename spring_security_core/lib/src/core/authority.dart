/// Something a principal may do, like Spring's `GrantedAuthority`: a role
/// (`ROLE_ADMIN`), a scope (`SCOPE_read`) or any permission name.
abstract interface class GrantedAuthority {
  /// The authority's name; `null` for an authority that only a custom
  /// `AuthorizationManager` understands.
  String? get authority;
}

/// An authority given by its name, like Spring's `SimpleGrantedAuthority`.
///
/// ```dart
/// final admin = SimpleGrantedAuthority('ROLE_ADMIN');
/// ```
final class SimpleGrantedAuthority implements GrantedAuthority {
  /// The authority [authority] (not empty).
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

/// Helpers for lists of authorities, like Spring's `AuthorityUtils`.
abstract final class AuthorityUtils {
  /// No authorities.
  static const List<GrantedAuthority> noAuthorities = [];

  /// [SimpleGrantedAuthority]s for [authorities].
  ///
  /// ```dart
  /// AuthorityUtils.createAuthorityList(['ROLE_USER', 'SCOPE_read']);
  /// ```
  static List<GrantedAuthority> createAuthorityList(
    Iterable<String> authorities,
  ) => [for (final name in authorities) SimpleGrantedAuthority(name)];

  /// [SimpleGrantedAuthority]s from a comma-separated list
  /// (`'ROLE_A, ROLE_B'`).
  static List<GrantedAuthority> commaSeparatedStringToAuthorityList(
    String authorities,
  ) => createAuthorityList([
    for (final name in authorities.split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ]);

  /// The names of [authorities] (those with one).
  static Set<String> authorityListToSet(
    Iterable<GrantedAuthority> authorities,
  ) => {for (final authority in authorities) ?authority.authority};
}
