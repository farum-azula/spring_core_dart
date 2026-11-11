import 'package:spring_core_dart/spring_core_dart.dart';

/// How much one key may do: [count] permits every [period], with a burst
/// of [capacity].
///
/// It describes a token bucket. The bucket of a key holds at most
/// [capacity] tokens and starts full; every permit takes one token, and
/// the bucket is filled again evenly, [count] tokens per [period]. So a
/// client may spend its burst at once, and then goes on at the steady
/// rate. `5/1m` is five requests at once, then one every twelve seconds.
///
/// ```dart
/// const login = RateLimit(5, Duration(minutes: 1));
/// final api = RateLimit.parse('120/1m', burst: 20);
/// ```
///
/// Spring has no rate limiter in its core. The nearest are Resilience4j's
/// `RateLimiterConfig` (`limitForPeriod`, `limitRefreshPeriod`), Bucket4j's
/// `Bandwidth` and the `replenishRate` / `burstCapacity` of Spring Cloud
/// Gateway's `RedisRateLimiter`.
final class RateLimit {
  /// [count] permits every [period]; `burst` is the size of the bucket
  /// when it is not [count].
  ///
  /// All three must be positive, and [count] and the burst at most
  /// [maxCount]. A constant cannot check that, so a limit that is not
  /// valid is refused where it is used: [refillPerSecond], [fullAfter]
  /// and [TokenBucket] throw an [ArgumentError] ([requireValid]).
  const RateLimit(this.count, this.period, {this._burst});

  /// Reads `<count>/<duration>`: `5/1m`, `120/1m`, `10/s`, `1000/1h`,
  /// `3/500ms`. The count is decimal digits, 1 to [maxCount]. The
  /// duration is a number of `ms`, `s`, `m`, `h` or `d`, a year at most; a
  /// unit alone is one of it. The unit is required: `100/60` would be 100
  /// every 60 milliseconds, a limit that never limits, where `100/60s` or
  /// `100/1m` was meant.
  ///
  /// Throws a [FormatException] for anything else, and for a burst that
  /// is not 1 to [maxCount].
  factory RateLimit.parse(String text, {int? burst}) {
    Never refuse(String why) => throw FormatException(
      'A rate limit is <count>/<duration>, such as 5/1m or 120/1m: $why',
      text,
    );
    final slash = text.indexOf('/');
    if (slash < 0) {
      refuse('there is no "/"');
    }
    final counted = text.substring(0, slash).trim();
    final per = text.substring(slash + 1).trim();
    if (!_digits.hasMatch(counted)) {
      refuse('the count is a whole number in decimal digits');
    }
    final count = counted.length > 10 ? 0 : int.parse(counted);
    if (count < 1 || count > maxCount) {
      refuse('the count is 1 to $maxCount');
    }
    if (_digits.hasMatch(per)) {
      refuse(
        'the duration needs a unit (ms, s, m, h, d), '
        'write $count/${per}s or $count/${per}m',
      );
    }
    final amount = _period.firstMatch(per);
    if (amount == null) {
      refuse('the duration is a number and a unit (ms, s, m, h, d)');
    }
    final number = amount[1]!.isEmpty ? 1 : int.parse(amount[1]!);
    final period = switch (amount[2]!.toLowerCase()) {
      'ms' => Duration(milliseconds: number),
      's' => Duration(seconds: number),
      'm' => Duration(minutes: number),
      'h' => Duration(hours: number),
      _ => Duration(days: number),
    };
    if (period <= Duration.zero || period > _longest) {
      refuse('the duration is more than nothing and a year at most');
    }
    if (burst != null && (burst < 1 || burst > maxCount)) {
      refuse('the burst is 1 to $maxCount, not $burst');
    }
    return RateLimit(count, period, burst: burst);
  }

  /// The largest [count] and burst: a thousand million. Beyond it the
  /// arithmetic of a bucket is no longer exact, and no server serves as
  /// much.
  static const maxCount = 1000000000;

  static final _digits = RegExp(r'^[0-9]+$');

  // At most seven digits: no number of days that is read overflows.
  static final _period = RegExp(
    r'^([0-9]{0,7})\s*(ms|s|m|h|d)$',
    caseSensitive: false,
  );

  static const _longest = Duration(days: 366);

