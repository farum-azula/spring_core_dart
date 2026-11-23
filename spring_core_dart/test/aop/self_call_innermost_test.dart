// A call on a subclass proxy is a self-call only when the bean's own code
// is the innermost running (SIG-3): a callback that another advised bean
// makes through the bean's reference is advised, as in Spring where the
// reference is the proxy; code the framework runs on its own
// (runOutsideProxyBodies) is no self-call (SIG-2); an invocation says
// whether it is a self-call's (SIG-1).
import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

late Shop shop;

class Shop {
  String buy(Relay relay) => relay.relay(() => shop.price());

  String buyOwn() => 'own(${price()})';

  Future<String> buyLater(Relay relay) async {
    await Future<void>.delayed(Duration.zero);
    return await relay.relayLater(() => shop.price());
  }

  String price() => 'price';
}

class Relay {
  String relay(String Function() call) => call();

  Future<String> relayLater(String Function() call) async {
    await Future<void>.delayed(Duration.zero);
    return call();
  }
}

const _shop = [
  MethodSignature(name: 'buy', declaringType: 'Shop', targetType: 'Shop'),
  MethodSignature(name: 'buyOwn', declaringType: 'Shop', targetType: 'Shop'),
  MethodSignature(name: 'buyLater', declaringType: 'Shop', targetType: 'Shop'),
  MethodSignature(name: 'price', declaringType: 'Shop', targetType: 'Shop'),
];

const _relay = [
  MethodSignature(name: 'relay', declaringType: 'Relay', targetType: 'Relay'),
  MethodSignature(
    name: 'relayLater',
    declaringType: 'Relay',
    targetType: 'Relay',
  ),
];

// Subclass proxies as the generator writes them (trimmed).
class _$ShopProxy extends Shop {
  _$ShopProxy(this._$invoker);

  final ProxyInvoker _$invoker;

  @override
  String buy(Relay relay) =>
      _$invoker.invoke(
            proxy: this,
            target: this,
            methodIndex: 0,
            arguments: [relay],
            original: (args) => super.buy(args[0]! as Relay),
          )!
          as String;

  @override
  String buyOwn() =>
      _$invoker.invoke(
            proxy: this,
            target: this,
            methodIndex: 1,
            arguments: const [],
            original: (args) => super.buyOwn(),
          )!
          as String;

  @override
  Future<String> buyLater(Relay relay) => _$invoker.invokeAsync<String>(
    proxy: this,
    target: this,
    methodIndex: 2,
    arguments: [relay],
    original: (args) => super.buyLater(args[0]! as Relay),
  );

  @override
  String price() =>
      _$invoker.invoke(
            proxy: this,
            target: this,
            methodIndex: 3,
            arguments: const [],
            original: (args) => super.price(),
          )!
          as String;
}

class _$RelayProxy extends Relay {
  _$RelayProxy(this._$invoker);

  final ProxyInvoker _$invoker;

  @override
  String relay(String Function() call) =>
      _$invoker.invoke(
            proxy: this,
            target: this,
            methodIndex: 0,
            arguments: [call],
            original: (args) => super.relay(args[0]! as String Function()),
          )!
          as String;

  @override
  Future<String> relayLater(String Function() call) =>
      _$invoker.invokeAsync<String>(
        proxy: this,
        target: this,
        methodIndex: 1,
        arguments: [call],
        original: (args) => super.relayLater(args[0]! as String Function()),
      );
}

class _FrameworkRelay extends Relay {
  @override
  Future<String> relayLater(String Function() call) async {
    await Future<void>.delayed(Duration.zero);
    return runOutsideProxyBodies<String>(call);
  }
}

class _Record implements MethodInterceptor {
  final calls = <String>[];
  final selfCalls = <String>[];

  @override
  Object? invoke(MethodInvocation invocation) {
    calls.add(invocation.signature.name);
    if (invocation.isSelfCall) {
      selfCalls.add(invocation.signature.name);
    }
    return invocation.proceed();
  }
}

class _SeesSelfCalls extends _Record implements SelfCallInterceptor {}

void main() {
  late _Record record;
  late Relay relay;

  setUp(() {
    record = _Record();
    shop = _$ShopProxy(
      ProxyInvoker(_shop, [
        DefaultPointcutAdvisor(const TruePointcut(), record),
      ], 'shop'),
    );
    relay = _$RelayProxy(
      ProxyInvoker(_relay, [
        DefaultPointcutAdvisor(const TruePointcut(), _Record()),
      ], 'relay'),
    );
  });

  test('a call on this is not advised', () {
    expect(shop.buyOwn(), 'own(price)');
    expect(record.calls, ['buyOwn']);
  });

  test(
    'a callback of another advised bean through the reference is advised',
    () {
      expect(shop.buy(relay), 'price');
      expect(record.calls, ['buy', 'price']);
    },
  );

  test('the same after an await, in the zone of the bean’s call', () async {
    expect(await shop.buyLater(relay), 'price');
    expect(record.calls, ['buyLater', 'price']);
  });

  test('code the framework runs on its own is no self-call (SIG-2)', () async {
    // A plain object in the bean's zone (no advised call of its own): its
    // call through the reference cannot be told from one on this.
    expect(await shop.buyLater(Relay()), 'price');
    expect(record.calls, ['buyLater']);
    record.calls.clear();
    // The framework's own run (an effect re-run by an assignment).
    expect(await shop.buyLater(_FrameworkRelay()), 'price');
    expect(record.calls, ['buyLater', 'price']);
  });

  test('an invocation tells a self-call’s (SIG-1)', () {
    final sees = _SeesSelfCalls();
    final bean = _$ShopProxy(
      ProxyInvoker(
        _shop,
        [DefaultPointcutAdvisor(const TruePointcut(), sees)],
        'bean',
        adviseSelfCalls: true,
      ),
    );
    expect(bean.buyOwn(), 'own(price)');
    expect(sees.calls, ['buyOwn', 'price']);
    expect(sees.selfCalls, ['price']);
  });
}
