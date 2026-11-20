// What a call through a generated AOP proxy costs: a wrapper proxy and a
// subclass proxy, written as the generator writes them, calling
// `ProxyInvoker.invoke` with and without advice (one interceptor that
// proceeds), and `invokeAsync` with advice. Not part of the tests; run with
//   dart run benchmark/proxy_invoker_benchmark.dart
//   dart compile exe benchmark/proxy_invoker_benchmark.dart -o /tmp/pi && /tmp/pi
//
// November 2026, Apple M5, AOT, nanoseconds per call (medians of 5 runs),
// the invoker's positional arguments before, the named ones after: the
// same. A wrapper proxy 32.3 / 32.3 with advice, 19.8 / 19.8 without; a
// subclass proxy 44.4 / 44.0 with advice, 28.0 / 27.3 without, 4.2 / 4.2
// before advice is attached; the bean itself 2.1; an awaited async call
// 264 / 266 with advice, 228 / 229 without.
// The proxies are written as the generator writes them.
// ignore_for_file: cast_nullable_to_non_nullable, unnecessary_parenthesis
// ignore_for_file: unnecessary_this
// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';

class Calculator {
  int add(int a, int b) => a + b;

  Future<int> later(int a) => Future.value(a);
}

const _target = AopTarget('Calculator', types: ['Calculator']);

const _signatures = [
  MethodSignature.of(
    'add',
    _target,
    returnType: 'int',
    parameterTypes: ['int', 'int'],
    parameterNames: ['a', 'b'],
  ),
  MethodSignature.of(
    'later',
    _target,
    returnType: 'Future',
    parameterTypes: ['int'],
    parameterNames: ['a'],
  ),
];

class CalculatorProxy with AdvisedWrapper implements Calculator {
  CalculatorProxy(this._target, this.aopInvoker);

  final Calculator _target;

  @override
  final ProxyInvoker aopInvoker;

  @override
  Object get aopTarget => _target;

  @override
  int add(int a, int b) => (this.aopInvoker.invoke(
    proxy: this,
    target: this._target,
    methodIndex: 0,
    arguments: [a, b],
    original: (args) => this._target.add((args[0] as int), (args[1] as int)),
  ) as int);

  @override
  Future<int> later(int a) => this.aopInvoker.invokeAsync<int>(
    proxy: this,
    target: this._target,
    methodIndex: 1,
    arguments: [a],
    original: (args) => this._target.later((args[0] as int)),
  );
}

class CalculatorSubclass extends Calculator with AdvisedSubclass {
  @override
  int add(int a, int b) {
    final _$invoker = this.aopInvoker;
    return _$invoker == null
        ? super.add(a, b)
        : (_$invoker.invoke(
            proxy: this,
            target: this,
            methodIndex: 0,
            arguments: [a, b],
            original: (args) => super.add((args[0] as int), (args[1] as int)),
          ) as int);
  }
}

final class _Proceed implements MethodInterceptor {
  const _Proceed();

  @override
  Object? invoke(MethodInvocation invocation) => invocation.proceed();
}

ProxyInvoker _invoker({required bool advised}) => ProxyInvoker(
  _signatures,
  [
    if (advised) DefaultPointcutAdvisor(const TruePointcut(), const _Proceed()),
  ],
  'calculator',
);

// Nanoseconds per call of [body], over two million calls.
double _measure(void Function() body) {
  for (var i = 0; i < 200000; i++) {
    body();
  }
  const calls = 2000000;
  final watch = Stopwatch()..start();
  for (var i = 0; i < calls; i++) {
    body();
  }
  return watch.elapsedMicroseconds * 1000 / calls;
}

// Nanoseconds per awaited call of [body], over 200,000 calls.
Future<double> _measureAsync(Future<int> Function() body) async {
  for (var i = 0; i < 20000; i++) {
    await body();
  }
  const calls = 200000;
  final watch = Stopwatch()..start();
  for (var i = 0; i < calls; i++) {
    await body();
  }
  return watch.elapsedMicroseconds * 1000 / calls;
}

Future<void> main() async {
  final advised = CalculatorProxy(Calculator(), _invoker(advised: true));
  final unadvised = CalculatorProxy(Calculator(), _invoker(advised: false));
  final subclassAdvised = CalculatorSubclass()
    ..aopInvoker = _invoker(advised: true);
  final subclassUnadvised = CalculatorSubclass()
    ..aopInvoker = _invoker(advised: false);
  final subclassPlain = CalculatorSubclass();
  final plain = Calculator();
  var sink = 0;
  final results = {
    'wrapper, advised': _measure(() => sink += advised.add(sink & 7, 1)),
    'wrapper, no advice': _measure(() => sink += unadvised.add(sink & 7, 1)),
    'subclass, advised': _measure(
      () => sink += subclassAdvised.add(sink & 7, 1),
    ),
    'subclass, no advice': _measure(
      () => sink += subclassUnadvised.add(sink & 7, 1),
    ),
    'subclass, no invoker': _measure(
      () => sink += subclassPlain.add(sink & 7, 1),
    ),
    'no proxy': _measure(() => sink += plain.add(sink & 7, 1)),
    'wrapper async, advised': await _measureAsync(() => advised.later(1)),
    'wrapper async, no advice': await _measureAsync(() => unadvised.later(1)),
  };
  for (final MapEntry(:key, :value) in results.entries) {
    stdout.writeln('$key: ${value.toStringAsFixed(1)} ns');
  }
  stdout.writeln('(sink $sink)');
}