  /// Throws an [ArgumentError] unless the limit can be used: [count] and
  /// [capacity] from 1 to [maxCount], and a [period] that is positive.
  ///
  /// The stores that work a bucket out themselves call it (or read
  /// [refillPerSecond], which does) before they change anything. A limit
  /// of nothing, or every no time, has no rate: its bucket would hold
  /// "not a number" of tokens from then on.
  void requireValid() {
    if (count < 1 || count > maxCount) {
      throw ArgumentError.value(
        count,
        'count',
        'A rate limit counts 1 to $maxCount permits',
      );
    }
    if (period <= Duration.zero) {
      throw ArgumentError.value(
        period,
        'period',
        'A rate limit needs a positive period',
      );
    }
    if (capacity < 1 || capacity > maxCount) {
      throw ArgumentError.value(
        capacity,
        'burst',
        'A rate limit has a burst of 1 to $maxCount',
      );
    }
  }

  /// The permits added in one [period].
  final int count;

  /// The time in which [count] permits are added.
  final Duration period;

  final int? _burst;

  /// The size of the bucket: the most permits taken at once. [count]
  /// unless a burst was given.
  int get capacity => _burst ?? count;

  /// The permits added in a second. Throws an [ArgumentError] for a limit
  /// that is not valid ([requireValid]).
  double get refillPerSecond {
    requireValid();
    return count * Duration.microsecondsPerSecond / period.inMicroseconds;
  }

  /// How long an empty bucket takes to be full again. A key not used for
  /// that long has a full bucket, so a store may forget it. Throws an
  /// [ArgumentError] for a limit that is not valid ([requireValid]).
  Duration get fullAfter =>
      Duration(microseconds: (capacity / refillPerSecond * 1e6).ceil());

  @override
  bool operator ==(Object other) =>
      other is RateLimit &&
      other.count == count &&
      other.period == period &&
      other.capacity == capacity;

  @override
  int get hashCode => Object.hash(count, period, capacity);

  @override
  String toString() =>
      '$count/${DurationStyle.format(period)}'
      '${capacity == count ? '' : ' (burst $capacity)'}';
}

/// What a [RateLimitStore] answered: whether the permits were taken, what
/// is left, and when to come back.
final class RateLimitDecision {
  /// A decision.
  const RateLimitDecision({
    required this.allowed,
    required this.remaining,
    this.retryAfter = Duration.zero,
  });

  /// The decision [json] ([toJson]) describes.
  factory RateLimitDecision.fromJson(Object? json) => switch (json) {
    {
      'allowed': final bool allowed,
      'remaining': final num remaining,
      'retryAfterMicros': final num micros,
    } =>
      RateLimitDecision(
        allowed: allowed,
        remaining: remaining.toInt(),
        retryAfter: Duration(microseconds: micros.toInt()),
      ),
    _ => throw FormatException('Not a rate limit decision', '$json'),
  };

  /// Whether the permits were taken. When `false` nothing was taken.
  final bool allowed;

  /// The whole permits left in the bucket after this decision.
  final int remaining;

  /// When refused: how long until the permits asked for are there. Zero
  /// when [allowed].
  final Duration retryAfter;

  /// The decision as JSON, which crosses isolates.
  Map<String, Object?> toJson() => {
    'allowed': allowed,
    'remaining': remaining,
    'retryAfterMicros': retryAfter.inMicroseconds,
  };

  @override
  String toString() => allowed
      ? 'allowed, $remaining left'
      : 'refused, retry after ${retryAfter.inMilliseconds} ms';
}

/// Where the rate limiter keeps its buckets: one operation, which is
/// atomic.
///
/// [tryAcquire] does all of the arithmetic in one step that nothing can
/// interleave with: it fills the bucket of the key for the time that
/// passed, takes the permits when they are there, and answers. Two
/// requests that arrive together, in one isolate, in two, or on two
/// servers over one database, never both get the last permit.
///
/// The framework has a store in memory (`InMemoryRateLimitStore`), one
/// that keeps the buckets of all isolates in the first
/// (`PrimaryIsolateRateLimitStore`), one over SQL (the data starter) and
/// one over a database function (the Supabase starter); the default is
/// the most specific the application has (`spring.web.rate-limit.store`
/// names one). An application keeps the buckets elsewhere by declaring a
/// bean of this type, which replaces them all:
///
/// ```dart
/// // The buckets in the application's own key-value service.
/// @Component()
/// class KvRateLimitStore implements RateLimitStore {
///   KvRateLimitStore(this.kv);
///   final KvClient kv;
///
///   @override
///   Future<RateLimitDecision> tryAcquire(
///     String key,
///     RateLimit limit, {
///     int permits = 1,
///   }) async {
///     final answer = await kv.eval(tokenBucketScript, [
///       key, limit.capacity, limit.refillPerSecond, permits,
///     ]);
///     return RateLimitDecision.fromJson(answer);
///   }
/// }
/// ```
///
/// A store that cannot be reached throws; what happens to the request
/// then is the rule's `on-store-failure` (refused by default).
///
/// Spring has none in its core. Spring Cloud Gateway's `RateLimiter`
/// (`isAllowed(routeId, id)`, over Redis) and Bucket4j's `ProxyManager`
/// are the nearest.
abstract interface class RateLimitStore {
  /// Takes [permits] from the bucket of [key] under [limit] when it holds
  /// them, in one atomic step. A key seen for the first time has a full
  /// bucket.
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  });
}

