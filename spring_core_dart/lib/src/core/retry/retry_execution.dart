import 'package:spring_core_dart/src/core/request_deadline.dart';
import 'package:spring_core_dart/src/core/retry/back_off.dart';
import 'package:spring_core_dart/src/core/retry/retry_exception.dart';
import 'package:spring_core_dart/src/core/retry/retry_listener.dart';
import 'package:spring_core_dart/src/core/retry/retry_policy.dart';

/// The retries of one operation under a policy, step by step: what
/// `RetryTemplate` and the `@Retryable` interceptor share. After each
/// failure [failed] says whether to try again and after which pause.
///
/// Framework code; applications use `RetryTemplate`.
final class RetryExecution {
  /// The retries of the operation [name] under [policy], told to
  /// [listener].
  RetryExecution(this.policy, this.listener, this.name);

  /// The policy.
  final RetryPolicy policy;

  /// Who is told.
  final RetryListener listener;

  /// The operation's name.
  final String name;

  final Stopwatch _clock = Stopwatch()..start();
  late final BackOffExecution _backOff = policy.backOff.start();
  final List<Object> _errors = [];

  /// The failures so far, oldest first.
  List<Object> get errors => List.unmodifiable(_errors);

  /// Where the last failure was thrown.
  StackTrace? lastStackTrace;

  /// The new attempts made so far.
  int retryCount = 0;

  /// Why no new attempt is made, once [failed] returned `null`.
  RetryStop? stop;

  /// Records the failure [error] of the last attempt and returns the
  /// pause before the next one, or `null` when there is to be none
  /// ([stop] says why). [vetoed] stops at once.
  Duration? failed(Object error, StackTrace stackTrace, {bool vetoed = false}) {
    _errors.add(error);
    lastStackTrace = stackTrace;
    if (retryCount > 0) {
      listener.onRetryFailure(policy, name, error);
    }
    if (vetoed) {
      stop = RetryStop.vetoed;
      return null;
    }
    if (!policy.shouldRetry(error)) {
      stop = RetryStop.notRetryable;
      return null;
    }
    final pause = _backOff.nextBackOff();
    if (pause == null) {
      stop = RetryStop.exhausted;
      return null;
    }
    final timeout = policy.timeout;
    if (timeout > Duration.zero && _clock.elapsed + pause > timeout) {
      stop = RetryStop.timeout;
      return null;
    }
    if (RequestDeadline.current case final deadline?
        when pause >= deadline.remaining) {
      stop = RetryStop.deadline;
      return null;
    }
    return pause;
  }

  /// A new attempt starts.
  void retrying() {
    retryCount++;
    listener.beforeRetry(policy, name);
  }

  /// The last attempt succeeded with [result].
  void succeeded(Object? result) {
    if (retryCount > 0) {
      listener.onRetrySuccess(policy, name, result);
    }
  }

  /// The end of the retries, once [failed] returned `null`: the
  /// [RetryException] with every failure, told to the listener.
  RetryException end() {
    final stop = this.stop ?? RetryStop.exhausted;
    final exception = RetryException(
      switch (stop) {
        RetryStop.notRetryable =>
          "Operation '$name' failed with an error its retry policy does not "
              'retry',
        RetryStop.exhausted =>
          "Retry policy for operation '$name' exhausted after $retryCount "
              'retries; aborting execution',
        RetryStop.timeout =>
          "Retry policy for operation '$name' timed out after "
              '${_clock.elapsed.inMilliseconds} ms; aborting execution',
        RetryStop.deadline =>
          "Operation '$name' not retried: the next attempt would start after "
              'the request deadline',
        RetryStop.vetoed => "Operation '$name' may not be retried here",
      },
      cause: _errors.last,
      causeStackTrace: lastStackTrace,
      previousErrors: List.unmodifiable(_errors.sublist(0, _errors.length - 1)),
      retryCount: retryCount,
      stop: stop,
      name: name,
    );
    if (stop == RetryStop.timeout) {
      listener.onRetryPolicyTimeout(policy, name, exception);
    } else {
      listener.onRetryPolicyExhaustion(policy, name, exception);
    }
    return exception;
  }
}
