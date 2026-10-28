import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/exceptions.dart';

/// The base class of the application events about logins and logouts.
///
/// Listen to a subclass with `@EventListener()` to audit logins, count
/// failures or lock accounts; the security packages themselves keep no
/// count. Listening to this class receives all of them.
///
/// Spring (Java): `AbstractAuthenticationEvent`.
abstract class AbstractAuthenticationEvent extends ApplicationEvent {
  /// An event about [authentication], which is also the event's source.
  AbstractAuthenticationEvent(this.authentication) : super(authentication);

  /// The login concerned: the authenticated result for a success, the
  /// login request (with the typed username) for a failure.
  final Authentication authentication;
}

/// Published by `ProviderManager` each time a login succeeds, by any
/// method (form, basic, bearer token, or a call of your own).
///
/// For basic and bearer-token logins that means every request that
/// carries credentials.
///
/// ```dart
/// @EventListener()
/// void onLogin(AuthenticationSuccessEvent event) =>
///     audit.loggedIn(event.authentication.name);
/// ```
///
/// Spring (Java): `AuthenticationSuccessEvent`.
class AuthenticationSuccessEvent extends AbstractAuthenticationEvent {
  /// A success; [authentication] is the authenticated result.
  AuthenticationSuccessEvent(super.authentication);
}

/// Published when a user logged in through the login form and is now
/// logged in for the session.
///
/// It comes after the [AuthenticationSuccessEvent] of the same login, and
/// only from the web starter's form login. Listen to it rather than to the
/// success event to count real user logins.
///
/// Spring (Java): `InteractiveAuthenticationSuccessEvent`.
class InteractiveAuthenticationSuccessEvent
    extends AbstractAuthenticationEvent {
  /// A form login of [authentication].
  InteractiveAuthenticationSuccessEvent(super.authentication);
}

/// Published by `ProviderManager` when a login is refused; a subclass
/// tells why.
///
/// Count these to lock accounts or slow clients down: the security
/// packages do neither. An exception without a subclass of its own is
/// published as this class itself.
///
/// ```dart
/// @EventListener()
/// void onFailure(AbstractAuthenticationFailureEvent event) =>
///     attempts.failed(event.authentication.name);
/// ```
///
/// Spring (Java): `AbstractAuthenticationFailureEvent` (abstract there).
class AbstractAuthenticationFailureEvent extends AbstractAuthenticationEvent {
  /// A refusal of the login request [authentication], with [exception].
  AbstractAuthenticationFailureEvent(super.authentication, this.exception);

  /// The reason the login was refused.
  final AuthenticationException exception;
}

/// A login was refused for a wrong password or an unknown username
/// (a `BadCredentialsException` or `UsernameNotFoundException`).
class AuthenticationFailureBadCredentialsEvent
    extends AbstractAuthenticationFailureEvent {
  /// A refusal of the login request [authentication], with [exception].
  AuthenticationFailureBadCredentialsEvent(
    super.authentication,
    super.exception,
  );
}

/// A login was refused because the account is disabled.
class AuthenticationFailureDisabledEvent
    extends AbstractAuthenticationFailureEvent {
  /// A refusal of the login request [authentication], with [exception].
  AuthenticationFailureDisabledEvent(super.authentication, super.exception);
}

/// A login was refused because the account is locked.
class AuthenticationFailureLockedEvent
    extends AbstractAuthenticationFailureEvent {
  /// A refusal of the login request [authentication], with [exception].
  AuthenticationFailureLockedEvent(super.authentication, super.exception);
}

/// A login was refused because the account has expired.
class AuthenticationFailureExpiredEvent
    extends AbstractAuthenticationFailureEvent {
  /// A refusal of the login request [authentication], with [exception].
  AuthenticationFailureExpiredEvent(super.authentication, super.exception);
}

