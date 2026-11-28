// A bean with @Retryable and @ConcurrencyLimit methods, and its proxy
// written as the generator writes it (the signatures, `invokeAsync` for a
// Future, `invoke` for the rest, the element type of a stream).
// The hand-written proxy uses `this.` like generated code does.
// ignore_for_file: unnecessary_this
// Any object may be thrown in Dart; the bean throws what a test asks.
// ignore_for_file: only_throw_errors
import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';

/// A failure that is retried.
class Flaky implements Exception {
  Flaky(this.attempt);

  final int attempt;

  @override
  String toString() => 'Flaky($attempt)';
}

/// A failure behind another one.
class Wrapped implements Exception, NestedException {
  Wrapped(this.cause);

  @override
  final Object? cause;
}

const _quick = Duration(milliseconds: 1);

class Remote {
  int calls = 0;
  final seen = <List<String>>[];
  final pending = <Completer<String>>[];
  int failUntil = 3;
  Object Function(int attempt) failure = Flaky.new;

  @Retryable(delay: _quick)
  Future<String> fetch(List<String> items) async {
    calls++;
    seen.add([...items]);
    items.add('changed by $calls');
    if (calls < failUntil) {
      throw failure(calls);
    }
    return 'ok after $calls';
  }

  @Retryable(maxRetries: 2, delay: Duration.zero)
  int count() {
    calls++;
    if (calls < failUntil) {
      throw failure(calls);
    }
    return calls;
  }

  @Retryable(includes: [Flaky], excludes: [StateError], delay: _quick)
  Future<void> only(Object error) async {
    calls++;
    throw error;
  }

  @Retryable(maxRetries: 9, delay: Duration(milliseconds: 40))
  Future<void> slow() async {
    calls++;
    throw Flaky(calls);
  }

  @Retryable(maxRetries: 2, delay: _quick)
  Stream<int> ticks() {
    calls++;
    final attempt = calls;
    if (attempt < failUntil) {
      return Stream.fromIterable([attempt * 10]).followedBy(Flaky(attempt));
    }
    return Stream.fromIterable([attempt * 10, attempt * 10 + 1]);
  }

  @ConcurrencyLimit(2)
  Future<String> limited() {
    calls++;
    final completer = Completer<String>();
    pending.add(completer);
    return completer.future;
  }

  @ConcurrencyLimit(1, policy: ThrottlePolicy.reject)
  Future<String> rejecting() {
    calls++;
    final completer = Completer<String>();
    pending.add(completer);
    return completer.future;
  }

  @ConcurrencyLimit(1)
  @Retryable(maxRetries: 2, delay: _quick)
  Future<String> limitedRetried() {
    calls++;
    final completer = Completer<String>();
    pending.add(completer);
    return completer.future;
  }

  /// Calls [count] on itself: not through the proxy.
  int countOnItself() => count();
}

extension<T> on Stream<T> {
  Stream<T> followedBy(Object error) async* {
    yield* this;
    throw error;
  }
}

const _target = AopTarget('Remote', types: ['Remote']);

const remoteSignatures = [
  MethodSignature.of(
    'fetch',
    _target,
    returnType: 'Future',
    parameterTypes: ['List'],
    parameterNames: ['items'],
    annotations: [Retryable(delay: _quick)],
    annotationTypes: ['Retryable'],
  ),
  MethodSignature.of(
    'count',
    _target,
    returnType: 'int',
    annotations: [Retryable(maxRetries: 2, delay: Duration.zero)],
    annotationTypes: ['Retryable'],
  ),
  MethodSignature.of(
    'only',
    _target,
    returnType: 'Future',
    parameterTypes: ['Object'],
    parameterNames: ['error'],
    annotations: [
      Retryable(includes: [Flaky], excludes: [StateError], delay: _quick),
    ],
    annotationTypes: ['Retryable'],
  ),
  MethodSignature.of(
    'slow',
    _target,
    returnType: 'Future',
    annotations: [Retryable(maxRetries: 9, delay: Duration(milliseconds: 40))],
    annotationTypes: ['Retryable'],
  ),
  MethodSignature.of(
    'ticks',
    _target,
    returnType: 'Stream',
    annotations: [Retryable(maxRetries: 2, delay: _quick)],
    annotationTypes: ['Retryable'],
    returnTypeArguments: [TypeCapture<int>()],
  ),
  MethodSignature.of(
    'limited',
    _target,
    returnType: 'Future',
    annotations: [ConcurrencyLimit(2)],
    annotationTypes: ['ConcurrencyLimit'],
  ),
  MethodSignature.of(
    'rejecting',
    _target,
    returnType: 'Future',
    annotations: [ConcurrencyLimit(1, policy: ThrottlePolicy.reject)],
    annotationTypes: ['ConcurrencyLimit'],
  ),
  MethodSignature.of(
    'limitedRetried',
    _target,
    returnType: 'Future',
    annotations: [
      ConcurrencyLimit(1),
      Retryable(maxRetries: 2, delay: _quick),
    ],
    annotationTypes: ['ConcurrencyLimit', 'Retryable'],
  ),
  MethodSignature.of('countOnItself', _target, returnType: 'int'),
];

