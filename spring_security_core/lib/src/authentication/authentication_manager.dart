import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/authentication/events.dart';
import 'package:spring_security_core/src/authentication/offload_stub.dart'
    if (dart.library.isolate) 'package:spring_security_core/src/authentication/offload_io.dart';
import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/exceptions.dart';
import 'package:spring_security_core/src/crypto/password_encoder.dart';
import 'package:spring_security_core/src/userdetails/user_details.dart';
import 'package:spring_security_core/src/userdetails/user_details_service.dart';

const _log = SpringLog('spring.security.authentication');

/// Turns an authentication request into an authenticated [Authentication],
/// like Spring's `AuthenticationManager`.
///
/// ```dart
/// final user = await manager.authenticate(
///   UsernamePasswordAuthenticationToken.unauthenticated('ada', 'secret'),
/// );
/// ```
abstract interface class AuthenticationManager {
  /// The authenticated form of [authentication]; throws an
  /// [AuthenticationException] when it fails.
  Future<Authentication> authenticate(Authentication authentication);
}

/// Authenticates one kind of request, like Spring's
/// `AuthenticationProvider`.
abstract interface class AuthenticationProvider {
  /// The authenticated form of [authentication], `null` when this provider
  /// cannot decide (the next one is asked), or throws an
  /// [AuthenticationException].
  Future<Authentication?> authenticate(Authentication authentication);

  /// Whether this provider handles requests like [authentication].
  bool supports(Authentication authentication);
}

/// Asks its [providers] in order, like Spring's `ProviderManager`: the first
/// result wins; failures are remembered and the last one thrown when no
/// provider succeeds; the [parent] is asked last. Publishes success and
/// failure events and erases credentials of the result.
final class ProviderManager implements AuthenticationManager {
  /// A manager over [providers].
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

  /// The providers, in order.
  final List<AuthenticationProvider> providers;

  /// Asked when no provider authenticated.
  final AuthenticationManager? parent;

  /// Receives success and failure events.
  AuthenticationEventPublisher? eventPublisher;

  /// Whether the credentials of the result are erased.
  final bool eraseCredentialsAfterAuthentication;

  @override
  Future<Authentication> authenticate(Authentication authentication) async {
    AuthenticationException? lastException;
    AuthenticationException? parentException;
    Authentication? result;
    for (final provider in providers) {
      if (!provider.supports(authentication)) {
        continue;
      }
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

/// Authenticates a username and password against a [UserDetailsService]
/// and a [PasswordEncoder], like Spring's `DaoAuthenticationProvider`.
///
/// - An unknown username and a wrong password both fail with
///   [BadCredentialsException], and an unknown username still checks the
///   password against a stored dummy hash, so neither the answer nor its
///   time tells whether a user exists.
/// - A locked, disabled or expired account fails before the password is
///   checked (Spring's order); an expired password after it.
/// - A hash made with older settings is upgraded through the
///   [userDetailsPasswordService] after a successful login.
/// - The hash is checked on another isolate where Dart has them, so a
///   login does not stop the server's other requests.
final class DaoAuthenticationProvider implements AuthenticationProvider {
  /// A provider loading users from [userDetailsService]; passwords
  /// checked with [passwordEncoder] (default: the delegating encoder).
  DaoAuthenticationProvider(
    this.userDetailsService, {
    PasswordEncoder? passwordEncoder,
    this.userDetailsPasswordService,
    this.preAuthenticationChecks = const AccountStatusUserDetailsChecker(),
    this.postAuthenticationChecks = const CredentialsExpiryChecker(),
    this.hideUserNotFoundExceptions = true,
    this.offloadPasswordChecks = true,
  }) : passwordEncoder =
           passwordEncoder ??
           PasswordEncoderFactories.createDelegatingPasswordEncoder();

  /// Loads the users.
  final UserDetailsService userDetailsService;

  /// Checks and encodes passwords.
  final PasswordEncoder passwordEncoder;

  /// Stores upgraded hashes, when set.
  final UserDetailsPasswordService? userDetailsPasswordService;

  /// Checks before the password.
  final UserDetailsChecker preAuthenticationChecks;

  /// Checks after the password.
  final UserDetailsChecker postAuthenticationChecks;

  /// Whether an unknown username fails as bad credentials (like Spring,
  /// `true`): never set it to `false` for a login a stranger can reach.
  final bool hideUserNotFoundExceptions;

  /// Whether the password is checked on another isolate.
  final bool offloadPasswordChecks;

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
      _log.debug('Failed to authenticate since password does not match');
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
      offloadPasswordChecks ? offload(work) : Future.sync(work);
}
