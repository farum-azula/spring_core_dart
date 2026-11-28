// RetryTemplate and RetryPolicy: retries until a success, RetryException
// with every failure on exhaustion, invoke rethrows the last failure, the
// policy's matching, the back-off, the timeout and the deadline.
import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

final class _Stops extends RetryListener {
  final stops = <String>[];

  @override
  void onRetryPolicyExhaustion(
    RetryPolicy retryPolicy,
    String name,
    RetryException exception,
  ) => stops.add('exhausted $name');

  @override
  void onRetryPolicyTimeout(
    RetryPolicy retryPolicy,
    String name,
    RetryException exception,
  ) => stops.add('timeout $name');
}

void main() {
  RetryTemplate template({
    int maxRetries = 3,
    Duration delay = Duration.zero,
    RetryListener? listener,
    RetryPolicyBuilder Function(RetryPolicyBuilder)? more,
  }) {
    var builder = RetryPolicy.builder().maxRetries(maxRetries).delay(delay);
    if (more != null) {
      builder = more(builder);
    }
    return RetryTemplate(retryPolicy: builder.build(), retryListener: listener);
  }

  test('runs again until it succeeds', () async {
    var calls = 0;
    final result = await template().execute(() {
      calls++;
      if (calls < 3) {
        throw TimeoutException('slow');
      }
      return calls;
    });
    expect(result, 3);
  });

  test('exhausted: a RetryException with every failure', () async {
    var calls = 0;
    final listener = _Stops();
    final exception = await template(listener: listener)
        .execute<void>(
          () async => throw FormatException('${++calls}'),
          name: 'load',
        )
        .then<RetryException?>(
          (_) => null,
          onError: (Object e) => e as RetryException,
        );
    expect(exception!.retryCount, 3);
    expect(exception.stop, RetryStop.exhausted);
    expect((exception.cause as FormatException).message, '4');
    expect(
      [
        for (final e in exception.previousErrors)
          (e as FormatException).message,
      ],
      ['1', '2', '3'],
    );
    expect(exception.errors, hasLength(4));
    expect(listener.stops, ['exhausted load']);
    expect(NestedExceptionUtils.rootCause(exception), exception.cause);
  });

  test('invoke rethrows the last failure itself', () async {
    var calls = 0;
    await expectLater(
      template(maxRetries: 1).invoke<void>(() => throw StateErrorLike(++calls)),
      throwsA(isA<StateErrorLike>().having((e) => e.attempt, 'attempt', 2)),
    );
  });

  test('a Dart Error is not retried', () async {
    var calls = 0;
    await expectLater(
      template().invoke<void>(() {
        calls++;
        throw StateError('bug');
      }),
      throwsStateError,
    );
    expect(calls, 1);
  });

  test('include, exclude and predicate', () async {
    final policy = RetryPolicy.builder()
        .include<TimeoutException>()
        .exclude<_NotThisOne>()
        .predicate((error) => '$error'.contains('again'))
        .build();
    expect(policy.shouldRetry(TimeoutException('again')), isTrue);
    expect(policy.shouldRetry(TimeoutException('once')), isFalse);
    expect(policy.shouldRetry(const FormatException('again')), isFalse);
    expect(policy.shouldRetry(_NotThisOne('again')), isFalse);
  });

  test('the back-off grows, is capped and gets its jitter', () {
    final policy = RetryPolicy.builder()
        .maxRetries(5)
        .delay(const Duration(milliseconds: 100))
        .multiplier(2)
        .maxDelay(const Duration(milliseconds: 500))
        .build();
    final execution = policy.backOff.start();
    expect(
      [
        for (var i = 0; i < 6; i++) execution.nextBackOff()?.inMilliseconds,
      ],
      [100, 200, 400, 500, 500, null],
    );
    final jittered = const ExponentialBackOff(
      initialInterval: Duration(milliseconds: 100),
      jitter: Duration(milliseconds: 50),
    ).start();
    for (var i = 0; i < 20; i++) {
      expect(
        jittered.nextBackOff()!.inMilliseconds,
        inInclusiveRange(100, 150),
      );
    }
  });

  test(
    'the timeout stops the retries before a pause that would pass it',
    () async {
      final listener = _Stops();
      var calls = 0;
      final exception =
          await template(
                maxRetries: 10,
                delay: const Duration(milliseconds: 30),
                listener: listener,
                more: (b) => b.timeout(const Duration(milliseconds: 70)),
              )
              .execute<void>(
                () => throw TimeoutException('${++calls}'),
                name: 'x',
              )
              .then<RetryException?>(
                (_) => null,
                onError: (Object e) => e as RetryException,
              );
      expect(exception!.stop, RetryStop.timeout);
      expect(calls, 3);
      expect(listener.stops, ['timeout x']);
    },
  );

  test('the request deadline stops the retries', () async {
    var calls = 0;
    final exception = await RequestDeadline.run(
      const Duration(milliseconds: 50),
      () => template(maxRetries: 10, delay: const Duration(milliseconds: 30))
          .execute<void>(() => throw TimeoutException('${++calls}'))
          .then<RetryException?>(
            (_) => null,
            onError: (Object e) => e as RetryException,
          ),
    );
    expect(exception!.stop, RetryStop.deadline);
    expect(calls, 2);
  });
}

final class StateErrorLike implements Exception {
  StateErrorLike(this.attempt);

  final int attempt;
}

final class _NotThisOne extends TimeoutException {
  _NotThisOne(super.message);
}
