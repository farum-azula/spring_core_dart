// @ConcurrencyLimit through a proxy: BLOCK waits in turn, REJECT throws,
// the permit is held across the retries of a @Retryable method, and the
// limit counts per proxy.
import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'support/remote.dart';

void main() {
  late Remote remote;
  late Remote proxy;
  late ConcurrencyLimitInterceptor limit;

  setUp(() {
    remote = Remote();
    limit = ConcurrencyLimitInterceptor();
    proxy = proxied(remote, limit: limit);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('BLOCK: the calls over the limit wait, in turn', () async {
    final results = <String>[];
    for (var i = 0; i < 4; i++) {
      unawaited(proxy.limited().then(results.add));
    }
    await settle();
    expect(remote.calls, 2);
    remote.pending[1].complete('second');
    await settle();
    expect(remote.calls, 3);
    remote.pending[0].complete('first');
    await settle();
    expect(remote.calls, 4);
    for (final pending in remote.pending.skip(2)) {
      pending.complete('later');
    }
    await settle();
    expect(results, ['second', 'first', 'later', 'later']);
    expect(limit.running(proxy, remoteSignatures[5]), 0);
  });

  test('REJECT: a call over the limit fails at once', () async {
    final first = proxy.rejecting();
    expect(
      proxy.rejecting,
      throwsA(
        isA<InvocationRejectedException>().having(
          (e) => e.message,
          'message',
          contains('Remote.rejecting'),
        ),
      ),
    );
    remote.pending.single.complete('done');
    expect(await first, 'done');
    final second = proxy.rejecting();
    remote.pending.last.complete('again');
    expect(await second, 'again');
  });

  test('the permit is held across the retries', () async {
    final first = proxy.limitedRetried();
    final second = proxy.limitedRetried();
    await settle();
    expect(remote.calls, 1);
    remote.pending[0].completeError(Flaky(1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(remote.calls, 2, reason: 'the retry, not the waiting call');
    remote.pending[1].complete('first');
    expect(await first, 'first');
    await settle();
    expect(remote.calls, 3);
    remote.pending[2].complete('second');
    expect(await second, 'second');
  });

  test('each proxy has its own permits', () async {
    final other = proxied(Remote(), limit: limit);
    unawaited(proxy.rejecting());
    expect(other.rejecting(), isA<Future<String>>());
  });

  test('the pointcut and the limit of a class', () {
    const ofClass = MethodSignature(
      name: 'run',
      declaringType: 'Job',
      targetType: 'Job',
      targetAnnotations: [ConcurrencyLimit(3)],
    );
    expect(const ConcurrencyLimitPointcut().matches(ofClass, 'job'), isTrue);
    expect(ConcurrencyLimitInterceptor.limitOf(ofClass)?.ofClass, isTrue);
    expect(ConcurrencyLimitPointcut.annotationTypes, [ConcurrencyLimit]);
  });
}
