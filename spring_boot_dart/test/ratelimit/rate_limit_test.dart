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

    test('a duration without a unit is refused, with what to write', () {
      // Milliseconds otherwise: 100 every 60 ms never limits.
      expect(
        () => RateLimit.parse('100/60'),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('needs a unit'))
              .having((e) => e.message, 'message', contains('100/60s'))
              .having((e) => e.source, 'source', '100/60'),
        ),
      );
      expect(() => RateLimit.parse('5/1'), throwsFormatException);
      expect(() => RateLimit.parse('5/ 1000 '), throwsFormatException);
    });

    test('the count is decimal digits, with a bound', () {
      for (final text in [
        '0x10/1m',
        '+5/1m',
        '5e2/1m',
        '5.0/1m',
        '1 0/1m',
        '9223372036854775807/1s',
        '99999999999999999999999999/1s',
        '${RateLimit.maxCount + 1}/1s',
      ]) {
        expect(
          () => RateLimit.parse(text),
          throwsFormatException,
          reason: text,
        );
      }
      final most = RateLimit.parse('${RateLimit.maxCount}/1s');
      expect(most.count, RateLimit.maxCount);
      expect(most.refillPerSecond, RateLimit.maxCount);
      expect(RateLimit.parse('007/1m').count, 7);
      expect(
        () => RateLimit.parse('5/1m', burst: RateLimit.maxCount + 1),
        throwsFormatException,
      );
    });

    test('the duration is a number of ms, s, m, h or d, a year at most', () {
      expect(RateLimit.parse('5/1D').period, const Duration(days: 1));
      expect(RateLimit.parse('5/366d').period, const Duration(days: 366));
      expect(RateLimit.parse('5/ms').period, const Duration(milliseconds: 1));
      for (final text in [
        '5/367d',
        '5/9999999d',
        '5/99999999999999999999d',
        '5/-1s',
        '5/+1s',
        '5/1.5s',
        '5/PT1M',
        '5/1w',
        '5/0ms',
      ]) {
        expect(
          () => RateLimit.parse(text),
          throwsFormatException,
          reason: text,
        );
      }
    });

    test('a limit that is not valid cannot be used', () {
      const minute = Duration(minutes: 1);
      for (final limit in const [
        RateLimit(0, minute),
        RateLimit(-1, minute),
        RateLimit(5, Duration.zero),
        RateLimit(5, Duration(seconds: -1)),
        RateLimit(5, minute, burst: 0),
        RateLimit(9223372036854775807, Duration(seconds: 1)),
        RateLimit(5, minute, burst: RateLimit.maxCount + 1),
      ]) {
        expect(limit.requireValid, throwsArgumentError, reason: '$limit');
        expect(() => limit.refillPerSecond, throwsArgumentError);
        expect(() => limit.fullAfter, throwsArgumentError);
        expect(() => TokenBucket.full(limit, 0), throwsArgumentError);
      }
      const RateLimit(1, Duration(microseconds: 1)).requireValid();
      const RateLimit(RateLimit.maxCount, minute, burst: 1).requireValid();
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

    test('a limit that is not valid leaves the bucket as it was', () {
      final bucket = TokenBucket.full(limit, 0);
      expect(bucket.tryAcquire(limit, 0).allowed, isTrue);
      for (final broken in const [
        RateLimit(0, Duration(minutes: 1)),
        RateLimit(5, Duration.zero),
      ]) {
        expect(() => bucket.tryAcquire(broken, _second), throwsArgumentError);
        expect(() => bucket.isFullAt(broken, _second), throwsArgumentError);
      }
      expect(bucket.tokens, 4);
      expect(bucket.updatedMicros, 0);
      // And it goes on with a limit that is one.
      final next = bucket.tryAcquire(limit, 0);
      expect(next.allowed, isTrue);
      expect(next.remaining, 3);
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

    test('refuses a size that keeps no key', () {
      for (final size in [0, -1]) {
        expect(
          () => InMemoryRateLimitStore(maxEntries: size),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              contains('spring.web.rate-limit.memory.max-entries'),
            ),
          ),
        );
      }
    });

    test('with room for one key it still limits that key', () {
      final store = InMemoryRateLimitStore(maxEntries: 1, clockMicros: () => 0);
      const one = RateLimit(1, Duration(minutes: 1));
      expect(store.acquire('a', one).allowed, isTrue);
      expect(store.acquire('a', one).allowed, isFalse);
      expect(store.length, 1);
    });

    test('a limit that is not valid changes no bucket', () async {
      var now = 0;
      final store = InMemoryRateLimitStore(
        maxEntries: 2,
        clockMicros: () => now,
      );
      const one = RateLimit(1, Duration(minutes: 1));
      const none = RateLimit(0, Duration(minutes: 1));
      expect(store.acquire('a', one).allowed, isTrue);
      expect(() => store.acquire('a', none), throwsArgumentError);
      expect(() => store.acquire('b', none), throwsArgumentError);
      // In the future, not thrown at the caller.
      await expectLater(store.tryAcquire('b', none), throwsArgumentError);
      expect(store.length, 1);
      // The store works on: the sweep of a full store reads every
      // bucket's limit.
      now = 2 * _second;
      expect(store.acquire('b', one).allowed, isTrue);
      expect(store.acquire('c', one).allowed, isTrue);
      expect(store.acquire('a', one).allowed, isTrue);
      expect(store.length, 2);
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
