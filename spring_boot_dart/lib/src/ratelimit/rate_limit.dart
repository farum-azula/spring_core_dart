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
  const RateLimit(this.count, this.period, {this._burst});

  /// Reads `<count>/<duration>`: `5/1m`, `120/1m`, `10/s`, `1000/1h`,
  /// `3/500ms`. The duration is written as every duration of the
  /// configuration (`ms`, `s`, `m`, `h`, `d`; a unit alone is one of it).
  /// Throws a [FormatException] for anything else, and for a count or a
  /// duration that is not positive.
  factory RateLimit.parse(String text, {int? burst}) {
    final slash = text.indexOf('/');
    final count = slash < 0
        ? null
        : int.tryParse(text.substring(0, slash).trim());
    var per = slash < 0 ? '' : text.substring(slash + 1).trim();
    if (per.isNotEmpty && int.tryParse(per[0]) == null) {
      per = '1$per';
    }
    Duration? period;
    try {
      period = per.isEmpty ? null : DurationStyle.parse(per);
    } on Object {
      period = null;
    }
    if (count == null || count < 1 || period == null) {
      throw FormatException(
        'A rate limit is <count>/<duration>, such as 5/1m or 120/1m',
        text,
      );
    }
    return RateLimit(count, period, burst: burst)._checked(text);
  }

  RateLimit _checked(String text) {
    if (period <= Duration.zero || capacity < 1) {
      throw FormatException(
        'A rate limit needs a positive duration and burst',
        text,
      );
    }
    return this;
  }

  /// The permits added in one [period].
  final int count;

  /// The time in which [count] permits are added.
  final Duration period;

  final int? _burst;

  /// The size of the bucket: the most permits taken at once. [count]
  /// unless a burst was given.
  int get capacity => _burst ?? count;

  /// The permits added in a second.
  double get refillPerSecond =>
      count * Duration.microsecondsPerSecond / period.inMicroseconds;

  /// How long an empty bucket takes to be full again. A key not used for
  /// that long has a full bucket, so a store may forget it.
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

  /// A full bucket of [limit] at [nowMicros].
  TokenBucket.full(RateLimit limit, int nowMicros)
    : this(limit.capacity.toDouble(), nowMicros);

  /// The tokens in the bucket at [updatedMicros].
  double tokens;

  /// When [tokens] was worked out, in microseconds of the caller's clock.
  int updatedMicros;

  /// Fills the bucket for the time since [updatedMicros], then takes
  /// [permits] when they are there. A clock that went back fills nothing.
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
