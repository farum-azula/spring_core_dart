import 'package:spring_boot_starter_feign/src/feign_exception.dart';

/// Decides whether a Feign call that failed is tried again, and after
/// how long.
///
/// A remote service can be briefly out of reach, time out, or ask to be
/// called later. A retryer makes such calls succeed without code around
/// every call. Only [RetryableException]s are retried: no connection, a
/// timeout, or an answer with a `Retry-After` header; an error status
/// alone is not. Nothing is retried by default ([Retryer.never]), as in
/// Spring Cloud OpenFeign. Declare a `Retryer` bean to retry the calls of
/// every client, or put it in a client's `configuration` class for that
/// client only. Each attempt is built again from the arguments and passes
/// the interceptors again, so a refreshed token reaches the retry.
///
/// ```dart
/// // Up to 3 attempts per call, with pauses of 150 ms and 225 ms.
/// @Bean()
/// Retryer retryer() => const DefaultRetryer(maxAttempts: 3);
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean Retryer retryer() { return new Retryer.Default(100, 1000, 3); }
/// ```
abstract interface class Retryer {
  /// A retryer that never retries: the first failure is thrown. The
  /// default.
  static const Retryer never = _NeverRetry();

  /// The pause before the next attempt, after attempt number [attempt]
  /// (counted from 1) failed with [error]; `null` to give up, so the call
  /// throws [error].
  Duration? nextDelay(int attempt, RetryableException error);
}

final class _NeverRetry implements Retryer {
  const _NeverRetry();

  @override
  Duration? nextDelay(int attempt, RetryableException error) => null;
}

/// A [Retryer] with a growing pause between attempts, as Feign's
/// `Retryer.Default`.
///
/// It makes up to [maxAttempts] attempts in all. After failed attempt
/// `n`, it waits [period] × 1.5^n: 150 ms, 225 ms, 338 ms, ... with the
/// default period of 100 ms. When the server sent `Retry-After`, it waits
/// until then instead. No pause is longer than [maxPeriod].
///
/// ```dart
/// // A slow partner: 4 attempts, pauses from 750 ms up to 5 s.
/// @Bean()
/// Retryer partnerRetryer() => const DefaultRetryer(
///   period: Duration(milliseconds: 500),
///   maxPeriod: Duration(seconds: 5),
///   maxAttempts: 4,
/// );
/// ```
class DefaultRetryer implements Retryer {
  /// Retries with growing pauses; by default 5 attempts, a period of
  /// 100 ms and pauses of at most 1 second.
  const DefaultRetryer({
    this.period = const Duration(milliseconds: 100),
    this.maxPeriod = const Duration(seconds: 1),
    this.maxAttempts = 5,
  });

  /// The base of the pauses: the first one is 1.5 × [period].
  final Duration period;

  /// The longest pause, also when `Retry-After` asks for more.
  final Duration maxPeriod;

  /// How many attempts a call gets in all, the first one included.
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
