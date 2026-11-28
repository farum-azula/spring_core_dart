// @NotifyListeners around @Retryable: the notification is outside the
// retries (AdvisorOrder), so listeners hear once for the whole call,
// however many attempts it took.
// The hand-written proxy uses `this.` like generated code does.
// ignore_for_file: unnecessary_this
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

const _quick = Duration(milliseconds: 1);

class Basket extends ChangeNotifier {
  int calls = 0;
  int count = 0;

  @NotifyListeners()
  @Retryable(delay: _quick)
  Future<void> load() async {
    calls++;
    count = calls;
    if (calls < 3) {
      throw TimeoutException('slow');
    }
  }
}

const _target = AopTarget('Basket', types: ['Basket', 'ChangeNotifier']);

final _proxies = AopProxyFactory(
  signatures: const [
    MethodSignature.of(
      'load',
      _target,
      returnType: 'Future',
      annotations: [
        NotifyListeners(),
        Retryable(delay: _quick),
      ],
      annotationTypes: ['NotifyListeners', 'Retryable'],
    ),
  ],
  create: (target, invoker) => _$BasketProxy(target as Basket, invoker),
);

class _$BasketProxy extends Basket {
  _$BasketProxy(this._target, this._invoker);

  final Basket _target;
  final ProxyInvoker _invoker;

  @override
  Future<void> load() => this._invoker.invokeAsync<void>(
    proxy: this,
    target: this._target,
    methodIndex: 0,
    arguments: const [],
    original: (args) => this._target.load(),
  );
}

void main() {
  test('listeners hear once for the whole retried call', () async {
    final advisors = [
      DefaultPointcutAdvisor(
        const RetryablePointcut(),
        RetryInterceptor(),
        order: AdvisorOrder.retry,
      ),
      DefaultPointcutAdvisor(
        const NotifyListenersPointcut(),
        const NotifyListenersInterceptor(),
        order: AdvisorOrder.notifyListeners,
      ),
    ]..sort((a, b) => a.order.compareTo(b.order));
    final basket = Basket();
    final proxy = _proxies.createProxy(basket, advisors) as Basket;
    var heard = 0;
    proxy.addListener(() => heard++);
    await proxy.load();
    expect(basket.calls, 3);
    expect(heard, 1);
  });

  test('the notification is outside the retries', () {
    expect(AdvisorOrder.notifyListeners, lessThan(AdvisorOrder.retry));
    expect(AdvisorOrder.beanReads, lessThan(AdvisorOrder.retry));
  });
}