/// The arithmetic of one token bucket: its [tokens] at the time
/// [updatedMicros], and [tryAcquire].
///
/// The stores in memory use it, and a store of an application's own may:
/// it holds no clock and no lock, the caller gives the time and makes the
/// step atomic.
///
/// ```dart
/// final bucket = TokenBucket.full(limit, now);
/// final decision = bucket.tryAcquire(limit, now); // one permit
/// ```
final class TokenBucket {
  /// A bucket with [tokens] at [updatedMicros].
  TokenBucket(this.tokens, this.updatedMicros);

  /// A full bucket of [limit] at [nowMicros]. Throws an [ArgumentError]
  /// for a limit that is not valid ([RateLimit.requireValid]).
  TokenBucket.full(RateLimit limit, int nowMicros)
    : this((limit..requireValid()).capacity.toDouble(), nowMicros);

  /// The tokens in the bucket at [updatedMicros].
  double tokens;

  /// When [tokens] was worked out, in microseconds of the caller's clock.
  int updatedMicros;

  /// Fills the bucket for the time since [updatedMicros], then takes
  /// [permits] when they are there. A clock that went back fills nothing.
  ///
  /// Throws an [ArgumentError] for a limit that is not valid
  /// ([RateLimit.requireValid]), before anything changes: the bucket is
  /// as it was.
  RateLimitDecision tryAcquire(
    RateLimit limit,
    int nowMicros, {
    int permits = 1,
  }) {
    final rate = limit.refillPerSecond;
    final elapsed = nowMicros > updatedMicros ? nowMicros - updatedMicros : 0;
    final filled = tokens + elapsed * rate / Duration.microsecondsPerSecond;
    tokens = filled > limit.capacity ? limit.capacity.toDouble() : filled;
    updatedMicros = nowMicros;
    if (tokens >= permits) {
      tokens -= permits;
      return RateLimitDecision(allowed: true, remaining: tokens.floor());
    }
    return RateLimitDecision(
      allowed: false,
      remaining: tokens.floor(),
      retryAfter: Duration(
        microseconds: ((permits - tokens) / rate * 1e6).ceil(),
      ),
    );
  }

  /// Whether the bucket is full again at [nowMicros]: a store may then
  /// forget it.
  bool isFullAt(RateLimit limit, int nowMicros) =>
      nowMicros - updatedMicros >=
      (limit.capacity - tokens) /
          limit.refillPerSecond *
          Duration.microsecondsPerSecond;
}

/// A [RateLimitStore] that can say, when the application starts, whether
/// what it keeps its buckets in is there: a table, a database function, a
/// binding.
///
/// Without the check a forgotten migration shows only at the first
/// request under a limit, as a 503 (`on-store-failure: deny`) or as no
/// limit at all (`allow`). The web starter calls [verify] once at startup
/// (`spring.web.rate-limit.verify-store`, on by default).
///
/// Differs from Spring: Spring has no rate limiter; Spring Cloud
/// Gateway's `RedisRateLimiter` checks nothing at startup.
abstract interface class VerifiableRateLimitStore implements RateLimitStore {
  /// Completes when the store can count.
  ///
  /// Throws a [RateLimitStoreSetupException] when what it needs is not
  /// there and will not come by itself: the application does not start.
  /// Any other error means the store could not be asked now (the database
  /// is down, the network): the start goes on with a warning, and
  /// `on-store-failure` decides for each request until it answers.
  Future<void> verify();
}

/// What a [VerifiableRateLimitStore] needs is missing: the table or the
/// function of a migration that was not run, a binding that is not
/// declared. The message says what to do.
final class RateLimitStoreSetupException implements Exception {
  /// The setup problem [message] tells.
  const RateLimitStoreSetupException(this.message);

  /// What is missing, and how to get it.
  final String message;

  @override
  String toString() => 'RateLimitStoreSetupException: $message';
}
