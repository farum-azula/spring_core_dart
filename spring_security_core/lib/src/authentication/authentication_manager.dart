import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/authentication/events.dart';
import 'package:spring_security_core/src/authentication/offload_stub.dart'
    if (dart.library.isolate) 'package:spring_security_core/src/authentication/offload_io.dart';
import 'package:spring_security_core/src/authentication/password_checks.dart';
import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/exceptions.dart';
import 'package:spring_security_core/src/core/log_support.dart';
import 'package:spring_security_core/src/crypto/password_encoder.dart';
import 'package:spring_security_core/src/userdetails/user_details.dart';
import 'package:spring_security_core/src/userdetails/user_details_service.dart';

const _log = SpringLog('spring.security.authentication');

/// The service that checks a login: given what the user presented, it
/// returns the authenticated [Authentication] or throws.
///
/// Every login goes through it: the web starter's form, basic and bearer
/// logins, and the login code of a Flutter app or a custom endpoint. You
/// rarely implement it. With a `UserDetailsService` or
/// `AuthenticationProvider` bean the auto-configuration builds one (a
/// [ProviderManager]), and you inject it where you log users in yourself.
///
/// ```dart
/// // A JSON login endpoint: check the password, then keep the user.
/// final user = await authenticationManager.authenticate(
///   UsernamePasswordAuthenticationToken.unauthenticated(
///     body.username,
///     body.password,
///   ),
/// );
/// SecurityContextHolder.setContext(SecurityContextImpl(user));
/// ```
///
/// Spring (Java):
/// ```java
/// Authentication user = authenticationManager.authenticate(
///     UsernamePasswordAuthenticationToken.unauthenticated(
///         body.username(), body.password()));
/// ```
abstract interface class AuthenticationManager {
  /// Checks the login request [authentication] and returns a new,
  /// authenticated one with the user's authorities.
  ///
  /// Throws an [AuthenticationException] when the login is refused, such
  /// as a [BadCredentialsException] for a wrong password.
  Future<Authentication> authenticate(Authentication authentication);
}

/// One way of checking a login, such as "username and password against
/// the user store" or "an API key against a table".
///
/// A [ProviderManager] holds a list of providers and asks each one that
/// [supports] the request. Write one when users log in with something
/// other than a username and password from a `UserDetailsService`, and
/// declare it as a bean: the auto-configuration then builds the
/// `AuthenticationManager` from all `AuthenticationProvider` beans instead
/// of the default [DaoAuthenticationProvider].
///
/// ```dart
/// // API keys: the token's credentials are the key a client sent.
/// @Component()
/// class ApiKeyProvider implements AuthenticationProvider {
///   ApiKeyProvider(this.keys);
///   final ApiKeyRepository keys;
///
///   @override
///   bool supports(Authentication authentication) =>
///       authentication is ApiKeyAuthenticationToken;
///
///   @override
///   Future<Authentication?> authenticate(
///     Authentication authentication,
///   ) async {
///     final key = await keys.find(authentication.credentials as String) ??
///         (throw BadCredentialsException());
///     return ApiKeyAuthenticationToken(
///       key.owner,
///       null,
///       AuthorityUtils.createAuthorityList(key.authorities),
///     )..isAuthenticated = true;
///   }
/// }
/// ```
///
/// Spring (Java): `AuthenticationProvider`, the same two methods.
abstract interface class AuthenticationProvider {
  /// Checks [authentication] and returns the authenticated result.
  ///
  /// Returns `null` when this provider cannot decide, so the next one is
  /// asked. Throws an [AuthenticationException] to refuse the login; an
  /// [AccountStatusException] or [InternalAuthenticationServiceException]
  /// stops the manager at once, any other one lets the next provider
  /// try.
  Future<Authentication?> authenticate(Authentication authentication);

  /// Whether this provider knows how to check [authentication], usually a
  /// test of its type. The manager skips providers that return `false`.
  bool supports(Authentication authentication);
}