/// A login was refused because the password has expired.
class AuthenticationFailureCredentialsExpiredEvent
    extends AbstractAuthenticationFailureEvent {
  /// A refusal of the login request [authentication], with [exception].
  AuthenticationFailureCredentialsExpiredEvent(
    super.authentication,
    super.exception,
  );
}

/// A login was refused because no `AuthenticationProvider` handles its
/// kind of request, usually a configuration error.
class AuthenticationFailureProviderNotFoundEvent
    extends AbstractAuthenticationFailureEvent {
  /// A refusal of the login request [authentication], with [exception].
  AuthenticationFailureProviderNotFoundEvent(
    super.authentication,
    super.exception,
  );
}

/// A login could not be checked because something failed, such as the
/// user store (an `AuthenticationServiceException`).
class AuthenticationFailureServiceExceptionEvent
    extends AbstractAuthenticationFailureEvent {
  /// A refusal of the login request [authentication], with [exception].
  AuthenticationFailureServiceExceptionEvent(
    super.authentication,
    super.exception,
  );
}

/// Published by the web starter's logout when a logged-in user logged
/// out; not for anonymous users.
///
/// Spring (Java): `LogoutSuccessEvent`.
class LogoutSuccessEvent extends AbstractAuthenticationEvent {
  /// The logout of [authentication].
  LogoutSuccessEvent(super.authentication);
}

/// Where `ProviderManager` reports each login outcome.
///
/// The auto-configured [DefaultAuthenticationEventPublisher] turns them
/// into application events. Declare your own bean of this type to send
/// them somewhere else, such as a security monitoring system.
///
/// Spring (Java): `AuthenticationEventPublisher`.
abstract interface class AuthenticationEventPublisher {
  /// Reports that the login succeeded; [authentication] is the result.
  void publishAuthenticationSuccess(Authentication authentication);

  /// Reports that the login request [authentication] was refused with
  /// [exception].
  void publishAuthenticationFailure(
    AuthenticationException exception,
    Authentication authentication,
  );
}

/// The default [AuthenticationEventPublisher]: it publishes each outcome as
/// an application event that `@EventListener` methods receive.
///
/// A success becomes an [AuthenticationSuccessEvent]. A failure becomes
/// the event class matching its exception, such as
/// [AuthenticationFailureBadCredentialsEvent] for wrong credentials, or
/// [AbstractAuthenticationFailureEvent] for an exception with no event of
/// its own.
///
/// Spring (Java): `DefaultAuthenticationEventPublisher`.
final class DefaultAuthenticationEventPublisher
    implements AuthenticationEventPublisher {
  /// A publisher sending the events to [publisher], usually the
  /// application context.
  DefaultAuthenticationEventPublisher(this.publisher);

  /// The application's event publisher.
  final ApplicationEventPublisher publisher;

  @override
  void publishAuthenticationSuccess(Authentication authentication) =>
      publisher.publishEvent(AuthenticationSuccessEvent(authentication));

  @override
  void publishAuthenticationFailure(
    AuthenticationException exception,
    Authentication authentication,
  ) => publisher.publishEvent(switch (exception) {
    BadCredentialsException() || UsernameNotFoundException() =>
      AuthenticationFailureBadCredentialsEvent(authentication, exception),
    DisabledException() => AuthenticationFailureDisabledEvent(
      authentication,
      exception,
    ),
    LockedException() => AuthenticationFailureLockedEvent(
      authentication,
      exception,
    ),
    AccountExpiredException() => AuthenticationFailureExpiredEvent(
      authentication,
      exception,
    ),
    CredentialsExpiredException() =>
      AuthenticationFailureCredentialsExpiredEvent(authentication, exception),
    ProviderNotFoundException() => AuthenticationFailureProviderNotFoundEvent(
      authentication,
      exception,
    ),
    AuthenticationServiceException() =>
      AuthenticationFailureServiceExceptionEvent(authentication, exception),
    _ => AbstractAuthenticationFailureEvent(authentication, exception),
  });
}
