import 'dart:async';

import 'package:spring_security_core/src/core/exceptions.dart';
import 'package:spring_security_core/src/userdetails/user_details.dart';

/// Your user store, as the login code sees it: one method that finds a
/// user by the name typed at login.
///
/// This is the interface an application implements to plug its own users
/// (a database table, a directory, an external service) into password
/// logins. With a bean of this type the auto-configuration builds the
/// `AuthenticationManager`: a `DaoAuthenticationProvider` loads the user
/// through it and checks the typed password against the returned hash.
/// The method only loads; it never checks the password itself.
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
///
/// Spring (Java):
/// ```java
/// @Service
/// class AccountUsers implements UserDetailsService {
///   @Override
///   public UserDetails loadUserByUsername(String username) {
///     Account account = accounts.findByEmail(username)
///         .orElseThrow(() -> new UsernameNotFoundException(username));
///     return User.withUsername(account.email())
///         .password(account.passwordHash())
///         .roles(account.roles())
///         .build();
///   }
/// }
/// ```
abstract interface class UserDetailsService {
  /// The user who logs in as [username], with the stored password hash.
  ///
  /// Throw a [UsernameNotFoundException] when there is none; the login
  /// then fails as "bad credentials", like a wrong password. Any other
  /// error fails the login with an `InternalAuthenticationServiceException`.
  /// Whether the lookup ignores case is up to you.
  FutureOr<UserDetails> loadUserByUsername(String username);
}

/// Saves a new hash of a user's password when the login code re-hashes it.
///
/// Password hashing settings get stronger over time. At a successful login
/// the typed password is known, so `DaoAuthenticationProvider` can hash it
/// again with today's settings when the stored hash is older (another
/// `{id}` or weaker parameters) and hand the new hash to this service to
/// store. Implement it on your user store to keep hashes up to date
/// without asking users to change their passwords. Without it, old hashes
/// keep working and are never upgraded.
///
/// ```dart
/// @Service()
/// class AccountUsers
///     implements UserDetailsService, UserDetailsPasswordService {
///   ...
///
///   @override
///   Future<UserDetails> updatePassword(
///     UserDetails user,
///     String newPassword,
///   ) async {
///     await accounts.setPasswordHash(user.username, newPassword);
///     return User.withUserDetails(user).password(newPassword).build();
///   }
/// }
/// ```
///
/// Spring (Java): `UserDetailsPasswordService`.
abstract interface class UserDetailsPasswordService {
  /// Stores [newPassword], already encoded, for [user] and returns the
  /// user with the new password; the returned user becomes the principal
  /// of the login.
  FutureOr<UserDetails> updatePassword(UserDetails user, String newPassword);
}

/// A [UserDetailsService] that can also add, change and remove users.
///
/// Implement it when the same object should serve logins and manage the
/// accounts, for example in an admin screen. [InMemoryUserDetailsManager]
/// is the implementation shipped here.
///
/// Spring (Java): `UserDetailsManager` (here without `changePassword`).
abstract interface class UserDetailsManager implements UserDetailsService {
  /// Adds [user]; [InMemoryUserDetailsManager] throws an [ArgumentError]
  /// when the username exists.
  FutureOr<void> createUser(UserDetails user);

  /// Replaces the stored user whose username is [user]'s;
  /// [InMemoryUserDetailsManager] throws an [ArgumentError] when there is
  /// none.
  FutureOr<void> updateUser(UserDetails user);

  /// Removes the user named [username]; nothing happens when there is
  /// none.
  FutureOr<void> deleteUser(String username);

  /// Whether a user named [username] is stored.
  FutureOr<bool> userExists(String username);
}

/// A user store kept in a map in memory, for tests, demos and small tools.
///
/// The users are lost when the program stops. Usernames are compared
/// without case (`Ada` and `ada` are one user). Every lookup returns a
/// copy, so a login erasing the password of its user does not change the
/// store. It also stores upgraded hashes ([UserDetailsPasswordService]).
/// `spring_boot_starter_security` uses one for its default user when the
/// application declares no user store.
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
///
/// Spring (Java):
/// ```java
/// @Bean
/// UserDetailsService users(PasswordEncoder encoder) {
///   return new InMemoryUserDetailsManager(
///       User.withUsername("ada")
///           .password(encoder.encode("secret"))
///           .roles("ADMIN")
///           .build());
/// }
/// ```
final class InMemoryUserDetailsManager
    implements UserDetailsManager, UserDetailsPasswordService {
  /// A store holding copies of [users].
  ///
  /// Throws an [ArgumentError] when two of them have the same username
  /// (ignoring case).
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

/// A check of an account's state, run during a password login.
///
/// `DaoAuthenticationProvider` runs one before the password check
/// ([AccountStatusUserDetailsChecker]) and one after it
/// ([CredentialsExpiryChecker]). Implement it to refuse accounts for a
/// reason of your own, such as an unverified e-mail address, and pass it
/// as `preAuthenticationChecks` or `postAuthenticationChecks`.
///
/// Spring (Java): `UserDetailsChecker`.
abstract interface class UserDetailsChecker {
  /// Returns normally when [user] may log in; otherwise throws an
  /// [AccountStatusException], which fails the login.
  void check(UserDetails user);
}

/// The check run before the password: refuses locked, disabled and expired
/// accounts, in that order.
///
/// It throws [LockedException], [DisabledException] or
/// [AccountExpiredException]. Running it before the password check means
/// such an account is refused even with the right password.
///
/// Spring (Java): `AccountStatusUserDetailsChecker` (the default
/// pre-authentication check).
final class AccountStatusUserDetailsChecker implements UserDetailsChecker {
  /// The stateless checker.
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

/// The check run after the password matched: refuses an expired password
/// with a [CredentialsExpiredException].
///
/// It runs after the password check, so only someone who knows the
/// password learns that it expired.
///
/// Spring (Java): the default post-authentication check of
/// `DaoAuthenticationProvider`.
final class CredentialsExpiryChecker implements UserDetailsChecker {
  /// The stateless checker.
  const CredentialsExpiryChecker();

  @override
  void check(UserDetails user) {
    if (!user.isCredentialsNonExpired) {
      throw CredentialsExpiredException();
    }
  }
}
