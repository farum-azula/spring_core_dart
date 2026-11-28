// @Retryable around @Cacheable(sync: true): the retry is outside the cache
// (AdvisorOrder), so a failed attempt caches nothing, the callers sharing
// the key get the value of the attempt that succeeds, and later calls are
// hits.
// The hand-written proxy uses `this.` like generated code does.
// ignore_for_file: unnecessary_this
import 'dart:async';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:test/test.dart';

const _quick = Duration(milliseconds: 1);

class Prices {
  int calls = 0;

  @Cacheable('prices', sync: true)
  @Retryable(delay: _quick)
  Future<int> price(String isbn) async {
    calls++;
    await Future<void>.delayed(_quick);
    if (calls < 2) {
      throw TimeoutException('slow');
    }
    return 40 + calls;
  }
}

const _target = AopTarget('Prices', types: ['Prices']);

final _proxies = AopProxyFactory(
  signatures: const [
    MethodSignature.of(
      'price',
      _target,
      returnType: 'Future',
      parameterTypes: ['String'],
      parameterNames: ['isbn'],
      annotations: [
        Cacheable('prices', sync: true),
        Retryable(delay: _quick),
      ],
      annotationTypes: ['Cacheable', 'Retryable'],
    ),
  ],
  create: (target, invoker) => _$PricesProxy(target as Prices, invoker),
);

class _$PricesProxy implements Prices {
  _$PricesProxy(this._target, this._invoker);

  final Prices _target;
  final ProxyInvoker _invoker;

  @override
  int get calls => _target.calls;

  @override
  set calls(int value) => _target.calls = value;

  @override
  Future<int> price(String isbn) => this._invoker.invokeAsync<int>(
    proxy: this,
    target: this._target,
    methodIndex: 0,
    arguments: [isbn],
    original: (args) => this._target.price(args[0]! as String),
  );
}

void main() {
  test('a failed attempt caches nothing; the sharing callers get the '
      'success', () async {
    final manager = InMemoryCacheManager();
    final advisors = [
      DefaultPointcutAdvisor(
        const CacheAnnotationPointcut(),
        CacheInterceptor(cacheManager: manager),
        order: AdvisorOrder.cache,
      ),
      DefaultPointcutAdvisor(
        const RetryablePointcut(),
        RetryInterceptor(),
        order: AdvisorOrder.retry,
      ),
    ]..sort((a, b) => a.order.compareTo(b.order));
    final prices = Prices();
    final proxy = _proxies.createProxy(prices, advisors) as Prices;

    final both = await Future.wait([proxy.price('1'), proxy.price('1')]);
    expect(both, [42, 42]);
    expect(prices.calls, 2);
    expect(await proxy.price('1'), 42);
    expect(prices.calls, 2, reason: 'a hit');
    expect(manager.getCache('prices')!.get('1')?.value, 42);
  });

  test('the cache advisor is inside the retries', () {
    expect(AdvisorOrder.retry, lessThan(AdvisorOrder.cache));
  });
}