/// The standard [AuthenticationManager]: it asks a list of
/// [AuthenticationProvider]s in turn until one authenticates the request.
///
/// It lets one application accept several kinds of login (passwords, API
/// keys, tokens) through one entry point. The rules:
///
/// - Providers whose `supports` is `false` are skipped. The first non-null
///   result wins.
/// - A refused login (an [AuthenticationException]) is remembered and the
///   next provider tried; when none succeeds, the last failure is thrown.
///   An [AccountStatusException] or an
///   [InternalAuthenticationServiceException] is thrown at once, because
///   the account was found or the system failed.
/// - The [parent] manager, if any, is asked when no provider succeeded.
/// - When no provider supports the request (or all of them return
///   `null`), it throws a [ProviderNotFoundException].
/// - On success the credentials of the result are erased (see
///   [eraseCredentialsAfterAuthentication]) and an
///   `AuthenticationSuccessEvent` is published; on failure, a failure
///   event.
///
/// The auto-configuration builds one when the application has a
/// `UserDetailsService` or `AuthenticationProvider` beans. Build one
/// yourself to combine providers in another way.
///
/// ```dart
/// @Bean()
/// AuthenticationManager authenticationManager(
///   UserDetailsService users,
///   ApiKeyProvider apiKeys,
/// ) => ProviderManager([DaoAuthenticationProvider(users), apiKeys]);
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// AuthenticationManager authenticationManager(
///     UserDetailsService users, ApiKeyProvider apiKeys) {
///   return new ProviderManager(new DaoAuthenticationProvider(users), apiKeys);
/// }
/// ```
final class ProviderManager implements AuthenticationManager {
  /// A manager asking [providers] in order, then [parent].
  ///
  /// Throws an [ArgumentError] when there are no providers and no
  /// parent.
  ProviderManager(
    List<AuthenticationProvider> providers, {
    this.parent,
    this.eventPublisher,
    this.eraseCredentialsAfterAuthentication = true,
  }) : providers = List.unmodifiable(providers) {
    if (providers.isEmpty && parent == null) {
      throw ArgumentError('A ProviderManager needs a provider or a parent');
    }
  }

  /// The providers, in the order they are asked; cannot be modified.
  final List<AuthenticationProvider> providers;

  /// A manager asked when no provider authenticated the request, or
  /// `null`.
  ///
  /// When it finds no provider either, the failure of this manager
  /// stands.
  final AuthenticationManager? parent;

  /// Where success and failure events go; `null` publishes nothing.
  ///
  /// The auto-configured manager publishes them as application events.
  AuthenticationEventPublisher? eventPublisher;

  /// Whether the password is erased from a successful result before it is
  /// returned, so it does not stay in memory with the session; `true` by
  /// default.
  final bool eraseCredentialsAfterAuthentication;

  @override
  Future<Authentication> authenticate(Authentication authentication) async {
    AuthenticationException? lastException;
    AuthenticationException? parentException;
    Authentication? result;
    var position = 0;
    for (final provider in providers) {
      position++;
      if (!provider.supports(authentication)) {
        continue;
      }
      _log.trace(
        () =>
            'Authenticating request with ${authentication.runtimeType} '
            '($position/${providers.length})',
      );
      try {
        result = await provider.authenticate(authentication);
        if (result != null) {
          break;
        }
      } on AccountStatusException catch (e) {
        _prepare(e, authentication);
        rethrow; // the account exists: no other provider should try
      } on InternalAuthenticationServiceException catch (e) {
        _prepare(e, authentication);
        rethrow;
      } on AuthenticationException catch (e) {
        lastException = e;
      }
    }
    final parent = this.parent;
    if (result == null && parent != null) {
      try {
        result = await parent.authenticate(authentication);
      } on ProviderNotFoundException {
        // The parent knows no provider either: our failure stands.
      } on AuthenticationException catch (e) {
        parentException = lastException = e;
      }
    }
    if (result != null) {
      if (eraseCredentialsAfterAuthentication &&
          result is CredentialsContainer) {
        (result as CredentialsContainer).eraseCredentials();
      }
      eventPublisher?.publishAuthenticationSuccess(result);
      return result;
    }
    final failure =
        lastException ??
        ProviderNotFoundException(
          'No AuthenticationProvider found for ${authentication.runtimeType}',
        );
    _log.debug(
      () => 'Failed to authenticate since ${logText(failure.message)}',
    );
    // The parent published its own failure already.
    if (parentException == null) {
      _prepare(failure, authentication);
    }
    throw failure;
  }

