import 'package:spring_security_core/src/core/authentication.dart';

/// The base class of every "who are you?" failure: a login was refused, or
/// an identity is needed and there is none.
///
/// An `AuthenticationManager` throws a subclass when a login fails, and
/// method security throws [AuthenticationCredentialsNotFoundException]
/// when there is no `Authentication` at all. Catch it around your own
/// login call to show "wrong username or password". Throw a subclass from
/// your own `AuthenticationProvider` to refuse a login.
///
/// With `spring_boot_starter_security` a request that fails with it is
/// answered by the login method's entry point: usually `401 Unauthorized`
/// with a `WWW-Authenticate` challenge, or a redirect to the login page.
/// The answer never carries [message], which may say more than a client
/// should learn (such as which part of a login failed).
///
/// ```dart
/// try {
///   final user = await authenticationManager.authenticate(
///     UsernamePasswordAuthenticationToken.unauthenticated(name, password),
///   );
///   SecurityContextHolder.setContext(SecurityContextImpl(user));
/// } on AuthenticationException {
///   // The same text for every cause: do not tell which part was wrong.
///   showError('Wrong username or password');
/// }
/// ```
///
/// Spring (Java): `AuthenticationException`, with the same subclasses.
abstract class AuthenticationException implements Exception {
  /// A failure described by [message], optionally caused by [cause].
  AuthenticationException(this.message, [this.cause]);

  /// What went wrong, for logs; never sent to the client.
  final String message;

  /// The lower-level error that led to this one, or `null`.
  final Object? cause;

  /// The login request that failed, set by `ProviderManager`; `null` when
  /// unknown.
  Authentication? authenticationRequest;

  @override
  String toString() => '$runtimeType: $message';
}

/// A login was refused because the username or the password is wrong.
///
/// `DaoAuthenticationProvider` throws it for a wrong password and also for
/// an unknown username, so a client cannot learn which usernames exist. A
/// login request whose credentials are not a `String` fails with it too.
///
/// Spring (Java): `BadCredentialsException`.
class BadCredentialsException extends AuthenticationException {
  /// A refused login; [message] defaults to `'Bad credentials'`.
  BadCredentialsException([super.message = 'Bad credentials', super.cause]);
}

/// No user has the given username.
///
/// Throw it from your `UserDetailsService.loadUserByUsername`. It does not
/// reach the client: `DaoAuthenticationProvider` turns it into a
/// [BadCredentialsException] so a wrong username and a wrong password look
/// the same.
///
/// Spring (Java): `UsernameNotFoundException`.
class UsernameNotFoundException extends AuthenticationException {
  /// No user; [message] is usually the username that was looked up.
  UsernameNotFoundException(super.message, [super.cause]);
}

/// The base class of the failures where the account exists but may not
/// log in now: locked, disabled, expired, or with an expired password.
///
/// Unlike other failures, `ProviderManager` stops at once on it and asks no
/// other provider, because the account was found. Throw a subclass from a
/// `UserDetailsChecker` to refuse an account for a reason of your own.
///
/// Spring (Java): `AccountStatusException`.
abstract class AccountStatusException extends AuthenticationException {
  /// An account failure described by [message].
  AccountStatusException(super.message, [super.cause]);
}

/// The login was refused because the account is disabled
/// (`UserDetails.isEnabled` is `false`).
///
/// Checked before the password.
///
/// Spring (Java): `DisabledException`.
class DisabledException extends AccountStatusException {
  /// A refused login; [message] defaults to `'User is disabled'`.
  DisabledException([super.message = 'User is disabled', super.cause]);
}

/// The login was refused because the account is locked
/// (`UserDetails.isAccountNonLocked` is `false`).
///
/// Checked before the password.
///
/// Spring (Java): `LockedException`.
class LockedException extends AccountStatusException {
  /// A refused login; [message] defaults to `'User account is locked'`.
  LockedException([super.message = 'User account is locked', super.cause]);
}

/// The login was refused because the account has expired
/// (`UserDetails.isAccountNonExpired` is `false`).
///
/// Checked before the password.
///
/// Spring (Java): `AccountExpiredException`.
class AccountExpiredException extends AccountStatusException {
  /// A refused login; [message] defaults to
  /// `'User account has expired'`.
  AccountExpiredException([
    super.message = 'User account has expired',
    super.cause,
  ]);
}

