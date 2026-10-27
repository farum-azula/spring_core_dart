import 'dart:async';

import 'package:spring_security_core/src/core/exceptions.dart';
import 'package:spring_security_core/src/userdetails/user_details.dart';

/// Loads a user by name, like Spring's `UserDetailsService`: the store of
/// the application's users (a database, a directory, memory).
///
/// ```dart
/// @Service()
/// class AccountUsers implements UserDetailsService {
///   AccountUsers(this.accounts);
///   final AccountRepository accounts;
///
///   @override
///   Future<UserDetails> loadUserByUsername(String username) async {
///     final account = await accounts.findByEmail(username) ??
///         (throw UsernameNotFoundException(username));
///     return User.withUsername(account.email)
///         .password(account.passwordHash)
///         .roles(account.roles)
///         .build();
///   }
/// }
/// ```
abstract interface class UserDetailsService {
  /// The user named [username]; throws [UsernameNotFoundException] when
  /// there is none.
  FutureOr<UserDetails> loadUserByUsername(String username);
}

/// Stores a re-encoded password, like Spring's `UserDetailsPasswordService`:
/// `DaoAuthenticationProvider` upgrades a hash made with old settings at the
/// next successful login.
abstract interface class UserDetailsPasswordService {
  /// [user] with [newPassword] (encoded) stored.
  FutureOr<UserDetails> updatePassword(UserDetails user, String newPassword);
}

/// A [UserDetailsService] that can also change users, like Spring's
/// `UserDetailsManager`.
abstract interface class UserDetailsManager implements UserDetailsService {
  /// Adds [user].
  FutureOr<void> createUser(UserDetails user);

  /// Replaces the user with [user]'s name.
  FutureOr<void> updateUser(UserDetails user);

  /// Removes [username].
  FutureOr<void> deleteUser(String username);

  /// Whether [username] exists.
  FutureOr<bool> userExists(String username);
}

/// Users kept in memory, like Spring's `InMemoryUserDetailsManager`: for
/// tests, demos and the starter's default user. Names are compared without
/// case; every lookup returns a copy, so a caller erasing its password does
/// not change the store.
///
/// ```dart
/// @Bean()
/// UserDetailsService users(PasswordEncoder encoder) =>
///     InMemoryUserDetailsManager([
///       User.withUsername('ada')
///           .password(encoder.encode('secret'))
///           .roles(['ADMIN'])
///           .build(),
///     ]);
/// ```
final class InMemoryUserDetailsManager
    implements UserDetailsManager, UserDetailsPasswordService {
  /// A manager holding [users].
  InMemoryUserDetailsManager([Iterable<UserDetails> users = const []]) {
    users.forEach(createUser);
  }

  final _users = <String, UserDetails>{};

  static String _key(String username) => username.toLowerCase();

  @override
  UserDetails loadUserByUsername(String username) {
    final user = _users[_key(username)];
    if (user == null) {
      throw UsernameNotFoundException(username);
    }
    return User.withUserDetails(user).build();
  }

  @override
  void createUser(UserDetails user) {
    if (userExists(user.username)) {
      throw ArgumentError('User ${user.username} already exists');
    }
    _users[_key(user.username)] = User.withUserDetails(user).build();
  }

  @override
  void updateUser(UserDetails user) {
    if (!userExists(user.username)) {
      throw ArgumentError('User ${user.username} does not exist');
    }
    _users[_key(user.username)] = User.withUserDetails(user).build();
  }

  @override
  void deleteUser(String username) => _users.remove(_key(username));

  @override
  bool userExists(String username) => _users.containsKey(_key(username));

  @override
  UserDetails updatePassword(UserDetails user, String newPassword) {
    final updated = User.withUserDetails(user).password(newPassword).build();
    _users[_key(user.username)] = updated;
    return User.withUserDetails(updated).build();
  }
}

/// Checks the state of an account, like Spring's `UserDetailsChecker`.
abstract interface class UserDetailsChecker {
  /// Throws an [AccountStatusException] when [user] may not log in.
  void check(UserDetails user);
}

/// Refuses locked, disabled and expired accounts, like Spring's
/// `AccountStatusUserDetailsChecker` (the checks before the password).
final class AccountStatusUserDetailsChecker implements UserDetailsChecker {
  /// The checker.
  const AccountStatusUserDetailsChecker();

  @override
  void check(UserDetails user) {
    if (!user.isAccountNonLocked) {
      throw LockedException();
    }
    if (!user.isEnabled) {
      throw DisabledException();
    }
    if (!user.isAccountNonExpired) {
      throw AccountExpiredException();
    }
  }
}

/// Refuses an expired password, like the check Spring's
/// `DaoAuthenticationProvider` makes after the password matched.
final class CredentialsExpiryChecker implements UserDetailsChecker {
  /// The checker.
  const CredentialsExpiryChecker();

  @override
  void check(UserDetails user) {
    if (!user.isCredentialsNonExpired) {
      throw CredentialsExpiredException();
    }
  }
}
