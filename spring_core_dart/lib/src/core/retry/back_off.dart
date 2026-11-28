import 'dart:math';

/// How long to wait before each new attempt of a failed operation, and
/// when to stop: [start] gives the pauses of one operation.
///
/// A `RetryPolicy` holds one; [ExponentialBackOff] and [FixedBackOff] are
/// the two kinds, and an application may write its own.
///
/// ```dart
/// final execution = FixedBackOff(
///   interval: const Duration(milliseconds: 200),
///   maxAttempts: 3,
/// ).start();
/// execution.nextBackOff(); // 200 ms, three times, then null
/// ```
///
/// Spring (Java): `org.springframework.util.backoff.BackOff`.
abstract interface class BackOff {
  /// The pauses of a new operation.
  BackOffExecution start();
}

/// The pauses of one operation, from [BackOff.start].
///
/// Spring (Java): `org.springframework.util.backoff.BackOffExecution`.
abstract interface class BackOffExecution {
  /// The pause before the next attempt; `null` when there is to be none
  /// (Spring's `STOP`).
  Duration? nextBackOff();
}

/// The same pause before each attempt, at most [maxAttempts] times.
///
/// ```dart
/// const FixedBackOff(interval: Duration(seconds: 1), maxAttempts: 5);
/// ```
///
/// Spring (Java): `org.springframework.util.backoff.FixedBackOff`.
final class FixedBackOff implements BackOff {
  /// Pauses of [interval] (5 seconds, as in Spring), [maxAttempts] times
  /// (`null`: no end).
  const FixedBackOff({
    this.interval = const Duration(seconds: 5),
    this.maxAttempts,
  });

  /// The pause before each attempt.
  final Duration interval;

  /// How many pauses at most; `null` for no end.
  final int? maxAttempts;

  @override
  BackOffExecution start() => _FixedExecution(this);

  @override
  String toString() =>
      'FixedBackOff(${interval.inMilliseconds} ms, '
      '${maxAttempts ?? 'unlimited'} attempts)';
}

final class _FixedExecution implements BackOffExecution {
  _FixedExecution(this._backOff);

  final FixedBackOff _backOff;
  int _attempts = 0;

  @override
  Duration? nextBackOff() {
    final max = _backOff.maxAttempts;
    if (max != null && _attempts >= max) {
      return null;
    }
    _attempts++;
    return _backOff.interval;
  }
}

/// A pause that grows by [multiplier] after each attempt, from
/// [initialInterval] up to [maxInterval], with a random [jitter] added,
/// at most [maxAttempts] times.
///
/// The jitter grows with the pause: a pause of three times the initial
/// interval may be up to three jitters longer. It never makes a pause
/// shorter than [initialInterval] or longer than [maxInterval].
///
/// ```dart
/// // 100 ms, 200 ms, 400 ms, 800 ms, then 1 s each, ten times in all.
/// const ExponentialBackOff(
///   initialInterval: Duration(milliseconds: 100),
///   multiplier: 2,
///   maxInterval: Duration(seconds: 1),
///   maxAttempts: 10,
/// );
/// ```
///
/// Spring (Java): `org.springframework.util.backoff.ExponentialBackOff`
/// (whose defaults, 2 s and 1.5, are not repeated here: a `RetryPolicy`
/// gives its own).
final class ExponentialBackOff implements BackOff {
  /// The pauses; [maxInterval] `null` is no limit, [maxAttempts] `null` no
  /// end. [random] draws the jitter.
  const ExponentialBackOff({
    this.initialInterval = const Duration(seconds: 1),
    this.multiplier = 1,
    this.maxInterval,
    this.jitter = Duration.zero,
    this.maxAttempts,
    this.random,
  });

  /// The first pause.
  final Duration initialInterval;

  /// What each pause is multiplied by for the next one; `1` keeps it.
  final double multiplier;

  /// The longest pause; `null` for no limit.
  final Duration? maxInterval;

  /// The most added at random to a pause of [initialInterval]; zero for
  /// none.
  final Duration jitter;

  /// How many pauses at most; `null` for no end.
  final int? maxAttempts;

  /// Where the jitter is drawn from; a new `Random` when `null`.
  final Random? random;

  @override
  BackOffExecution start() => _ExponentialExecution(this);

  @override
  String toString() =>
      'ExponentialBackOff(${initialInterval.inMilliseconds} ms x $multiplier'
      '${switch (maxInterval) {
        null => '',
        final limit => ', at most ${limit.inMilliseconds} ms',
      }}'
      '${jitter == Duration.zero ? '' : ', jitter ${jitter.inMilliseconds} ms'}'
      ', ${maxAttempts ?? 'unlimited'} attempts)';
}

final class _ExponentialExecution implements BackOffExecution {
  _ExponentialExecution(this._backOff);

  final ExponentialBackOff _backOff;
  late final Random _random = _backOff.random ?? Random();
  int _attempts = 0;
  int? _current;

  @override
  Duration? nextBackOff() {
    final backOff = _backOff;
    final max = backOff.maxAttempts;
    if (max != null && _attempts >= max) {
      return null;
    }
    _attempts++;
    final initial = backOff.initialInterval.inMicroseconds;
    final limit = backOff.maxInterval?.inMicroseconds;
    var interval = switch (_current) {
      null => initial,
      final previous => (previous * backOff.multiplier).round(),
    };
    if (limit != null && interval > limit) {
      interval = limit;
    }
    _current = interval;
    return Duration(microseconds: _withJitter(interval, initial, limit));
  }

  int _withJitter(int interval, int initial, int? limit) {
    final jitter = _backOff.jitter.inMicroseconds;
    if (jitter <= 0) {
      return interval;
    }
    final scale = initial <= 0 ? 1.0 : interval / initial;
    final applicable = (jitter * scale).round();
    final low = max(interval - applicable, initial);
    var high = interval + applicable;
    if (limit != null && high > limit) {
      high = limit;
    }
    if (high <= low) {
      return low;
    }
    return low + _random.nextInt(min(high - low, 0x7FFFFFFF));
  }
}
