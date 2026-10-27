import 'package:spring_security_core/src/core/authentication.dart';

/// Authentication failed or is missing, like Spring's
/// `AuthenticationException`.
///
/// With `spring_boot_starter_security` a request failing with it is
/// answered `401 Unauthorized` (with the `WWW-Authenticate` challenge of
/// the login method); the answer never carries [message]: it may say more
/// than a client should learn (which part of a login failed).
abstract class AuthenticationException implements Exception {
  /// A failure described by [message], caused by [cause].
  AuthenticationException(this.message, [this.cause]);

  /// What went wrong, for logs.
  final String message;

  /// What caused it.
  final Object? cause;

  /// The authentication request that failed, when known.
  Authentication? authenticationRequest;

  @override
  String toString() => '$runtimeType: $message';
}

/// The username or the password is wrong, like Spring's
/// `BadCredentialsException`. Also what an unknown username becomes, so a
/// client cannot tell which one was wrong.
class BadCredentialsException extends AuthenticationException {
  /// Bad credentials, described by [message].
  BadCredentialsException([super.message = 'Bad credentials', super.cause]);
}

/// No user with that name, like Spring's `UsernameNotFoundException`.
/// `DaoAuthenticationProvider` turns it into a [BadCredentialsException].
class UsernameNotFoundException extends AuthenticationException {
  /// No user, described by [message].
  UsernameNotFoundException(super.message, [super.cause]);
}

/// The account exists but may not log in, like Spring's
/// `AccountStatusException`.
abstract class AccountStatusException extends AuthenticationException {
  /// Described by [message].
  AccountStatusException(super.message, [super.cause]);
}

/// The account is disabled, like Spring's `DisabledException`.
class DisabledException extends AccountStatusException {
  /// Described by [message].
  DisabledException([super.message = 'User is disabled', super.cause]);
}

/// The account is locked, like Spring's `LockedException`.
class LockedException extends AccountStatusException {
  /// Described by [message].
  LockedException([super.message = 'User account is locked', super.cause]);
}

/// The account has expired, like Spring's `AccountExpiredException`.
class AccountExpiredException extends AccountStatusException {
  /// Described by [message].
  AccountExpiredException([
    super.message = 'User account has expired',
    super.cause,
  ]);
}

/// The password has expired, like Spring's `CredentialsExpiredException`.
class CredentialsExpiredException extends AccountStatusException {
  /// Described by [message].
  CredentialsExpiredException([
    super.message = 'User credentials have expired',
    super.cause,
  ]);
}

/// The request is authenticated, but not strongly enough (anonymous), like
/// Spring's `InsufficientAuthenticationException`.
class InsufficientAuthenticationException extends AuthenticationException {
  /// Described by [message].
  InsufficientAuthenticationException([
    super.message = 'Full authentication is required to access this resource',
    super.cause,
  ]);
}

/// There is no authentication where one is needed, like Spring's
/// `AuthenticationCredentialsNotFoundException`: a secured method called
/// with an empty security context.
class AuthenticationCredentialsNotFoundException
    extends AuthenticationException {
  /// Described by [message].
  AuthenticationCredentialsNotFoundException([
    super.message =
        'An Authentication object was not found in the SecurityContext',
    super.cause,
  ]);
}

/// No `AuthenticationProvider` supports the request, like Spring's
/// `ProviderNotFoundException`.
class ProviderNotFoundException extends AuthenticationException {
  /// Described by [message].
  ProviderNotFoundException(super.message, [super.cause]);
}

/// Authentication could not be done (a store is down), like Spring's
/// `AuthenticationServiceException`. Still a 401 for the client, which
/// learns nothing about the failure.
class AuthenticationServiceException extends AuthenticationException {
  /// Described by [message].
  AuthenticationServiceException(super.message, [super.cause]);
}

/// A failure inside the authentication system itself, like Spring's
/// `InternalAuthenticationServiceException`: not retried with the next
/// provider.
class InternalAuthenticationServiceException
    extends AuthenticationServiceException {
  /// Described by [message].
  InternalAuthenticationServiceException(super.message, [super.cause]);
}

/// The principal may not do this, like Spring's `AccessDeniedException`.
/// With `spring_boot_starter_security` a request failing with it is
/// answered `403 Forbidden` (without [message]), unless the request is
/// anonymous: then it is asked to log in first.
class AccessDeniedException implements Exception {
  /// Denied, described by [message].
  AccessDeniedException([this.message = 'Access Denied', this.cause]);

  /// What was denied, for logs.
  final String message;

  /// What caused it.
  final Object? cause;

  @override
  // The text names the actual class, subclasses included, like Java's
  // getClass().getName().
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType: $message';
}
