import 'package:spring_core_dart/src/core/retry/retry_exception.dart';
import 'package:spring_core_dart/src/core/retry/retry_policy.dart';
import 'package:spring_core_dart/src/core/retry/retry_template.dart';

/// Told how the retries of an operation go: each new attempt, its
/// failure, the success after retries, and the end when the policy gives
/// up. Override the methods you need; the others do nothing.
///
/// A [RetryTemplate] takes one; for `@Retryable` methods every bean of
/// this type is told (and a `MethodRetryEvent` is published for each
/// failure). `name` is the operation's: `Class.method` for a method.
///
/// ```dart
/// @Component()
/// class RetryLog extends RetryListener {
///   @override
///   void beforeRetry(RetryPolicy retryPolicy, String name) =>
///       log.info('retrying $name');
/// }
/// ```
///
/// Spring (Java): `org.springframework.core.retry.RetryListener`, whose
/// methods get the `Retryable` instead of its name.
abstract class RetryListener {
  /// A listener; subclasses override what they need.
  const RetryListener();

  /// A new attempt is about to start, after a failure and its pause.
  void beforeRetry(RetryPolicy retryPolicy, String name) {}

  /// A new attempt succeeded with [result]; not called when the first
  /// attempt does.
  void onRetrySuccess(RetryPolicy retryPolicy, String name, Object? result) {}

  /// A new attempt failed with [error]; not called for the first attempt.
  void onRetryFailure(RetryPolicy retryPolicy, String name, Object error) {}

  /// The policy gives up: the failure is not retried, the attempts are
  /// used up or the request's deadline would pass; [exception] holds every
  /// failure.
  void onRetryPolicyExhaustion(
    RetryPolicy retryPolicy,
    String name,
    RetryException exception,
  ) {}

  /// The policy's timeout would pass before the next attempt;
  /// [exception] holds every failure.
  void onRetryPolicyTimeout(
    RetryPolicy retryPolicy,
    String name,
    RetryException exception,
  ) {}
}

/// Tells each of [listeners] in turn.
///
/// Spring (Java):
/// `org.springframework.core.retry.support.CompositeRetryListener`.
final class CompositeRetryListener extends RetryListener {
  /// The listeners, told in this order.
  CompositeRetryListener(Iterable<RetryListener> listeners)
    : _listeners = (() => listeners);

  /// The listeners [listeners] gives when first told something, kept from
  /// then on: for beans that are not to be made before they are needed.
  CompositeRetryListener.lazy(Iterable<RetryListener> Function() listeners)
    : _listeners = listeners;

  final Iterable<RetryListener> Function() _listeners;

  /// The listeners.
  late final List<RetryListener> listeners = List.unmodifiable(_listeners());

  @override
  void beforeRetry(RetryPolicy retryPolicy, String name) {
    for (final listener in listeners) {
      listener.beforeRetry(retryPolicy, name);
    }
  }

  @override
  void onRetrySuccess(RetryPolicy retryPolicy, String name, Object? result) {
    for (final listener in listeners) {
      listener.onRetrySuccess(retryPolicy, name, result);
    }
  }

  @override
  void onRetryFailure(RetryPolicy retryPolicy, String name, Object error) {
    for (final listener in listeners) {
      listener.onRetryFailure(retryPolicy, name, error);
    }
  }

  @override
  void onRetryPolicyExhaustion(
    RetryPolicy retryPolicy,
    String name,
    RetryException exception,
  ) {
    for (final listener in listeners) {
      listener.onRetryPolicyExhaustion(retryPolicy, name, exception);
    }
  }

  @override
  void onRetryPolicyTimeout(
    RetryPolicy retryPolicy,
    String name,
    RetryException exception,
  ) {
    for (final listener in listeners) {
      listener.onRetryPolicyTimeout(retryPolicy, name, exception);
    }
  }
}
