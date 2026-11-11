// The rate limiter's contract: the limit, the token bucket's arithmetic
// with a clock the test moves, the store in memory and the first
// isolate's side of the pool's store.
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

const int _second = Duration.microsecondsPerSecond;

void main() {
  group('RateLimit', () {
    test('reads <count>/<duration>', () {
      expect(RateLimit.parse('5/1m'), const RateLimit(5, Duration(minutes: 1)));
      expect(RateLimit.parse('120/1m').refillPerSecond, 2);
      expect(
        RateLimit.parse('10/s'),
        const RateLimit(10, Duration(seconds: 1)),
      );
      expect(RateLimit.parse(' 3 / 500ms ').period.inMilliseconds, 500);
      expect(RateLimit.parse('1000/1h').capacity, 1000);
    });

    test('a burst is the size of the bucket', () {
      final limit = RateLimit.parse('60/1m', burst: 10);
      expect(limit.capacity, 10);
      expect(limit.refillPerSecond, 1);
      expect(limit.fullAfter, const Duration(seconds: 10));
      expect('$limit', '60/1m (burst 10)');
    });

    test('refuses what is no limit', () {
      for (final text in [
        '',
        '5',
        '5/',
        '/1m',
        'x/1m',
        '0/1m',
        '-1/1m',
        '5/0s',
        '5/soon',
      ]) {
        expect(
          () => RateLimit.parse(text),
          throwsFormatException,
          reason: text,
        );
      }
      expect(() => RateLimit.parse('5/1m', burst: 0), throwsFormatException);
    });
  });

  group('TokenBucket', () {
    const limit = RateLimit(5, Duration(minutes: 1));

    test('a burst of the capacity, then nothing', () {
      final bucket = TokenBucket.full(limit, 0);
      for (var left = 4; left >= 0; left--) {
        final decision = bucket.tryAcquire(limit, 0);
        expect(decision.allowed, isTrue);
        expect(decision.remaining, left);
        expect(decision.retryAfter, Duration.zero);
      }
      final refused = bucket.tryAcquire(limit, 0);
      expect(refused.allowed, isFalse);
      expect(refused.remaining, 0);
      // One token every twelve seconds.
      expect(refused.retryAfter, const Duration(seconds: 12));
    });

    test('refills evenly, and retry-after shrinks with the time', () {
      final bucket = TokenBucket(0, 0);
      expect(
        bucket.tryAcquire(limit, 3 * _second).retryAfter,
        const Duration(seconds: 9),
      );
      expect(bucket.tryAcquire(limit, 11 * _second).allowed, isFalse);
      expect(bucket.tryAcquire(limit, 12 * _second).allowed, isTrue);
      // Half a minute later: two and a half tokens.
      final later = bucket.tryAcquire(limit, 42 * _second);
      expect(later.allowed, isTrue);
      expect(later.remaining, 1);
    });

    test('never holds more than the capacity', () {
      final bucket = TokenBucket(0, 0);
      final decision = bucket.tryAcquire(limit, 3600 * _second);
      expect(decision.remaining, 4);
      expect(bucket.isFullAt(limit, 3600 * _second), isFalse);
      expect(bucket.isFullAt(limit, 3612 * _second), isTrue);
    });

    test('a refused request takes nothing', () {
      final bucket = TokenBucket(0.5, 0);
      expect(bucket.tryAcquire(limit, 0).allowed, isFalse);
      expect(bucket.tokens, 0.5);
    });

    test('several permits at once', () {
      final bucket = TokenBucket.full(limit, 0);
      expect(bucket.tryAcquire(limit, 0, permits: 3).remaining, 2);
      final refused = bucket.tryAcquire(limit, 0, permits: 3);
      expect(refused.allowed, isFalse);
      expect(refused.retryAfter, const Duration(seconds: 12));
      // More than the bucket holds: never.
      expect(bucket.tryAcquire(limit, 0, permits: 6).allowed, isFalse);
    });

    test('a clock that went back fills nothing', () {
      final bucket = TokenBucket(0, 100 * _second);
      expect(bucket.tryAcquire(limit, 50 * _second).allowed, isFalse);
      expect(bucket.tokens, 0);
    });

    test('a burst apart from the rate', () {
      const bursty = RateLimit(60, Duration(minutes: 1), burst: 3);
      final bucket = TokenBucket.full(bursty, 0);
      for (var i = 0; i < 3; i++) {
        expect(bucket.tryAcquire(bursty, 0).allowed, isTrue);
      }
      expect(
        bucket.tryAcquire(bursty, 0).retryAfter,
        const Duration(seconds: 1),
      );
      expect(bucket.tryAcquire(bursty, _second).allowed, isTrue);
    });
  });

  group('InMemoryRateLimitStore', () {
    const limit = RateLimit(5, Duration(minutes: 1));

    test('a bucket for each key', () async {
      var now = 0;
      final store = InMemoryRateLimitStore(clockMicros: () => now);
      for (var i = 0; i < 5; i++) {
        expect((await store.tryAcquire('a', limit)).allowed, isTrue);
      }
      expect((await store.tryAcquire('a', limit)).allowed, isFalse);
      expect((await store.tryAcquire('b', limit)).allowed, isTrue);
      now = 12 * _second;
      expect((await store.tryAcquire('a', limit)).allowed, isTrue);
      expect((await store.tryAcquire('a', limit)).allowed, isFalse);
    });

    test('100 acquisitions at once never pass the limit', () async {
      final store = InMemoryRateLimitStore(clockMicros: () => 0);
      const ten = RateLimit(10, Duration(minutes: 1));
      final decisions = await Future.wait([
        for (var i = 0; i < 100; i++) store.tryAcquire('k', ten),
      ]);
      expect(decisions.where((d) => d.allowed), hasLength(10));
    });

    test('forgets the buckets that are full again when it is full', () {
      var now = 1;
      final store = InMemoryRateLimitStore(
        maxEntries: 3,
        clockMicros: () => now,
      );
      for (final key in ['a', 'b', 'c']) {
        store.acquire(key, limit);
      }
      expect(store.length, 3);
      // Twelve seconds later a, b and c are full again: all go.
      now = 13 * _second;
      store.acquire('d', limit);
      expect(store.length, 1);
    });

    test('past its size the key not used for the longest goes', () {
      var now = 1;
      final store = InMemoryRateLimitStore(
        maxEntries: 2,
        clockMicros: () => now,
      );
      for (var i = 0; i < 5; i++) {
        store.acquire('a', limit);
      }
      now = 2;
      store.acquire('b', limit);
      now = 3;
      // a is used again, so b is the oldest.
      expect(store.acquire('a', limit).allowed, isFalse);
      store.acquire('c', limit);
      expect(store.length, 2);
      // a kept its empty bucket; b starts anew.
      expect(store.acquire('a', limit).allowed, isFalse);
      expect(store.acquire('b', limit).remaining, 4);
    });

    test('names what it keeps for the warning of a pool', () {
      expect(InMemoryRateLimitStore().isolateLocalState, contains('rate'));
    });
  });

  group('PrimaryIsolateRateLimitStore', () {
    test('asks the handler of the first isolate', () async {
      final handler = PrimaryIsolateRateLimitHandler(
        InMemoryRateLimitStore(clockMicros: () => 0),
      );
      final store = PrimaryIsolateRateLimitStore(PrimaryIsolate([handler]));
      const limit = RateLimit(60, Duration(minutes: 1), burst: 2);
      expect((await store.tryAcquire('k', limit)).remaining, 1);
      expect((await store.tryAcquire('k', limit)).remaining, 0);
      final refused = await store.tryAcquire('k', limit);
      expect(refused.allowed, isFalse);
      expect(refused.retryAfter, const Duration(seconds: 1));
      expect(handler.buckets.length, 1);
    });

    test('the handler refuses what is no question', () {
      final handler = PrimaryIsolateRateLimitHandler(InMemoryRateLimitStore());
      expect(() => handler.handle('x'), throwsArgumentError);
    });

    test('a decision crosses isolates as JSON', () {
      const decision = RateLimitDecision(
        allowed: false,
        remaining: 0,
        retryAfter: Duration(milliseconds: 1500),
      );
      final copy = RateLimitDecision.fromJson(decision.toJson());
      expect(copy.allowed, isFalse);
      expect(copy.retryAfter, const Duration(milliseconds: 1500));
      expect('$copy', contains('1500 ms'));
      expect(
        () => RateLimitDecision.fromJson(const [1]),
        throwsFormatException,
      );
    });
  });
}
