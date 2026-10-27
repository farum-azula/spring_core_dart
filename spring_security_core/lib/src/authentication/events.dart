import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/exceptions.dart';

/// An authentication happened, like Spring's
/// `AbstractAuthenticationEvent`; its [authentication] is the source.
abstract class AbstractAuthenticationEvent extends ApplicationEvent {
  /// An event about [authentication].
  AbstractAuthenticationEvent(this.authentication) : super(authentication);

  /// The authentication.
  final Authentication authentication;
}

/// A login succeeded, like Spring's `AuthenticationSuccessEvent`.
///
/// ```dart
/// @EventListener()
/// void onLogin(AuthenticationSuccessEvent event) =>
///     audit.loggedIn(event.authentication.name);
/// ```
class AuthenticationSuccessEvent extends AbstractAuthenticationEvent {
  /// [authentication] succeeded.
  AuthenticationSuccessEvent(super.authentication);
}

/// A login through a form or a login request succeeded and the user is now
/// logged in, like Spring's `InteractiveAuthenticationSuccessEvent`.
class InteractiveAuthenticationSuccessEvent
    extends AbstractAuthenticationEvent {
  /// [authentication] logged in.
  InteractiveAuthenticationSuccessEvent(super.authentication);
}

/// A login failed, like Spring's `AbstractAuthenticationFailureEvent`:
/// count these to lock accounts or slow clients down (the packages do not).
///
/// ```dart
/// @EventListener()
/// void onFailure(AbstractAuthenticationFailureEvent event) =>
///     attempts.failed(event.authentication.name);
/// ```
class AbstractAuthenticationFailureEvent extends AbstractAuthenticationEvent {
  /// [authentication] failed with [exception].
  AbstractAuthenticationFailureEvent(super.authentication, this.exception);

  /// Why.
  final AuthenticationException exception;
}

/// Wrong username or password.
class AuthenticationFailureBadCredentialsEvent
    extends AbstractAuthenticationFailureEvent {
  /// [authentication] failed with [exception].
  AuthenticationFailureBadCredentialsEvent(
    super.authentication,
    super.exception,
  );
}

/// The account is disabled.
class AuthenticationFailureDisabledEvent
    extends AbstractAuthenticationFailureEvent {
  /// [authentication] failed with [exception].
  AuthenticationFailureDisabledEvent(super.authentication, super.exception);
}

/// The account is locked.
class AuthenticationFailureLockedEvent
    extends AbstractAuthenticationFailureEvent {
  /// [authentication] failed with [exception].
  AuthenticationFailureLockedEvent(super.authentication, super.exception);
}

/// The account has expired.
class AuthenticationFailureExpiredEvent
    extends AbstractAuthenticationFailureEvent {
  /// [authentication] failed with [exception].
  AuthenticationFailureExpiredEvent(super.authentication, super.exception);
}

/// The password has expired.
class AuthenticationFailureCredentialsExpiredEvent
    extends AbstractAuthenticationFailureEvent {
  /// [authentication] failed with [exception].
  AuthenticationFailureCredentialsExpiredEvent(
    super.authentication,
    super.exception,
  );
}

/// No provider could handle the request.
class AuthenticationFailureProviderNotFoundEvent
    extends AbstractAuthenticationFailureEvent {
  /// [authentication] failed with [exception].
  AuthenticationFailureProviderNotFoundEvent(
    super.authentication,
    super.exception,
  );
}

/// Authentication could not be done (a store failed).
class AuthenticationFailureServiceExceptionEvent
    extends AbstractAuthenticationFailureEvent {
  /// [authentication] failed with [exception].
  AuthenticationFailureServiceExceptionEvent(
    super.authentication,
    super.exception,
  );
}

/// A user logged out, like Spring's `LogoutSuccessEvent`.
class LogoutSuccessEvent extends AbstractAuthenticationEvent {
  /// [authentication] logged out.
  LogoutSuccessEvent(super.authentication);
}

/// Publishes authentication outcomes, like Spring's
/// `AuthenticationEventPublisher`.
abstract interface class AuthenticationEventPublisher {
  /// [authentication] succeeded.
  void publishAuthenticationSuccess(Authentication authentication);

  /// [authentication] failed with [exception].
  void publishAuthenticationFailure(
    AuthenticationException exception,
    Authentication authentication,
  );
}

/// Publishes the events above as application events, like Spring's
/// `DefaultAuthenticationEventPublisher`.
final class DefaultAuthenticationEventPublisher
    implements AuthenticationEventPublisher {
  /// Publishes through [publisher].
  DefaultAuthenticationEventPublisher(this.publisher);

  /// Where events go.
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
