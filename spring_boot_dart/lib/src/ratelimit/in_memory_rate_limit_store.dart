import 'package:spring_boot_dart/src/ratelimit/rate_limit.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// The buckets in the memory of one isolate: the [RateLimitStore] of an
/// application with one isolate and no database
/// (`spring.web.rate-limit.store: memory`).
///
/// Dart runs one piece of code of an isolate at a time, and [tryAcquire]
/// never waits, so the step is atomic without a lock. The buckets are
/// lost when the application stops, and each isolate of a pool would
/// have its own (the pool's default is `PrimaryIsolateRateLimitStore`).
///
/// It keeps at most [maxEntries] keys. A bucket that is full again is
/// forgotten (a key never seen has a full bucket too); when that is not
/// enough, the keys not used for the longest go, so a flood of new keys
/// cannot fill the memory. A key that went this way starts with a full
/// bucket: size [maxEntries] for the clients you expect at once.
///
/// ```dart
/// final store = InMemoryRateLimitStore();
/// final decision = await store.tryAcquire('ip:203.0.113.7', limit);
/// ```
///
/// Spring (Java): Resilience4j's `AtomicRateLimiter` and Bucket4j's local
/// `Bucket` keep theirs in the JVM's heap the same way.
final class InMemoryRateLimitStore
    implements RateLimitStore, IsolateLocalState {
  /// A store of at most [maxEntries] keys; [clockMicros] is the time in
  /// microseconds (default: a clock that never goes back).
  InMemoryRateLimitStore({
    this.maxEntries = 100000,
    int Function()? clockMicros,
  }) : _clock = clockMicros ?? _monotonic();

  static int Function() _monotonic() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds;
  }

  /// The most keys kept.
  final int maxEntries;

  final int Function() _clock;

  // In the order of use: the first is the one not used for the longest.
  final _buckets = <String, _Entry>{};
  var _sweptAt = 0;

  /// How many keys are kept now.
  int get length => _buckets.length;

  @override
  String get isolateLocalState => "the rate limiter's buckets";

  @override
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  }) => Future.value(acquire(key, limit, permits: permits));

  /// [tryAcquire] without a future, for code that is in the isolate.
  RateLimitDecision acquire(String key, RateLimit limit, {int permits = 1}) {
    final now = _clock();
    var entry = _buckets.remove(key);
    if (entry == null) {
      _makeRoom(now);
      entry = _Entry(TokenBucket.full(limit, now), limit);
    } else {
      entry.limit = limit;
    }
    _buckets[key] = entry;
    return entry.bucket.tryAcquire(limit, now, permits: permits);
  }

  // Room for one more key: the full buckets go (at most once a second,
  // or the sweep itself would be the load), then the oldest.
  void _makeRoom(int now) {
    if (_buckets.length < maxEntries) {
      return;
    }
    if (now - _sweptAt >= Duration.microsecondsPerSecond || _sweptAt == 0) {
      _sweptAt = now;
      _buckets.removeWhere((_, e) => e.bucket.isFullAt(e.limit, now));
    }
    while (_buckets.length >= maxEntries && _buckets.isNotEmpty) {
      _buckets.remove(_buckets.keys.first);
    }
  }
}

final class _Entry {
  _Entry(this.bucket, this.limit);

  final TokenBucket bucket;
  RateLimit limit;
}
