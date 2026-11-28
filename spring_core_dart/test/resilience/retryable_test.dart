// @Retryable through a proxy: futures and sync methods retried, the
// caller gets the last original error, each attempt a copy of the
// arguments, errors and NonRetryableException never retried, includes
// and excludes along the causes, the deadline, events and listeners,
// streams keep their type, a self-call is not retried, vetoes.
import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'support/remote.dart';

final class _Recorded extends RetryListener {
  final calls = <String>[];

  @override
  void beforeRetry(RetryPolicy retryPolicy, String name) =>
      calls.add('before $name');

  @override
  void onRetrySuccess(RetryPolicy retryPolicy, String name, Object? result) =>
      calls.add('success $result');

  @override
  void onRetryFailure(RetryPolicy retryPolicy, String name, Object error) =>
      calls.add('failure $error');

  @override
  void onRetryPolicyExhaustion(
    RetryPolicy retryPolicy,
    String name,
    RetryException exception,
  ) => calls.add('exhausted ${exception.stop.name} ${exception.errors}');
}

final class _Events implements ApplicationEventPublisher {
  final events = <MethodRetryEvent>[];

  @override
  void publishEvent<T extends Object>(T event) =>
      events.add(event as MethodRetryEvent);
}

final class _Denied implements NonRetryableException, Exception {}

final class _Always implements MethodRetryVeto {
  final asked = <String>[];

  @override
  String? vetoRetry(MethodInvocation invocation) {
    asked.add(invocation.signature.name);
    return 'it runs inside a transaction it did not open';
  }
}

