import 'dart:async';

import 'package:spring_boot_dart/src/ratelimit/in_memory_rate_limit_store.dart';
import 'package:spring_boot_dart/src/ratelimit/rate_limit.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// The buckets of every isolate in one place, the application's first
/// isolate: the [RateLimitStore] of a server with a pool of isolates
/// (`server.isolates.*`; `spring.web.rate-limit.store: primary-isolate`).
///
/// A request reaches any isolate of the pool; each asks the first one
/// ([PrimaryIsolate.ask]), where [PrimaryIsolateRateLimitHandler] keeps
/// one set of buckets in memory. So a limit of `5/1m` is five for the
/// server, not five per isolate. In the first isolate itself the question
/// is a plain call. The buckets are lost when the application stops; two
/// servers do not share them (a database does: the SQL store).
///
/// ```dart
/// final store = PrimaryIsolateRateLimitStore(primaryIsolate);
/// ```
///
/// Spring has no counterpart: a JVM's threads share one heap.
final class PrimaryIsolateRateLimitStore implements RateLimitStore {
  /// A store that asks through [primary].
  PrimaryIsolateRateLimitStore(PrimaryIsolate primary)
    : _primary = (() => primary);

  /// A store that asks through what [primary] gives, looked up at the
  /// first question: for a bean that the `primaryIsolate` bean's handlers
  /// depend on themselves.
  PrimaryIsolateRateLimitStore.lazy(this._primary);

  final PrimaryIsolate Function() _primary;

  /// Asks the first isolate.
  late final PrimaryIsolate primary = _primary();

  @override
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  }) async => RateLimitDecision.fromJson(
    await primary.ask(PrimaryIsolateRateLimitHandler.handlerId, [
      key,
      limit.count,
      limit.period.inMicroseconds,
      limit.capacity,
      permits,
    ]),
  );
}

/// The first isolate's side of [PrimaryIsolateRateLimitStore]: it answers
/// the isolates' questions from one [InMemoryRateLimitStore].
final class PrimaryIsolateRateLimitHandler implements PrimaryIsolateHandler {
  /// A handler over [buckets].
  PrimaryIsolateRateLimitHandler(this.buckets);

  /// The name it answers under ([PrimaryIsolate.ask]).
  static const handlerId = 'web.rate-limit';

  /// The buckets of the whole server.
  final InMemoryRateLimitStore buckets;

  @override
  String get id => handlerId;

  @override
  Object? handle(Object? request) => switch (request) {
    [
      final String key,
      final int count,
      final int periodMicros,
      final int capacity,
      final int permits,
    ] =>
      buckets
          .acquire(
            key,
            RateLimit(
              count,
              Duration(microseconds: periodMicros),
              burst: capacity,
            ),
            permits: permits,
          )
          .toJson(),
    _ => throw ArgumentError.value(request, 'request', 'Not a rate limit'),
  };
}
