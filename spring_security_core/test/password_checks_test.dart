// The bound on password checks: at most maxConcurrent run, maxQueued
// wait, the next one is refused at once.
import 'dart:async';

import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

void main() {
  test('runs at most maxConcurrent at once, in order', () async {
    final limiter = PasswordCheckLimiter(maxConcurrent: 2, maxQueued: 10);
    var running = 0;
    var most = 0;
    final order = <int>[];
    Future<int> check(int i) => limiter.run(() async {
      running++;
      most = running > most ? running : most;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      running--;
      order.add(i);
      return i;
    });
    final results = await Future.wait([for (var i = 0; i < 8; i++) check(i)]);
    expect(results, [0, 1, 2, 3, 4, 5, 6, 7]);
    expect(most, 2);
    expect(limiter.running, 0);
    expect(limiter.waiting, 0);
  });

  test('a full queue refuses at once, without running the check', () async {
    final limiter = PasswordCheckLimiter(maxConcurrent: 1, maxQueued: 1);
    final release = Completer<void>();
    final first = limiter.run(() => release.future);
    final second = limiter.run(() async {});
    var ran = false;
    await expectLater(
      limiter.run(() async => ran = true),
      throwsA(isA<PasswordChecksBusyException>()),
    );
    expect(ran, isFalse);
    release.complete();
    await Future.wait([first, second]);
    // Free again.
    expect(await limiter.run(() async => 'ok'), 'ok');
  });

  test('a failing check frees its place', () async {
    final limiter = PasswordCheckLimiter(maxConcurrent: 1, maxQueued: 0);
    await expectLater(
      limiter.run<void>(() async => throw StateError('boom')),
      throwsStateError,
    );
    expect(limiter.running, 0);
    expect(await limiter.run(() async => 1), 1);
  });

  test('the provider goes through its limiter', () async {
    final limiter = PasswordCheckLimiter(maxConcurrent: 1, maxQueued: 0);
    final users = InMemoryUserDetailsManager([
      User.withUsername('ada').password('{noop}pw').roles(['USER']).build(),
    ]);
    final provider = DaoAuthenticationProvider(
      users,
      offloadPasswordChecks: false,
      passwordCheckLimiter: limiter,
    );
    final release = Completer<void>();
    final busy = limiter.run(() => release.future);
    await expectLater(
      provider.authenticate(
        UsernamePasswordAuthenticationToken.unauthenticated('ada', 'pw'),
      ),
      throwsA(isA<PasswordChecksBusyException>()),
    );
    release.complete();
    await busy;
    final ok = await provider.authenticate(
      UsernamePasswordAuthenticationToken.unauthenticated('ada', 'pw'),
    );
    expect(ok!.isAuthenticated, isTrue);
  });

  test('maxConcurrent below 1 or maxQueued below 0 are refused', () {
    expect(() => PasswordCheckLimiter(maxConcurrent: 0), throwsArgumentError);
    expect(() => PasswordCheckLimiter(maxQueued: -1), throwsArgumentError);
  });
}
