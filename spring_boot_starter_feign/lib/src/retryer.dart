import 'package:spring_boot_starter_feign/src/feign_exception.dart';

/// Decides whether a failed call is tried again, and after how long, like
/// Feign's `Retryer`. Only [RetryableException]s (connection errors,
/// timeouts, `Retry-After` responses) are retried. Spring Cloud OpenFeign's
/// default is [Retryer.never]; declare a bean to retry:
///
/// ```dart
/// @Bean()
/// Retryer retryer() => const DefaultRetryer(maxAttempts: 3);
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean Retryer retryer() { return new Retryer.Default(100, 1000, 3); }
/// ```
abstract interface class Retryer {
  /// Never retries (the default).
  static const Retryer never = _NeverRetry();

  /// The pause before attempt `attempt + 1` after [error] failed attempt
  /// [attempt] (1-based), or `null` to give up and throw.
  Duration? nextDelay(int attempt, RetryableException error);
}

final class _NeverRetry implements Retryer {
  const _NeverRetry();

  @override
  Duration? nextDelay(int attempt, RetryableException error) => null;
}

/// Feign's `Retryer.Default`: up to [maxAttempts] attempts, waiting
/// [period] × 1.5^attempt after failed attempt `attempt` (150 ms, 225 ms,
/// ... with the default 100 ms, as in Feign), at most [maxPeriod] (or
/// until the server's `Retry-After`).
class DefaultRetryer implements Retryer {
  /// Retries with growing pauses.
  const DefaultRetryer({
    this.period = const Duration(milliseconds: 100),
    this.maxPeriod = const Duration(seconds: 1),
    this.maxAttempts = 5,
  });

  /// The base of the pauses: the first one is 1.5 × [period].
  final Duration period;

  /// The longest pause.
  final Duration maxPeriod;

  /// Attempts in total, the first one included.
  final int maxAttempts;

  @override
  Duration? nextDelay(int attempt, RetryableException error) {
    if (attempt >= maxAttempts) {
      return null;
    }
    final retryAfter = error.retryAfter;
    Duration delay;
    if (retryAfter != null) {
      delay = retryAfter.difference(DateTime.now());
      if (delay.isNegative) {
        delay = Duration.zero;
      }
    } else {
      // Feign counts the attempt before computing the interval:
      // period × 1.5^(attempt + 1 − 1).
      var micros = period.inMicroseconds.toDouble();
      for (var i = 0; i < attempt; i++) {
        micros *= 1.5;
      }
      delay = Duration(microseconds: micros.round());
    }
    return delay > maxPeriod ? maxPeriod : delay;
  }
}