class _$RemoteProxy implements Remote {
  _$RemoteProxy(this._target, this._invoker);

  final Remote _target;
  final ProxyInvoker _invoker;

  @override
  int get calls => _target.calls;

  @override
  set calls(int value) => _target.calls = value;

  @override
  List<List<String>> get seen => _target.seen;

  @override
  List<Completer<String>> get pending => _target.pending;

  @override
  int get failUntil => _target.failUntil;

  @override
  set failUntil(int value) => _target.failUntil = value;

  @override
  Object Function(int attempt) get failure => _target.failure;

  @override
  set failure(Object Function(int attempt) value) => _target.failure = value;

  @override
  Future<String> fetch(List<String> items) => this._invoker.invokeAsync<String>(
    proxy: this,
    target: this._target,
    methodIndex: 0,
    arguments: [items],
    original: (args) => this._target.fetch(args[0]! as List<String>),
  );

  @override
  int count() =>
      this._invoker.invoke(
            proxy: this,
            target: this._target,
            methodIndex: 1,
            arguments: const [],
            original: (args) => this._target.count(),
          )!
          as int;

  @override
  Future<void> only(Object error) => this._invoker.invokeAsync<void>(
    proxy: this,
    target: this._target,
    methodIndex: 2,
    arguments: [error],
    original: (args) => this._target.only(args[0]!),
  );

  @override
  Future<void> slow() => this._invoker.invokeAsync<void>(
    proxy: this,
    target: this._target,
    methodIndex: 3,
    arguments: const [],
    original: (args) => this._target.slow(),
  );

  @override
  Stream<int> ticks() =>
      this._invoker.invoke(
            proxy: this,
            target: this._target,
            methodIndex: 4,
            arguments: const [],
            original: (args) => this._target.ticks(),
          )!
          as Stream<int>;

  @override
  Future<String> limited() => this._invoker.invokeAsync<String>(
    proxy: this,
    target: this._target,
    methodIndex: 5,
    arguments: const [],
    original: (args) => this._target.limited(),
  );

  @override
  Future<String> rejecting() => this._invoker.invokeAsync<String>(
    proxy: this,
    target: this._target,
    methodIndex: 6,
    arguments: const [],
    original: (args) => this._target.rejecting(),
  );

  @override
  Future<String> limitedRetried() => this._invoker.invokeAsync<String>(
    proxy: this,
    target: this._target,
    methodIndex: 7,
    arguments: const [],
    original: (args) => this._target.limitedRetried(),
  );

  @override
  int countOnItself() =>
      this._invoker.invoke(
            proxy: this,
            target: this._target,
            methodIndex: 8,
            arguments: const [],
            original: (args) => this._target.countOnItself(),
          )!
          as int;
}

final remoteProxies = AopProxyFactory(
  signatures: remoteSignatures,
  create: (target, invoker) => _$RemoteProxy(target as Remote, invoker),
);

/// The type tests a generated module registers for the types its
/// annotations name.
Introspector remoteTypeTests() => Introspector()
  ..registerTypeTests({
    Flaky: (value) => value is Flaky,
    StateError: (value) => value is StateError,
  });

/// [remote] behind a proxy with the retry and concurrency-limit advisors,
/// in the order of [AdvisorOrder].
Remote proxied(
  Remote remote, {
  RetryInterceptor? retry,
  ConcurrencyLimitInterceptor? limit,
}) {
  final advisors = [
    DefaultPointcutAdvisor(
      const ConcurrencyLimitPointcut(),
      limit ?? ConcurrencyLimitInterceptor(),
      order: AdvisorOrder.concurrencyLimit,
    ),
    DefaultPointcutAdvisor(
      const RetryablePointcut(),
      retry ?? RetryInterceptor(introspector: remoteTypeTests()),
      order: AdvisorOrder.retry,
    ),
  ]..sort((a, b) => a.order.compareTo(b.order));
  final factory = ProxyFactory(remote, remoteProxies, beanName: 'remote');
  advisors.forEach(factory.addAdvisor);
  return factory.getProxy() as Remote;
}
