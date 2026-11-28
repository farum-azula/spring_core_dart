import 'dart:async';

import 'package:spring_core_dart/src/core/retry/retry_exception.dart';
import 'package:spring_core_dart/src/core/retry/retry_execution.dart';
import 'package:spring_core_dart/src/core/retry/retry_listener.dart';
import 'package:spring_core_dart/src/core/retry/retry_policy.dart';

/// Runs an operation again when it fails, as its [retryPolicy] says: the
/// failures it retries, the pauses between attempts, how many and for how
/// long.
///
/// The framework's own retries use it, and so does code that wants the
/// retries of `@Retryable` without an annotation; it needs no switch and
/// no container. The operation may be synchronous or return a `Future`;
/// the pauses are timers, so nothing blocks. A retry whose pause would end
/// after the `RequestDeadline` of the code is not made.
///
/// ```dart
/// final template = RetryTemplate(
///   retryPolicy: RetryPolicy.builder()
///       .maxRetries(4)
///       .delay(const Duration(milliseconds: 100))
///       .multiplier(2)
///       .include<TimeoutException>()
///       .build(),
/// );
/// final order = await template.execute(() => api.send(basket));
/// ```
///
/// Spring (Java):
/// ```java
/// var template = new RetryTemplate(RetryPolicy.builder()
///     .maxRetries(4).delay(Duration.ofMillis(100)).multiplier(2)
///     .includes(TimeoutException.class).build());
/// Order order = template.execute(() -> api.send(basket));
/// ```
final class RetryTemplate {
  /// A template retrying as [retryPolicy] says (three retries one second
  /// apart by default), telling [retryListener].
  RetryTemplate({RetryPolicy? retryPolicy, RetryListener? retryListener})
    : retryPolicy = retryPolicy ?? RetryPolicy.withDefaults(),
      retryListener = retryListener ?? const _NoListener();

  /// What is retried, and how.
  final RetryPolicy retryPolicy;

  /// Who is told of the attempts.
  final RetryListener retryListener;

  /// Runs [retryable] until it succeeds, and returns its result; when the
  /// policy gives up, throws a [RetryException] whose cause is the last
  /// failure, with the earlier ones. [name] names the operation for the
  /// listener and the exception.
  Future<R> execute<R>(
    FutureOr<R> Function() retryable, {
    String name = 'operation',
  }) => _run(retryable, name, original: false);

  /// As [execute], but when the policy gives up the last failure itself is
  /// thrown, with its stack trace: for a caller that handles the
  /// operation's own exceptions.
  ///
  /// Spring (Java): `RetryTemplate.invoke(Supplier)`.
  Future<R> invoke<R>(
    FutureOr<R> Function() retryable, {
    String name = 'operation',
  }) => _run(retryable, name, original: true);

  Future<R> _run<R>(
    FutureOr<R> Function() retryable,
    String name, {
    required bool original,
  }) async {
    final execution = RetryExecution(retryPolicy, retryListener, name);
    while (true) {
      try {
        final result = await retryable();
        execution.succeeded(result);
        return result;
      } on Object catch (error, stackTrace) {
        final pause = execution.failed(error, stackTrace);
        if (pause == null) {
          final exception = execution.end();
          if (original) {
            Error.throwWithStackTrace(error, stackTrace);
          }
          throw exception;
        }
        if (pause > Duration.zero) {
          await Future<void>.delayed(pause);
        }
        execution.retrying();
      }
    }
  }

  @override
  String toString() => 'RetryTemplate($retryPolicy)';
}

final class _NoListener extends RetryListener {
  const _NoListener();
}
