import 'package:spring_core_dart/src/core/nested_exception.dart';

/// Why the retries of an operation ended without a success.
enum RetryStop {
  /// The failure is not one the policy retries (or never retried at all:
  /// a Dart `Error`, a `NonRetryableException`).
  notRetryable,

  /// The policy's retries are used up.
  exhausted,

  /// The policy's timeout would pass before the next attempt.
  timeout,

  /// The `RequestDeadline` of the code would pass before the next
  /// attempt.
  deadline,

  /// A rule of the framework refused to retry a call (a `MethodRetryVeto`:
  /// the call runs in a transaction it did not open).
  vetoed,
}

/// Thrown by `RetryTemplate.execute` when an operation failed and the
/// policy gives up: [cause] is the last failure, [previousErrors] the
/// earlier ones, oldest first.
///
/// ```dart
/// try {
///   await template.execute(() => api.send(order));
/// } on RetryException catch (e) {
///   log.warning('gave up after ${e.retryCount} retries', error: e.cause);
/// }
/// ```
///
/// Spring (Java): `org.springframework.core.retry.RetryException`, whose
/// earlier failures are the suppressed exceptions.
class RetryException implements NestedException, Exception {
  /// The end of the retries of [name], for the reason [stop].
  RetryException(
    this.message, {
    required this.cause,
    this.causeStackTrace,
    this.previousErrors = const [],
    this.retryCount = 0,
    this.stop = RetryStop.exhausted,
    this.name = '',
  });

  /// What happened.
  final String message;

  /// The last failure.
  @override
  final Object cause;

  /// Where [cause] was thrown.
  final StackTrace? causeStackTrace;

  /// The failures before the last one, oldest first.
  final List<Object> previousErrors;

  /// How many new attempts were made after the first.
  final int retryCount;

  /// Why the retries ended.
  final RetryStop stop;

  /// The operation's name.
  final String name;

  /// Every failure, oldest first: [previousErrors], then [cause].
  List<Object> get errors => [...previousErrors, cause];

  @override
  String toString() => 'RetryException: $message; caused by $cause';
}