void main() {
  late Remote remote;
  late Remote proxy;

  setUp(() {
    remote = Remote();
    proxy = proxied(remote);
  });

  test('a failed future is retried; the caller gets the success', () async {
    expect(await proxy.fetch(['a']), 'ok after 3');
    expect(remote.calls, 3);
  });

  test('each attempt gets a copy of the arguments', () async {
    final items = ['a'];
    await proxy.fetch(items);
    expect(remote.seen, [
      ['a'],
      ['a'],
      ['a'],
    ]);
    expect(items, ['a']);
  });

  test('exhausted: the caller gets the last original error', () async {
    remote.failUntil = 100;
    await expectLater(
      proxy.fetch([]),
      throwsA(isA<Flaky>().having((e) => e.attempt, 'attempt', 4)),
    );
    expect(remote.calls, 4);
  });

  test('a synchronous method is retried at once', () {
    remote.failUntil = 2;
    expect(proxy.count(), 2);
    remote
      ..calls = 0
      ..failUntil = 100;
    expect(proxy.count, throwsA(isA<Flaky>()));
    expect(remote.calls, 3);
  });

  test('a Dart Error and a NonRetryableException are never retried', () async {
    remote.failure = (_) => StateError('a bug');
    await expectLater(proxy.fetch([]), throwsStateError);
    expect(remote.calls, 1);
    remote
      ..calls = 0
      ..failure = (_) => _Denied();
    await expectLater(proxy.fetch([]), throwsA(isA<_Denied>()));
    expect(remote.calls, 1);
    remote
      ..calls = 0
      ..failure = (attempt) => Wrapped(ArgumentError('behind'));
    await expectLater(proxy.fetch([]), throwsA(isA<Wrapped>()));
    expect(remote.calls, 1, reason: 'an Error behind the failure');
  });

  test('includes and excludes are matched along the causes', () async {
    await expectLater(proxy.only(Flaky(0)), throwsA(isA<Flaky>()));
    expect(remote.calls, 4);
    remote.calls = 0;
    await expectLater(proxy.only(Wrapped(Flaky(0))), throwsA(isA<Wrapped>()));
    expect(remote.calls, 4, reason: 'Flaky is behind the failure');
    remote.calls = 0;
    await expectLater(
      proxy.only(const FormatException('not included')),
      throwsFormatException,
    );
    expect(remote.calls, 1);
  });

  test('a retry whose pause would pass the deadline is not made', () async {
    final stopwatch = Stopwatch()..start();
    await expectLater(
      RequestDeadline.run(const Duration(milliseconds: 100), proxy.slow),
      throwsA(isA<Flaky>()),
    );
    expect(remote.calls, inInclusiveRange(2, 3));
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 150)));
  });

  test('every failure is published and the listener told', () async {
    final events = _Events();
    final listener = _Recorded();
    proxy = proxied(
      remote,
      retry: RetryInterceptor(
        introspector: remoteTypeTests(),
        eventPublisher: events,
        retryListener: listener,
      ),
    );
    remote.failUntil = 2;
    await proxy.fetch([]);
    expect(
      [for (final e in events.events) (e.method.name, e.retryAborted)],
      [('fetch', false)],
    );
    expect(listener.calls, ['before Remote.fetch', 'success ok after 2']);

    remote
      ..calls = 0
      ..failUntil = 100;
    events.events.clear();
    listener.calls.clear();
    await expectLater(proxy.fetch([]), throwsA(isA<Flaky>()));
    expect(
      [for (final e in events.events) e.retryAborted],
      [
        false,
        false,
        false,
        true,
      ],
    );
    expect(identical(events.events.first.source, remote), isTrue);
    expect(listener.calls.last, startsWith('exhausted exhausted [Flaky(1)'));
    expect(
      listener.calls.where((c) => c.startsWith('failure')),
      hasLength(3),
    );
  });

  test('a stream is retried into the same stream, keeping its type', () async {
    final ticks = proxy.ticks();
    expect(ticks, isA<Stream<int>>());
    expect(await ticks.toList(), [10, 20, 30, 31]);
    expect(remote.calls, 3);
  });

  test('a stream gives the last error once the retries are used', () async {
    remote.failUntil = 100;
    final events = <Object>[];
    await proxy.ticks().handleError(events.add).forEach(events.add);
    expect(events, [10, 20, 30, isA<Flaky>()]);
  });

  test("a call the bean makes on itself skips the proxy's retries", () {
    remote.failUntil = 2;
    expect(proxy.countOnItself, throwsA(isA<Flaky>()));
    expect(remote.calls, 1);
  });

  test('a veto stops the retries at the first failure', () async {
    final veto = _Always();
    proxy = proxied(
      remote,
      retry: RetryInterceptor(
        introspector: remoteTypeTests(),
        vetoes: [veto],
      ),
    );
    await expectLater(proxy.fetch([]), throwsA(isA<Flaky>()));
    expect(remote.calls, 1);
    expect(veto.asked, ['fetch']);
    remote
      ..calls = 0
      ..failure = (_) => StateError('not retried anyway');
    await expectLater(proxy.fetch([]), throwsStateError);
    expect(veto.asked, ['fetch'], reason: 'not asked for an Error');
  });

  test('placeholders fill the *String attributes', () {
    const signature = MethodSignature(
      name: 'load',
      declaringType: 'Loader',
      targetType: 'Loader',
      returnType: 'Future',
      annotations: [
        Retryable(
          maxRetriesString: r'${retries}',
          delayString: r'${pause:250ms}',
          timeoutString: '5s',
        ),
      ],
    );
    final interceptor = RetryInterceptor(
      environment: StandardEnvironment()
        ..propertySources.addFirst(
          const MapPropertySource('test', {'retries': '7'}),
        ),
    );
    final policy = interceptor.policyOf(signature)!;
    final execution = policy.backOff.start();
    expect(
      [for (var i = 0; i < 8; i++) execution.nextBackOff()],
      [...List.filled(7, const Duration(milliseconds: 250)), null],
    );
    expect(policy.timeout, const Duration(seconds: 5));
  });

  test('the pointcut matches marked members and the methods of a marked '
      'class', () {
    const pointcut = RetryablePointcut();
    expect(
      [for (final s in remoteSignatures) pointcut.matches(s, 'remote')],
      [true, true, true, true, true, false, false, true, false],
    );
    const ofClass = MethodSignature(
      name: 'run',
      declaringType: 'Job',
      targetType: 'Job',
      targetAnnotations: [Retryable()],
    );
    const getter = MethodSignature(
      name: 'state',
      declaringType: 'Job',
      targetType: 'Job',
      kind: MemberKind.getter,
      targetAnnotations: [Retryable()],
    );
    expect(pointcut.matches(ofClass, 'job'), isTrue);
    expect(pointcut.matches(getter, 'job'), isFalse);
    expect(RetryablePointcut.annotationTypes, [Retryable]);
  });
}