  void _prepare(AuthenticationException e, Authentication request) {
    e.authenticationRequest = request;
    eventPublisher?.publishAuthenticationFailure(e, request);
  }
}

/// The password login: it loads the user from a [UserDetailsService] and
/// checks the typed password against the stored hash with a
/// [PasswordEncoder].
///
/// It handles [UsernamePasswordAuthenticationToken]s. The
/// auto-configuration builds one when the application declares a
/// `UserDetailsService` and no `AuthenticationProvider`, so most
/// applications only write the user store. What it guarantees:
///
/// - An unknown username and a wrong password both fail with
///   [BadCredentialsException], and an unknown username still checks the
///   password against a dummy hash, so neither the answer nor its time
///   tells whether a user exists.
/// - A locked, disabled or expired account fails before the password is
///   checked; an expired password fails after it.
/// - A stored hash no encoder understands (such as `{bcrypt}`) fails as a
///   wrong password, with a warning in the log; it never logs in.
/// - A hash made with older settings is re-hashed with the encoder's
///   current ones after a successful login and stored through the
///   [userDetailsPasswordService].
/// - The password is checked on another isolate where Dart has them, so a
///   login, which takes hundreds of milliseconds of CPU, does not stop the
///   server's other requests.
/// - The result's principal is the loaded [UserDetails], with its
///   authorities; the request's details are copied over.
///
/// ```dart
/// // A manager over the users table, with PBKDF2 hashes.
/// final provider = DaoAuthenticationProvider(
///   accountUsers,
///   passwordEncoder: Pbkdf2PasswordEncoder.defaultsForSpringSecurity(),
/// );
/// ```
///
/// Spring (Java): `DaoAuthenticationProvider`, with the same rules.
final class DaoAuthenticationProvider implements AuthenticationProvider {
  /// A provider loading users from [userDetailsService] and checking
  /// passwords with [passwordEncoder].
  ///
  /// Without a [passwordEncoder] it uses
  /// `PasswordEncoderFactories.createDelegatingPasswordEncoder()`, which
  /// writes `{argon2}` hashes and reads the other `{id}` formats.
  DaoAuthenticationProvider(
    this.userDetailsService, {
    PasswordEncoder? passwordEncoder,
    this.userDetailsPasswordService,
    this.preAuthenticationChecks = const AccountStatusUserDetailsChecker(),
    this.postAuthenticationChecks = const CredentialsExpiryChecker(),
    this.hideUserNotFoundExceptions = true,
    this.offloadPasswordChecks = true,
    this.passwordCheckLimiter,
  }) : passwordEncoder =
           passwordEncoder ??
           PasswordEncoderFactories.createDelegatingPasswordEncoder();

  /// The user store asked for the user named at login.
  final UserDetailsService userDetailsService;

  /// Checks typed passwords against stored hashes, and makes the new hash
  /// when one is upgraded.
  final PasswordEncoder passwordEncoder;

  /// Where an upgraded hash is stored after a successful login; `null`
  /// leaves old hashes as they are.
  final UserDetailsPasswordService? userDetailsPasswordService;

  /// Runs before the password check; by default refuses locked,
  /// disabled and expired accounts.
  final UserDetailsChecker preAuthenticationChecks;

