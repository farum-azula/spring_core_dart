import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/authority.dart';

/// A user as the application stores it, like Spring's `UserDetails`: the
/// name, the encoded password, the authorities and the account's state.
abstract interface class UserDetails {
  /// The login name.
  String get username;

  /// The encoded password (`{argon2}...`), or `null` when erased.
  String? get password;

  /// What the user may do.
  List<GrantedAuthority> get authorities;

  /// Whether the account has not expired.
  bool get isAccountNonExpired;

  /// Whether the account is not locked.
  bool get isAccountNonLocked;

  /// Whether the password has not expired.
  bool get isCredentialsNonExpired;

  /// Whether the account is enabled.
  bool get isEnabled;
}

/// The plain [UserDetails], like Spring's `User`; build one with
/// [User.withUsername].
///
/// ```dart
/// final ada = User.withUsername('ada')
///     .password('{argon2}...')
///     .roles(['ADMIN'])
///     .build();
/// ```
final class User implements UserDetails, CredentialsContainer {
  /// A user with all flags set (enabled, nothing expired or locked).
  User(
    String username,
    String? password,
    Iterable<GrantedAuthority> authorities,
  ) : this.full(username, password, authorities);

  /// A user with every flag given.
  User.full(
    this.username,
    this._password,
    Iterable<GrantedAuthority> authorities, {
    this.isEnabled = true,
    this.isAccountNonExpired = true,
    this.isCredentialsNonExpired = true,
    this.isAccountNonLocked = true,
  }) : authorities = List.unmodifiable(_sorted(authorities)) {
    if (username.isEmpty) {
      throw ArgumentError('A user needs a non-empty username');
    }
  }

  /// A builder for a user named [username].
  static UserBuilder withUsername(String username) =>
      UserBuilder._().username(username);

  /// A builder starting from [user].
  static UserBuilder withUserDetails(UserDetails user) => UserBuilder._()
      .username(user.username)
      .password(user.password)
      .authorities(user.authorities)
      .accountExpired(!user.isAccountNonExpired)
      .accountLocked(!user.isAccountNonLocked)
      .credentialsExpired(!user.isCredentialsNonExpired)
      .disabled(!user.isEnabled);

  @override
  final String username;

  String? _password;

  @override
  String? get password => _password;

  @override
  final List<GrantedAuthority> authorities;

  @override
  final bool isEnabled;

  @override
  final bool isAccountNonExpired;

  @override
  final bool isCredentialsNonExpired;

  @override
  final bool isAccountNonLocked;

  @override
  void eraseCredentials() => _password = null;

  // Like Spring: the same authorities in any order are the same set.
  static List<GrantedAuthority> _sorted(
    Iterable<GrantedAuthority> authorities,
  ) {
    final unique = <String?, GrantedAuthority>{};
    for (final authority in authorities) {
      unique.putIfAbsent(authority.authority, () => authority);
    }
    return unique.values.toList()
      ..sort((a, b) => (a.authority ?? '').compareTo(b.authority ?? ''));
  }

  /// Users are equal by username, like Spring's `User`.
  @override
  bool operator ==(Object other) => other is User && other.username == username;

  @override
  int get hashCode => username.hashCode;

  /// Never the password.
  @override
  String toString() =>
      'User [Username=$username, Password=[PROTECTED], Enabled=$isEnabled, '
      'AccountNonExpired=$isAccountNonExpired, '
      'CredentialsNonExpired=$isCredentialsNonExpired, '
      'AccountNonLocked=$isAccountNonLocked, Granted Authorities=$authorities]';
}

/// Builds a [User], like Spring's `User.UserBuilder`.
final class UserBuilder {
  UserBuilder._();

  String? _username;
  String? _password;
  List<GrantedAuthority> _authorities = const [];
  bool _accountExpired = false;
  bool _accountLocked = false;
  bool _credentialsExpired = false;
  bool _disabled = false;
  String Function(String)? _passwordEncoder;

  /// The username.
  UserBuilder username(String username) {
    _username = username;
    return this;
  }

  /// The (already encoded) password, e.g. `{argon2}...` or `{noop}secret`.
  UserBuilder password(String? password) {
    _password = password;
    return this;
  }

  /// Encodes the raw password given to [password] when building.
  UserBuilder passwordEncoder(String Function(String raw) encoder) {
    _passwordEncoder = encoder;
    return this;
  }

  /// Roles: `roles(['ADMIN'])` gives `ROLE_ADMIN`; a name already
  /// starting with `ROLE_` is refused, like Spring.
  UserBuilder roles(List<String> roles) {
    _authorities = [
      for (final role in roles)
        if (role.startsWith('ROLE_'))
          throw ArgumentError(
            '$role cannot start with ROLE_ (it is automatically added)',
          )
        else
          SimpleGrantedAuthority('ROLE_$role'),
    ];
    return this;
  }

  /// Authorities, replacing [roles].
  UserBuilder authorities(Iterable<GrantedAuthority> authorities) {
    _authorities = List.of(authorities);
    return this;
  }

  /// Authorities by name.
  UserBuilder authorityNames(List<String> authorities) {
    _authorities = AuthorityUtils.createAuthorityList(authorities);
    return this;
  }

  /// Whether the account has expired.
  UserBuilder accountExpired(bool value) {
    _accountExpired = value;
    return this;
  }

  /// Whether the account is locked.
  UserBuilder accountLocked(bool value) {
    _accountLocked = value;
    return this;
  }

  /// Whether the password has expired.
  UserBuilder credentialsExpired(bool value) {
    _credentialsExpired = value;
    return this;
  }

  /// Whether the account is disabled.
  UserBuilder disabled(bool value) {
    _disabled = value;
    return this;
  }

  /// The user.
  User build() {
    final username = _username;
    if (username == null) {
      throw StateError('A user needs a username');
    }
    final raw = _password;
    final encoder = _passwordEncoder;
    return User.full(
      username,
      raw != null && encoder != null ? encoder(raw) : raw,
      _authorities,
      isEnabled: !_disabled,
      isAccountNonExpired: !_accountExpired,
      isCredentialsNonExpired: !_credentialsExpired,
      isAccountNonLocked: !_accountLocked,
    );
  }
}
