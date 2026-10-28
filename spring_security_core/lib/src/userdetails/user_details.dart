import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/authority.dart';

/// What the security code needs to know about one of your users to log
/// them in: the username, the stored password hash, the authorities and
/// whether the account may log in at all.
///
/// Your user store returns it from `UserDetailsService.loadUserByUsername`,
/// and after a successful login it becomes the `principal` of the
/// `Authentication`. Most applications build a [User] instead of
/// implementing this interface. Implement it on your own account class
/// when you want the principal to carry more, such as the account id or
/// the tenant.
///
/// ```dart
/// // The account entity itself serves as the logged-in principal.
/// class Account implements UserDetails {
///   Account(this.id, this.email, this.passwordHash, this.authorities);
///
///   final int id;
///   final String email;
///   final String passwordHash;
///
///   @override
///   String get username => email;
///
///   @override
///   String? get password => passwordHash;
///
///   @override
///   final List<GrantedAuthority> authorities;
///
///   @override
///   bool get isAccountNonExpired => true;
///
///   @override
///   bool get isAccountNonLocked => true;
///
///   @override
///   bool get isCredentialsNonExpired => true;
///
///   @override
///   bool get isEnabled => true;
/// }
/// ```
///
/// Spring (Java): `UserDetails`; Java's `getUsername()` and
/// `isEnabled()` are getters here.
abstract interface class UserDetails {
  /// The name the user logs in with; `Authentication.name` returns it.
  String get username;

  /// The stored password hash, such as `{argon2}$argon2id$...`; `null`
  /// after the login erased it, and a `null` password never matches.
  String? get password;

  /// The user's permissions, such as `ROLE_ADMIN`; they become the
  /// authorities of the `Authentication`.
  List<GrantedAuthority> get authorities;

  /// `false` refuses every login with an `AccountExpiredException`,
  /// before the password is checked.
  bool get isAccountNonExpired;

  /// `false` refuses every login with a `LockedException`, before the
  /// password is checked.
  bool get isAccountNonLocked;

  /// `false` refuses the login with a `CredentialsExpiredException`, after
  /// the password matched.
  bool get isCredentialsNonExpired;

  /// `false` refuses every login with a `DisabledException`, before the
  /// password is checked.
  bool get isEnabled;
}

/// A ready-made [UserDetails]: a username, a password hash, authorities
/// and the four account flags, all fixed at creation.
///
/// Build one with [User.withUsername], usually inside your
/// `UserDetailsService` from a database row, or for the users of an
/// `InMemoryUserDetailsManager`. Two users are equal when their usernames
/// are equal. Duplicate authorities are dropped and the rest are sorted by
/// name. [toString] never shows the password.
///
/// ```dart
/// // A user loaded from the accounts table.
/// final user = User.withUsername(row.email)
///     .password(row.passwordHash) // {argon2}$argon2id$...
///     .roles(['ADMIN'])
///     .build();
/// ```
///
/// Spring (Java):
/// ```java
/// UserDetails user = User.withUsername(row.email())
///     .password(row.passwordHash())
///     .roles("ADMIN")
///     .build();
/// ```
final class User implements UserDetails, CredentialsContainer {
  /// An enabled user with nothing expired or locked.
  ///
  /// [password] is the stored hash. Throws an [ArgumentError] when
  /// [username] is empty.
  User(
    String username,
    String? password,
    Iterable<GrantedAuthority> authorities,
  ) : this.full(username, password, authorities);

  /// A user with every account flag given; all default to `true`, the
  /// state that allows a login.
  ///
  /// Throws an [ArgumentError] when [username] is empty.
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

  /// Starts building a user named [username]; finish with
  /// [UserBuilder.build].
  static UserBuilder withUsername(String username) =>
      UserBuilder._().username(username);

  /// Starts building a copy of [user], with its password, authorities and
  /// flags, so you can change one thing, such as the password.
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

  /// Users are equal when their usernames are equal; the password,
  /// authorities and flags are not compared.
  @override
  bool operator ==(Object other) => other is User && other.username == username;

  @override
  int get hashCode => username.hashCode;

  /// A description for logs: everything but the password, which shows as
  /// `[PROTECTED]`.
  @override
  String toString() =>
      'User [Username=$username, Password=[PROTECTED], Enabled=$isEnabled, '
      'AccountNonExpired=$isAccountNonExpired, '
      'CredentialsNonExpired=$isCredentialsNonExpired, '
      'AccountNonLocked=$isAccountNonLocked, Granted Authorities=$authorities]';
}

/// Collects the parts of a [User] step by step; get one from
/// [User.withUsername] or [User.withUserDetails].
///
/// Without calls to the flag methods the user is enabled, with nothing
/// expired or locked. Each authority method replaces what an earlier one
/// set.
///
/// Spring (Java): `User.UserBuilder`.
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

  /// Sets the username; [build] throws an [ArgumentError] when it is
  /// empty.
  UserBuilder username(String username) {
    _username = username;
    return this;
  }

  /// Sets the stored password, already encoded, such as `{argon2}...` (or
  /// `{noop}secret` in a demo).
  ///
  /// When [passwordEncoder] is also set, this is the raw password and is
  /// encoded at [build].
  UserBuilder password(String? password) {
    _password = password;
    return this;
  }

  /// Makes [build] encode the value given to [password] with [encoder],
  /// so you can write the raw password.
  ///
  /// Meant for demos and tests: in production the password comes already
  /// encoded from the store.
  UserBuilder passwordEncoder(String Function(String raw) encoder) {
    _passwordEncoder = encoder;
    return this;
  }

  /// Sets the authorities from role names: `roles(['ADMIN'])` gives the
  /// authority `ROLE_ADMIN`.
  ///
  /// Replaces any authorities set before. Throws an [ArgumentError] for a
  /// name that already starts with `ROLE_`, as Spring does.
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

  /// Sets the authorities, replacing any set before by [roles] or
  /// [authorityNames].
  UserBuilder authorities(Iterable<GrantedAuthority> authorities) {
    _authorities = List.of(authorities);
    return this;
  }

  /// Sets the authorities by their full names, such as `ROLE_ADMIN` or
  /// `SCOPE_read` (no prefix is added); replaces any set before.
  UserBuilder authorityNames(List<String> authorities) {
    _authorities = AuthorityUtils.createAuthorityList(authorities);
    return this;
  }

  /// `true` makes every login fail with an `AccountExpiredException`.
  UserBuilder accountExpired(bool value) {
    _accountExpired = value;
    return this;
  }

  /// `true` makes every login fail with a `LockedException`.
  UserBuilder accountLocked(bool value) {
    _accountLocked = value;
    return this;
  }

  /// `true` makes the login fail with a `CredentialsExpiredException`
  /// once the password matched.
  UserBuilder credentialsExpired(bool value) {
    _credentialsExpired = value;
    return this;
  }

  /// `true` makes every login fail with a `DisabledException`.
  UserBuilder disabled(bool value) {
    _disabled = value;
    return this;
  }

  /// Creates the [User].
  ///
  /// Throws a [StateError] when no username was set, and an [ArgumentError]
  /// when it is empty.
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