  /// Runs after the password matched; by default refuses an expired
  /// password.
  final UserDetailsChecker postAuthenticationChecks;

  /// Whether an unknown username fails as a [BadCredentialsException],
  /// like a wrong password; `true` by default, as in Spring.
  ///
  /// With `false` it fails with the [UsernameNotFoundException] itself,
  /// which tells a stranger which usernames exist: never set it for a
  /// login a stranger can reach.
  final bool hideUserNotFoundExceptions;

  /// Whether password hashing runs on another isolate; `true` by default.
  ///
  /// On the web, which has no isolates, the work runs on the caller's
  /// event loop either way. Set it to `false` in tests that use a fast
  /// encoder.
  final bool offloadPasswordChecks;

  /// Bounds the password checks running and waiting at once;
  /// [PasswordCheckLimiter.shared] when `null`. Above its bound a login
  /// fails at once with a [PasswordChecksBusyException] (a 503 from the
  /// security starter), so a flood of logins cannot take every core.
  final PasswordCheckLimiter? passwordCheckLimiter;

  static const _userNotFoundPassword = 'userNotFoundPassword';
  String? _userNotFoundEncodedPassword;

  @override
  bool supports(Authentication authentication) =>
      authentication is UsernamePasswordAuthenticationToken;

  @override
  Future<Authentication?> authenticate(Authentication authentication) async {
    final username = authentication.name;
    final UserDetails user;
    try {
      user = await _load(username);
    } on UsernameNotFoundException catch (e) {
      _log.debug(() => "Failed to find user '${logText(username)}'");
      // The same work as for a known user: timing must not tell.
      await _check(_presented(authentication), await _dummyHash());
      if (hideUserNotFoundExceptions) {
        throw BadCredentialsException('Bad credentials', e);
      }
      rethrow;
    }
    preAuthenticationChecks.check(user);
    final presented = _presented(authentication);
    if (!await _check(presented, user.password)) {
      _log.debug(
        'Failed to authenticate since password does not match stored value',
      );
      throw BadCredentialsException();
    }
    postAuthenticationChecks.check(user);
    var principal = user;
    final service = userDetailsPasswordService;
    if (service != null && passwordEncoder.upgradeEncoding(user.password)) {
      final upgraded = passwordEncoder.encode(presented);
      principal = await service.updatePassword(user, upgraded);
    }
    final result = UsernamePasswordAuthenticationToken.authenticated(
      principal,
      authentication.credentials,
      principal.authorities,
    )..details = authentication.details;
    return result;
  }

  Future<UserDetails> _load(String username) async {
    try {
      return await userDetailsService.loadUserByUsername(username);
    } on AuthenticationException {
      rethrow;
    } on Object catch (e) {
      throw InternalAuthenticationServiceException(
        'UserDetailsService failed to load the user',
        e,
      );
    }
  }

  static String _presented(Authentication authentication) {
    final credentials = authentication.credentials;
    if (credentials is! String) {
      throw BadCredentialsException();
    }
    return credentials;
  }

  Future<String> _dummyHash() async {
    final encoder = passwordEncoder;
    final hash =
        _userNotFoundEncodedPassword ??
        await _run<String>(() => encoder.encode(_userNotFoundPassword));
    _userNotFoundEncodedPassword = hash;
    return hash;
  }

  Future<bool> _check(String raw, String? encoded) async {
    if (encoded == null) {
      return false;
    }
    final encoder = passwordEncoder;
    try {
      return await _run(() => encoder.matches(raw, encoded));
    } on ArgumentError catch (e) {
      // A stored hash no encoder understands: a misconfiguration to fix,
      // never a successful login.
      _log.warning('Cannot check the stored password: ${e.message}');
      return false;
    }
  }

  Future<T> _run<T>(T Function() work) =>
      (passwordCheckLimiter ?? PasswordCheckLimiter.shared).run(
        () => offloadPasswordChecks ? offload(work) : Future.sync(work),
      );
}