/// The login was refused because the password has expired
/// (`UserDetails.isCredentialsNonExpired` is `false`).
///
/// Checked after the password matched, so only the real user learns it
/// and can be sent to a "change your password" page.
///
/// Spring (Java): `CredentialsExpiredException`.
class CredentialsExpiredException extends AccountStatusException {
  /// A refused login; [message] defaults to
  /// `'User credentials have expired'`.
  CredentialsExpiredException([
    super.message = 'User credentials have expired',
    super.cause,
  ]);
}

/// Access needs a real login, but the caller is anonymous.
///
/// The web starter raises it when an anonymous request is denied, so the
/// client is asked to log in (401 or a redirect) instead of getting a 403.
///
/// Spring (Java): `InsufficientAuthenticationException`.
class InsufficientAuthenticationException extends AuthenticationException {
  /// A missing login; [message] defaults to
  /// `'Full authentication is required to access this resource'`.
  InsufficientAuthenticationException([
    super.message = 'Full authentication is required to access this resource',
    super.cause,
  ]);
}

/// A security check ran with no `Authentication` in the security context,
/// not even an anonymous one.
///
/// A method with `@PreAuthorize`, `@Secured` or another security
/// annotation throws it before any expression runs when it is called
/// outside a login, for example from a background job or a test that set
/// no user. Run such code with `SecurityContextHolder.runWithContext`, or
/// `withMockUser` in tests. In a web request the starter's anonymous user
/// prevents it.
///
/// Spring (Java): `AuthenticationCredentialsNotFoundException`.
class AuthenticationCredentialsNotFoundException
    extends AuthenticationException {
  /// A missing authentication; [message] defaults to
  /// `'An Authentication object was not found in the SecurityContext'`.
  AuthenticationCredentialsNotFoundException([
    super.message =
        'An Authentication object was not found in the SecurityContext',
    super.cause,
  ]);
}

/// No `AuthenticationProvider` of a `ProviderManager` accepts this kind of
/// login request (its `supports` returned `false` for all of them).
///
/// It usually means a configuration error, such as a bearer-token login
/// with no provider for tokens.
///
/// Spring (Java): `ProviderNotFoundException`.
class ProviderNotFoundException extends AuthenticationException {
  /// A failure described by [message], which names the request type.
  ProviderNotFoundException(super.message, [super.cause]);
}

/// A login could not be checked because something failed, such as the
/// user database being down, rather than because the credentials are
/// wrong.
///
/// A web client still gets a 401 and learns nothing about the failure;
/// the [message] and the cause are for the logs.
///
/// Spring (Java): `AuthenticationServiceException`.
class AuthenticationServiceException extends AuthenticationException {
  /// A failure described by [message], caused by [cause].
  AuthenticationServiceException(super.message, [super.cause]);
}

/// A login could not be checked because the authentication code itself
/// failed.
///
/// `DaoAuthenticationProvider` wraps any error of the `UserDetailsService`
/// other than an [AuthenticationException] in it. `ProviderManager` stops
/// at once and does not try the next provider.
///
/// Spring (Java): `InternalAuthenticationServiceException`.
class InternalAuthenticationServiceException
    extends AuthenticationServiceException {
  /// A failure described by [message], caused by [cause].
  InternalAuthenticationServiceException(super.message, [super.cause]);
}

/// The current user is known but may not do what was asked.
///
/// Method security throws it (as `AuthorizationDeniedException`) when a
/// `@PreAuthorize`, `@PostAuthorize` or `@Secured` check fails, and the web
/// starter's rules throw it for a request they deny. Throw it yourself
/// from a service when a check of your own fails.
///
/// With `spring_boot_starter_security` a request that fails with it is
/// answered `403 Forbidden`, without [message]. When the user is anonymous
/// (or there is no user), the request is asked to log in instead (401 or
/// a redirect to the login page).
///
/// ```dart
/// if (order.owner != currentUser.name) {
///   throw AccessDeniedException('Not the owner of order ${order.id}');
/// }
/// ```
///
/// Spring (Java): `AccessDeniedException`.
class AccessDeniedException implements Exception {
  /// A denial; [message] (for logs) defaults to `'Access Denied'`.
  AccessDeniedException([this.message = 'Access Denied', this.cause]);

  /// What was denied, for logs; never sent to the client.
  final String message;

  /// The lower-level error that led to this one, or `null`.
  final Object? cause;

  @override
  // The text names the actual class, subclasses included, like Java's
  // getClass().getName().
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType: $message';
}
